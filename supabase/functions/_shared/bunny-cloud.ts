import {createClient} from 'npm:@supabase/supabase-js@2.49.8';
import {requiredEnv,signedCdnUrl} from './bunny.ts';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-upload-size','Access-Control-Allow-Methods':'POST,PUT,OPTIONS'};
const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{...cors,'Content-Type':'application/json'}});
export const cloudConfigured=()=>['BUNNY_STORAGE_ZONE','BUNNY_STORAGE_PASSWORD','BUNNY_STORAGE_HOST','BUNNY_STORAGE_CDN_HOST','BUNNY_STORAGE_TOKEN_KEY'].every(n=>Boolean(Deno.env.get(n)?.trim()));
function storageUrl(path:string) {
 const env=requiredEnv(['BUNNY_STORAGE_ZONE','BUNNY_STORAGE_PASSWORD','BUNNY_STORAGE_HOST']);
 if(!/^(?:storage|uk\.storage|ny\.storage|la\.storage|sg\.storage|se\.storage|br\.storage|jh\.storage|syd\.storage)\.bunnycdn\.com$/.test(env.BUNNY_STORAGE_HOST))throw new Error('Invalid storage region');
 if(!/^[\w-]+$/.test(env.BUNNY_STORAGE_ZONE)||path.split('/').some(segment=>segment==='..'||segment==='.')||path.startsWith('/'))throw new Error('Invalid storage path');
 return {env,url:`https://${env.BUNNY_STORAGE_HOST}/${env.BUNNY_STORAGE_ZONE}/${path.split('/').map(encodeURIComponent).join('/')}`};
}
async function storage(path:string,init:RequestInit={}) {
 const {env,url}=storageUrl(path);
 const response=await fetch(url,{...init,headers:{AccessKey:env.BUNNY_STORAGE_PASSWORD,...init.headers},signal:AbortSignal.timeout(120000)});
 if(!response.ok&&response.status!==404)throw new Error(`Storage request failed (${response.status})`);return response;
}
export async function handleCloud(req:Request,body?:Record<string,unknown>):Promise<Response|null> {
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 const url=Deno.env.get('SUPABASE_URL')!;
 const sb=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:req.headers.get('Authorization')??''}},auth:{persistSession:false}});
 const a=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
 const {data:{user}}=await sb.auth.getUser();if(!user)return json({error:'Sign in again'},401);
 try {
  if(req.method==='PUT') {
   const id=new URL(req.url).searchParams.get('id')??'';
   const {data:file}=await sb.from('cloud_files').select('*').eq('id',id).eq('user_id',user.id).eq('storage_provider','bunny').single();
   if(!file||file.upload_status!=='uploading')return json({error:'Upload reservation unavailable'},404);
   if(Number(req.headers.get('x-upload-size'))!==Number(file.size_bytes)||!req.body)return json({error:'Upload size does not match reservation'},400);
   let bytes=0;
   const counted=req.body.pipeThrough(new TransformStream<Uint8Array,Uint8Array>({transform(chunk,controller){bytes+=chunk.byteLength;if(bytes>Number(file.size_bytes))throw new Error('File exceeds reserved size');controller.enqueue(chunk);}}));
   try {
    const response=await storage(file.storage_path,{method:'PUT',body:counted,headers:{'Content-Type':'application/octet-stream'}});
    if(!response.ok||bytes!==Number(file.size_bytes))throw new Error('Upload size mismatch');
    const {error}=await a.from('cloud_files').update({upload_status:'ready'}).eq('id',id).eq('user_id',user.id);if(error)throw error;
    return json({ok:true});
   }catch(_) {
    await storage(file.storage_path,{method:'DELETE'}).catch(()=>{});
    await a.from('cloud_files').delete().eq('id',id).eq('user_id',user.id);
    return json({error:'Upload failed. Please retry the file.'},400);
   }
  }
  const b=body??await req.json(),action=String(b.action??'');
  if(action==='upload') {
   if(!b.supports_bunny||!cloudConfigured())return null;
   const name=String(b.name??'').trim().replace(/[\\/\x00-\x1F]/g,'_').slice(0,180),size=Number(b.size);
   if(!name||!Number.isSafeInteger(size)||size<=0)return json({error:'Invalid file'},400);
   const path=`${user.id}/${crypto.randomUUID()}/${name}`;
   // The caller's RLS and atomic quota trigger authorize/reserve the upload.
   const {data:file,error}=await sb.from('cloud_files').insert({user_id:user.id,name,storage_path:path,size_bytes:size,mime:'application/octet-stream'}).select('*').single();
   if(error||!file)return json({error:error?.message??'Upload not permitted'},403);
   const {error:reserve}=await a.from('cloud_files').update({storage_provider:'bunny',upload_status:'uploading'}).eq('id',file.id);if(reserve){await sb.from('cloud_files').delete().eq('id',file.id);throw reserve;}
   return json({file,upload:{provider:'bunny',url:`${url}/functions/v1/cloud-upload?id=${file.id}`}});
  }
  if(!['download','delete','finalize'].includes(action))return null;
  const {data:file}=await sb.from('cloud_files').select('*').eq('id',String(b.id??'')).eq('user_id',user.id).single();
  if(!file||file.storage_provider!=='bunny')return null;
  if(action==='delete') {
   const result=await storage(file.storage_path,{method:'DELETE'});await result.body?.cancel();
   const {error}=await sb.from('cloud_files').delete().eq('id',file.id);if(error)throw error;return json({ok:true});
  }
  if(file.upload_status!=='ready')return json({error:'File upload has not finished'},409);
  if(action==='finalize')return json({file});
  const env=requiredEnv(['BUNNY_STORAGE_CDN_HOST','BUNNY_STORAGE_TOKEN_KEY']);
  return json({url:await signedCdnUrl(env.BUNNY_STORAGE_CDN_HOST,'/'+file.storage_path.split('/').map(encodeURIComponent).join('/'),env.BUNNY_STORAGE_TOKEN_KEY,Math.floor(Date.now()/1000)+600)});
 }catch(_){return json({error:'Private storage is unavailable. Check the storage configuration.'},503);}
}
