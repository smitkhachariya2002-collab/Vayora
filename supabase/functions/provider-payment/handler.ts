export function providerHandler(secret: () => string | undefined, apply: (value: Record<string, unknown>) => Promise<void>) {
 return async (req: Request): Promise<Response> => {
  const reply=(status:number,message:string)=>new Response(JSON.stringify({message}),{status,headers:{"Content-Type":"application/json"}});
  if(req.method!=="POST")return reply(405,"POST required");
  const keyValue=secret();if(!keyValue)return reply(503,"Provider webhook not configured");
  const timestamp=Number(req.headers.get("X-Provider-Timestamp"));
  if(!Number.isFinite(timestamp)||Math.abs(Date.now()/1000-timestamp)>300)return reply(401,"Invalid timestamp");
  const raw=await req.text();if(new TextEncoder().encode(raw).length>8192)return reply(413,"Payload too large");
  const supplied=req.headers.get("X-Provider-Signature")??"";
  if(!/^sha256=[0-9a-fA-F]{64}$/.test(supplied))return reply(401,"Invalid signature");
  const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(keyValue),{name:"HMAC",hash:"SHA-256"},false,["verify"]);
  const bytes=new Uint8Array(supplied.slice(7).match(/../g)!.map(x=>parseInt(x,16)));
  if(!await crypto.subtle.verify("HMAC",key,bytes,new TextEncoder().encode(raw)))return reply(401,"Invalid signature");
  let value;
  try{value=JSON.parse(raw);}catch{return reply(400,"Invalid JSON");}
  if(!value||typeof value.order_id!=="string"||!/^[0-9a-f-]{36}$/i.test(value.order_id)||
   !["SUCCESS","PAID","FAILURE","FAILED","PENDING"].includes(value.status)||
   !Number.isSafeInteger(value.amount_paise)||value.amount_paise<1||
   typeof value.utr!=="string"||!/^[A-Za-z0-9]{6,40}$/.test(value.utr)||
   typeof value.provider_ref!=="string"||value.provider_ref.length>200)return reply(400,"Invalid payment");
  try{await apply(value);return reply(200,"Payment update accepted");}
  catch{return reply(409,"Payment update could not be applied");}
 };
}
