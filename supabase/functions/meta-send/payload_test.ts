import {buildEvent,type QueuedEvent} from "./payload.ts";
const base=():QueuedEvent=>({event_name:"Purchase",event_id:"purchase-test",created_at:new Date().toISOString(),action_source:"app",advertising_consent:true,user_id:"user-1",anon_id:"install-1",app_data:{advertiser_tracking_enabled:1,application_tracking_enabled:1,extinfo:["a2","com.vayora.app","9","1.0.8","14","","en_IN","","","1080","1920","3","4","","",""]},value_inr:49,content_name:"Day pass",custom_data:{password:"never",filename:"private.mp4",search:"private",progress:25}});
function ok(v:unknown){if(!v)throw Error("Assertion failed");}
async function rejects(e:QueuedEvent){try{await buildEvent(e);throw Error("did not reject");}catch(x){if(String(x).includes("did not reject"))throw x;}}
Deno.test("server payload hashes identifiers and strips private properties",async()=>{const r=await buildEvent(base(),"  TEST@EXAMPLE.COM ");const u=r.user_data as Record<string,string[]>;ok(u.em[0].length===64&&u.external_id[0].length===64);ok(!JSON.stringify(r).includes("private")&&!JSON.stringify(r).includes("password"));const c=r.custom_data as Record<string,unknown>;ok(c.value===49&&c.currency==="INR"&&c.progress===25);});
Deno.test("declined advertising is rejected",()=>rejects({...base(),advertising_consent:false}));
Deno.test("app context is mandatory",()=>rejects({...base(),app_data:null}));
Deno.test("expired events are rejected",()=>rejects({...base(),created_at:new Date(Date.now()-8*86400000).toISOString()}));
Deno.test("non-positive Purchase rejected",()=>rejects({...base(),value_inr:0}));
Deno.test("website event uses same dedup ID",async()=>{const r=await buildEvent({...base(),event_name:"Lead",action_source:"website",event_id:"web-123",value_inr:null,source_url:"https://vayora-eta.vercel.app/d"});ok(r.event_id==="web-123"&&!r.app_data);ok((r.custom_data as Record<string,string>).content_name==="apk_download");});


Deno.test("Play app payload uses its own Android package",async()=>{
 const app=base();
 const ext=[...((app.app_data as Record<string,unknown>).extinfo as string[])];
 ext[1]="com.vayora.play";
 app.app_data={advertiser_tracking_enabled:1,application_tracking_enabled:1,extinfo:ext};
 const r=await buildEvent(app,null);
 ok(((r.app_data as Record<string,unknown>).extinfo as string[])[1]==="com.vayora.play");
});
