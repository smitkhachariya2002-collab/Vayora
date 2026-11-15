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

async function removeStorage(a:any,uid:string){
 const {data:cf}=await a.from("cloud_files").select("storage_path").eq("user_id",uid);
 const cloud=(cf??[]).map((x:any)=>x.storage_path).filter(Boolean); for(let i=0;i<cloud.length;i+=100)await a.storage.from("cloud").remove(cloud.slice(i,i+100));
 const {data:chs}=await a.from("channels").select("id,icon_url").eq("created_by",uid); const cids=(chs??[]).map((x:any)=>x.id);
 const {data:p1}=await a.from("posts").select("id").eq("created_by",uid); let posts=(p1??[]).map((x:any)=>x.id);
 if(cids.length){const {data:p2}=await a.from("posts").select("id").in("channel_id",cids);posts=[...new Set([...posts,...(p2??[]).map((x:any)=>x.id)])];}
 if(posts.length){const {data:items}=await a.from("post_items").select("media_key,thumbnail_key,trailer_key").in("post_id",posts);const media=[...new Set((items??[]).flatMap((x:any)=>[x.media_key,x.thumbnail_key,x.trailer_key]).filter(Boolean))];for(let i=0;i<media.length;i+=100)await a.storage.from("media").remove(media.slice(i,i+100));}
 const icons=(chs??[]).map((x:any)=>x.icon_url).filter(Boolean);if(icons.length)await a.storage.from("channel-icons").remove(icons);
 const {data:avs}=await a.storage.from("avatars").list(uid,{limit:1000});const ap=(avs??[]).map((x:any)=>`${uid}/${x.name}`);if(ap.length)await a.storage.from("avatars").remove(ap);
}
Deno.serve(async(req)=>{
 try{
  if(req.method!=="POST")return json({error:"method not allowed"},405);
  const {user:u}=await user(req);
  if(await isOwner(u.id))return json({error:"Transfer ownership before deleting your account"},403);
  const a=admin(); await removeStorage(a,u.id);
  await a.from("payment_orders").update({email_at_purchase:null}).eq("user_id",u.id);
  await a.from("posts").delete().eq("created_by",u.id); await a.from("channels").delete().eq("created_by",u.id);
  const {error}=await a.auth.admin.deleteUser(u.id); if(error)return json({error:error.message},400);
  return json({ok:true});
 }catch(e){return json({error:e instanceof Error?e.message:"delete failed"},401);}
});
