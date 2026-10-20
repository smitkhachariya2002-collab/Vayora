export type DeletionRequest = {email:string; details:string};
export type RequestStore = {record:(input:DeletionRequest)=>Promise<string>};
const cors = {"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"apikey, authorization, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Cache-Control":"no-store"};
export function deletionHandler(store:RequestStore) {
  return async (request:Request):Promise<Response> => {
    const reply=(status:number,data:unknown)=>new Response(JSON.stringify(data),{status,headers:{...cors,"Content-Type":"application/json"}});
    if(request.method==="OPTIONS") return new Response(null,{status:204,headers:cors});
    if(request.method!=="POST") return reply(405,{error:"POST required."});
    try {
      if(Number(request.headers.get("content-length")||0)>8192) return reply(413,{error:"Request too large."});
      const raw=await request.text();
      if(raw.length>4096) return reply(413,{error:"Request too large."});
      let body;
      try {body=JSON.parse(raw);} catch {return reply(400,{error:"Invalid request."});}
      if(!body || typeof body!=="object" || Array.isArray(body)) return reply(400,{error:"Invalid request."});
      const email=typeof body.email==="string"?body.email.trim().toLowerCase():"";
      const details=typeof body.details==="string"?body.details.trim():"";
      if(email.length>254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || details.length>1000 || body.consent!==true || (body.website && body.website!=="")) return reply(400,{error:"Enter your account email, leave the website field empty and confirm the deletion request."});
      const reference=await store.record({email,details});
      return reply(200,{reference,message:"Request recorded. Ownership must be verified before deletion."});
    } catch {
      return reply(503,{error:"Request could not be recorded. Please email help.vayora@gmail.com."});
    }
  };
}
