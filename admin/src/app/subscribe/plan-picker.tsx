"use client";
import Link from "next/link";
import {useEffect,useState} from "react";
export type WebPlan={id:string;name:string;price_inr:number;duration_days:number;perks:string[]|null;badge:string|null};
type Bridge={postMessage:(message:string)=>void};
const duration=(days:number)=>days===1?"1 day":days===30?"1 month":days===180?"6 months":days===365?"1 year":days+" days";
const rupees=(value:number)=>"₹ "+value.toLocaleString("en-IN");
export default function PlanPicker({plans,free,paused,inApp}:{plans:WebPlan[];free:string[];paused:boolean;inApp:boolean}){
 const [selected,setSelected]=useState<string|null>(null);
 const [busy,setBusy]=useState(false);
 useEffect(()=>{if(!busy)return;const t=setTimeout(()=>setBusy(false),4000);return()=>clearTimeout(t);},[busy]);
 const plan=plans.find(p=>p.id===selected),isFree=!!plan&&free.includes(plan.id);
 const label=!plan?"Select a plan":isFree?"Activate for free":paused?"Payments unavailable":"Pay "+rupees(plan.price_inr)+" with UPI";
 const disabled=!plan||busy||(!isFree&&paused)||!inApp;
 if(!plans.length)return <p className="mt-8 rounded-2xl border border-[#2A2A45] bg-[#141424] p-4 text-sm">No plans are available right now.</p>;
 return <>
 {free.length>0&&<p className="mt-6 rounded-2xl border border-[#1F5C45] bg-[#10261D] p-4 text-sm text-[#34D399]">Plans marked FREE are free for you for a limited time.</p>}
 {paused&&free.length===0&&<p className="mt-6 rounded-2xl border border-[#5C4A1F] bg-[#2A2210] p-4 text-sm text-[#FBBF24]">Payments are paused. Please try again later.</p>}
 <div role="radiogroup" aria-label="Plans" className="mt-6 space-y-3">{plans.map(p=>{const on=p.id===selected,f=free.includes(p.id);
 return <button key={p.id} type="button" role="radio" aria-checked={on} onClick={()=>setSelected(p.id)}
 className={"flex w-full items-center gap-3 rounded-2xl border p-4 text-left transition "+(on?"border-2 border-[#7C5CFF] bg-[#1E1838]":"border-[#2A2A45] bg-[#141424]")}>
 <span className={"h-5 w-5 shrink-0 rounded-full border-2 "+(on?"border-[#7C5CFF] bg-[#7C5CFF] shadow-[inset_0_0_0_3px_#1E1838]":"border-[#9C9CB8]")}/>
 <span className="min-w-0 flex-1"><span className="block font-semibold">{p.name}</span>
 {p.badge&&<span className="mt-1 inline-block rounded-md bg-[#7C5CFF]/20 px-2 py-0.5 text-xs text-[#C9BCFF]">{p.badge}</span>}
 <span className="mt-1 block text-xs text-[#9C9CB8]">{duration(p.duration_days)}</span></span>
 {f?<span className="text-right"><span className="block text-xs text-[#9C9CB8] line-through">{rupees(p.price_inr)}</span><span className="mt-1 inline-block rounded-md bg-[#34D399]/15 px-2 py-0.5 text-xs font-bold text-[#34D399]">FREE</span></span>
 :<span className="text-lg font-semibold">{rupees(p.price_inr)}</span>}
 </button>;})}</div>
 {plan?.perks?.length?<ul className="mt-5 space-y-1 text-sm text-[#C8C8DA]">{plan.perks.map(perk=><li key={perk}>✓ {perk}</li>)}</ul>:null}
 <button type="button" disabled={disabled} onClick={()=>{const bridge=(window as unknown as {VayoraApp?:Bridge}).VayoraApp;if(!plan||!bridge)return;setBusy(true);bridge.postMessage(JSON.stringify({type:"buy",plan_id:plan.id}));}}
 className="mt-6 w-full rounded-2xl bg-gradient-to-br from-[#6A5CFF] via-[#9B5CFF] to-[#FF5CA8] px-4 py-4 font-semibold text-white disabled:opacity-40">{busy?"Opening…":label}</button>
 {!inApp&&<p className="mt-4 text-center text-sm text-[#9C9CB8]">Open this page from the Vayora app to buy a plan. <Link href="/d" className="text-[#C9BCFF] underline">Download Vayora</Link></p>}
 <p className="mt-4 text-center text-xs text-[#9C9CB8]">You pay with the UPI app you choose. Your plan starts as soon as the payment succeeds.</p>
 </>;
}
