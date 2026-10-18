import {createClient} from "npm:@supabase/supabase-js@2.118.0";
const headers={"Content-Type":"application/json"};
function reply(status:number,message:string){return new Response(JSON.stringify({message}),{status,headers});}
function constantTime(a:string,b:string){if(a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0;}
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return reply(405,"POST required");
 if(Deno.env.get("UPI_WEBHOOK_ENABLED")!=="true")return reply(503,"Webhook disabled");
 const secret=Deno.env.get("UPI_WEBHOOK_SECRET");if(!secret)return reply(503,"Webhook not configured");
 const timestamp=req.headers.get("x-vayora-timestamp")??"",signature=req.headers.get("x-vayora-signature")??"";
 const when=Number(timestamp);if(!Number.isFinite(when)||Math.abs(Date.now()/1000-when)>300)return reply(401,"Invalid timestamp");
 const raw=await req.text();if(raw.length>8192)return reply(413,"Payload too large");
 const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
 const digest=await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(timestamp+"."+raw));
 const expected=Array.from(new Uint8Array(digest)).map(b=>b.toString(16).padStart(2,"0")).join("");
 if(!constantTime(expected,signature.toLowerCase()))return reply(401,"Invalid signature");
 try{
 const value=JSON.parse(raw);
 if(typeof value.reference!=="string"||!/^VY[0-9A-Za-z]+$/.test(value.reference)||!Number.isSafeInteger(value.amount_paise)||value.amount_paise<=0||typeof value.utr!=="string"||!/^[A-Za-z0-9]{6,40}$/.test(value.utr))return reply(400,"Invalid payment");
 const db=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {error}=await db.rpc("provider_activate_payment",{reference:value.reference,amount_paise:value.amount_paise,utr:value.utr});
 if(error)return reply(409,"Payment could not be activated");
 return reply(200,"Payment accepted");
 }catch{return reply(400,"Invalid payload");}
});
