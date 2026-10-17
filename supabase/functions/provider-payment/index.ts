import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { providerHandler } from "./handler.ts";
Deno.serve(providerHandler(()=>Deno.env.get("PROVIDER_WEBHOOK_SECRET"),async(value)=>{
 const db=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {error}=await db.rpc("provider_payment_update",value);
 if(error)throw error;
}));
