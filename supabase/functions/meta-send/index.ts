import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2.49.8";
import {buildEvent,hash,type QueuedEvent} from "./payload.ts";
const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json"}});
async function authorised(req:Request){
 const key=req.headers.get("x-cron-key");
 if(key){const {data}=await admin.rpc("meta_cron_ok",{p_key:key});if(data===true)return true;}
 const sb=createClient(url,anon,{global:{headers:{Authorization:req.headers.get("Authorization")??""}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data}=await sb.auth.getUser();if(!data.user)return false;
 const {data:role}=await sb.rpc("admin_role");return role==="owner";
}
async function settings(){const {data,error}=await admin.from("meta_settings").select("pixel_id,capi_token,enabled,test_event_code,revision").eq("id",1).single();if(error)throw error;return data;}
async function graph(id:string,token:string,body?:unknown,path=""){
 const response=await fetch(`https://graph.facebook.com/v27.0/${encodeURIComponent(id)}${path}`,{
  method:body?"POST":"GET",headers:{Authorization:"Bearer "+token,"content-type":"application/json"},
  ...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(20000)});
 const data=await response.json().catch(()=>({}));
 if(!response.ok)throw new Error(String(data?.error?.message??`Meta HTTP ${response.status}`).replaceAll(token,"[redacted]"));
 if(body&&Number(data.events_received)!==1)throw new Error("Meta did not acknowledge exactly one event");
 return data;
}
async function flush(){
 const s=await settings();if(!s.enabled||!s.pixel_id||!s.capi_token)return {skipped:true,sent:0,failed:0,pending:0};
 const {data:rows,error}=await admin.rpc("meta_claim_batch",{p_limit:20});if(error)throw error;
 const emails=new Map<string,string|null>();let sent=0,failed=0,suppressed=0,test_sent=0;
 for(const e of rows??[]){
  try{
   // Recheck immediately before sending; a revoked plan or tracking preference must not become a conversion.
   if(e.user_id){
    const {data:pref}=await admin.from("measurement_preferences").select("advertising").eq("user_id",e.user_id).single();
    if(!pref?.advertising)throw new Error("SUPPRESS: User withdrew advertising permission");
   }
   const current=await settings();
   if(!current.enabled||current.pixel_id!==s.pixel_id||current.revision!==e.config_revision)throw new Error("SUPPRESS: Measurement configuration changed");
   if(e.event_name==="Purchase"){
    const {data:o}=await admin.from("payment_orders").select("status,bank_verified,amount_paise,user_id").eq("id",e.order_id).single();
    if(o?.status!=="paid"||!o.bank_verified||o.user_id!==e.user_id||Number(e.value_inr)!==Number(o.amount_paise)/100)throw new Error("SUPPRESS: Purchase is not a verified paid order");
   }
   if(e.user_id&&!emails.has(e.user_id)){
    const {data}=await admin.auth.admin.getUserById(e.user_id);emails.set(e.user_id,data.user?.email??null);
   }
   const event=await buildEvent(e as QueuedEvent,e.user_id?emails.get(e.user_id):null);
   const response=await graph(s.pixel_id,s.capi_token,{data:[event],...(s.test_event_code?{test_event_code:s.test_event_code}:{})},"/events");
   const status=s.test_event_code?"test_sent":"sent";
   const {error:saveError}=await admin.from("meta_events").update({status,sent_at:new Date().toISOString(),lease_until:null,last_error:null,meta_trace_id:response.fbtrace_id??null}).eq("id",e.id).eq("status","processing");
   if(saveError)throw saveError;
   if(s.test_event_code)test_sent++;else sent++;
  }catch(error){
   const message=String(error instanceof Error?error.message:error).replaceAll(s.capi_token,"[redacted]").slice(0,500);
   const suppress=message.startsWith("SUPPRESS:");
   const terminal=e.attempts>=8||/outside the delivery window|Invalid event|permission|app_data/.test(message);
   await admin.from("meta_events").update({status:suppress?"suppressed":terminal?"failed":"pending",lease_until:null,last_error:message,
    next_attempt_at:new Date(Date.now()+Math.min(3600,30*2**Math.min(e.attempts,7))*1000).toISOString()}).eq("id",e.id).eq("status","processing");
   if(suppress)suppressed++;else failed++;
  }
 }
 const {count}=await admin.from("meta_events").select("id",{count:"exact",head:true}).in("status",["pending","processing"]);
 return {sent,test_sent,failed,suppressed,pending:count??0};
}
Deno.serve(async req=>{
 try{
  if(req.method!=="POST")return json({error:"method not allowed"},405);
  if(!await authorised(req))return json({error:"forbidden"},403);
  const body=await req.json().catch(()=>({}));const action=String(body.action??"flush"),s=await settings();
  if(action==="verify"){
   if(!s.pixel_id||!s.capi_token)return json({ok:false,message:"Dataset/Pixel ID and access token are required."});
   const data=await graph(s.pixel_id,s.capi_token,undefined,"?fields=name");
   return json({ok:true,name:data.name??s.pixel_id,message:"Connected. App events also require this dataset to be linked to your Meta app in Events Manager."});
  }
  if(action==="test"){
   if(!s.enabled||!s.pixel_id||!s.capi_token||!s.test_event_code)return json({ok:false,message:"Save enabled settings and a Meta Test Event Code first. No test is sent as a live purchase."});
   const event={event_name:"Purchase",event_time:Math.floor(Date.now()/1000),event_id:"vayora-test-"+crypto.randomUUID(),action_source:"app",
    user_data:{external_id:[await hash("vayora-admin-test")]},custom_data:{currency:"INR",value:1},
    app_data:{advertiser_tracking_enabled:1,application_tracking_enabled:1,extinfo:["a2","com.vayora.app","9","1.0.8","14","","en_IN","IST","","1080","1920","3","4","","","Asia/Kolkata"]}};
   const data=await graph(s.pixel_id,s.capi_token,{data:[event],test_event_code:s.test_event_code},"/events");
   return json({ok:true,meta:{events_received:data.events_received,fbtrace_id:data.fbtrace_id},test_only:true});
  }
  return json(await flush());
 }catch(error){return json({error:error instanceof Error?error.message:"Measurement delivery failed"},500);}
});

