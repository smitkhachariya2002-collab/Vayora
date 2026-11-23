import {createClient} from 'npm:@supabase/supabase-js@2.49.8';
import {BunnyNotConfigured,requiredEnv,videoId,tusAuthorization,signedCdnUrl,streamApi,cleanupReason,cdnOrigin} from './bunny.ts';
import {cutPreview} from './bunny-preview.ts';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-cron-key','Access-Control-Allow-Methods':'GET,POST,PUT,OPTIONS'};
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
const admin=()=>createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
async function caller(req:Request) {
 const sb=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:req.headers.get('Authorization')??''}},auth:{persistSession:false}});
 const {data,error}=await sb.auth.getUser();if(error||!data.user)throw new Error('AUTH: Sign in again');
 const {data:role}=await sb.rpc('admin_role');return {sb,user:data.user,owner:role==='owner'};
}
async function privileged(req:Request) {
 const key=req.headers.get('x-cron-key');if(key) {const {data}=await admin().rpc('meta_cron_ok',{p_key:key});if(data===true)return;}
 if(!(await caller(req)).owner)throw new Error('AUTH: Owner access required');
}
async function mac(value:string,key:string) {
 const k=await crypto.subtle.importKey('raw',new TextEncoder().encode(key),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return [...new Uint8Array(await crypto.subtle.sign('HMAC',k,new TextEncoder().encode(value)))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
function validPath(path:string) {
 if(!/^[a-zA-Z0-9_./-]+$/.test(path)||path.includes('..')||path.startsWith('/'))throw new Error('Invalid resource path');return path;
}
async function contentAccess(req:Request,id:string) {
 const c=await caller(req),a=admin();
 const {data:item,error}=await c.sb.from('post_items').select('id,post_id,is_premium,bunny_video_id,trailer_bunny_video_id,processing_status,trailer_processing_status').eq('id',id).single();
 if(error||!item)throw new Error('AUTH: Content is unavailable');
 const {data:edit}=await c.sb.rpc('can_edit_post',{p_post:item.post_id});
 const {data:status}=await c.sb.rpc('my_status');
 const full=edit===true||((!status?.is_guest||status?.source==='ads')&&(!item.is_premium||status?.can_play_premium===true));
 const preview=edit===true||!status?.is_guest||status?.source==='ads';
 return {...c,a,item,full,preview};
}
async function streamPreview(req:Request,item:any,id:string) {
 const env=requiredEnv(['BUNNY_STREAM_CDN_HOST','BUNNY_STREAM_TOKEN_KEY']);
 const origin=cdnOrigin(env.BUNNY_STREAM_CDN_HOST),expires=Math.floor(Date.now()/1000)+600;
 const fetchMedia=async(path:string)=>{
  const u=await signedCdnUrl(origin,`/${id}/${validPath(path)}`,env.BUNNY_STREAM_TOKEN_KEY,expires);
  const r=await fetch(u,{signal:AbortSignal.timeout(15000)});if(!r.ok)throw new Error('Preview is still processing');return r.text();
 };
 let path='playlist.m3u8',text=await fetchMedia(path);
 if(text.includes('#EXT-X-STREAM-INF')) {
  const lines=text.split(/\r?\n/);const index=lines.findIndex(x=>x.startsWith('#EXT-X-STREAM-INF'));
  path=validPath(lines.slice(index+1).find(x=>x.trim()&&!x.startsWith('#'))?.trim()??'');
  text=await fetchMedia(path);
 }
 const folder=path.includes('/')?path.slice(0,path.lastIndexOf('/')+1):'';
 return cutPreview(text,async(resource)=>{
  const part=validPath(folder+resource),value=`${id}|${part}|${expires}`;
  const url=new URL(`${Deno.env.get('SUPABASE_URL')}/functions/v1/bunny-preview`);
  url.search=new URLSearchParams({video:id,part,expires:String(expires),sig:await mac(value,env.BUNNY_STREAM_TOKEN_KEY)}).toString();return url.toString();
 });
}
export async function handleBunny(req:Request,operation:string):Promise<Response> {
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 try {
  const a=admin();
  if(operation==='bunny-preview'&&req.method==='GET') {
   const q=new URL(req.url).searchParams,id=videoId(q.get('video')),part=validPath(q.get('part')??''),expires=Number(q.get('expires'));
   const env=requiredEnv(['BUNNY_STREAM_CDN_HOST','BUNNY_STREAM_TOKEN_KEY']);
   if(!Number.isSafeInteger(expires)||expires<Math.floor(Date.now()/1000)||expires>Math.floor(Date.now()/1000)+610||q.get('sig')!==await mac(`${id}|${part}|${expires}`,env.BUNNY_STREAM_TOKEN_KEY))throw new Error('AUTH: Preview expired');
   const {data:referenced}=await a.from('post_items').select('id').eq('bunny_video_id',id).limit(1);if(!referenced?.length)throw new Error('AUTH: Content removed');
   if(part==='preview.m3u8')return new Response(await streamPreview(req,null,id),{headers:{...cors,'Content-Type':'application/vnd.apple.mpegurl','Cache-Control':'private,no-store'}});
   // A segment token cannot be upgraded to the provider's main manifest/directory token.
   if(part.endsWith('.m3u8'))throw new Error('AUTH: Invalid preview segment');
   const url=await signedCdnUrl(env.BUNNY_STREAM_CDN_HOST,`/${id}/${part}`,env.BUNNY_STREAM_TOKEN_KEY,expires);
   const r=await fetch(url,{signal:AbortSignal.timeout(20000)});if(!r.ok)return json({error:'Preview unavailable'},404);
   return new Response(r.body,{headers:{...cors,'Content-Type':r.headers.get('Content-Type')??'application/octet-stream','Cache-Control':'private,max-age=60'}});
  }
  if(req.method!=='POST')return json({error:'method not allowed'},405);
  const b=await req.json();
  if(operation==='bunny-status') {
   const c=await caller(req);if(!c.owner)throw new Error('AUTH: Owner access required');
   const names=['BUNNY_STREAM_LIBRARY_ID','BUNNY_STREAM_API_KEY','BUNNY_STREAM_CDN_HOST','BUNNY_STREAM_TOKEN_KEY','BUNNY_STORAGE_ZONE','BUNNY_STORAGE_PASSWORD','BUNNY_STORAGE_HOST','BUNNY_STORAGE_CDN_HOST','BUNNY_STORAGE_TOKEN_KEY'];
   return json({configured:Object.fromEntries(names.map(n=>[n,Boolean(Deno.env.get(n)?.trim())])),credentials_deferred:true});
  }
  if(operation==='bunny-stream-create') {
   const c=await caller(req),itemId=String(b.item_id??''),slot=b.slot==='trailer'?'trailer':'main';
   const {data:item}=await c.sb.from('post_items').select('post_id').eq('id',itemId).single();if(!item)throw new Error('AUTH: Content unavailable');
   const {data:allowed}=await c.sb.rpc('can_edit_post',{p_post:item.post_id});if(!allowed)throw new Error('AUTH: Upload not allowed');
   const {data:post}=await c.sb.from('posts').select('channel_id,title').eq('id',item.post_id).single();if(!post)throw new Error('AUTH: Post unavailable');
   const env=requiredEnv(['BUNNY_STREAM_LIBRARY_ID','BUNNY_STREAM_API_KEY','BUNNY_STREAM_CDN_HOST','BUNNY_STREAM_TOKEN_KEY']);
   const {data:previous}=await a.from('bunny_assets').select('video_id,status,bytes').eq('item_id',itemId).eq('slot',slot).maybeSingle();
   if(previous?.status==='deleting')throw new Error('Upload is being removed');
   if(previous&&Number(previous.bytes)!==Number(b.size))throw new Error('Retry with the original file; create a new media item for a replacement');
   await a.rpc('activate_bunny_processing');
   const id=previous?.video_id??videoId((await streamApi('/videos',{method:'POST',body:JSON.stringify({title:String(b.title??post.title).slice(0,160)})})).guid);
   if(!previous) {
    const {error}=await a.from('bunny_assets').insert({video_id:id,item_id:itemId,slot,uploaded_by:c.user.id,bytes:Math.max(0,Math.floor(Number(b.size)||0))});
    if(error){await streamApi(`/videos/${id}`,{method:'DELETE'});throw new Error('Could not reserve video upload');}
   }
   const completed=previous&&['processing','ready'].includes(previous.status);
   if(completed)return json({video_id:previous.video_id,completed:true,chunk_size:32*1024*1024});
   const fields=slot==='main'?{bunny_video_id:id,media_key:`${post.channel_id}/bunny/${id}`,processing_status:'uploading'}:{trailer_bunny_video_id:id,trailer_key:`${post.channel_id}/bunny/${id}`,trailer_processing_status:'uploading'};
   const {error}=await a.from('post_items').update(fields).eq('id',itemId);if(error)throw new Error('Could not link this video');
   const {data:publication}=await a.from('posts').select('status,publish_at').eq('id',item.post_id).single();
   if(publication&&['published','scheduled'].includes(publication.status))await a.from('posts').update({status:'draft',bunny_publish_requested:true,publish_at:publication.publish_at}).eq('id',item.post_id);
   const expires=Math.floor(Date.now()/1000)+86400;
   return json({video_id:id,endpoint:'https://video.bunnycdn.com/tusupload',headers:await tusAuthorization(env.BUNNY_STREAM_LIBRARY_ID,env.BUNNY_STREAM_API_KEY,id,expires),chunk_size:32*1024*1024});
  }
  if(operation==='bunny-stream-url'||operation==='bunny-preview') {
   const c=await contentAccess(req,String(b.item_id??''));
   if(b.thumbnail===true) {
    const id=videoId(c.item.bunny_video_id),env=requiredEnv(['BUNNY_STREAM_CDN_HOST','BUNNY_STREAM_TOKEN_KEY']);
    return json({url:await signedCdnUrl(env.BUNNY_STREAM_CDN_HOST,`/${id}/thumbnail.jpg`,env.BUNNY_STREAM_TOKEN_KEY,Math.floor(Date.now()/1000)+3600)});
   }
   if(!c.preview)throw new Error('AUTH: Log in to view this content');
   const preview=!c.full||b.preview===true;
   if(preview&&!c.full&&c.item.is_premium&&c.item.trailer_processing_status!=='ready'&&c.item.processing_status!=='ready')return json({error:'Preview is still processing'},409);
   const id=videoId(preview&&c.item.trailer_bunny_video_id&&c.item.trailer_processing_status==='ready'?c.item.trailer_bunny_video_id:c.item.bunny_video_id);
   if(preview&&(!c.item.trailer_bunny_video_id||c.item.trailer_processing_status!=='ready')) {
    const env=requiredEnv(['BUNNY_STREAM_TOKEN_KEY']),expires=Math.floor(Date.now()/1000)+600;
    const url=new URL(`${Deno.env.get('SUPABASE_URL')}/functions/v1/bunny-preview`),part='preview.m3u8';
    url.search=new URLSearchParams({video:id,part,expires:String(expires),sig:await mac(`${id}|${part}|${expires}`,env.BUNNY_STREAM_TOKEN_KEY)}).toString();
    return json({preview:true,url:url.toString(),seconds:120});
   }
   const state=preview?c.item.trailer_processing_status:c.item.processing_status;if(state!=='ready')return json({error:'Video is still processing'},409);
   const env=requiredEnv(['BUNNY_STREAM_CDN_HOST','BUNNY_STREAM_TOKEN_KEY']);const expires=Math.floor(Date.now()/1000)+3600;
   return json({url:await signedCdnUrl(env.BUNNY_STREAM_CDN_HOST,`/${id}/playlist.m3u8`,env.BUNNY_STREAM_TOKEN_KEY,expires,`/${id}/`),preview,expires});
  }
  if(operation==='bunny-sync') {
   await privileged(req);requiredEnv(['BUNNY_STREAM_LIBRARY_ID','BUNNY_STREAM_API_KEY']);
   const {data:assets}=await a.from('bunny_assets').select('*').in('status',['uploading','processing']).order('updated_at').limit(30);let ready=0,failed=0;
   for(const asset of assets??[]) {
    const v=await streamApi(`/videos/${videoId(asset.video_id)}`);
    let status=v.status===5?'failed':[0,1].includes(v.status)?'uploading':'processing';
    if(v.status===4) {
     const env=requiredEnv(['BUNNY_STREAM_CDN_HOST','BUNNY_STREAM_TOKEN_KEY']),path=`/${videoId(asset.video_id)}/playlist.m3u8`;
     const signed=await fetch(await signedCdnUrl(env.BUNNY_STREAM_CDN_HOST,path,env.BUNNY_STREAM_TOKEN_KEY,Math.floor(Date.now()/1000)+120,`/${asset.video_id}/`),{signal:AbortSignal.timeout(15000)});
     const unsigned=await fetch(cdnOrigin(env.BUNNY_STREAM_CDN_HOST)+path,{signal:AbortSignal.timeout(15000),redirect:'manual'});
     const works=signed.ok&&(await signed.text()).startsWith('#EXTM3U');await unsigned.body?.cancel();
     if(works&&[401,403].includes(unsigned.status))status='ready';
    }
    const fields:Record<string,unknown>=asset.slot==='main'?{processing_status:status,duration_s:Math.max(0,Math.round(Number(v.length)||0)),size_bytes:Number(v.storageSize)||asset.bytes}:{trailer_processing_status:status};
    const {error}=await a.from('post_items').update(fields).eq('id',asset.item_id);if(error)throw new Error('Could not update media processing state');
    await a.from('bunny_assets').update({status,updated_at:new Date().toISOString()}).eq('video_id',asset.video_id);
    if(status==='ready')ready++;if(status==='failed')failed++;
   }
   const {data:waiting}=await a.from('posts').select('id,channel_id,publish_at').eq('bunny_publish_requested',true).limit(100);
   let published=0;
   for(const post of waiting??[]) {
    if(post.publish_at&&Date.parse(post.publish_at)>Date.now())continue;
    const {data:channel}=await a.from('channels').select('review_status,status,hidden').eq('id',post.channel_id).single();
    if(!channel||channel.review_status!=='approved'||channel.hidden||!['active','published'].includes(channel.status))continue;
    const {data:items,error}=await a.from('post_items').select('bunny_video_id,trailer_bunny_video_id,processing_status,trailer_processing_status').eq('post_id',post.id);
    if(error||!items?.length||items.some(i=>(i.bunny_video_id&&i.processing_status!=='ready')||(i.trailer_bunny_video_id&&i.trailer_processing_status!=='ready')))continue;
    const {error:save}=await a.from('posts').update({status:'published',publish_at:new Date().toISOString(),bunny_publish_requested:false}).eq('id',post.id).eq('bunny_publish_requested',true);if(!save)published++;
   }
   const {data:removed}=await a.from('bunny_assets').select('video_id').eq('status','cleanup_queued').is('item_id',null).limit(20);let cleaned=0;
   for(const asset of removed??[]) {
    try {
     const id=videoId(asset.video_id),video=await streamApi(`/videos/${id}`);
     const {data:refs,error}=await a.from('post_items').select('id').or(`bunny_video_id.eq.${id},trailer_bunny_video_id.eq.${id}`).limit(1);
     if(error||!cleanupReason(video,Boolean(refs?.length)))continue;
     await streamApi(`/videos/${id}`,{method:'DELETE'});await a.from('bunny_assets').delete().eq('video_id',id).is('item_id',null);cleaned++;
    }catch{/* Retry queued cleanup next minute. */}
   }
   return json({checked:assets?.length??0,ready,failed,published,cleaned});
  }
  if(operation==='bunny-stream-delete') {
   const c=await caller(req);if(!c.owner)throw new Error('AUTH: Owner access required');
   if(b.confirm!==true)throw new Error('Deletion confirmation is required');
   // Database removal detaches assets into the cleanup queue. Never destroy a provider
   // file before the transaction that removes its references has succeeded.
   if(b.item_id){const {error}=await a.from('post_items').delete().eq('id',String(b.item_id));if(error)throw error;}
   else if(b.channel_id){const {error}=await a.from('channels').delete().eq('id',String(b.channel_id));if(error)throw error;}
   else if(b.post_id){const {error}=await a.from('posts').delete().eq('id',String(b.post_id));if(error)throw error;}
   else throw new Error('Choose a post, item or channel');
   return json({ok:true});
  }
  if(operation==='bunny-cleanup') {
   const c=await caller(req);if(!c.owner)throw new Error('AUTH: Owner access required');
   const page=Math.max(1,Math.floor(Number(b.page)||1)),listing=await streamApi(`/videos?page=${page}&itemsPerPage=100`);
   const ids=(listing.items??[]).map((v:any)=>videoId(v.guid));
   const {data:main,error:mainError}=await a.from('post_items').select('bunny_video_id').in('bunny_video_id',ids);
   const {data:trailers,error:trailerError}=await a.from('post_items').select('trailer_bunny_video_id').in('trailer_bunny_video_id',ids);
   if(mainError||trailerError)throw new Error('Could not verify media references');
   const used=new Set([...(main??[]).map(x=>x.bunny_video_id),...(trailers??[]).map(x=>x.trailer_bunny_video_id)]);
   const unused=(listing.items??[]).map((v:any)=>({...v,reason:cleanupReason(v,used.has(v.guid))})).filter((v:any)=>v.reason);
   for(const video of unused){const env=requiredEnv(['BUNNY_STREAM_CDN_HOST','BUNNY_STREAM_TOKEN_KEY']);video.thumbnail_url=await signedCdnUrl(env.BUNNY_STREAM_CDN_HOST,`/${videoId(video.guid)}/thumbnail.jpg`,env.BUNNY_STREAM_TOKEN_KEY,Math.floor(Date.now()/1000)+600);}
   if(b.action!=='delete')return json({items:unused,total_provider:listing.totalItems,page,used_on_page:used.size,unused_bytes:unused.reduce((n:number,v:any)=>n+(Number(v.storageSize)||0),0),cost_estimate:null});
   if(b.confirm!==true||!Array.isArray(b.video_ids)||b.video_ids.length>100)throw new Error('Confirm up to 100 selected videos');
   let deleted=0;
   for(const value of b.video_ids) {
    const id=videoId(value);
    // Re-read actual provider age and both references immediately before deletion.
    const v=await streamApi(`/videos/${id}`);
    const {data:refs,error:refError}=await a.from('post_items').select('id').or(`bunny_video_id.eq.${id},trailer_bunny_video_id.eq.${id}`).limit(1);
    if(refError||!cleanupReason(v,Boolean(refs?.length)))continue;
    const {data:asset,error:assetError}=await a.from('bunny_assets').select('item_id').eq('video_id',id).maybeSingle();
    if(assetError||asset?.item_id)continue; // A reserved upload remains protected until its item is removed.
    await streamApi(`/videos/${id}`,{method:'DELETE'});await a.from('bunny_assets').delete().eq('video_id',id).is('item_id',null);deleted++;
   }
   return json({deleted});
  }
  return json({error:'Unknown Bunny operation'},400);
 }catch(error) {
  if(error instanceof BunnyNotConfigured)return json({error:'Bunny credentials have not been added yet.',missing:error.missing,code:'NOT_CONFIGURED'},503);
  const message=error instanceof Error?error.message:'Media request failed';return json({error:message},message.startsWith('AUTH:')?403:400);
 }
}
