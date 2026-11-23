"use client";
import { useState } from "react";
import SiteShell from "@/components/SiteShell";
import { supabaseBrowser } from "@/lib/supabase/client";

export default function DeleteAccount() {
  const sb = supabaseBrowser();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [signedIn, setSignedIn] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ kind: "ok" | "err" | "info"; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  // Fallback request form (for people who cannot log in)
  const [reqEmail, setReqEmail] = useState("");
  const [partial, setPartial] = useState(false);
  const [details, setDetails] = useState("");
  const [website, setWebsite] = useState(""); // honeypot
  const [reqState, setReqState] = useState<"idle" | "busy" | "ok" | "err">("idle");

  async function login(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setMsg(null);
    const { data, error } = await sb.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error || !data.user) setMsg({ kind: "err", text: "Wrong email or password." });
    else setSignedIn(data.user.email ?? email);
  }

  async function remove() {
    if (!confirm("Delete your account permanently? Your profile, files and posts will be removed. This cannot be undone.")) return;
    setBusy(true); setMsg(null);
    const { error } = await sb.functions.invoke("delete-account");
    if (error) { setBusy(false); setMsg({ kind: "err", text: "Could not delete the account. Please try again or send a request below." }); return; }
    await sb.auth.signOut();
    setBusy(false); setSignedIn(null);
    setMsg({ kind: "ok", text: "Your account has been deleted." });
  }

  async function submitRequest(e: React.FormEvent) {
    e.preventDefault();
    setReqState("busy");
    try {
      const r = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/deletion-request`, {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY! },
        body: JSON.stringify({ email: reqEmail, partial, details, website }),
      });
      setReqState(r.ok ? "ok" : "err");
    } catch { setReqState("err"); }
  }

  return (
    <SiteShell>
      <main className="mx-auto max-w-2xl px-4 py-12 space-y-8 text-sm">
        <section className="space-y-3">
          <h1 className="text-3xl font-bold text-slate-900">Delete your Vayora account</h1>
          <p className="text-slate-600">
            Deleting removes your profile, cloud files, channels and posts. Payment records are kept without any link to you for up to 8 years, as tax and
            accounting rules require. In the app you can also go to Profile → Delete account.
          </p>
        </section>

        {msg && <p role="status" className={`rounded-lg border px-4 py-3 ${msg.kind === "ok" ? "border-green-300 bg-green-50 text-green-800" : msg.kind === "err" ? "border-red-300 bg-red-50 text-red-800" : "border-cyan-200 bg-cyan-50 text-indigo-900"}`}>{msg.text}</p>}

        {!signedIn ? (
          <form onSubmit={login} className="card space-y-3">
            <p className="rounded-lg border border-cyan-200 bg-cyan-50 px-4 py-3 text-indigo-900">Please log in to delete your account.</p>
            <label className="block">Email<input className="input mt-1" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} /></label>
            <label className="block">Password<input className="input mt-1" type="password" required value={password} onChange={(e) => setPassword(e.target.value)} /></label>
            <button className="btn" disabled={busy}>Login</button>
          </form>
        ) : (
          <div className="card space-y-3">
            <p>Signed in as <b>{signedIn}</b>.</p>
            <button className="btn !bg-red-600 !bg-none" onClick={remove} disabled={busy}>Delete my account</button>
          </div>
        )}

        <section>
          <h2 className="text-xl font-semibold text-slate-900">Cannot log in, or want to delete only some data?</h2>
          {reqState === "ok" ? (
            <p className="card mt-3 text-green-700" role="status">Request received. We will process it within 30 days.</p>
          ) : (
            <form onSubmit={submitRequest} className="card mt-3 space-y-3">
              <input className="input" type="email" required placeholder="Account email" value={reqEmail} onChange={(e) => setReqEmail(e.target.value)} />
              <label className="flex items-center gap-2"><input type="checkbox" checked={partial} onChange={(e) => setPartial(e.target.checked)} /> Delete only some data (describe below)</label>
              <textarea className="input" rows={4} maxLength={2000} placeholder="Details (optional)" value={details} onChange={(e) => setDetails(e.target.value)} />
              <input className="hidden" tabIndex={-1} autoComplete="off" aria-hidden value={website} onChange={(e) => setWebsite(e.target.value)} name="website" />
              {reqState === "err" && <p className="text-red-600" role="alert">Could not send. Please try again.</p>}
              <button className="btn" disabled={reqState === "busy"}>Submit request</button>
            </form>
          )}
        </section>
      </main>
    </SiteShell>
  );
}
