import { requireAdmin } from "@/lib/admin";
import { ist, gb, inr } from "@/lib/format";
import { PageHeader, Card, Field, Input, Hidden, Badge, StatusBadge, Stat, ErrorNote, Table, Th, Td, Empty } from "@/components/admin/ui";
import { SubmitButton } from "@/components/admin/client";
import { saveMeta, metaSend } from "../actions";
import ApkUpload from "./ApkUpload";

export default async function Meta() {
  const { sb } = await requireAdmin(true);
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const [ms, last, failed, pending, files, ov] = await Promise.all([
    sb.from("meta_settings").select("pixel_id,test_event_code,enabled,updated_at,capi_token").eq("id", 1).single(),
    sb.from("meta_events").select("sent_at").eq("status", "sent").order("sent_at", { ascending: false }).limit(1),
    sb.from("meta_events").select("id", { count: "exact", head: true }).not("last_error", "is", null).gte("created_at", since),
    sb.from("meta_events").select("id", { count: "exact", head: true }).eq("status", "pending"),
    sb.storage.from("downloads").list("", { limit: 20, sortBy: { column: "created_at", order: "desc" } }),
    sb.rpc("admin_meta_overview"),
  ]);
  type Row = { event_name: string; d1: number; d7: number; d30: number; sent: number; test_sent:number; failed: number; with_click: number; value_d7: number; value_d30: number };
  type Ev = { id: number; event_name: string; status: string; value_inr: number | null; content_name: string | null; attempts: number; last_error: string | null; created_at: string; has_click: boolean };
  const o = (ov.data ?? {}) as { funnel?: Row[]; recent?: Ev[]; clicks_7d?: number; matched_installs_7d?: number; auto_send?: boolean };
  const funnel = o.funnel ?? [];
  const purchase = funnel.find((f) => f.event_name === "Purchase");
  const LABEL: Record<string, string> = {
    Lead: "Tapped Download on the website", MobileAppInstall: "First open, after advertising permission", CompleteRegistration: "Signed up with email",
    InitiateCheckout: "Started a payment", Purchase: "Bank-verified paid plan (INR)",
  };
  const m = ms.data;
  const hasToken = !!m?.capi_token; // only a yes/no is ever sent to the browser
  const apk = (files.data ?? []).find((f) => f.name.toLowerCase().endsWith(".apk"));
  const steps: [boolean, string][] = [
    [!!m?.pixel_id, "Pixel ID saved"],
    [hasToken, "Conversions API token saved"],
    [!!m?.enabled, "Meta sharing enabled for opted-in users"],
    [!!o.auto_send, "Automatic sending on"],
    [(last.data ?? []).length > 0, "At least one event delivered"],
  ];
  return (
    <>
      <PageHeader title="Meta Pixel" sub="One central configuration for the website Pixel and server-side app events. Replace the Dataset/Pixel ID and token here to change the destination; no app rebuild is needed." />
      <ErrorNote error={ms.error ?? ov.error} />
      <div className="grid gap-4 lg:grid-cols-3">
        <Card title="Setup checklist">
          <ul className="space-y-1.5 text-sm">
            {steps.map(([ok, label]) => <li key={label} className="flex items-center gap-2"><span className={ok ? "text-green-600" : "text-gray-300"} aria-hidden>{ok ? "✔" : "○"}</span><span className={ok ? "text-gray-900" : "text-gray-500"}>{label}</span></li>)}
          </ul>
        </Card>
        <Card title="Settings" className="lg:col-span-2">
          <form action={saveMeta} className="grid gap-3 sm:grid-cols-2">
            <Field label="Dataset / Pixel ID"><Input name="pixel_id" defaultValue={m?.pixel_id ?? ""} inputMode="numeric" /></Field>
            <Field label="Test event code" hint="Optional. Remove it when you finish testing."><Input name="test_event_code" defaultValue={m?.test_event_code ?? ""} placeholder="TEST12345" /></Field>
            <Field label="Conversions API token" hint={hasToken ? "A token is saved (hidden). Leave empty to keep it." : "Paste the token from Events Manager."} className="sm:col-span-2">
              <Input name="capi_token" type="password" autoComplete="off" placeholder={hasToken ? "••••••••••••" : ""} />
            </Field>
            <label className="flex items-center gap-2 text-sm text-gray-800"><input type="checkbox" name="enabled" defaultChecked={!!m?.enabled} /> Tracking on</label>
            {hasToken && <label className="flex items-center gap-2 text-sm text-gray-800"><input type="checkbox" name="clear_token" /> Remove the saved token</label>}
            <div className="sm:col-span-2 flex flex-wrap items-center gap-3"><SubmitButton>Save and check connection</SubmitButton><span className="text-xs text-gray-500">Saving checks the ID and token with Meta. No app update is needed.</span></div>
          </form>
        </Card>
      </div>
      <Card title="Before starting ads" className="mt-4"><p className="text-sm text-gray-600">Link this dataset to your Meta app in Events Manager once. Install the latest Vayora app so users can choose optional measurement. Enter a Test Event Code, send a test, then check Events Manager and remove the code for live campaigns. Download events measure button taps; installs measure first app opens. Purchase events are sent only after bank/provider verification. Users who decline advertising measurement are excluded.</p><p className="mt-2 text-sm text-gray-600">Changing the Dataset ID cancels unsent events for the previous destination. Updating only the token keeps eligible retries. Never paste access tokens into chat or public pages.</p></Card>
      <div className="mt-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Last sent" value={<span className="text-base">{last.data?.[0]?.sent_at ? ist(last.data[0].sent_at) : "Never"}</span>} />
        <Stat label="Failures in 24 h" value={failed.count ?? 0} tone={(failed.count ?? 0) > 0 ? "warn" : undefined} />
        <Stat label="Waiting to send" value={pending.count ?? 0} />
        <Stat label="Delivered purchases, 7 days" value={inr(purchase?.value_d7 ?? 0)} />
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        <form action={metaSend}><Hidden name="kind" value="verify" /><SubmitButton small variant="secondary">Check connection</SubmitButton></form>
        <form action={metaSend}><Hidden name="kind" value="test" /><SubmitButton small variant="secondary">Send test Purchase</SubmitButton></form>
        <form action={metaSend}><Hidden name="kind" value="flush" /><SubmitButton small variant="secondary">Send waiting events now</SubmitButton></form>
        <form action={metaSend}><Hidden name="kind" value="retry" /><SubmitButton small variant="secondary">Retry failed events</SubmitButton></form>
      </div>

      <h2 className="mb-2 mt-6 text-sm font-semibold text-gray-900">Events sent to Meta (last 30 days)</h2>
      <Table>
        <thead><tr><Th>Event</Th><Th>What it means</Th><Th className="text-right">24 h</Th><Th className="text-right">7 days</Th><Th className="text-right">30 days</Th><Th className="text-right">Delivered</Th><Th className="text-right">Test only</Th><Th className="text-right">Failed</Th><Th className="text-right">Has click identifiers</Th></tr></thead>
        <tbody>
          {funnel.map((f) => (
            <tr key={f.event_name}>
              <Td className="font-medium">{f.event_name}</Td><Td className="text-gray-600">{LABEL[f.event_name]??f.event_name.replace(/([a-z])([A-Z])/g,"$1 $2")}</Td>
              <Td className="text-right">{f.d1}</Td><Td className="text-right">{f.d7}</Td><Td className="text-right">{f.d30}</Td>
              <Td className="text-right">{f.sent}</Td><Td className="text-right">{f.test_sent??0}</Td><Td className={f.failed > 0 ? "text-right text-red-600" : "text-right"}>{f.failed}</Td><Td className="text-right">{f.with_click}</Td>
            </tr>
          ))}
        </tbody>
      </Table>
      <p className="mt-2 text-xs text-gray-500">
        Purchase value: {inr(purchase?.value_d7 ?? 0)} in 7 days, {inr(purchase?.value_d30 ?? 0)} in 30 days. Ad clicks recorded in 7 days: {o.clicks_7d ?? 0}. An APK download tap cannot prove installation or carry a browser click ID into the installed app.
        Use Events Manager diagnostics to check app-event eligibility and matching before choosing campaign optimisation. ROAS uses verified purchase value and the ad spend in Meta Ads Manager; delivery and attribution depend on Meta configuration and user permission.
      </p>

      <h2 className="mb-2 mt-6 text-sm font-semibold text-gray-900">Latest events</h2>
      {(o.recent ?? []).length === 0 ? <Empty>No events yet. They appear here once tracking is on and someone uses the app.</Empty> : (
        <Table>
          <thead><tr><Th>Time</Th><Th>Event</Th><Th>Plan</Th><Th className="text-right">Value</Th><Th>Ad click</Th><Th>Status</Th><Th>Problem</Th></tr></thead>
          <tbody>
            {(o.recent ?? []).map((e) => (
              <tr key={e.id}>
                <Td className="whitespace-nowrap">{ist(e.created_at)}</Td><Td className="font-medium">{e.event_name}</Td><Td>{e.content_name ?? "—"}</Td>
                <Td className="text-right">{e.value_inr != null ? inr(e.value_inr) : "—"}</Td>
                <Td>{e.has_click ? <Badge tone="blue">click ID</Badge> : <span className="text-gray-400">—</span>}</Td>
                <Td><StatusBadge value={e.status} /></Td><Td className="max-w-xs text-xs text-red-600">{e.last_error ?? ""}</Td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
      <Card title="Ads APK" sub="The app file for people coming from ads. Stored in the public downloads bucket." className="mt-4">
        <p className="mb-3 text-sm text-gray-700">
          {apk ? <>Current file: <strong>{apk.name}</strong> · {gb(Number((apk.metadata as { size?: number } | null)?.size ?? 0))} · {ist(apk.created_at)} <Badge tone="green">uploaded</Badge></> : "No APK uploaded here yet."}
        </p>
        <ApkUpload />
      </Card>
    </>
  );
}

