"use server";
import {revalidatePath} from "next/cache";
import {redirect,unstable_rethrow} from "next/navigation";
import {requireAdmin} from "@/lib/supabase";
import {changeAccess,grantPlan,markPaid,revokePayment,saveMode,saveUpi,saveChannel,savePost} from "./actions";
const value=(f:FormData,k:string)=>String(f.get(k)??"").trim();
export async function workspaceAction(f:FormData){
 const op=value(f,"operation"),raw=value(f,"return_to");
 let back=(/^\/(dashboard|channels|posts|approvals|payments|users|requests|plans|admins|meta)(\/|$)/.test(raw)||raw==="/")?raw.split("?")[0]:"/";
 let error="";
 try{
 const existing:Record<string,(f:FormData)=>Promise<unknown>>={changeAccess,grantPlan,markPaid,revokePayment,saveMode,saveUpi,saveChannel,savePost};
 if(existing[op]){const result=await existing[op](f);if(op==="savePost"&&!value(f,"id")&&typeof result==="string")back="/posts/"+result;}
 else{
  const {client}=await requireAdmin(!["deletePost","removeItem","saveItem","reorderItems"].includes(op));
  let result:{error:{message:string}|null}={error:null};
  if(op==="testMeta")result=await client.rpc("admin_meta_test");
  else if(op==="rejectPayment")result=await client.rpc("admin_reject_payment",{order_id:value(f,"order_id"),reason:value(f,"reason")});
  else if(op==="confirmBankPayment")result=await client.rpc("admin_confirm_bank_payment",{order_id:value(f,"order_id")});
  else if(op==="deletePost")result=await client.functions.invoke("post-delete",{body:{post_id:value(f,"id")}});
  else if(op==="removeItem")result=await client.from("post_items").delete().eq("id",value(f,"id"));
  else if(op==="saveItem")result=await client.from("post_items").update({is_premium:f.has("is_premium"),duration_s:value(f,"duration_s")?Number(value(f,"duration_s")):null,position:Number(value(f,"position"))||0}).eq("id",value(f,"id"));
  else if(op==="reviewChannel")result=await client.rpc("review_channel",{channel_id:value(f,"id"),approve:value(f,"review_status")==="approved",audience:value(f,"audience")||"all"});
  else if(op==="closeRequest")result=await client.from("support_requests").update({status:"closed"}).eq("id",value(f,"id"));
  else if(op==="deleteRequestedAccount"){const {data:{session}}=await client.auth.getSession();if(!session)throw new Error("Sign in again");const response=await fetch(process.env.NEXT_PUBLIC_SUPABASE_URL+"/functions/v1/admin-delete-account",{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+session.access_token},body:JSON.stringify({request_id:value(f,"id"),confirm:true})});if(!response.ok){const data=await response.json();throw new Error(data.error||"Deletion failed");}}
  else if(op==="saveAdmin"){
result=await client.rpc("admin_manage_member",{target_email:value(f,"email"),target_role:value(f,"role"),channel_ids:f.getAll("channel_ids").map(String),remove_member:false});
if(result.error?.message==="User must register and confirm this email first"){
const {data:{session}}=await client.auth.getSession();if(!session)throw new Error("Sign in again");
const response=await fetch(process.env.NEXT_PUBLIC_SUPABASE_URL+"/functions/v1/admin-invite",{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+session.access_token},body:JSON.stringify({email:value(f,"email"),role:value(f,"role"),channel_ids:f.getAll("channel_ids").map(String)})});
if(!response.ok){const d=await response.json();throw new Error(d.error||"Invitation failed");}result={error:null};
}
}
  else if(op==="removeAdmin")result=await client.rpc("admin_manage_member",{target_email:value(f,"email"),target_role:"content",channel_ids:[],remove_member:true});
  else if(op==="saveMeta")result=await client.rpc("admin_save_meta",{pixel_id:value(f,"pixel_id"),api_token:value(f,"api_token")||null,test_code:value(f,"test_code"),website:value(f,"website"),enabled:f.has("enabled")});
  else throw new Error("Unknown action");
  if(result.error)throw new Error(result.error.message);
 }
 }catch(e){unstable_rethrow(e);error=e instanceof Error?e.message:"Could not save changes";}
 revalidatePath("/dashboard","layout");
 revalidatePath("/","layout");
 redirect(back+"?"+(error?"error="+encodeURIComponent(error):"ok=Changes+saved+successfully"));
}
