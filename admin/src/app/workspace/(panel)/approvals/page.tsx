import { requireAdmin } from "@/lib/admin";
import { ist, rowsOf } from "@/lib/format";
import { PageHeader, Table, Th, Td, Empty, SourceBadge, Tabs, Hidden, ErrorNote, Badge } from "@/components/admin/ui";
import { SubmitButton } from "@/components/admin/client";
import { setAccess } from "../actions";

const TABS = ["pending", "approved", "rejected"] as const;

export default async function Approvals({ searchParams: pending }: { searchParams: Promise<{ tab?: string }> }) {
 const searchParams=await pending;
  const { sb } = await requireAdmin(true);
  const tab = TABS.includes(searchParams.tab as (typeof TABS)[number]) ? searchParams.tab! : "pending";
  const { data, error } = await sb.rpc("admin_approvals", { p_status: tab });
  const rows = rowsOf(data);
  const back = `/workspace/approvals?tab=${tab}`;
  const act = (user: string, status: string, label: string, variant: "success" | "danger" | "secondary", confirm?: string) => (
    <form action={setAccess}>
      <Hidden name="user" value={user} /><Hidden name="status" value={status} /><Hidden name="back" value={back} />
      <SubmitButton small variant={variant} confirm={confirm}>{label}</SubmitButton>
    </form>
  );
  return (
    <>
      <PageHeader title="Approvals" sub="Organic users asking for full access. Approved users see the same content as ads users." />
      <Tabs current={tab} items={TABS.map((t) => ({ key: t, label: t[0].toUpperCase() + t.slice(1), href: `/workspace/approvals?tab=${t}` }))} />
      <ErrorNote error={error} />
      {rows.length === 0 ? <Empty>Nothing {tab} right now.</Empty> : (
        <Table>
          <thead><tr><Th>User</Th><Th>Source</Th><Th>Campaign</Th><Th>Plan</Th><Th>Joined</Th><Th>Actions</Th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id as string}>
                <Td>{r.email ? String(r.email) : <Badge>Guest</Badge>}</Td>
                <Td><SourceBadge value={r.source as string} /></Td>
                <Td>{r.campaign ? String(r.campaign) : "—"}</Td>
                <Td>{r.plan_name ? <Badge tone="amber">{String(r.plan_name)}</Badge> : "Requested full access"}</Td>
                <Td className="whitespace-nowrap text-xs text-gray-500">{ist(r.created_at as string)}</Td>
                <Td>
                  <div className="flex flex-wrap gap-1.5">
                    {tab !== "approved" && act(r.id as string, "approved", "Approve", "success")}
                    {tab === "pending" && act(r.id as string, "rejected", "Reject", "danger", "Reject this request?")}
                    {tab === "approved" && act(r.id as string, "none", "Revoke", "danger", "Revoke full access for this user?")}
                  </div>
                </Td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
    </>
  );
}
