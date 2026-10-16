"use server";
import {revalidatePath} from "next/cache";
import {redirect} from "next/navigation";
import {requireAdmin} from "@/lib/supabase";
import {changeAccess,grantPlan,markPaid,revokePayment,saveMode,saveUpi,savePlan,saveChannel,savePost} from "./actions";
const value=(f:FormData,k:string)=>String(f.get(k)??"").trim();
export async function workspaceAction(f:FormData){
 const op=value(f,"operation"),raw=value(f,"return_to");
 const back=raw.startsWith("/dashboard")&&!raw.startsWith("//")?raw.split("?")[0]:"/dashboard";
 let error="";
 try{
 const existing:Record<string,(f:FormData)=>Promise<void>>={changeAccess,grantPlan,markPaid,revokePayment,saveMode,saveUpi,savePlan,saveChannel,savePost};
 if(existing[op])await existing[op](f);
 else{
  const {client}=await requireAdmin(!["deletePost","removeItem","saveItem","reorderItems"].includes(op));
  let result:{error:{message:string}|null}={error:null};
  if(op==="deletePost")result=await client.from("posts").delete().eq("id",value(f,"id"));
  else if(op==="removeItem")result=await client.from("post_items").delete().eq("id",value(f,"id"));
  else if(op==="saveItem")result=await client.from("post_items").update({is_premium:f.has("is_premium"),duration_s:value(f,"duration_s")?Number(value(f,"duration_s")):null,position:Number(value(f,"position"))||0}).eq("id",value(f,"id"));
  else if(op==="reviewChannel")result=await client.from("channels").update({review_status:value(f,"review_status")}).eq("id",value(f,"id"));
  else if(op==="closeRequest")result=await client.from("support_requests").update({status:"closed"}).eq("id",value(f,"id"));
  else if(op==="saveAdmin")result=await client.rpc("admin_manage_member",{target_email:value(f,"email"),target_role:value(f,"role"),channel_ids:f.getAll("channel_ids").map(String),remove_member:false});
  else if(op==="removeAdmin")result=await client.rpc("admin_manage_member",{target_email:value(f,"email"),target_role:"content",channel_ids:[],remove_member:true});
  else if(op==="saveMeta")result=await client.rpc("admin_save_meta",{pixel_id:value(f,"pixel_id"),api_token:value(f,"api_token")||null,test_code:value(f,"test_code"),website:value(f,"website"),enabled:f.has("enabled")});
  else throw new Error("Unknown action");
  if(result.error)throw new Error(result.error.message);
 }
 }catch(e){error=e instanceof Error?e.message:"Could not save changes";}
 revalidatePath("/dashboard","layout");
 redirect(back+"?"+(error?"error="+encodeURIComponent(error):"ok=Changes+saved+successfully"));
}
