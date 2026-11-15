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
  const {user:u}=await user(req); const b=await req.json(); const id=String(b?.post_id??""); const a=admin();
  const role=await adminRole(u.id); if(!role)return json({error:"forbidden"},403);
  const {data:post,error:pe}=await a.from("posts").select("id,channel_id").eq("id",id).single(); if(pe||!post)return json({error:"not found"},404);
  if(role!=="owner"){const {data:access}=await a.from("admin_channel_access").select("channel_id").eq("user_id",u.id).eq("channel_id",post.channel_id).maybeSingle();if(!access)return json({error:"forbidden"},403);}
  const {data:items}=await a.from("post_items").select("media_key,thumbnail_key,trailer_key").eq("post_id",id);
  const keys=[...new Set((items??[]).flatMap((x:any)=>[x.media_key,x.thumbnail_key,x.trailer_key]).filter(Boolean))]; if(keys.length)await a.storage.from("media").remove(keys);
  const {error}=await a.from("posts").delete().eq("id",id); if(error)return json({error:error.message},400); return json({ok:true});
 }catch(e){return json({error:e instanceof Error?e.message:"request failed"},401);}
});