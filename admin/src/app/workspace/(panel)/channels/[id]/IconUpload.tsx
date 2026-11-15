"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

export default function IconUpload({ channelId, current }: { channelId: string; current: string | null }) {
  const router = useRouter();
  const [preview, setPreview] = useState<string | null>(current);
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  async function pick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    if (!f.type.startsWith("image/")) return setMsg("Choose an image file.");
    if (f.size > 2 * 1024 * 1024) return setMsg("The image is larger than 2 MB.");
    setBusy(true); setMsg("Uploading…");
    const sb = supabaseBrowser();
    const ext = (f.name.split(".").pop() ?? "png").toLowerCase().replace(/[^a-z0-9]/g, "") || "png";
    const path = `${channelId}/icon-${Date.now()}.${ext}`;
    const up = await sb.storage.from("channel-icons").upload(path, f, { contentType: f.type, upsert: true });
    if (up.error) { setBusy(false); return setMsg("Upload failed: " + up.error.message); }
    const { error } = await sb.from("channels").update({ icon_url: path }).eq("id", channelId);
    setBusy(false);
    if (error) return setMsg("Could not save: " + error.message);
    setPreview(URL.createObjectURL(f));
    setMsg("Picture saved.");
    router.refresh();
  }

  return (
    <div className="space-y-3">
      <div className="grid h-28 w-28 place-items-center overflow-hidden rounded-xl border border-gray-200 bg-gray-50 text-xs text-gray-400">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        {preview ? <img src={preview} alt="Channel picture" className="h-full w-full object-cover" /> : "No picture"}
      </div>
      <label className="inline-flex cursor-pointer items-center rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
        {busy ? "Uploading…" : "Choose picture"}
        <input type="file" accept="image/*" className="sr-only" onChange={pick} disabled={busy} />
      </label>
      {msg && <p className="text-xs text-gray-600" role="status">{msg}</p>}
    </div>
  );
}
