import {createClient} from "npm:@supabase/supabase-js@2.118.0";
import {googleToken,sha256,base64url} from "../_shared/google.ts";
const headers={"Content-Type":"application/json"},app="com.vayora.app";
const response=(status:number,message:string,data?:unknown)=>new Response(JSON.stringify({message,data}),{status,headers});
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return response(405,"POST required");
 try{
 const jwt=req.headers.get("Authorization")?.replace(/^Bearer /i,"");if(!jwt)return response(401,"Login required");
 const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error}=await admin.auth.getUser(jwt);if(error||!user||user.is_anonymous)return response(401,"Member account required");
 const caller=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:"Bearer "+jwt}}});
 const body=await req.json();
 if(body.operation==="challenge"){
  const project=Deno.env.get("PLAY_CLOUD_PROJECT_NUMBER");if(!project||!Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT"))return response(503,"Play verification is not configured");
  const {data:nonce,error:challenge}=await caller.rpc("play_integrity_challenge");if(challenge)return response(400,challenge.message);
  return response(200,"Ready",{nonce,project_number:project});
 }
 if(body.operation==="enroll"){
  if(typeof body.integrity_token!=="string"||body.integrity_token.length>20000)return response(400,"Invalid verification");
  const token=await googleToken("https://www.googleapis.com/auth/playintegrity");
  const decoded=await fetch("https://playintegrity.googleapis.com/v1/"+app+":decodeIntegrityToken",{method:"POST",headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify({integrity_token:body.integrity_token})});
  if(!decoded.ok)return response(403,"App verification failed");
  const payload=(await decoded.json()).tokenPayloadExternal,details=payload?.requestDetails,integrity=payload?.appIntegrity;
  const allowed=(Deno.env.get("PLAY_CERTIFICATE_SHA256")??"").split(",").map(s=>{
   const value=s.trim();return /^([0-9a-f]{2}:){31}[0-9a-f]{2}$/i.test(value)?base64url(Uint8Array.from(value.split(":").map(x=>parseInt(x,16)))):value;
  }).filter(Boolean);
  const timestamp=Number(details?.timestampMillis);
  if(details?.requestPackageName!==app||integrity?.packageName!==app||integrity?.appRecognitionVerdict!=="PLAY_RECOGNIZED"
   ||payload?.accountDetails?.appLicensingVerdict!=="LICENSED"||!payload?.deviceIntegrity?.deviceRecognitionVerdict?.includes("MEETS_DEVICE_INTEGRITY")
   ||!integrity?.certificateSha256Digest?.some((s:string)=>allowed.includes(s))||!Number.isFinite(timestamp)||Date.now()-timestamp>300000||timestamp>Date.now()+60000)return response(403,"App verification failed");
  const claims=JSON.parse(atob(jwt.split(".")[1].replace(/-/g,"+").replace(/_/g,"/")));
  const {error:grant}=await admin.rpc("enable_play_free_cloud",{user_id:user.id,session_id:claims.session_id,nonce:details.nonce});
  if(grant)return response(403,"Verification expired. Please retry");
  return response(200,"Cloud enabled");
 }
 if(body.operation==="purchase"){
  const {data:status,error:failed}=await caller.rpc("my_status");
  if(failed||!status?.play_verified||!status?.play_billing_enabled)return response(403,"Play billing is disabled");
  const purchase=body.purchase_token;if(typeof purchase!=="string"||purchase.length>4096)return response(400,"Invalid purchase");
  const token=await googleToken("https://www.googleapis.com/auth/androidpublisher");
  const base="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"+app;
  const checked=await fetch(base+"/purchases/subscriptionsv2/tokens/"+encodeURIComponent(purchase),{headers:{Authorization:"Bearer "+token}});
  if(!checked.ok)return response(403,"Purchase could not be verified");
  const data=await checked.json();
  if(!["SUBSCRIPTION_STATE_ACTIVE","SUBSCRIPTION_STATE_IN_GRACE_PERIOD"].includes(data.subscriptionState)
    ||data.externalAccountIdentifiers?.obfuscatedExternalAccountId!==await sha256(user.id))return response(403,"Purchase is not active for this account");
  const items=Array.isArray(data.lineItems)?data.lineItems:[];
  const {data:mappings,error:mappingError}=await caller.from("play_products").select().eq("active",true);if(mappingError)return response(503,"Products unavailable");
  const item=items.find((i:{productId:string;offerDetails?:{basePlanId?:string};expiryTime?:string})=>
    mappings?.some(m=>m.product_id===i.productId&&m.base_plan_id===i.offerDetails?.basePlanId)&&Date.parse(i.expiryTime??"")>Date.now());
  if(!item)return response(403,"Product not mapped");
  const {error:activated}=await admin.rpc("activate_play_purchase",{user_id:user.id,token_hash:await sha256(purchase),product_id:item.productId,base_plan_id:item.offerDetails.basePlanId,verified_ends_at:item.expiryTime});
  if(activated)return response(409,"Purchase could not be applied");
  if(data.acknowledgementState!=="ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED"){
   const acknowledged=await fetch(base+"/purchases/subscriptions/"+encodeURIComponent(item.productId)+"/tokens/"+encodeURIComponent(purchase)+":acknowledge",{method:"POST",headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},body:"{}"});
   if(!acknowledged.ok)return response(503,"Plan applied; purchase acknowledgement will retry");
  }
  return response(200,"Purchase verified");
 }
 return response(400,"Unknown operation");
 }catch{return response(503,"Google Play setup is not ready. Please try again later");}
});
