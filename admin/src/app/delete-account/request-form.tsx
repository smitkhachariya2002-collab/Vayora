"use client";
import { useState, type FormEvent } from "react";

export default function DeletionForm() {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [reference, setReference] = useState("");
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    const form = new FormData(event.currentTarget);
    setPending(true); setError("");
    try {
      const response = await fetch("/api/deletion-request", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({email: form.get("email"), details: form.get("details"), consent: form.get("consent") === "on", website: form.get("website")}),
      });
      const data = await response.json();
      if (!response.ok || typeof data.reference !== "string") throw new Error(data.error || "Request could not be sent.");
      setReference(data.reference);
    } catch {
      setError("We could not record your request. Please try again or email help.vayora@gmail.com.");
    } finally { setPending(false); }
  }
  if (reference) return <div role="status" className="rounded-xl border border-green-200 bg-green-50 p-5 text-green-900">
    <h3 className="text-lg font-semibold">Request received</h3>
    <p className="mt-2 leading-6">Your request has been recorded. Support will contact your account email to verify ownership before deleting anything.</p>
    <p className="mt-3 break-all text-sm">Request reference: {reference}</p>
    <p className="mt-3 text-sm">Keep this reference when contacting help.vayora@gmail.com. Your account has not been deleted yet.</p>
  </div>;
  return <form onSubmit={submit} className="space-y-5">
    <div><label htmlFor="email" className="mb-2 block font-medium">Account email address</label>
      <input id="email" name="email" type="email" autoComplete="email" required maxLength={254} className="w-full rounded-lg border border-gray-300 px-3 py-3 focus:outline-2 focus:outline-violet-700" /></div>
    <div><label htmlFor="details" className="mb-2 block font-medium">Additional details <span className="font-normal text-gray-500">(optional)</span></label>
      <textarea id="details" name="details" rows={3} maxLength={1000} className="w-full rounded-lg border border-gray-300 px-3 py-3 focus:outline-2 focus:outline-violet-700" aria-describedby="details-hint"/>
      <p id="details-hint" className="mt-1 text-sm text-gray-500">For example, your display name or a problem accessing your account. Do not include passwords or payment details.</p></div>
    <div hidden aria-hidden="true"><label htmlFor="website">Leave this field empty</label><input id="website" name="website" tabIndex={-1} autoComplete="off" /></div>
    <label className="flex items-start gap-3 leading-6"><input type="checkbox" name="consent" required className="mt-1 h-4 w-4 shrink-0" /><span>I am requesting deletion of my own Vayora account and associated data. I understand deletion is permanent after ownership is verified.</span></label>
    {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-red-800">{error}</p>}
    <button disabled={pending} type="submit" className="min-h-12 w-full rounded-lg bg-violet-800 px-5 py-3 font-semibold text-white hover:bg-violet-900 disabled:opacity-60">{pending ? "Sending request…" : "Request account deletion"}</button>
  </form>;
}
