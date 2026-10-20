import {createClient} from "npm:@supabase/supabase-js@2.118.0";
import {deletionHandler} from "./handler.ts";

// This public endpoint only queues unverified requests. It never looks up or
// deletes Auth users, links an email to a user_id, or returns account existence.
Deno.serve(deletionHandler({record:async({email,details})=>{
  const client=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:existing,error:readError}=await client.from("support_requests").select("id")
    .eq("kind","account_deletion").eq("email",email).eq("status","open")
    .gte("created_at",new Date(Date.now()-24*60*60*1000).toISOString()).limit(1);
  if(readError)throw readError;
  if(existing?.length)return existing[0].id;
  const {data,error}=await client.from("support_requests").insert({
    kind:"account_deletion",email,user_id:null,reason:"Website account deletion request — ownership unverified",
    details:"Verify ownership by contacting the account email before processing. Never delete solely on this form submission.\n\n"+details,
  }).select("id").single();
  if(error)throw error;
  return data.id;
}}));
