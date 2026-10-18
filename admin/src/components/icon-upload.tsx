"use client";
import {useState} from "react";
import {createBrowserClient} from "@supabase/ssr";
import {Field,Input} from "./ui";
export default function IconUpload({initial,userId}:{initial:string;userId:string}){
 const [url,setUrl]=useState(initial),[busy,setBusy]=useState(false),[error,setError]=useState("");
 async function upload(file:File){setBusy(true);setError("");try{if(!["image/jpeg","image/png","image/webp"].includes(file.type)||file.size>=5242880)throw new Error("Use a JPG, PNG or WebP image under 5 MB.");
 const client=createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!);const key=userId+"/icons/"+crypto.randomUUID();const {error}=await client.storage.from("channel-icons").upload(key,file);if(error)throw error;setUrl(client.storage.from("public").getPublicUrl(key).data.publicUrl);
 }catch(e){setError(e instanceof Error?e.message:"Upload failed");}finally{setBusy(false)}}
 return <Field label="Channel icon" hint="JPG, PNG or WebP · under 5 MB"><input type="hidden" name="icon_url" value={url}/>{url&&<div className="h-16 w-16 overflow-hidden rounded-xl border border-gray-200" style={{backgroundImage:"url("+JSON.stringify(url)+")",backgroundSize:"cover",backgroundPosition:"center"}} role="img" aria-label="Channel icon preview"/>}<Input type="file" accept="image/jpeg,image/png,image/webp" disabled={busy} onChange={e=>{if(e.target.files?.[0])void upload(e.target.files[0])}}/>{busy&&<progress className="w-full accent-red-700" aria-label="Uploading icon"/>}<p role="status" className="text-xs text-red-700">{busy?"Uploading icon…":error}</p></Field>;
}