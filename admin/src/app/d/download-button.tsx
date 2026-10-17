"use client";
import {useState} from "react";
type Pixel=((...args:unknown[])=>void)&{queue?:unknown[][];callMethod?:(...args:unknown[])=>void;push?:Pixel;loaded?:boolean;version?:string};
declare global{interface Window{fbq?:Pixel;_fbq?:Pixel}}
export default function DownloadButton({url,pixel}:{url:string;pixel:string}){
 const [consent,setConsent]=useState(false);
 async function download(){
  if(consent){
   if(/^[0-9]+$/.test(pixel)&&!window.fbq){
    const fbq:Pixel=(...args)=>{if(fbq.callMethod)fbq.callMethod(...args);else fbq.queue?.push(args);};
    fbq.queue=[];fbq.push=fbq;fbq.loaded=true;fbq.version="2.0";window.fbq=fbq;window._fbq=fbq;
    const script=document.createElement("script");script.async=true;script.src="https://connect.facebook.net/en_US/fbevents.js";document.head.append(script);
    fbq("init",pixel);fbq("track","PageView");fbq("track","ViewContent",{content_name:"Vayora Android download"});
   }
   const q=new URLSearchParams(location.search),fbp=document.cookie.split("; ").find(s=>s.startsWith("_fbp="))?.slice(5)??"";
   await fetch("/api/click",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({consent:true,fbclid:q.get("fbclid"),campaign:q.get("utm_campaign"),fbp}),keepalive:true}).catch(()=>{});
  }
  location.assign(url);
 }
 return <><label className="mb-5 flex items-start gap-2 text-sm text-gray-500"><input type="checkbox" checked={consent} onChange={e=>setConsent(e.target.checked)}/>Allow optional Meta advertising measurement for this download.</label>
 <button onClick={()=>void download()} className="min-h-12 rounded-xl bg-orange-600 px-6 py-3 font-semibold text-white">Download Android app</button></>;
}
