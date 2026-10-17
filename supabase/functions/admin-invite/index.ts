import {createClient} from "npm:@supabase/supabase-js@2.118.0";
Deno.serve(async(req:Request)=>{
 const headers={"Content-Type":"application/json"};
 const reply=(status:number,message:string)=>new Response(JSON.stringify({error:message}),{status,headers});
 if(req.method!=="POST")return reply(405,"POST required");
 try{
 const token=req.headers.get("Authorization")?.replace(/^Bearer /i,"");if(!token)return reply(401,"Authentication required");
 const c=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error}=await c.auth.getUser(token);if(error||!user||user.is_anonymous)return reply(401,"Member required");
 const {data:actor}=await c.from("admins").select("role").eq("user_id",user.id).single();if(actor?.role!=="owner")return reply(403,"Owner required");
 const b=await req.json();if(typeof b.email!=="string"||b.email.length>254||!b.email.includes("@")||!["owner","content"].includes(b.role)||!Array.isArray(b.channel_ids)||b.channel_ids.some((id:unknown)=>typeof id!=="string"||!/^[0-9a-f-]{36}$/i.test(id)))return reply(400,"Valid email, role and channels required");
 if(b.channel_ids.length){const {data,error}=await c.from("channels").select("id").in("id",b.channel_ids);if(error||data?.length!==new Set(b.channel_ids).size)return reply(400,"Unknown channel");}
 const invited=await c.auth.admin.inviteUserByEmail(b.email.trim(),{redirectTo:"https://vayora-eta.vercel.app/invite"});
 if(invited.error||!invited.data.user)return reply(400,"Could not send invitation. Existing users must confirm their email before being granted access.");
 const id=invited.data.user.id;
 const saved=await c.from("admins").insert({user_id:id,role:b.role});if(saved.error)throw saved.error;
 if(b.channel_ids.length){const grants=await c.from("admin_channel_access").insert(b.channel_ids.map((channel_id:string)=>({user_id:id,channel_id})));if(grants.error)throw grants.error;}
 const audit=await c.from("audit_logs").insert({actor_id:user.id,action:"admin_invited",target_id:id});if(audit.error)throw audit.error;
 return new Response(JSON.stringify({invited:true}),{headers});
 }catch{return reply(500,"Invitation could not finish. Review the administrator list before retrying.")}
});
