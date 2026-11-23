"use client";
import { useEffect, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

/** Fetch a signed URL only when the admin asks to preview the saved file. */
export default function SavedMediaPreview({ storageKey, label, mime, poster, itemId, trailer=false }: { storageKey: string; label: string; mime: string; poster?: string; itemId?:string; trailer?:boolean }) {
  const [url, setUrl] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const pending = useRef(false);
  const player = useRef<HTMLVideoElement>(null);
  useEffect(()=>{
    if(!url.includes('.m3u8')||!player.current)return;
    if(player.current.canPlayType('application/vnd.apple.mpegurl')){player.current.src=url;return;}
    let cancelled=false;let cleanup:(()=>void)|undefined;
    void import('hls.js').then(({default:Hls})=>{
      if(cancelled||!player.current)return;
      if(!Hls.isSupported()){setError('HLS playback is unavailable in this browser.');return;}
      const hls=new Hls();hls.loadSource(url);hls.attachMedia(player.current);cleanup=()=>hls.destroy();
      hls.on(Hls.Events.ERROR,(_event,data)=>{if(data.fatal)setError('Video preview could not load. Retry once encoding finishes.');});
    }).catch(()=>setError('Could not load the video player.'));
    return()=>{cancelled=true;cleanup?.();};
  },[url]);
  const load = async () => {
    if (pending.current) return;
    pending.current = true; setLoading(true); setError("");
    try {
      if(itemId&&storageKey.includes('/bunny/')) {
        const {data,error}=await supabaseBrowser().functions.invoke('bunny-stream-url',{body:{item_id:itemId,preview:trailer}});
        if(error||!data?.url)throw Error('Video is processing or unavailable. Retry after encoding finishes.');
        setUrl(data.url);return;
      }
      const { data, error: signingError } = await supabaseBrowser().storage.from("media").createSignedUrl(storageKey, 3600);
      if (signingError || !data?.signedUrl) throw new Error(signingError?.message ?? "Could not load preview.");
      setUrl(data.signedUrl);
    } catch (e) { setError(e instanceof Error ? e.message : "Could not load preview."); }
    finally { pending.current = false; setLoading(false); }
  };
  return <details className="mt-2 rounded-lg border p-2" onToggle={event => {
    if (event.currentTarget.open) { if (!url) void load(); }
    else player.current?.pause();
  }}>
    <summary className="cursor-pointer text-sm font-medium">{label}</summary>
    {loading && <p role="status" className="mt-2 text-xs">Loading preview…</p>}
    {url && (mime.startsWith("video") ? <video ref={player} controls playsInline preload="metadata" src={url.includes('.m3u8')?undefined:url} onLoadedMetadata={()=>setError('')} poster={poster} aria-label={label} onError={() => setError("This browser could not play the file. Try another browser or replace the video.")} className="mt-2 max-h-96 w-full rounded-lg bg-black" /> :
      /* eslint-disable-next-line @next/next/no-img-element */
      <img src={url} alt={label} className="mt-2 max-h-96 max-w-full rounded-lg object-contain" />)}
    {error && <div className="mt-2 text-xs text-red-700" role="alert">{error} <button type="button" className="underline" disabled={loading} onClick={() => void load()}>Retry preview</button></div>}
  </details>;
}
