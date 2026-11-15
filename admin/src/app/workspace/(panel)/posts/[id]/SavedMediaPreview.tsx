"use client";
import { useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

/** Fetch a signed URL only when the admin asks to preview the saved file. */
export default function SavedMediaPreview({ storageKey, label, mime, poster }: { storageKey: string; label: string; mime: string; poster?: string }) {
  const [url, setUrl] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const pending = useRef(false);
  const player = useRef<HTMLVideoElement>(null);
  const load = async () => {
    if (pending.current) return;
    pending.current = true; setLoading(true); setError("");
    try {
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
    {url && (mime.startsWith("video") ? <video ref={player} controls playsInline preload="metadata" src={url} poster={poster} aria-label={label} onError={() => setError("This browser could not play the file. Try another browser or replace the video.")} className="mt-2 max-h-96 w-full rounded-lg bg-black" /> :
      /* eslint-disable-next-line @next/next/no-img-element */
      <img src={url} alt={label} className="mt-2 max-h-96 max-w-full rounded-lg object-contain" />)}
    {error && <div className="mt-2 text-xs text-red-700" role="alert">{error} <button type="button" className="underline" disabled={loading} onClick={() => void load()}>Retry preview</button></div>}
  </details>;
}
