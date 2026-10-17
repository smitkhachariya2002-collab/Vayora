const encoder=new TextEncoder();
export function base64url(bytes:Uint8Array):string{return btoa(String.fromCharCode(...bytes)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");}
export async function sha256(value:string):Promise<string>{
 return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",encoder.encode(value)))).map(x=>x.toString(16).padStart(2,"0")).join("");
}
export async function googleToken(scope:string):Promise<string>{
 const credentials=JSON.parse(Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT")??"{}");
 if(!credentials.client_email||!credentials.private_key)throw new Error("Google service account is not configured");
 const now=Math.floor(Date.now()/1000);
 const header=base64url(encoder.encode(JSON.stringify({alg:"RS256",typ:"JWT"})));
 const payload=base64url(encoder.encode(JSON.stringify({iss:credentials.client_email,scope,aud:"https://oauth2.googleapis.com/token",iat:now,exp:now+3600})));
 const pem=String(credentials.private_key).replace(/-----[^-]+-----/g,"").replace(/\s/g,"");
 const key=await crypto.subtle.importKey("pkcs8",Uint8Array.from(atob(pem),c=>c.charCodeAt(0)),{name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"},false,["sign"]);
 const signature=base64url(new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5",key,encoder.encode(header+"."+payload))));
 const result=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},
 body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion:header+"."+payload+"."+signature})});
 if(!result.ok)throw new Error("Google authorization failed");
 const body=await result.json();if(typeof body.access_token!=="string")throw new Error("Google authorization failed");return body.access_token;
}
