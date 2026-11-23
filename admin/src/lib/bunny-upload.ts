"use client";
import {supabaseBrowser} from './supabase/client';

/** Upload one existing media item using 32 MiB resumable TUS chunks. */
export async function uploadBunnyVideo(itemId:string,file:File,onProgress:(percent:number)=>void,slot:'main'|'trailer'='main'):Promise<boolean> {
 const sb=supabaseBrowser();
 const {data,error}=await sb.functions.invoke('bunny-stream-create',{body:{item_id:itemId,slot,title:file.name,size:file.size}});
 if(error) {
  const context=(error as {context?:Response}).context;
  const body=context?await context.clone().json().catch(()=>null):null;
  if(body?.code==='NOT_CONFIGURED')return false;
  throw new Error(body?.error??error.message);
 }
 if(data.completed){onProgress(100);return true;}
 const headers={...data.headers,'Tus-Resumable':'1.0.0'} as Record<string,string>;
 const key=`vayora-tus-${itemId}-${slot}-${file.size}-${file.lastModified}-${encodeURIComponent(file.name)}`;
 let location:string|null=null;
 try {location=localStorage.getItem(key);} catch {/* Persistence may be disabled. */}
 const allowed=(value:string)=>{const u=new URL(value,data.endpoint);if(u.origin!=='https://video.bunnycdn.com'||!u.pathname.startsWith('/tusupload'))throw new Error('Unexpected upload destination');return u.toString();};
 let offset=0;
 if(location) {
  location=allowed(location);
  const check=await fetch(location,{method:'HEAD',headers});
  if(check.ok)offset=Number(check.headers.get('Upload-Offset'));else location=null;
 }
 if(!location) {
  const encode=(s:string)=>btoa(String.fromCharCode(...new TextEncoder().encode(s)));
  const response=await fetch(data.endpoint,{method:'POST',headers:{...headers,'Upload-Length':String(file.size),'Upload-Metadata':`filetype ${encode(file.type||'video/mp4')},title ${encode(file.name.slice(0,160))}`}});
  const target=response.headers.get('Location');if(!response.ok||!target)throw new Error(`Could not start video upload (${response.status})`);
  location=allowed(target);try{localStorage.setItem(key,location);}catch{/* Continue without resume persistence. */}
 }
 if(!Number.isSafeInteger(offset)||offset<0||offset>file.size)throw new Error('Invalid upload position');
 let retries=0;
 while(offset<file.size) {
  const end=Math.min(file.size,offset+32*1024*1024),start=offset;
  try {
   const next=await new Promise<number>((resolve,reject)=>{
    const xhr=new XMLHttpRequest();xhr.open('PATCH',location!);xhr.timeout=180000;
    for(const [name,value]of Object.entries({...headers,'Content-Type':'application/offset+octet-stream','Upload-Offset':String(start)}))xhr.setRequestHeader(name,value);
    xhr.upload.onprogress=e=>{if(e.lengthComputable)onProgress(Math.min(99,Math.round((start+e.loaded)/file.size*100)));};
    xhr.onload=()=>xhr.status===204?resolve(Number(xhr.getResponseHeader('Upload-Offset'))):reject(new Error(`Video upload interrupted (${xhr.status})`));
    xhr.onerror=()=>reject(new Error('Connection interrupted'));xhr.ontimeout=()=>reject(new Error('Upload timed out'));xhr.send(file.slice(start,end));
   });
   if(next!==end)throw new Error('Unexpected upload position');offset=next;retries=0;
  }catch(e) {
   if(++retries>3)throw e;
   await new Promise(resolve=>setTimeout(resolve,500*2**retries));
   const check=await fetch(location,{method:'HEAD',headers});if(!check.ok)throw e;
   const next=Number(check.headers.get('Upload-Offset'));if(!Number.isSafeInteger(next)||next<start||next>file.size)throw e;offset=next;
  }
 }
 onProgress(100);return true;
}
