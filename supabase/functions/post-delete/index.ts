import {createClient} from "npm:@supabase/supabase-js@2.118.0";
const headers={"Content-Type":"application/json"};
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return new Response('{"error":"POST required"}',{status:405,headers});
 const token=req.headers.get("Authorization")?.replace(/^Bearer /i,"");if(!token)return new Response('{"error":"Authentication required"}',{status:401,headers});
 try{
 const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error}=await admin.auth.getUser(token);
 if(error||!user||user.is_anonymous)return new Response('{"error":"Member required"}',{status:401,headers});
 const caller=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:"Bearer "+token}}});
 const body=await req.json();
 const {data:target,error:denied}=await caller.rpc("prepare_post_delete",{post_id:body.post_id});
 if(denied)throw denied;
 for(const bucket of ["media","public"]){
 const keys=target.files.filter((f:{bucket:string;key:string})=>f.bucket===bucket).map((f:{key:string})=>f.key);
 for(let i=0;i<keys.length;i+=100){const removed=await admin.storage.from(bucket).remove(keys.slice(i,i+100));if(removed.error)throw removed.error;}
 }
 const result=await admin.rpc("finish_post_delete",{post_id:target.id});if(result.error)throw result.error;
 return new Response('{"deleted":true}',{headers});
 }catch{return new Response('{"error":"Could not finish deletion. Please retry."}',{status:409,headers});}
});
