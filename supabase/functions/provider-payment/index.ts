import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { providerHandler } from "./handler.ts";
Deno.serve(providerHandler(()=>Deno.env.get("PROVIDER_WEBHOOK_SECRET"),async(value)=>{
 const db=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:order,error:lookup}=await db.from("payment_orders").select("reference").eq("id",value.order_id).single();
 if(lookup||!order)throw new Error("Unknown order");
 const {error}=await db.rpc("provider_payment_update",{p_reference:order.reference,p_txn:value.utr,p_status:value.status==="PAID"?"SUCCESS":value.status,p_amount_paise:value.amount_paise});
 if(error)throw error;
}));
