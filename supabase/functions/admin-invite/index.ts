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
 const email=String(b.email??"").trim().toLowerCase(),role=b.role==="owner"?"owner":"content";
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return json({error:"valid email required"},400);
 let uid:string|undefined;
 const {data:list,error:le}=await admin.auth.admin.listUsers({page:1,perPage:1000});if(le)return json({error:le.message},500);
 uid=list.users.find((x:any)=>String(x.email??"").toLowerCase()===email)?.id;
 if(!uid){const {data:inv,error:ie}=await admin.auth.admin.inviteUserByEmail(email);if(ie||!inv.user)return json({error:ie?.message??"invite failed"},400);uid=inv.user.id}
 const {error:ae}=await admin.from("admins").upsert({user_id:uid,role},{onConflict:"user_id"});if(ae)return json({error:ae.message},500);
 await admin.from("admin_channel_access").delete().eq("user_id",uid);
 const ids=Array.isArray(b.channel_ids)?b.channel_ids.filter((x:any)=>typeof x==="string"):[];if(role==="content"&&ids.length){const {error}=await admin.from("admin_channel_access").insert(ids.map((channel_id:string)=>({user_id:uid,channel_id})));if(error)return json({error:error.message},500)}
 return json({ok:true,user_id:uid});
});