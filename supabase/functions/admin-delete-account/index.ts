import {createClient} from "npm:@supabase/supabase-js@2.118.0";
Deno.serve(async(req:Request)=>{
 const headers={"Content-Type":"application/json"};
 const reply=(status:number,error:string)=>new Response(JSON.stringify({error}),{status,headers});
 if(req.method!=="POST")return reply(405,"POST required");
 try{
 const token=req.headers.get("Authorization")?.replace(/^Bearer /i,"");if(!token)return reply(401,"Authentication required");
 const client=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error}=await client.auth.getUser(token);if(error||!user||user.is_anonymous)return reply(401,"Member required");
 const {data:admin}=await client.from("admins").select("role").eq("user_id",user.id).single();if(admin?.role!=="owner")return reply(403,"Owner required");
 const body=await req.json();if(body.confirm!==true||typeof body.request_id!=="string")return reply(400,"Confirmed deletion request required");
 const {data:request,error:requestError}=await client.from("support_requests").select("*").eq("id",body.request_id).eq("status","open").single();
 if(requestError||!request?.user_id||!["deletion","account_deletion","delete_account"].includes(request.kind))return reply(400,"Open account deletion request required");
 const target=request.user_id;
 const {data:targetAdmin}=await client.from("admins").select("user_id").eq("user_id",target).maybeSingle();if(targetAdmin||target===user.id)return reply(400,"Administrator accounts cannot be deleted here");
 const {data:channels,error:channelError}=await client.from("channels").select("id").eq("created_by",target);if(channelError)throw channelError;
 const ids=(channels??[]).map(c=>c.id);
 let query=client.from("posts").select("post_items(media_key,trailer_key,thumbnail_key)").eq("created_by",target);
 if(ids.length)query=client.from("posts").select("post_items(media_key,trailer_key,thumbnail_key)").or("created_by.eq."+target+",channel_id.in.("+ids.join(",")+")");
 const {data:posts,error:postError}=await query;if(postError)throw postError;
 for(const post of posts??[])for(const item of post.post_items??[]){
 const keys=[item.media_key,item.trailer_key].filter(Boolean) as string[];
 if(keys.length){const {error}=await client.storage.from("media").remove(keys);if(error)throw error}
 if(item.thumbnail_key){const {error}=await client.storage.from("public").remove([item.thumbnail_key]);if(error)throw error}
 }
 async function clear(bucket:string,prefix:string):Promise<void>{
 while(true){const {data,error}=await client.storage.from(bucket).list(prefix,{limit:100});if(error)throw error;if(!data?.length)return;
 for(const item of data){const path=prefix+"/"+item.name;if(item.id){const {error}=await client.storage.from(bucket).remove([path]);if(error)throw error}else await clear(bucket,path)}}
 }
 for(const bucket of ["cloud","media","public"])await clear(bucket,target);
 const removedPosts=await client.from("posts").delete().eq("created_by",target);if(removedPosts.error)throw removedPosts.error;
 const removedChannels=await client.from("channels").delete().eq("created_by",target);if(removedChannels.error)throw removedChannels.error;
 const deleted=await client.auth.admin.deleteUser(target);if(deleted.error)throw deleted.error;
 const closed=await client.from("support_requests").update({status:"closed"}).eq("id",request.id);if(closed.error)throw closed.error;
 const audit=await client.from("audit_logs").insert({actor_id:user.id,action:"requested_account_deleted",target_id:target});if(audit.error)throw audit.error;
 return new Response(JSON.stringify({deleted:true}),{headers});
 }catch{return reply(500,"Deletion could not finish. Review the request before retrying.")}
});
