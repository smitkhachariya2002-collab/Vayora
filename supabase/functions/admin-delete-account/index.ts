import { createClient } from "npm:@supabase/supabase-js@2.49.8";
const URL=Deno.env.get("SUPABASE_URL")!;
const ANON=Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,x-client-info,apikey,content-type","Access-Control-Allow-Methods":"POST,OPTIONS"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
function clients(req:Request){
 const auth=req.headers.get("Authorization")??"";
 return {
  user:createClient(URL,ANON,{global:{headers:{Authorization:auth}},auth:{persistSession:false}}),
  admin:createClient(URL,SERVICE,{auth:{persistSession:false}})
 };
}

Deno.serve(async(req)=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
 if(req.method!=="POST") return json({error:"method not allowed"},405);
 const {user,admin}=clients(req);const {data:ud}=await user.auth.getUser();if(!ud.user)return json({error:"login required"},401);
 const {data:owner}=await user.rpc("is_owner");if(owner!==true)return json({error:"forbidden"},403);
 let b:any={};try{b=await req.json()}catch{return json({error:"invalid json"},400)}
 const uid=String(b.user_id??"");if(!uid)return json({error:"user_id required"},400);
 const {data:targetAdmin}=await admin.from("admins").select("role").eq("user_id",uid).maybeSingle();
 if(targetAdmin?.role==="owner") return json({error:"owner accounts must be removed through the Admins page safeguards"},400);
 const {data:files}=await admin.from("cloud_files").select("storage_path").eq("user_id",uid);const cloud=(files??[]).map((x:any)=>x.storage_path).filter(Boolean);if(cloud.length)await admin.storage.from("cloud").remove(cloud);
 const {data:posts}=await admin.from("posts").select("id").eq("created_by",uid);const ids=(posts??[]).map((x:any)=>x.id);
 if(ids.length){const {data:items}=await admin.from("post_items").select("media_key,thumbnail_key,trailer_key").in("post_id",ids);const keys=[...new Set((items??[]).flatMap((x:any)=>[x.media_key,x.thumbnail_key,x.trailer_key]).filter(Boolean))] as string[];if(keys.length)await admin.storage.from("media").remove(keys);await admin.from("posts").delete().in("id",ids)}
 await admin.from("payment_orders").update({user_id:null,email_at_purchase:null}).eq("user_id",uid);
 await admin.from("support_requests").update({user_id:null,email:null}).eq("user_id",uid);
 const {error}=await admin.auth.admin.deleteUser(uid);if(error)return json({error:error.message},500);
 if(b.request_id) await admin.from("support_requests").update({status:"closed"}).eq("id",String(b.request_id));
 return json({ok:true});
});