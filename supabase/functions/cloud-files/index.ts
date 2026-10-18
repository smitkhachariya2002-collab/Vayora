import {createClient} from "npm:@supabase/supabase-js@2.118.0";
const headers={"Content-Type":"application/json"};
const reply=(status:number,message:string,data?:unknown)=>new Response(JSON.stringify({message,data}),{status,headers});
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return reply(405,"POST required");
 const token=req.headers.get("Authorization")?.replace(/^Bearer /i,"");if(!token)return reply(401,"Authentication required");
 const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error}=await admin.auth.getUser(token);
 if(error||!user||user.is_anonymous)return reply(401,"Member account required");
 const caller=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{
 auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:"Bearer "+token}}});
 try{
 if((req.headers.get("content-type")??"").startsWith("multipart/form-data")){
   const body=await req.formData(),file=body.get("file"),parent=body.get("parent_id");
   if(!(file instanceof File)||file.size>52428800)return reply(400,"50 MB maximum per file");
   const {data:entry,error:reserved}=await caller.rpc("cloud_reserve",{
     name:String(body.get("name")||file.name),parent_id:parent?String(parent):null,is_folder:false,mime:String(body.get("mime")||file.type||"application/octet-stream"),size:file.size}).single<{id:string;storage_key:string;mime:string}>();
   if(reserved||!entry)return reply(400,reserved?.message??"Reservation failed");

   try{
     const {error:stored}=await admin.storage.from("cloud").upload(entry.storage_key,await file.arrayBuffer(),{contentType:entry.mime,upsert:false});
     if(stored)throw stored;
     const {error:finished}=await admin.rpc("cloud_finish_upload",{user_id:user.id,entry_id:entry.id});
     if(finished)throw finished;
     return reply(200,"Uploaded",entry);
   }catch{
     // Never release counted quota while an object might still exist.
     const prepared=await caller.rpc("cloud_begin_delete",{entry_id:entry.id});
     if(!prepared.error){
       const cleaned=await admin.storage.from("cloud").remove([entry.storage_key]);
       if(!cleaned.error)await admin.rpc("cloud_finish_delete",{user_id:user.id,entry_id:entry.id,upload_finished:true});
     }
     return reply(409,"Upload could not finish. Retry or delete the incomplete entry.");
   }
 }
 const body=await req.json();
 if(body.operation!=="delete"||typeof body.entry_id!=="string")return reply(400,"Invalid action");
 const {data:deletion,error:begin}=await caller.rpc("cloud_begin_delete",{entry_id:body.entry_id});
 if(begin)return reply(400,begin.message);
 for(let i=0;i<deletion.keys.length;i+=100){
   const {error:removed}=await admin.storage.from("cloud").remove(deletion.keys.slice(i,i+100));if(removed)return reply(409,"Cleanup incomplete. Please retry deletion.");
 }
 const {error:finished}=await admin.rpc("cloud_finish_delete",{user_id:user.id,entry_id:body.entry_id});
 if(finished)return reply(409,"Cleanup incomplete. Please retry deletion.");
 return reply(200,"Deleted");
 }catch{return reply(400,"Could not complete the cloud operation");}
});
