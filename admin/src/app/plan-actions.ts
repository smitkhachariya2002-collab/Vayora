"use server";
import {revalidatePath} from "next/cache";
import {unstable_rethrow} from "next/navigation";
import {requireAdmin} from "@/lib/supabase";
export type PlanSaveResult={ok:boolean;message:string};
export async function saveManagedPlan(_previous:PlanSaveResult,form:FormData):Promise<PlanSaveResult>{
 try{
  const {client}=await requireAdmin(true);
  const text=(key:string)=>String(form.get(key)??"").trim();
  const integer=(key:string,min:number)=>{const raw=text(key),n=Number(raw);if(!raw||!Number.isInteger(n)||n<min||n>2147483647)throw new Error("Enter a valid whole number for "+key.replaceAll("_"," "));return n;};
  const name=text("name");if(!name)throw new Error("Plan name is required.");
  const values={name,price_inr:integer("price_inr",1),duration_days:integer("duration_days",1),
   perks:text("perks").split(/\r?\n/).map(p=>p.trim()).filter(Boolean),badge:text("badge")||null,
   position:integer("position",-2147483648),active:form.has("active"),free_eligible:form.has("free_eligible")};
  const id=text("id");
  let result;
  if(id)result=await client.from("plans").update(values).eq("id",id).select("id").single();
  else{
   const code=text("code");if(!/^[a-z0-9]+$/.test(code))throw new Error("Code must contain lowercase letters and numbers only.");
   result=await client.from("plans").insert({...values,code}).select("id").single();
  }
  if(result.error)throw new Error(result.error.code==="23505"?"That code is already used. Choose another code.":result.error.message);
  revalidatePath("/plans");revalidatePath("/dashboard/plans");revalidatePath("/settings");
  return {ok:true,message:"Plan saved."};
 }catch(error){unstable_rethrow(error);return {ok:false,message:error instanceof Error?error.message:"Could not save plan."};}
}
