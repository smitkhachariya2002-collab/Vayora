"use client";
import { createBrowserClient } from "@supabase/ssr";
import { useState } from "react";
import { useRouter } from "next/navigation";
export default function PostUploader({postId,creator}:{postId:string;creator:string}){
 const router=useRouter();
 const [main,setMain]=useState<File|null>(null),[trailer,setTrailer]=useState<File|null>(null),[thumbnail,setThumbnail]=useState<File|null>(null);
 const [premium,setPremium]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState("");
 async function upload(){
  if(!main)return;
  setBusy(true);setMessage("");
  const client=createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!);
  const uploaded:{bucket:string;key:string}[]=[];
  try{
   for(const file of [main,trailer,thumbnail])if(file&&file.size>52428800)throw new Error("50 MB maximum per file");
   const {data:{user}}=await client.auth.getUser();
   if(!user)throw new Error("Please sign in again");
   async function send(bucket:string,file:File,path:string){
    const {error}=await client.storage.from(bucket).upload(path,file,{contentType:file.type||"application/octet-stream"});
    if(error)throw error;uploaded.push({bucket,key:path});return path;
   }
   const prefix=creator+"/"+postId+"/";
   const key=await send("media",main,prefix+crypto.randomUUID());
   const trailerKey=trailer?await send("media",trailer,prefix+crypto.randomUUID()):null;
   const thumbnailKey=thumbnail?await send("public",thumbnail,user.id+"/"+crypto.randomUUID()):null;
   const {error}=await client.from("post_items").insert({post_id:postId,media_key:key,trailer_key:trailerKey,
    thumbnail_key:thumbnailKey,mime:main.type||"video/mp4",is_premium:premium});
   if(error)throw error;
   setMessage("Media added");setMain(null);setTrailer(null);setThumbnail(null);router.refresh();
  }catch(error){
   for(const object of uploaded)await client.storage.from(object.bucket).remove([object.key]);
   setMessage(error instanceof Error?error.message:"Upload failed");
  }finally{setBusy(false);}
 }
 return <div className="card"><h3>Add media</h3><p>Uploads go directly to private Supabase Storage.</p>
 <p><label>Main media<input type="file" accept="video/*,image/*" onChange={e=>setMain(e.target.files?.[0]??null)}/></label></p>
 <p><label>Trailer<input type="file" accept="video/*" onChange={e=>setTrailer(e.target.files?.[0]??null)}/></label></p>
 <p><label>Thumbnail<input type="file" accept="image/jpeg,image/png,image/webp" onChange={e=>setThumbnail(e.target.files?.[0]??null)}/></label></p>
 <label><input type="checkbox" checked={premium} onChange={e=>setPremium(e.target.checked)}/>Premium</label>
 <button type="button" disabled={busy||!main} onClick={upload}>{busy?"Uploading…":"Add media item"}</button><p role="status">{message}</p></div>;
}
