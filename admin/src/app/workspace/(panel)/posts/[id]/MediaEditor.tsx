"use client";
import { uploadBunnyVideo } from "@/lib/bunny-upload";
import { useRef, useState } from "react";
import SavedMediaPreview from "./SavedMediaPreview";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

export type Item = {
  id: string; media_key: string; thumbnail_key: string | null; trailer_key: string | null; mime: string;
  bunny_video_id?:string|null; processing_status?:string; trailer_processing_status?:string; is_premium: boolean; duration_s: number | null; position: number; size_bytes: number;
};

const mb = (b: number) => (b / (1 << 20)).toFixed(1) + " MB";
const extOf = (f: File) => (f.name.includes(".") ? f.name.split(".").pop()! : "bin").toLowerCase().replace(/[^a-z0-9]/g, "") || "bin";
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2));

/** Upload with real progress (the JS client has no progress callback). */
export async function upload(path: string, file: Blob, type: string, onProgress: (pct: number) => void) {
  const sb = supabaseBrowser();
  const { data } = await sb.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Your session expired. Sign in again.");
  await new Promise<void>((resolve, reject) => {
    const x = new XMLHttpRequest();
    x.open("POST", `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/media/${path}`);
    x.setRequestHeader("Authorization", `Bearer ${token}`);
    x.setRequestHeader("apikey", process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!);
    x.setRequestHeader("x-upsert", "true");
    x.setRequestHeader("Content-Type", type || "application/octet-stream");
    x.upload.onprogress = (e) => { if (e.lengthComputable) onProgress(Math.round((e.loaded / e.total) * 100)); };
    x.onload = () => {
      if (x.status >= 200 && x.status < 300) return resolve();
      let m = `Upload failed (${x.status})`;
      try { m = JSON.parse(x.responseText).message ?? m; } catch { /* keep */ }
      reject(new Error(x.status === 413 ? "This file is larger than your Supabase upload limit." : m));
    };
    x.onerror = () => reject(new Error("Network error during upload."));
    x.send(file);
  });
}

/** Duration and a JPEG frame from a local video file (both optional). */
export function probe(file: File): Promise<{ duration: number | null; thumb: Blob | null }> {
  return new Promise((resolve) => {
    const v = document.createElement("video");
    const url = URL.createObjectURL(file);
    let settled = false;
    const done = (r: { duration: number | null; thumb: Blob | null }) => {
      if (settled) return;
      settled = true; clearTimeout(timer);
      v.onloadedmetadata = null; v.onseeked = null; v.onerror = null;
      v.removeAttribute("src"); v.load();
      URL.revokeObjectURL(url); resolve(r);
    };
    const timer = setTimeout(() => done({ duration: null, thumb: null }), 8000);
    v.preload = "metadata"; v.muted = true; v.playsInline = true; v.src = url;
    v.onerror = () => { clearTimeout(timer); done({ duration: null, thumb: null }); };
    v.onloadedmetadata = () => { v.currentTime = Math.min(1, (v.duration || 2) / 2); };
    v.onseeked = () => {
      clearTimeout(timer);
      const duration = isFinite(v.duration) ? Math.round(v.duration) : null;
      try {
        const c = document.createElement("canvas");
        const w = 640, h = Math.round((v.videoHeight / (v.videoWidth || 1)) * w) || 360;
        c.width = w; c.height = h;
        c.getContext("2d")!.drawImage(v, 0, 0, w, h);
        c.toBlob((b) => done({ duration, thumb: b }), "image/jpeg", 0.8);
      } catch { done({ duration, thumb: null }); }
    };
  });
}

export default function MediaEditor({ postId, channelId, items, thumbs, owner }: { owner:boolean; postId: string; channelId: string; items: Item[]; thumbs: Record<string, string> }) {
  const router = useRouter();
  const pendingItems=useRef(new Map<string,string>());
  const [pct, setPct] = useState<number | null>(null);
  const [msg, setMsg] = useState("");
  const [err, setErr] = useState("");
  const busy = pct !== null;
  const sb = supabaseBrowser();

  const run = async (label: string, fn: () => Promise<void|string>) => {
    setErr(""); setMsg(label); setPct(0);
    try { const message=await fn(); setMsg(message||"Saved."); router.refresh(); }
    catch (e) { setErr(e instanceof Error ? e.message : "Something went wrong."); setMsg(""); }
    setPct(null);
  };
  const fail = (e: { message: string } | null) => { if (e) throw new Error(e.message); };

  const addMain = (file: File) => run(`Uploading ${file.name}…`, async () => {
    const key = `${channelId}/${uid()}.${extOf(file)}`;
    const isVideo = file.type.startsWith("video");
    const info = isVideo ? await probe(file) : { duration: null, thumb: null };
    if (isVideo) {
      const fingerprint=`${file.name}:${file.size}:${file.lastModified}`;
      const previous=pendingItems.current.get(fingerprint),itemId=previous??crypto.randomUUID();
      if(!previous)fail((await sb.from("post_items").insert({id:itemId,post_id:postId,media_key:`${channelId}/pending/${itemId}`,mime:file.type||"video/mp4",position:items.length,size_bytes:file.size})).error);
      pendingItems.current.set(fingerprint,itemId);
      const bunny=await uploadBunnyVideo(itemId,file,setPct);
      if(bunny){pendingItems.current.delete(fingerprint);return "Uploaded successfully. Video is processing; publish after encoding is verified.";}
      fail((await sb.from("post_items").delete().eq("id",itemId)).error);pendingItems.current.delete(fingerprint);
    }
    await upload(key, file, file.type, setPct);
    let thumbKey: string | null = null;
    if (info.thumb) { try {thumbKey = `${channelId}/${uid()}.jpg`; await upload(thumbKey, info.thumb, "image/jpeg", () => {});}catch{thumbKey=null;} }
    else if (file.type.startsWith("image")) thumbKey = key;
    const { error } = await sb.from("post_items").insert({
      post_id: postId, media_key: key, thumbnail_key: thumbKey, mime: file.type || "video/mp4", duration_s: info.duration,
      position: items.length ? Math.max(...items.map((i) => i.position)) + 1 : 0, size_bytes: file.size,
    });
    if (error) { await sb.storage.from("media").remove([key, ...(thumbKey && thumbKey !== key ? [thumbKey] : [])]); fail(error); }
  });

  const attach = (it: Item, field: "trailer_key" | "thumbnail_key", file: File) => run(`Uploading ${file.name}…`, async () => {
    const key = `${channelId}/${uid()}.${extOf(file)}`;
    if(field==="trailer_key"&&await uploadBunnyVideo(it.id,file,setPct,"trailer"))return;
    await upload(key, file, file.type, setPct);
    const old = it[field];
    const { error } = await sb.from("post_items").update({ [field]: key }).eq("id", it.id);
    if (error) { await sb.storage.from("media").remove([key]); fail(error); }
    if (old && old !== it.media_key) await sb.storage.from("media").remove([old]);
  });

  const patch = (it: Item, p: Partial<Item>) => run("Saving…", async () => fail((await sb.from("post_items").update(p).eq("id", it.id)).error));

  const move = (i: number, dir: -1 | 1) => run("Reordering…", async () => {
    const order = [...items];
    if (!order[i + dir]) return;
    [order[i], order[i + dir]] = [order[i + dir], order[i]];
    for (let k = 0; k < order.length; k++) {
      if (order[k].position !== k) fail((await sb.from("post_items").update({ position: k }).eq("id", order[k].id)).error);
    }
  });

  const remove = (it: Item) => {
    if (!window.confirm("Remove this media item and delete its files?")) return;
    return run("Removing…", async () => {
      const {error}=await sb.functions.invoke('bunny-stream-delete',{body:{item_id:it.id,confirm:true}});fail(error);
    });
  };

  const pick = (accept: string, cb: (f: File) => void) => (
    <input type="file" accept={accept} className="sr-only" disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) cb(f); }} />
  );
  const fileBtn = "inline-flex cursor-pointer items-center rounded-lg border border-gray-300 bg-white px-2.5 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50 aria-disabled:opacity-50";

  return (
    <div className="space-y-3">
      {items.length === 0 && <p className="rounded-lg border border-dashed border-gray-300 p-4 text-center text-sm text-gray-500">No media yet. Add the main video or image.</p>}
      {items.map((it, i) => (
        <div key={it.id} className="rounded-lg border border-gray-200 p-3">
          <div className="flex gap-3">
            <div className="grid h-16 w-28 shrink-0 place-items-center overflow-hidden rounded-md bg-gray-100 text-[10px] text-gray-400">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              {(thumbs[it.id]||(it.thumbnail_key&&thumbs[it.thumbnail_key])) ? <img src={thumbs[it.id]||(it.thumbnail_key?thumbs[it.thumbnail_key]:undefined)} alt="" className="h-full w-full object-cover" /> : "No thumbnail"}
            </div>
            <div className="min-w-0 flex-1 text-xs text-gray-600">
              <div className="font-medium text-gray-900">{it.mime.startsWith("video") ? "Video" : "Image"} · {mb(it.size_bytes)}{it.duration_s ? ` · ${Math.floor(it.duration_s / 60)}:${String(it.duration_s % 60).padStart(2, "0")}` : ""}</div>
              <div className="mt-0.5">{it.processing_status&&it.processing_status!=="ready"?`Video ${it.processing_status}`:(it.trailer_key ? "Trailer added" : "No trailer")} · {it.is_premium ? "Premium" : "Free"}</div>
              <label className="mt-2 flex items-center gap-2 text-sm text-gray-800">
                <input type="checkbox" checked={it.is_premium} disabled={busy} onChange={(e) => patch(it, { is_premium: e.target.checked })} />
                Premium (only plan holders watch the full video)
              </label>
            </div>
          </div>
          <SavedMediaPreview key={it.media_key} storageKey={it.media_key} itemId={it.id} label={it.mime.startsWith("video") ? "Preview full video" : "Preview image"} mime={it.mime} poster={it.thumbnail_key ? thumbs[it.thumbnail_key] : undefined} />
          {it.trailer_key && <SavedMediaPreview key={it.trailer_key} storageKey={it.trailer_key} itemId={it.id} trailer label="Preview trailer" mime="video/mp4" />}
          <div className="mt-2 flex flex-wrap items-center gap-1.5">
            <label className={fileBtn} aria-disabled={busy}>{it.trailer_key ? "Replace trailer" : "Add trailer"}{pick("video/*", (f) => attach(it, "trailer_key", f))}</label>
            <label className={fileBtn} aria-disabled={busy}>{it.thumbnail_key ? "Replace thumbnail" : "Add thumbnail"}{pick("image/*", (f) => attach(it, "thumbnail_key", f))}</label>
            <label className="flex items-center gap-1 text-xs text-gray-600">Seconds
              <input type="number" min={0} defaultValue={it.duration_s ?? ""} disabled={busy} className="w-20 rounded-lg border border-gray-300 px-2 py-1 text-xs"
                onBlur={(e) => { const v = e.target.value === "" ? null : Math.max(0, Math.floor(Number(e.target.value))); if (v !== it.duration_s) patch(it, { duration_s: v }); }} />
            </label>
            <button type="button" className={fileBtn} disabled={busy || i === 0} onClick={() => move(i, -1)} aria-label="Move up">↑</button>
            <button type="button" className={fileBtn} disabled={busy || i === items.length - 1} onClick={() => move(i, 1)} aria-label="Move down">↓</button>
            {it.bunny_video_id&&it.processing_status!=="ready"&&<label className={fileBtn}>Resume main upload{pick("video/*",file=>run("Resuming upload…",async()=>{await uploadBunnyVideo(it.id,file,setPct);}))}</label>}
            {owner&&<button type="button" className="inline-flex items-center rounded-lg bg-red-600 px-2.5 py-1 text-xs font-medium text-white hover:bg-red-700 disabled:opacity-50" disabled={busy} onClick={() => remove(it)}>Remove</button>}
          </div>
        </div>
      ))}
      <label className={"inline-flex cursor-pointer items-center rounded-lg bg-violet-600 px-3.5 py-2 text-sm font-medium text-white hover:bg-violet-700 " + (busy ? "pointer-events-none opacity-50" : "")}>
        Add video or image{pick("video/*,image/*", addMain)}
      </label>
      {busy && (
        <div role="status">
          <div className="h-2 overflow-hidden rounded-full bg-gray-200"><div className="h-full bg-violet-600 transition-all" style={{ width: `${pct}%` }} /></div>
          <p className="mt-1 text-xs text-gray-600">{msg} {pct}%</p>
        </div>
      )}
      {!busy && msg && <p className="text-xs text-green-700" role="status">{msg}</p>}
      {err && <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700" role="alert">{err}</p>}
    </div>
  );
}
