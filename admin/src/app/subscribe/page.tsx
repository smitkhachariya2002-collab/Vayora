import type {Metadata} from "next";
import {createClient} from "@supabase/supabase-js";
import PlanPicker,{type WebPlan} from "./plan-picker";
export const dynamic="force-dynamic";
export const metadata:Metadata={title:"Vayora Premium plans",robots:{index:false,follow:false}};
// Opened inside the Vayora app (website/ads APK). Payment itself runs in the app's UPI flow.
export default async function Subscribe({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}){
 const q=await searchParams;
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 let plans:WebPlan[]=[];let failed=false;
 if(url&&key){
  const c=createClient(url,key,{auth:{persistSession:false}});
  const {data,error}=await c.from("plans").select("id,name,price_inr,duration_days,perks,badge").eq("active",true).order("position").order("created_at");
  plans=(data??[]) as WebPlan[];failed=!!error;
 }else failed=true;
 const free=(q.free??"").split(",").filter(Boolean);
 return <main className="min-h-screen bg-[#0A0A14] px-4 pb-16 pt-8 text-[#F4F4FA]"><div className="mx-auto max-w-md">
 <h1 className="text-2xl font-semibold">Choose your plan</h1>
 <p className="mt-2 text-sm text-[#9C9CB8]">Full premium videos, 2 TB cloud storage and downloads. One-time payment, no automatic renewal.</p>
 {failed?<p className="mt-8 rounded-2xl border border-[#2A2A45] bg-[#141424] p-4 text-sm">Plans could not be loaded. Pull down to try again.</p>
 :<PlanPicker plans={plans} free={free} paused={q.paused==="1"} inApp={q.app==="1"}/>}
 </div></main>;
}
