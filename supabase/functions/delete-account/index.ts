import { createClient } from "npm:@supabase/supabase-js@2.118.0";

Deno.serve(async (req: Request) => {
  const headers = {"Content-Type":"application/json"};
  if (req.method !== "POST") return new Response('{"error":"POST required"}',{status:405,headers});
  try {
    const token = req.headers.get("Authorization")?.replace(/^Bearer /i,"");
    if (!token) return new Response('{"error":"Authentication required"}',{status:401,headers});
    const body = await req.json();
    if (body.confirm !== true) return new Response('{"error":"Confirmation required"}',{status:400,headers});
    const admin = createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{
      auth:{persistSession:false,autoRefreshToken:false}
    });
    const {data:{user},error} = await admin.auth.getUser(token);
    if (error || !user || user.is_anonymous) return new Response('{"error":"Member account required"}',{status:401,headers});
    const caller = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:"Bearer "+token}}
    });
    const prepared = await caller.rpc("prepare_account_deletion");
    if (prepared.error) return new Response(JSON.stringify({error:prepared.error.message}),{status:409,headers});
    // Revoke refresh sessions first. Every call revalidates the access token with Auth.
    const signedOut = await admin.auth.admin.signOut(token,"global");
    if(signedOut.error)throw signedOut.error;
    const {data:channels,error:channelError}=await admin.from("channels").select("id").eq("created_by",user.id);
    if(channelError)throw channelError;
    const channelIds=(channels??[]).map(c=>c.id);
    let query=admin.from("posts").select("id,post_items(media_key,trailer_key,thumbnail_key)").eq("created_by",user.id);
    if(channelIds.length)query=admin.from("posts").select("id,post_items(media_key,trailer_key,thumbnail_key)")
      .or("created_by.eq."+user.id+",channel_id.in.("+channelIds.join(",")+")");
    const {data:posts,error:postError}=await query;
    if(postError)throw postError;
    for(const post of posts??[]){
      for(const item of post.post_items??[]){
        const keys=[item.media_key,item.trailer_key].filter(Boolean) as string[];
        if(keys.length){const result=await admin.storage.from("media").remove(keys);if(result.error)throw result.error;}
        if(item.thumbnail_key){const result=await admin.storage.from("public").remove([item.thumbnail_key]);if(result.error)throw result.error;}
      }
    }
    async function clearPrefix(bucket:string,prefix:string):Promise<void>{
      while(true){
        const {data,error}=await admin.storage.from(bucket).list(prefix,{limit:100});
        if(error)throw error;
        if(!data?.length)return;
        for(const item of data){
          const path=prefix+"/"+item.name;
          if(item.id){const removed=await admin.storage.from(bucket).remove([path]);if(removed.error)throw removed.error;}
          else await clearPrefix(bucket,path);
        }
      }
    }
    for(const bucket of ["cloud","media","public"])await clearPrefix(bucket,user.id);
    const removedPosts=await admin.from("posts").delete().eq("created_by",user.id);
    if(removedPosts.error)throw removedPosts.error;
    const removedChannels=await admin.from("channels").delete().eq("created_by",user.id);
    if(removedChannels.error)throw removedChannels.error;
    const deleted=await admin.auth.admin.deleteUser(user.id);
    if(deleted.error)throw deleted.error;
    return new Response('{"deleted":true}',{headers});
  }catch{
    return new Response('{"error":"Deletion could not finish. Contact help.vayora@gmail.com before retrying."}',{status:500,headers});
  }
});
