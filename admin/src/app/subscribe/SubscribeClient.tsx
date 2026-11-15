"use client";
import type { Plan } from "@/lib/plans";
import { durationLabel } from "@/lib/plans";
import { inr } from "@/lib/format";

declare global {
  interface Window { VayoraApp?: { postMessage: (m: string) => void } }
}

export default function SubscribeClient({ plans, freeIds, paused, inApp }: { plans: Plan[]; freeIds: string[]; paused: boolean; inApp: boolean }) {
  const buy = (id: string) => {
    if (window.VayoraApp) window.VayoraApp.postMessage(JSON.stringify({ type: "buy", plan_id: id }));
    else window.location.href = "/d";
  };
  return (
    <main className="mx-auto max-w-md px-4 py-6">
      <h1 className="text-2xl font-bold text-center">Go <span className="text-gold">Premium</span></h1>
      <p className="mt-1 text-center text-sm text-muted">2 TB cloud, full-length videos and downloads.</p>
      {paused && <p className="mt-4 card text-sm text-warning">New purchases are paused right now. Please try again later.</p>}
      <ul className="mt-6 space-y-3">
        {plans.map((p) => {
          const isFree = freeIds.includes(p.id);
          return (
            <li key={p.id} className="card">
              <div className="flex items-baseline justify-between">
                <span className="font-semibold">{p.name}{p.badge && <span className="ml-2 rounded-full bg-gold/20 px-2 py-0.5 text-xs text-gold">{p.badge}</span>}</span>
                <span className="text-xl font-bold">{isFree ? <span className="text-success">FREE</span> : inr(p.price_inr)}</span>
              </div>
              <div className="text-xs text-muted">{durationLabel(p.duration_days, p.duration_hours)}</div>
              {p.perks && <ul className="mt-2 text-sm text-muted list-disc pl-5">{p.perks.map((x) => <li key={x}>{x}</li>)}</ul>}
              <button className="btn mt-3 w-full" disabled={paused && !isFree} onClick={() => buy(p.id)}>
                {isFree ? "Activate free" : "Buy now"}
              </button>
            </li>
          );
        })}
      </ul>
      {!inApp && <p className="mt-6 text-center text-xs text-muted">Purchases are made inside the Vayora app.</p>}
    </main>
  );
}
