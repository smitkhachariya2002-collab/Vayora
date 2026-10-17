import { providerHandler } from "./handler.ts";
const value={order_id:"10000000-0000-4000-8000-000000000001",status:"SUCCESS",amount_paise:100,utr:"123456789012",provider_ref:"bank-1"};
async function request(body=JSON.stringify(value),secret="test-secret",timestamp=String(Math.floor(Date.now()/1000))){
 const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
 const signature=Array.from(new Uint8Array(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(body)))).map(x=>x.toString(16).padStart(2,"0")).join("");
 return new Request("http://localhost",{method:"POST",body,headers:{"X-Provider-Timestamp":timestamp,"X-Provider-Signature":"sha256="+signature}});
}
Deno.test("provider authenticates raw body; disabled, stale, tampered and malformed requests fail",async()=>{
 let calls=0;const handler=providerHandler(()=>"test-secret",async()=>{calls++;});
 const check=(actual:number,expected:number)=>{if(actual!==expected)throw Error(actual+" != "+expected);};
 check((await providerHandler(()=>undefined,async()=>{})(await request())).status,503);
 check((await handler(await request())).status,200);
 check((await handler(await request(JSON.stringify(value),"wrong-secret"))).status,401);
 check((await handler(await request(JSON.stringify(value),"test-secret","1"))).status,401);
 check((await handler(await request("{}"))).status,400);
 check(calls,1);
});
