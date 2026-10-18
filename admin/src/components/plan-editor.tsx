"use client";
import {useActionState,useState} from "react";
import {saveManagedPlan} from "@/app/plan-actions";
import {Submit} from "./interactive";
import {Card,Field,Input,Textarea,FormGrid,Flash,Hidden,SectionTitle} from "./ui";
export type ManagedPlan={id?:string;code?:string;name?:string;price_inr?:number;duration_days?:number;perks?:string[];badge?:string|null;position?:number;active?:boolean;updated_at?:string};
export function durationLabel(days:number){return days===30?"1 month":days===180?"6 months":days===365?"1 year":days+" days";}
export default function PlanEditor({plan,subscribers=0,orders=0}:{plan:ManagedPlan;subscribers?:number;orders?:number}){
 const [result,save]=useActionState(saveManagedPlan,{ok:false,message:""});
 const [days,setDays]=useState(plan.duration_days??30);
 return <Card><form action={save} className="space-y-4" onSubmit={event=>{
  const data=new FormData(event.currentTarget);
  if(plan.id&&(Number(data.get("price_inr"))!==Number(plan.price_inr)||(plan.active&&!data.has("active")))&&
   !window.confirm("Existing subscribers keep their current plan until it ends. New buyers will see the new price."))event.preventDefault();
 }}>
 <SectionTitle>{plan.name||"New plan"}</SectionTitle>
 <Flash ok={result.ok?result.message:undefined} error={!result.ok?result.message:undefined}/>
 <Hidden name="id" value={plan.id??""}/>
 <FormGrid>
 <Field label="Name"><Input name="name" required defaultValue={plan.name??""}/></Field>
 <Field label="Code" hint="Used internally"><Input name="code" required readOnly={!!plan.id} pattern={plan.id?undefined:"[a-z0-9]+"} defaultValue={plan.code??""}/></Field>
 <Field label="Price (₹)"><Input name="price_inr" type="number" min="1" max="2147483647" step="1" required defaultValue={plan.price_inr??""}/></Field>
 <Field label="Duration (days)" hint={"= "+durationLabel(days)}><Input name="duration_days" type="number" min="1" max="2147483647" step="1" required value={days} onChange={e=>setDays(Number(e.target.value))}/></Field>
 </FormGrid>
 <Field label="Perks" hint="One per line"><Textarea name="perks" defaultValue={plan.perks?.join("\n")??""}/></Field>
 <FormGrid><Field label="Badge (optional)"><Input name="badge" placeholder="Best value" defaultValue={plan.badge??""}/></Field>
 <Field label="Order"><Input name="position" type="number" step="1" required defaultValue={plan.position??0}/></Field></FormGrid>
 <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="active" defaultChecked={plan.active??false}/>Show in app</label>
 <Submit>Save plan</Submit>
 <p className="border-t border-gray-100 pt-4 text-xs text-gray-500">{subscribers} active subscribers · {orders} orders</p>
 </form></Card>;
}
