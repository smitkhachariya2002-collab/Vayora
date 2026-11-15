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
 let b:any={};try{b=await req.json()}catch{return json({error:"invalid json"},400)}
 if(String(b.website??"").trim()) return json({ok:true});
 const email=String(b.email??"").trim().toLowerCase().slice(0,320);
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({error:"valid email required"},400);
 const details=String(b.details??"").trim().slice(0,2000);
 const partial=b.partial===true;
 const admin=createClient(URL,SERVICE,{auth:{persistSession:false}});
 const since=new Date(Date.now()-86400000).toISOString();
 const {count}=await admin.from("support_requests").select("id",{count:"exact",head:true}).eq("kind","deletion").eq("email",email).gte("created_at",since);
 if((count??0)>=5) return json({error:"too many requests"},429);
 const {error}=await admin.from("support_requests").insert({kind:"deletion",target_type:"account",email,reason:partial?"Partial deletion/data request":"Delete account",details,status:"open"});
 if(error)return json({error:"could not submit request"},500);
 return json({ok:true});
});