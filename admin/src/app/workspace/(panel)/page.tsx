import Link from "next/link";
import { requireAdmin } from "@/lib/admin";
import { inr, rowsOf } from "@/lib/format";
import { PageHeader, Stat, Table, Th, Td, Empty, SourceBadge, Card, LinkButton } from "@/components/admin/ui";
const n = (v: unknown) => new Intl.NumberFormat("en-IN").format(Number(v ?? 0));
function Alert({ count, text, href }: { count: number; text: string; href: string }) {
  if (!count) return null;
  return <Link href={href} className="flex items-center justify-between gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 hover:bg-amber-100">
    <span><strong className="mr-1">{n(count)}</strong>{text}</span><span aria-hidden="true">â†—</span>
  </Link>;
}
export default async function Dashboard() {
  const { sb, role } = await requireAdmin();
  const owner = role === "owner";
  const [{ data: d, error }, camp] = await Promise.all([sb.rpc("admin_dashboard"), owner ? sb.rpc("admin_campaigns") : Promise.resolve({ data: [] })]);
  const s = (d ?? {}) as Record<string, unknown>;
  const a = (s.alerts ?? {}) as Record<string, number>;
  const rows = rowsOf(camp.data);
  const date = new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "long", year: "numeric", timeZone: "Asia/Kolkata" }).format(new Date());
  return <>
    <PageHeader title="Workspace overview" sub="A clear view of your content, community and business.">
      <LinkButton href="/workspace/posts/bulk" variant="primary">+ Upload content</LinkButton>
    </PageHeader>
    <section className="admin-welcome mb-7 flex flex-wrap items-center justify-between gap-5 rounded-2xl p-6 sm:p-8">
      <div><p className="text-[10px] font-semibold uppercase tracking-[.2em] text-blue-200">YOUR VAYORA WORKSPACE</p><h2 className="mt-3 text-2xl font-semibold tracking-tight text-white sm:text-3xl">Good content starts here.</h2><p className="mt-2 max-w-xl text-sm leading-relaxed text-slate-300">Publish new videos, review channels and keep your community moving.</p></div>
      <div className="rounded-xl border border-white/15 bg-white/5 px-5 py-4"><p className="text-[10px] uppercase tracking-wider text-slate-400">Today Â· IST</p><p className="mt-2 text-sm font-medium text-white">{date}</p></div>
    </section>
    {error && <p role="alert" className="mb-5 rounded-xl bg-red-50 p-4 text-sm text-red-700">Could not load overview: {error.message}</p>}
    {owner && <div className="mb-6 grid gap-2 sm:grid-cols-2">
      <Alert count={a.channel_requests ?? 0} text="channel requests to review" href="/workspace/channels" />
      <Alert count={a.organic_buyers_waiting ?? 0} text="organic users waiting for approval" href="/workspace/approvals" />
      <Alert count={a.payments_to_verify ?? 0} text="payments to verify today" href="/workspace/payments?verify=today" />
      <Alert count={a.open_requests ?? 0} text="open requests and reports" href="/workspace/requests" />
    </div>}
    {owner && <div className="mb-5 grid grid-cols-2 gap-4 xl:grid-cols-4">
      <Stat label="Total app users" value={n(s.users)} />
      <Stat label="Premium members" value={n(s.premium_users)} />
      <Stat label="Revenue today" value={inr(Number(s.revenue_today ?? 0))} />
      <Stat label="Revenue this month" value={inr(Number(s.revenue_month ?? 0))} />
    </div>}
    <div className="mb-7 grid grid-cols-2 gap-4 lg:grid-cols-3">
      <Stat label="Channels" value={n(s.channels)} /><Stat label="Videos & posts" value={n(s.posts)} />
      {owner && <><Stat label="Installs from ads" value={n(s.ads_installs)} /><Stat label="Organic installs" value={n(s.organic_installs)} /><Stat label="Logged-in users" value={n(s.logged_in)} /><Stat label="Free plans claimed" value={n(s.free_claims)} /></>}
    </div>
    <div className="mb-8 grid gap-4 lg:grid-cols-3">
      <Card title="Content library" sub="Manage videos, images, previews and thumbnails."><Link href="/workspace/posts" className="inline-block text-sm font-semibold text-blue-700 hover:underline">Open library â†’</Link></Card>
      <Card title="Channels" sub="Review channel requests and manage their audience."><Link href="/workspace/channels" className="inline-block text-sm font-semibold text-blue-700 hover:underline">Manage channels â†’</Link></Card>
      <Card title="Bulk upload" sub="Preview your files and publish a batch to any channel you manage."><Link href="/workspace/posts/bulk" className="inline-block text-sm font-semibold text-blue-700 hover:underline">Upload a batch â†’</Link></Card>
    </div>
    {owner && <section>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2"><div><h2 className="text-base font-semibold text-slate-900">Audience acquisition</h2><p className="mt-1 text-xs text-slate-500">Installs, registrations and buyers by source and campaign.</p></div><Link href="/workspace/meta" className="text-xs font-medium text-blue-700 hover:underline">View Meta Pixel â†’</Link></div>
      {rows.length === 0 ? <Empty>No installs recorded yet. Campaign activity will appear here.</Empty> : <Table>
        <thead><tr><Th>Source</Th><Th>Campaign</Th><Th>Installs</Th><Th>Registrations</Th><Th>Buyers</Th></tr></thead>
        <tbody>{rows.map((r,i) => <tr key={i}><Td><SourceBadge value={r.source as string} /></Td><Td>{String(r.campaign)}</Td><Td>{n(r.installs)}</Td><Td>{n(r.registrations)}</Td><Td>{n(r.buyers)}</Td></tr>)}</tbody>
      </Table>}
    </section>}
  </>;
}
