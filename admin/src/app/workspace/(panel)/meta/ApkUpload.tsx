"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

export default function ApkUpload() {
  const router = useRouter();
  const [pct, setPct] = useState<number | null>(null);
  const [msg, setMsg] = useState("");
  const [err, setErr] = useState("");

  async function pick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f) return;
    if (!f.name.toLowerCase().endsWith(".apk")) return setErr("Choose an .apk file.");
    if (!window.confirm(`Replace the ads APK with ${f.name}?`)) return;
    setErr(""); setMsg(""); setPct(0);
    const { data } = await supabaseBrowser().auth.getSession();
    const token = data.session?.access_token;
    if (!token) { setPct(null); return setErr("Your session expired. Sign in again."); }
    const x = new XMLHttpRequest();
    x.open("POST", `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/downloads/Vayora-ads.apk`);
    x.setRequestHeader("Authorization", `Bearer ${token}`);
    x.setRequestHeader("apikey", process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!);
    x.setRequestHeader("x-upsert", "true");
    x.setRequestHeader("Content-Type", "application/vnd.android.package-archive");
    x.upload.onprogress = (ev) => { if (ev.lengthComputable) setPct(Math.round((ev.loaded / ev.total) * 100)); };
    x.onload = () => {
      setPct(null);
      if (x.status >= 200 && x.status < 300) { setMsg("APK uploaded."); router.refresh(); }
      else setErr(x.status === 413 ? "This APK is larger than your Supabase upload limit. Raise the limit in Supabase → Storage settings." : `Upload failed (${x.status}).`);
    };
    x.onerror = () => { setPct(null); setErr("Network error during upload."); };
    x.send(f);
  }

  return (
    <div className="space-y-2">
      <label className={"inline-flex cursor-pointer items-center rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 " + (pct !== null ? "pointer-events-none opacity-50" : "")}>
        Upload new APK<input type="file" accept=".apk" className="sr-only" onChange={pick} />
      </label>
      {pct !== null && <div role="status"><div className="h-2 overflow-hidden rounded-full bg-gray-200"><div className="h-full bg-violet-600" style={{ width: `${pct}%` }} /></div><p className="mt-1 text-xs text-gray-600">Uploading… {pct}%</p></div>}
      {msg && <p className="text-xs text-green-700" role="status">{msg}</p>}
      {err && <p className="text-sm text-red-700" role="alert">{err}</p>}
    </div>
  );
}
