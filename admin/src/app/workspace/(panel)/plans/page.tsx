import {Button} from "@/components/admin/ui";
import type {ReportQuery} from "@/lib/reporting";
import { requireAdmin } from "@/lib/admin";
import { PageHeader, Card, Field, Input, Textarea, Select, Hidden, Badge, ErrorNote } from "@/components/admin/ui";
import { SubmitButton } from "@/components/admin/client";
import UpiSettings from "./UpiSettings";
import {setRecommended} from "../actions";
import { saveMode, savePlan, addPlan } from "../actions";

const helper = (d: number, h: number) => {
  if (h > 0) return h % 24 === 0 ? `= ${h / 24} day${h === 24 ? "" : "s"}` : `= ${h} hour${h === 1 ? "" : "s"}`;
  if (d % 365 === 0) return `= ${d / 365} year${d === 365 ? "" : "s"}`;
  if (d % 30 === 0) return `= ${d / 30} month${d === 30 ? "" : "s"}`;
  return `= ${d} day${d === 1 ? "" : "s"}`;
};
const AUD = [["none", "Off"], ["organic", "Organic only"], ["ads", "Ads only"], ["everyone", "Everyone"]];
const SHOW = [["everyone", "Everyone"], ["ads", "Ads users only"], ["organic", "Organic users only"], ["none", "Nobody"]];

function PlanForm({ p, impact }: { p?: Record<string, any>; impact?: { subscribers: number; orders: number } }) {
  const hours = (p?.duration_hours ?? 0) > 0;
  return (
    <form action={p ? savePlan : addPlan} className="space-y-3">
      {p && <Hidden name="id" value={p.id} />}
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Name"><Input name="name" defaultValue={p?.name ?? ""} required placeholder="e.g. Day Pass" /></Field>
        <Field label="Code" hint={p ? "Cannot be changed" : "Lowercase, no spaces. Cannot be changed later."}><Input name="code" defaultValue={p?.code ?? ""} readOnly={!!p} required pattern="[a-z0-9][a-z0-9_-]{1,30}" placeholder="day-pass" /></Field>
        <Field label="Price ₹"><Input type="number" name="price_inr" min={1} defaultValue={p?.price_inr ?? 49} required /></Field>
        <Field label="Duration" hint={p ? helper(p.duration_days, p.duration_hours ?? 0) : "Use Hours for hourly plans"}>
          <div className="flex gap-2">
            <Input type="number" name="duration" min={1} defaultValue={hours ? p?.duration_hours : p?.duration_days ?? 7} required />
            <Select name="unit" defaultValue={hours ? "h" : "d"} aria-label="Duration unit" className="!w-28"><option value="d">Days</option><option value="h">Hours</option></Select>
          </div>
        </Field>
        <Field label="Badge">
          <Select name="badge" defaultValue={p?.badge ?? ""}><option value="">None</option><option>Popular</option><option>Best value</option></Select>
        </Field>
        <Field label="Order" hint="Lower numbers show first"><Input type="number" name="position" defaultValue={p?.position ?? 10} /></Field>
      </div>
      <Field label="Perks" hint="One per line"><Textarea name="perks" rows={3} defaultValue={(p?.perks ?? []).join("\n")} /></Field>
      <div className="flex flex-wrap items-center gap-4 text-sm text-gray-800">
        {p && <label className="flex items-center gap-2"><input type="checkbox" name="active" defaultChecked={!!p.active} /> Show in app</label>}
        <label className="flex items-center gap-2"><input type="checkbox" name="free_eligible" defaultChecked={!!p?.free_eligible} /> Free when free plans are on</label>
      </div>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <SubmitButton confirm={p ? "Save this plan? Existing subscribers keep their plan until it ends; new buyers see the new price and duration." : undefined}>{p ? "Save plan" : "Add plan"}</SubmitButton>
        {impact && <span className="text-xs text-gray-500">{impact.subscribers} active subscribers · {impact.orders} orders</span>}
      </div>
    </form>
  );
}

export default async function Plans({ searchParams: pending }: { searchParams: Promise<ReportQuery> }) {
 const q=await pending;
  const { sb } = await requireAdmin(true);
  const [mode, plans, impact, claims, payment] = await Promise.all([
    sb.from("app_mode").select("*").eq("id", 1).single(),
    sb.from("plans").select("*").order("position"),
    sb.rpc("admin_plan_impact"),
    sb.rpc("admin_free_plan_claims"),
    sb.from("payment_settings").select("*").eq("id",1).single(),
  ]);
  const m = (mode.data ?? {}) as Record<string, any>;
  const imp = (impact.data ?? {}) as Record<string, { subscribers: number; orders: number }>;
  const visible=(plans.data??[]).filter(p=>(!q.q||p.name.toLowerCase().includes(q.q.toLowerCase()))&&(!q.visibility||(q.visibility==="active"?p.active:!p.active))).sort((a,b)=>q.sort==="price_low"?a.price_inr-b.price_inr:q.sort==="price_high"?b.price_inr-a.price_inr:q.sort==="duration"?(a.duration_hours||a.duration_days*24)-(b.duration_hours||b.duration_days*24):q.sort==="name"?a.name.localeCompare(b.name):a.position-b.position);
  const cl = (claims.data ?? {}) as { organic?: number; ads?: number };
  return (
    <>
      <PageHeader title="Plans" sub="Changes reach the app within a minute." />
      <ErrorNote error={mode.error ?? plans.error} />
      <div className="grid gap-4 lg:grid-cols-3">
        <Card title="Free mode" sub="ON: no prices anywhere in the app, everyone gets 15 GB, ads users get full access and organic users request access.">
          <form action={saveMode} className="space-y-3">
            <Select name="free_mode" defaultValue={m.free_mode ? "on" : "off"} aria-label="Free mode"><option value="off">OFF — paid plans</option><option value="on">ON — everything free</option></Select>
            <SubmitButton confirm="Change free mode for the whole app?">Save</SubmitButton>
          </form>
        </Card>
        <Card title="Free plans" sub={`Give plans marked “free” at no cost. Claimed this promotion: organic ${cl.organic ?? 0} · ads ${cl.ads ?? 0}.`}>
          <form action={saveMode} className="space-y-3">
            <Select name="free_plans_for" defaultValue={m.free_plans_for ?? "none"} aria-label="Free plans for">{AUD.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</Select>
            <SubmitButton>Save</SubmitButton>
          </form>
        </Card>
        <Card title="Show plans in app" sub="Admins always see plans. Subscribers keep seeing their own plan.">
          <form action={saveMode} className="space-y-3">
            <Select name="plans_visible_for" defaultValue={m.plans_visible_for ?? "everyone"} aria-label="Show plans to">{SHOW.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</Select>
            <SubmitButton>Save</SubmitButton>
          </form>
        </Card>
      </div>
      <div className="my-6"><UpiSettings s={payment.data}/></div>
      <h2 className="mb-2 mt-6 text-sm font-semibold text-gray-900">Plans</h2><form className="mb-4 grid gap-2 sm:grid-cols-4"><Input name="q" defaultValue={q.q??""} placeholder="Search plan" aria-label="Search plan"/><Select name="visibility" defaultValue={q.visibility??""} aria-label="Visibility"><option value="">All plans</option><option value="active">Shown in app</option><option value="hidden">Hidden</option></Select><Select name="sort" defaultValue={q.sort??""} aria-label="Sort"><option value="">Display order</option><option value="price_low">Price: low to high</option><option value="price_high">Price: high to low</option><option value="duration">Duration: shortest first</option><option value="name">Name</option></Select><Button variant="secondary">Apply</Button></form>
      <div className="grid gap-4 lg:grid-cols-2">
        {visible.map((p) => (
          <Card key={p.id}>
            <div className="mb-3 flex flex-wrap items-center gap-2">
              <span className="font-semibold text-gray-900">{p.name}</span>
              <Badge tone={p.active ? "green" : "gray"}>{p.active ? "Shown in app" : "Hidden"}</Badge>
              {p.free_eligible && <Badge tone="blue">Free-eligible</Badge>}
            </div>
            <form action={setRecommended} className="mb-4 flex flex-wrap items-end gap-3"><Hidden name="id" value={p.id}/><label>Recommendation<Select name="label" defaultValue={p.recommendation_label??"MOST POPULAR"}><option>MOST POPULAR</option><option>BEST VALUE</option></Select></label><SubmitButton>{p.recommended?"Update recommended plan":"Make recommended"}</SubmitButton></form>
            <PlanForm p={p} impact={imp[p.id] ?? { subscribers: 0, orders: 0 }} />
          </Card>
        ))}
        <Card title="+ Add plan" className="border-dashed"><PlanForm /></Card>
      </div>
    </>
  );
}

