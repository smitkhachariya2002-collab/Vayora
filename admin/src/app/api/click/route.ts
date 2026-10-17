import {createClient} from "@supabase/supabase-js";
export async function POST(req:Request){
 const origin=req.headers.get("origin");
 if(origin!==new URL(req.url).origin)return Response.json({error:"Origin denied"},{status:403});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)return Response.json({error:"Click tracking is not configured"},{status:503});
 if(Number(req.headers.get("content-length")??0)>4096)return new Response(null,{status:413});
 try{
 const raw=await req.text();if(raw.length>4096)return new Response(null,{status:413});
 const body=JSON.parse(raw);if(body.consent!==true)return new Response(null,{status:400});
 const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const {error}=await client.rpc("record_ad_click",{fbclid:String(body.fbclid??""),fbp:String(body.fbp??""),
 client_ip:(req.headers.get("x-vercel-forwarded-for")??req.headers.get("x-forwarded-for")??"").split(",")[0].trim(),
 user_agent:req.headers.get("user-agent")??"",campaign:String(body.campaign??"")});
 return Response.json({ok:!error},{status:error?400:200});
 }catch{return Response.json({error:"Invalid click"},{status:400});}
}
