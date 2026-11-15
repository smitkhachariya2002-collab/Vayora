"use client";
import Link from "next/link";
import { useState } from "react";
import {trackWebEvent} from "./MetaPixel";

type P = { id: string; name: string; price: string; label: string; badge: string | null };

export default function PlanPicker({ plans }: { plans: P[] }) {
  const firstPopular = plans.find((p) => p.badge === "Popular") ?? plans[0];
  const [sel, setSel] = useState(firstPopular?.id);
  const cur = plans.find((p) => p.id === sel);
  return (
    <div className="card p-6">
      <h3 className="font-semibold text-slate-900">Select your plan</h3>
      <div role="radiogroup" aria-label="Plan" className="mt-3 divide-y divide-slate-200 rounded-xl border border-slate-200">
        {plans.map((p) => (
          <button
            key={p.id}
            role="radio"
            aria-checked={p.id === sel}
            onClick={() => {setSel(p.id);void trackWebEvent("PlanViewed");}}
            className={`flex w-full items-center gap-3 px-4 py-3 text-left ${p.id === sel ? "bg-violet-50 ring-1 ring-inset ring-primary" : ""}`}
          >
            <span className={`grid h-5 w-5 place-items-center rounded-full border ${p.id === sel ? "border-primary" : "border-slate-300"}`}>
              {p.id === sel && <span className="h-2.5 w-2.5 rounded-full bg-primary" />}
            </span>
            <span className="flex-1">
              <span className="block text-sm font-semibold text-slate-900">{p.name} Plan {p.badge && <span className="ml-1 rounded bg-primary px-1.5 py-0.5 text-[10px] text-white">{p.badge}</span>}</span>
              <span className="block text-xs text-slate-500">{p.label}</span>
            </span>
            <span className="font-bold text-primary">{p.price}</span>
          </button>
        ))}
      </div>
      <Link href="/d" className="btn mt-5 w-full py-3">Get the app to buy {cur ? `${cur.name} Plan` : "a plan"}</Link>
      <p className="mt-2 text-center text-xs text-slate-500">Plans are bought inside the Vayora app with UPI. No payment is taken on this website.</p>
    </div>
  );
}

