import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import {createClient} from 'npm:@supabase/supabase-js@2.49.8';
import {googleToken} from '../_shared/google.ts';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-cron-key'};
const json=(b:unknown,status=200)=>new Response(JSON.stringify(b),{status,headers:{...cors,'Content-Type':'application/json'}});
const db=()=>createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
async function authorized(req:Request) {
 const a=db(),key=req.headers.get('x-cron-key');
 if(key){const {data}=await a.rpc('meta_cron_ok',{p_key:key});if(data===true)return true;}
 const sb=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:req.headers.get('Authorization')??''}},auth:{persistSession:false}});
 const {data}=await sb.auth.getUser();if(!data.user)return false;const {data:role}=await sb.rpc('admin_role');return role==='owner';
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 if(req.method!=='POST')return json({error:'method not allowed'},405);
 try {
  if(!await authorized(req))return json({error:'Owner access required'},403);
  const service=JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT')??'{}');
  if(!service.project_id||!service.client_email||!service.private_key)return json({error:'Firebase is prepared but its service account has not been configured.',code:'NOT_CONFIGURED'},503);
  const a=db(),body=await req.json().catch(()=>({}));
  await a.rpc('schedule_push_automations');
  const {data:messages,error}=await a.from('push_messages').select('id').in('status',['scheduled','sending']).lte('scheduled_at',new Date().toISOString()).order('scheduled_at').limit(10);if(error)throw error;
  for(const m of messages??[]) {const {error}=await a.rpc('prepare_push_message',{p_message:m.id});if(error)throw error;}
  const {data:rows,error:claimError}=await a.rpc('claim_push_deliveries',{p_limit:30});if(claimError)throw claimError;
  if(!rows?.length)return json({sent:0,failed:0});
  const token=await googleToken('https://www.googleapis.com/auth/firebase.messaging','FCM_SERVICE_ACCOUNT');let sent=0,failed=0;
  for(const d of rows) {
   try {
    const {data:device}=await a.from('push_tokens').select('allowed,user_id').eq('id',d.token_id).single();
    if(!device?.allowed||device.user_id!==d.user_id){await a.from('push_deliveries').update({status:'skipped',lease_until:null,last_error:'Device ownership or permission changed'}).eq('id',d.id);continue;}
    const payload:Record<string,string>={delivery_id:d.id};
    for(const [key,value]of Object.entries(d.target??{}))if(typeof value==='string')payload[key]=value;
    const response=await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(service.project_id)}/messages:send`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({message:{token:d.token,notification:{title:d.title,body:d.body,...(d.image_url?{image:d.image_url}:{})},data:payload,android:{priority:'high',notification:{channel_id:'new_releases_offers',tag:d.message_id}}}}),signal:AbortSignal.timeout(15000)});
    const result=await response.json().catch(()=>({}));
    if(!response.ok) {
     const unregistered=(result.error?.details??[]).some((e:any)=>e.errorCode==='UNREGISTERED');
     if(unregistered)await a.from('push_tokens').update({allowed:false}).eq('id',d.token_id);
     throw new Error(unregistered?'Device registration expired':`FCM rejected message (${response.status})`);
    }
    const {error}=await a.from('push_deliveries').update({status:'sent',sent_at:new Date().toISOString(),lease_until:null,last_error:null}).eq('id',d.id).eq('status','processing');if(error)throw error;sent++;
   }catch(e) {
    failed++;await a.from('push_deliveries').update({status:d.attempts>=5?'failed':'pending',lease_until:null,next_attempt_at:new Date(Date.now()+Math.min(3600,30*2**d.attempts)*1000).toISOString(),last_error:e instanceof Error?e.message:'Delivery failed'}).eq('id',d.id).eq('status','processing');
   }
  }
  for(const m of messages??[]) {
   const {count}=await a.from('push_deliveries').select('id',{count:'exact',head:true}).eq('message_id',m.id).in('status',['pending','processing']);
   if(count===0)await a.from('push_messages').update({status:'sent'}).eq('id',m.id).eq('status','sending');
  }
  return json({sent,failed});
 }catch(e){return json({error:e instanceof Error?e.message:'Notification delivery failed'},500);}
});
