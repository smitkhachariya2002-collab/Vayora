"use client";
import { useEffect, useRef, useState } from "react";
import { probe } from "../[id]/MediaEditor";

function useObjectUrl(blob?: Blob | null) {
  const [url, setUrl] = useState<string>();
  useEffect(() => {
    if (!blob) { setUrl(undefined); return; }
    const next = URL.createObjectURL(blob);
    setUrl(next);
    return () => URL.revokeObjectURL(next);
  }, [blob]);
  return url;
}

/** Local previews never upload files; object URLs are released when a batch is cleared. */
export default function BulkMediaPreview({ file, thumbnail, trailer, video }: { file: File; thumbnail?: File; trailer?: File; video: boolean }) {
  const container = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  const [frame, setFrame] = useState<Blob | null>(null);
  const [probing, setProbing] = useState(false);
  useEffect(() => {
    const node = container.current;
    if (!node) return;
    if (typeof IntersectionObserver === "undefined") { setVisible(true); return; }
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) { setVisible(true); observer.disconnect(); }
    }, { rootMargin: "200px" });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  useEffect(() => {
    if (!visible || !video || thumbnail) return;
    let active = true;
    setProbing(true);
    probe(file).then(info => { if (active) setFrame(info.thumb); })
      .catch(() => { if (active) setFrame(null); })
      .finally(() => { if (active) setProbing(false); });
    return () => { active = false; };
  }, [file, thumbnail, video, visible]);
  const source = useObjectUrl(visible ? file : null);
  const poster = useObjectUrl(thumbnail ?? (video ? frame : visible ? file : null));
  const preview = useObjectUrl(trailer);
  return <div ref={container} className="grid gap-3 sm:grid-cols-[160px_1fr]">
    <figure>
      <div className="flex aspect-video items-center justify-center overflow-hidden rounded-lg bg-gray-100 text-center text-xs text-gray-500">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        {poster ? <img src={poster} alt={`Thumbnail for ${file.name}`} className="h-full w-full object-cover" /> : <span className="p-3">{probing ? "Generating thumbnail…" : "No thumbnail available. Choose a thumbnail below."}</span>}
      </div>
      <figcaption className="mt-1 text-xs text-gray-500">{thumbnail ? "Custom thumbnail" : "Automatic thumbnail"}</figcaption>
    </figure>
    <div className="min-w-0 space-y-2">
      <details className="rounded-lg border p-2" onToggle={event => { if (!event.currentTarget.open) event.currentTarget.querySelector("video")?.pause(); }}>
        <summary className="cursor-pointer text-sm font-medium">{video ? "Preview main video" : "Preview image"}</summary>
        {source && (video ? <video controls playsInline preload="none" src={source} poster={poster} aria-label={`Main video: ${file.name}`} className="mt-2 max-h-80 w-full rounded-lg bg-black" /> :
          /* eslint-disable-next-line @next/next/no-img-element */
          <img src={source} alt={file.name} className="mt-2 max-h-80 max-w-full rounded-lg object-contain" />)}
      </details>
      {preview && <details className="rounded-lg border p-2" onToggle={event => { if (!event.currentTarget.open) event.currentTarget.querySelector("video")?.pause(); }}>
        <summary className="cursor-pointer text-sm font-medium">Preview selected trailer</summary>
        <video controls playsInline preload="none" src={preview} aria-label={`Trailer: ${trailer?.name}`} className="mt-2 max-h-80 w-full rounded-lg bg-black" />
      </details>}
    </div>
  </div>;
}
