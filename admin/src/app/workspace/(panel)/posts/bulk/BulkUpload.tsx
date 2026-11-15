"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import BulkMediaPreview from "./BulkMediaPreview";
import { supabaseBrowser } from "@/lib/supabase/client";
import { upload, probe } from "../[id]/MediaEditor";

type Channel = { id: string; name: string; audience: string; review_status: string; status: string; hidden: boolean };
type Entry = { id: string; file?: File; thumbnail?: File; trailer?: File; title: string; description: string; state: "ready" | "uploading" | "done" | "error"; progress: number; error?: string; postId?: string; mediaDone?: boolean };
const audienceName = (value: string) => value === "ads" ? "Ads users" : value === "organic" ? "Organic users" : "Both ads and organic";
const mediaType = (file: File) => file.type || (/\.(mp4|m4v|mov|webm|mkv)$/i.test(file.name) ? "video/mp4" : /\.(png|jpg|jpeg|webp|gif)$/i.test(file.name) ? "image/" + (file.name.split(".").pop() === "jpg" ? "jpeg" : file.name.split(".").pop()) : "");

export default function BulkUpload({ channels, initialChannelId }: { channels: Channel[]; initialChannelId?: string }) {
  const [channelId, setChannelId] = useState(channels.some(c => c.id === initialChannelId) ? initialChannelId! : "");
  const [audience, setAudience] = useState("channel");
  const [publish, setPublish] = useState(true);
  const [premium, setPremium] = useState(false);
  const [entries, setEntries] = useState<Entry[]>([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const running = useRef(false);
  const stop = useRef(false);
  const channel = channels.find(c => c.id === channelId);
  const patch = (id: string, update: Partial<Entry>) => setEntries(rows => rows.map(row => row.id === id ? { ...row, ...update } : row));
  useEffect(() => {
    if (!busy) return;
    const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = ""; };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [busy]);

  const choose = (files: FileList | null) => {
    if (!files) return;
    const accepted: Entry[] = [];
    const invalid: string[] = [];
    for (const file of Array.from(files)) {
      if (!/^(video|image)\//.test(mediaType(file))) { invalid.push(file.name); continue; }
      accepted.push({ id: crypto.randomUUID(), file, title: file.name.replace(/\.[^.]+$/, "").slice(0, 160), description: "", state: "ready", progress: 0 });
    }
    setEntries(rows => [...rows, ...accepted]);
    setMessage(invalid.length ? `Skipped unsupported files: ${invalid.join(", ")}. Choose videos or images; use Add text post for written content.` : "");
  };

  const start = async () => {
    if (running.current || !channel) return;
    const pending = entries.filter(row => row.state !== "done");
    if (!pending.length) return;
    if (pending.some(row => !row.title.trim() || (!row.file && !row.description.trim()))) {
      setMessage("Give every post a title and add written content to text posts."); return;
    }
    running.current = true; stop.current = false; setBusy(true); setMessage("");
    const sb = supabaseBrowser();
    let succeeded = 0, failed = 0;
    try {
      const { data: allowed, error: permissionError } = await sb.rpc("can_manage_channel", { p_channel: channel.id });
      if (permissionError || !allowed) throw new Error("You no longer have permission to upload to this channel.");
      const selectedAudience = audience === "channel" ? channel.audience : audience;
      for (const row of pending) {
        if (stop.current) break;
        patch(row.id, { state: "uploading", progress: 0, error: undefined });
        let postId = row.postId;
        let mediaDone = row.mediaDone ?? false;
        let metadataAttempted = false;
        const filesToClean: string[] = [];
        try {
          if (!postId) {
            postId = crypto.randomUUID();
            patch(row.id, { postId });
          }
          const { data: existingPost, error: postLookupError } = await sb.from("posts").select("id").eq("id", postId).maybeSingle();
          if (postLookupError) throw new Error(postLookupError.message);
          if (!existingPost) {
            const { data, error } = await sb.from("posts").insert({ id: postId, channel_id: channel.id, title: row.title.trim(), description: row.description, audience: selectedAudience, status: "draft" }).select("id").single();
            if (error || !data) throw new Error(error?.message ?? "Could not create this post.");
          }
          if (row.file && !mediaDone) {
            const { data: existing, error: lookupError } = await sb.from("post_items").select("id").eq("post_id", postId).limit(1);
            if (lookupError) throw new Error(lookupError.message);
            if (existing?.length) { mediaDone = true; patch(row.id, { mediaDone: true }); }
          }
          if (row.file && !mediaDone) {
            const file = row.file;
            const mime = mediaType(file);
            const ext = file.name.split(".").pop()?.toLowerCase().replace(/[^a-z0-9]/g, "") || "bin";
            const key = `${channel.id}/${crypto.randomUUID()}.${ext}`;
            filesToClean.push(key);
            await upload(key, file, mime, percent => patch(row.id, { progress: percent }));
            let thumbnail: string | null = null;
            let duration: number | null = null;
            let thumb: Blob | null = row.thumbnail ?? null;
            const thumbnailMime = row.thumbnail?.type || 'image/jpeg';
            if (mime.startsWith("video/")) {
              const info = await probe(file); thumb ??= info.thumb; duration = info.duration;
            } else if (!thumb) {
              try {
                const image = await createImageBitmap(file);
                const canvas = document.createElement("canvas");
                canvas.width = Math.min(480, image.width);
                canvas.height = Math.max(1, Math.round(image.height * canvas.width / image.width));
                canvas.getContext("2d")!.drawImage(image, 0, 0, canvas.width, canvas.height); image.close();
                thumb = await new Promise<Blob | null>(resolve => canvas.toBlob(resolve, "image/jpeg", .75));
              } catch { /* A missing preview must not fail the original image. */ }
            }
            if (thumb) {
              const thumbExt = thumbnailMime === "image/png" ? "png" : thumbnailMime === "image/webp" ? "webp" : "jpg";
              thumbnail = `${channel.id}/${crypto.randomUUID()}.${thumbExt}`;
              filesToClean.push(thumbnail);
              await upload(thumbnail, thumb, thumbnailMime, () => {});
            }
            let trailerKey: string | null = null;
            if (row.trailer) {
              const trailerExt = row.trailer.name.split(".").pop()?.toLowerCase().replace(/[^a-z0-9]/g, "") || "mp4";
              trailerKey = `${channel.id}/${crypto.randomUUID()}.${trailerExt}`;
              filesToClean.push(trailerKey);
              await upload(trailerKey, row.trailer, mediaType(row.trailer), percent => patch(row.id, { progress: percent }));
            }
            metadataAttempted = true;
            const { error } = await sb.from("post_items").insert({ post_id: postId, media_key: key, thumbnail_key: thumbnail, trailer_key: trailerKey, mime, duration_s: duration, size_bytes: file.size, position: 0, is_premium: premium });
            if (error) throw new Error(error.message);
            mediaDone = true; patch(row.id, { mediaDone: true });
          }
          // Publish only after all media and metadata are saved. Failures remain drafts.
          const { data: saved, error } = await sb.from("posts").update({ title: row.title.trim(), description: row.description, audience: selectedAudience, status: publish ? "published" : "draft" }).eq("id", postId).select("id").single();
          if (error || !saved) throw new Error(error?.message ?? "Could not finish saving this post.");
          patch(row.id, { state: "done", progress: 100 }); succeeded++;
        } catch (error) {
          if (!mediaDone && !metadataAttempted && filesToClean.length) {
            const { error: cleanupError } = await sb.storage.from("media").remove(filesToClean);
            if (cleanupError) setMessage("Some incomplete uploaded files could not be cleaned up. Review drafts before removing any files manually.");
          }
          patch(row.id, { state: "error", error: error instanceof Error ? error.message : "Upload failed. Retry this item." }); failed++;
        }
      }
      setMessage(`${succeeded} saved, ${failed} failed.${stop.current ? " Paused after the current file." : ""} Published posts appear after the app refreshes, within the channelâ€™s audience.`);
    } catch (error) { setMessage(error instanceof Error ? error.message : "Could not start upload."); }
    finally { running.current = false; setBusy(false); }
  };

  const locked = busy || entries.some(row => row.postId);
  const cls = "w-full rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-sm text-slate-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-600/10 disabled:opacity-60";
  return <div className="space-y-5">
    <section className="rounded-2xl border border-slate-200 bg-white p-5 space-y-4 sm:p-6">
      <div><h2 className="text-base font-semibold text-slate-900">Choose your destination</h2><p className="mt-1 text-xs text-slate-500">Set the channel and audience once for this batch.</p></div>
      <label className="block text-sm font-medium">Channel<select className={cls} value={channelId} disabled={locked} onChange={e => setChannelId(e.target.value)}>
        <option value="">Choose a channel</option>{channels.map(c => <option key={c.id} value={c.id}>{c.name} Â· {audienceName(c.audience)}{c.review_status !== "approved" ? " Â· awaiting approval" : ""}</option>)}
      </select></label>
      {!channels.length && <p>No channels are available for your admin account.</p>}
      <label className="block text-sm font-medium">Post audience<select className={cls} value={audience} disabled={locked} onChange={e => setAudience(e.target.value)}>
        <option value="channel">Use channel audience</option><option value="all">Both ads and organic</option><option value="ads">Ads users</option><option value="organic">Organic users</option>
      </select></label>
      <p className="text-sm text-gray-600">Posts also respect the channelâ€™s audience. For example, a post in an ads-only channel stays restricted to ads users.</p>
      {channel && (channel.hidden || channel.review_status !== "approved" || !["published", "active"].includes(channel.status)) && <p role="status" className="text-amber-800">This channel is hidden, unapproved, or a draft. Uploads will not be visible to viewers until the channel is approved and published.</p>}
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={publish} disabled={locked} onChange={e => setPublish(e.target.checked)} />Publish posts after upload (uncheck to save drafts)</label>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={premium} disabled={locked} onChange={e => setPremium(e.target.checked)} />Premium media (full files require the existing Premium access)</label>
    </section>
    <div className="flex flex-wrap gap-3 items-center rounded-2xl border border-dashed border-blue-300 bg-blue-50/50 p-5">
      <label className="btn cursor-pointer">Select videos and images<input type="file" accept="video/*,image/*" multiple disabled={busy} className="sr-only" onChange={e => { choose(e.target.files); e.target.value = ""; }} /></label>
      <button type="button" className="rounded-lg border px-4 py-2" disabled={busy} onClick={() => setEntries(rows => [...rows, { id: crypto.randomUUID(), title: "", description: "", state: "ready", progress: 0 }])}>Add text post</button>
      <p className="text-sm text-gray-600">One post per file. Keep this page open until the batch finishes.</p>
    </div>
    {entries.length > 0 && <div className="flex flex-wrap items-center justify-between gap-2"><h2 className="text-base font-semibold text-slate-900">Upload queue <span className="ml-1 text-sm font-normal text-slate-400">{entries.length} items</span></h2><p className="text-xs text-slate-500">{entries.filter(row => row.state === "done").length} saved Â· {entries.filter(row => row.state === "error").length} need retry</p></div>}
    <div className="space-y-4">{entries.map(row => <article key={row.id} className="rounded-xl border bg-white p-4 space-y-2">
      <div className="flex flex-wrap justify-between gap-2"><span className="text-sm text-gray-600 break-all">{row.file ? `${row.file.name} Â· ${(row.file.size / 1048576).toFixed(1)} MB` : "Text post"}</span><span className="text-sm font-medium" role="status">{row.state === "uploading" ? `Uploading ${row.progress}%` : row.state === "done" ? publish ? "Published" : "Draft saved" : row.state === "error" ? "Needs retry" : "Ready"}</span></div>
      {row.file && <BulkMediaPreview file={row.file} thumbnail={row.thumbnail} trailer={row.trailer} video={mediaType(row.file).startsWith("video/")} />}
      <label className="block text-sm">Title<input className={cls} maxLength={160} value={row.title} disabled={busy || row.state === "done"} onChange={e => patch(row.id, { title: e.target.value })} /></label>
      <label className="block text-sm">{row.file ? "Description / content" : "Content"}<textarea className={cls} rows={3} value={row.description} disabled={busy || row.state === "done"} onChange={e => patch(row.id, { description: e.target.value })} /></label>
      {row.file && <div className="grid gap-3 sm:grid-cols-2">
        <label className="block text-sm">Thumbnail (optional)
          <input type="file" accept="image/jpeg,image/png,image/webp" disabled={busy || row.state === "done" || row.mediaDone} onChange={e => { patch(row.id, { thumbnail: e.target.files?.[0] }); e.target.value = ""; }} />
          <span className="block text-xs text-gray-500">{row.thumbnail?.name ?? "An automatic thumbnail is generated when no image is selected."}</span>
          {row.thumbnail && <button type="button" disabled={busy || row.state === "done" || row.mediaDone} onClick={() => patch(row.id, { thumbnail: undefined })} className="text-xs text-violet-700 underline">Use automatic thumbnail</button>}
        </label>
        {mediaType(row.file).startsWith("video/") && <label className="block text-sm">Trailer / preview (optional)
          <input type="file" accept="video/*" disabled={busy || row.state === "done" || row.mediaDone} onChange={e => { patch(row.id, { trailer: e.target.files?.[0] }); e.target.value = ""; }} />
          <span className="block text-xs text-gray-500">{row.trailer?.name ?? "Add a trailer so ads guests can preview a Premium video."}</span>
          {row.trailer && <button type="button" disabled={busy || row.state === "done" || row.mediaDone} onClick={() => patch(row.id, { trailer: undefined })} className="text-xs text-violet-700 underline">Remove selected trailer</button>}
        </label>}
      </div>}
      {row.state === "uploading" && <progress className="w-full" value={row.progress} max={100} aria-label={`Upload progress for ${row.title}`} />}
      {row.error && <p className="text-sm text-red-700" role="alert">{row.error}</p>}
      {row.postId && <Link className="text-sm text-violet-700 underline" href={`/workspace/posts/${row.postId}`}>View saved post</Link>}
      {!row.postId && <button type="button" className="ml-3 text-sm text-gray-600 underline" disabled={busy} onClick={() => setEntries(rows => rows.filter(item => item.id !== row.id))}>Remove from batch</button>}
    </article>)}</div>
    <div className="md:sticky bottom-4 z-10 flex flex-wrap items-center gap-3 rounded-2xl border border-slate-200 bg-white/95 p-4 shadow-lg backdrop-blur">
      <button type="button" className="btn disabled:opacity-50" disabled={busy || !channel || !entries.some(row => row.state !== "done")} onClick={start}>Upload / retry remaining posts</button>
      {busy && <button type="button" className="rounded-lg border px-4 py-2" onClick={() => { stop.current = true; setMessage("Will pause after the current file finishes."); }}>Pause after current file</button>}
      {!busy && entries.length > 0 && <button type="button" className="rounded-lg border px-4 py-2" onClick={() => { setEntries([]); setMessage("Batch cleared. Already saved posts are kept in Posts."); }}>Start a new batch</button>}
    </div>
    {message && <p className="rounded-lg bg-gray-100 p-3 text-sm" role="status">{message}</p>}
  </div>;
}

