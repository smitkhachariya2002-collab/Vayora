import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.49.8";
const url=Deno.env.get("SUPABASE_URL")!;
const anon=Deno.env.get("SUPABASE_ANON_KEY")!;
const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json"}});
const admin=()=>createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
const userClient=(req:Request)=>createClient(url,anon,{global:{headers:{Authorization:req.headers.get("Authorization")??""}},auth:{persistSession:false,autoRefreshToken:false}});
async function user(req:Request){const sb=userClient(req);const {data,error}=await sb.auth.getUser();if(error||!data.user)throw new Error("unauthorized");return {sb,user:data.user};}
async function isOwner(uid:string){const {data}=await admin().from("admins").select("role").eq("user_id",uid).maybeSingle();return data?.role==="owner";}
async function adminRole(uid:string){const {data}=await admin().from("admins").select("role").eq("user_id",uid).maybeSingle();return data?.role??null;}

Deno.serve(async(req)=>{
 try{
  if(req.method!=="POST")return json({error:"method not allowed"},405);
  const {sb,user:u}=await user(req); const b=await req.json(); const action=String(b?.action??"");
  if(action==="upload"){
    const name=String(b?.name??"").trim(); const size=Number(b?.size??0);
    if(!name||!Number.isFinite(size)||size<=0)return json({error:"invalid file"},400);
    const safe=name.replace(/[\\/\0]/g,"_").slice(0,180);
    const path=`${u.id}/${crypto.randomUUID()}/${safe}`;
    const {data:file,error:e1}=await sb.from("cloud_files").insert({user_id:u.id,name:safe,storage_path:path,size_bytes:Math.floor(size),mime:"application/octet-stream"}).select("id,name,size_bytes,mime,storage_path,created_at").single();
    if(e1)return json({error:e1.message},e1.code==="42501"?403:400);
    const {data:up,error:e2}=await sb.storage.from("cloud").createSignedUploadUrl(path);
    if(e2){await sb.from("cloud_files").delete().eq("id",file.id);return json({error:e2.message},400);}
    return json({file,upload:up});
  }
  if(action==="finalize"){
    const id=String(b?.id??""); const {data,error}=await sb.from("cloud_files").select("id,name,size_bytes,mime,storage_path,created_at").eq("id",id).single();
    if(error)return json({error:error.message},404); return json({file:data});
  }
  if(action==="download"){
    const id=String(b?.id??""); const {data:file,error:e1}=await sb.from("cloud_files").select("storage_path").eq("id",id).single();
    if(e1)return json({error:"not found"},404);
    const {data,error}=await sb.storage.from("cloud").createSignedUrl(file.storage_path,3600);
    if(error||!data?.signedUrl)return json({error:error?.message??"could not sign"},400);
    return json({url:data.signedUrl});
  }
  if(action==="delete"){
    const id=String(b?.id??""); const {data:file,error:e1}=await sb.from("cloud_files").select("storage_path").eq("id",id).single();
    if(e1)return json({error:"not found"},404);
    const {error:e2}=await sb.storage.from("cloud").remove([file.storage_path]); if(e2)return json({error:e2.message},400);
    const {error:e3}=await sb.from("cloud_files").delete().eq("id",id); if(e3)return json({error:e3.message},400);
    return json({ok:true});
  }
  return json({error:"unknown action"},400);
 }catch(e){return json({error:e instanceof Error?e.message:"request failed"},401);}
});