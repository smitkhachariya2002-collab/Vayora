import {createClient} from "npm:@supabase/supabase-js@2.118.0";
import {googleToken} from "../_shared/google.ts";
const headers={"Content-Type":"application/json"};
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return new Response(null,{status:405});
 const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
 const secret=req.headers.get("Authorization")?.replace(/^Bearer /i,"")??"";
 const allowed=await admin.rpc("authorize_play_report",{secret});if(allowed.error||allowed.data!==true)return new Response(null,{status:401});
 const token=await googleToken("https://www.googleapis.com/auth/androidpublisher");
 const {data:jobs,error}=await admin.rpc("claim_play_reports");if(error)return new Response(null,{status:403});
 const price=(paise:number)=>({currency:"INR",priceMicros:String(Math.round(paise)*10000)});
 for(const job of jobs??[]){
  const preTax=Math.round(Number(job.amount_paise)*10000/(10000+Number(job.tax_rate_bps))),tax=Number(job.amount_paise)-preTax;
  const body={originalPreTaxAmount:price(preTax),originalTaxAmount:price(tax),transactionTime:job.paid_at,userTaxAddress:{regionCode:"IN",administrativeArea:job.administrative_area},
   recurringTransaction:{externalTransactionToken:job.token,externalSubscription:{subscriptionType:"PREPAID"}}};
  const url="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.vayora.play/externalTransactions?externalTransactionId="+encodeURIComponent(job.id);
  let result=await fetch(url,{method:"POST",headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify(body)});
  // An uncertain previous response is recovered with the same immutable transaction ID.
  if(result.status===409)result=await fetch("https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.vayora.play/externalTransactions/"+encodeURIComponent(job.id),{headers:{Authorization:"Bearer "+token}});
  await admin.rpc("finish_play_report",{order_id:job.id,succeeded:result.ok,response:result.ok?"Reported to Google":String(result.status)});
 }
 return new Response('{"processed":true}',{headers});
 }catch{return new Response('{"error":"Play reporting setup is not ready"}',{status:503,headers});}
});
