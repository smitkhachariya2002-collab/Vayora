"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
export const CHOICE_KEY = "vayora_privacy_20261115";
export type WebChoices = { analytics: boolean; advertising: boolean; saved: number };
export function readWebChoices(): WebChoices | null {
  try {
    const value = JSON.parse(localStorage.getItem(CHOICE_KEY) ?? "null");
    return value && typeof value.advertising === "boolean" && Number.isFinite(value.saved) && Date.now() - value.saved < 180 * 86400000 ? value : null;
  } catch { return null; }
}
export function hasAdvertisingConsent() { return readWebChoices()?.advertising === true; }
export default function PrivacyChoices() {
  const [open, setOpen] = useState(false);
  const [advertising, setAdvertising] = useState(false);
  useEffect(() => {
    const value = readWebChoices(); setOpen(!value); setAdvertising(value?.advertising ?? false);
    const show = () => { setAdvertising(readWebChoices()?.advertising ?? false); setOpen(true); };
    window.addEventListener("vayora-privacy-open", show);
    return () => window.removeEventListener("vayora-privacy-open", show);
  }, []);
  function save(allow: boolean) {
    try { localStorage.setItem(CHOICE_KEY, JSON.stringify({ analytics: false, advertising: allow, saved: Date.now() })); }
    catch { return; }
    if (!allow) {
      window.fbq?.("consent", "revoke");
      for (const name of ["_fbc", "_fbp"]) {
        document.cookie = name + "=; Max-Age=0; Path=/; SameSite=Lax";
        document.cookie = name + "=; Max-Age=0; Path=/; Domain=" + location.hostname + "; SameSite=Lax";
      }
      try { sessionStorage.removeItem("vayora_fbclid"); sessionStorage.removeItem("vayora_ad"); } catch {}
    }
    window.dispatchEvent(new Event("vayora-privacy-change")); setOpen(false);
  }
  if (!open) return null;
  return <section role="dialog" aria-modal="false" aria-labelledby="privacy-title" className="privacy-choice">
    <h2 id="privacy-title" className="text-lg font-semibold">Your privacy choices</h2>
    <p className="mt-2 text-sm leading-relaxed text-slate-300">Essential storage keeps the website and downloads working. Optional Meta measurement shares page and download events, click identifiers, IP address and browser information. You can change your choice anytime.</p>
    <Link href="/privacy" className="mt-2 inline-block text-sm text-teal-200 underline">How data is used</Link>
    <label className="mt-4 flex items-center gap-2 text-sm"><input type="checkbox" checked={advertising} onChange={e => setAdvertising(e.target.checked)} />Meta advertising measurement</label>
    <div className="mt-5 flex flex-wrap gap-2"><button className="btn-ghost" onClick={() => save(false)}>Essential only</button><button className="btn-ghost" onClick={() => save(advertising)}>Save choices</button><button className="btn" onClick={() => save(true)}>Allow optional measurement</button></div>
  </section>;
}
export function PrivacyChoicesButton() { return <button type="button" className="text-left underline underline-offset-4" onClick={() => window.dispatchEvent(new Event("vayora-privacy-open"))}>Privacy choices</button>; }
