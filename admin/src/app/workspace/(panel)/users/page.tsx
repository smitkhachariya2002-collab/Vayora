import Link from "next/link";
import {range,pageNumber,type ReportQuery} from "@/lib/reporting";
import {DateFields,Pagination} from "@/components/admin/ReportFilters";
import { requireAdmin } from "@/lib/admin";
import { inr, ist, rowsOf } from "@/lib/format";
import { PageHeader, Table, Th, Td, Empty, SourceBadge, StatusBadge, Select, Input, Button, Hidden, Badge, ErrorNote } from "@/components/admin/ui";
import { SubmitButton } from "@/components/admin/client";
import { setAccess, grantPremium } from "../actions";

type Q = ReportQuery;

export default async function Users({ searchParams: pending }: { searchParams: Promise<Q> }) {
 const searchParams=await pending;
  const { sb } = await requireAdmin(true);
  const dates=range(searchParams);
  const [{ data, error }, { data: plans }] = await Promise.all([
    sb.rpc("admin_users_filtered", {
      p_search: searchParams.q ?? null, p_source: searchParams.source ?? null, p_plan: searchParams.plan ?? null,
      p_guest: searchParams.account === "guest" ? true : searchParams.account === "registered" ? false : null,
      p_access: searchParams.access||null, p_from:dates.from,p_to:dates.to,p_customer:searchParams.customer||null,p_sort:searchParams.sort||"newest",p_limit:50,p_offset:(pageNumber(searchParams.page)-1)*50,
    }),
    sb.from("plans").select("id,name").eq("active", true).order("position"),
  ]);
  const rows = rowsOf(data);
  const total = (data as { total?: number } | null)?.total ?? rows.length;
  const back = "/workspace/users?" + new URLSearchParams(Object.entries(searchParams).filter(([, v]) => v) as [string, string][]).toString();
  return (
    <>
      <PageHeader title={`Users (${total})`} sub="Filter by joined date, source, plan and account activity. Dates are inclusive in IST." />
      <ErrorNote error={error} />
      <form className="mb-4 grid grid-cols-2 gap-2 md:grid-cols-5">
        <Input name="q" defaultValue={searchParams.q ?? ""} placeholder="Search email or name" aria-label="Search email or name" />
        <Select name="source" defaultValue={searchParams.source ?? ""} aria-label="Source"><option value="">All sources</option><option value="ads">Ads</option><option value="organic">Organic</option></Select>
        <Select name="account" defaultValue={searchParams.account ?? ""} aria-label="Account"><option value="">Guests and registered</option><option value="guest">Guests</option><option value="registered">Registered</option></Select>
        <Select name="plan" defaultValue={searchParams.plan ?? ""} aria-label="Plan"><option value="">Any plan</option><option value="active">Active plan</option><option value="none">No plan</option></Select>
        <DateFields q={searchParams}/><Select name="customer" defaultValue={searchParams.customer??""} aria-label="Customer activity"><option value="">All customer activity</option><option value="repeat">Repeat buyers</option><option value="first">One paid order</option><option value="never">Never purchased</option><option value="returning">Returning app users</option></Select><Select name="sort" defaultValue={searchParams.sort??"newest"} aria-label="Sort"><option value="newest">Newest first</option><option value="oldest">Oldest first</option><option value="spent_high">Highest spending</option><option value="spent_low">Lowest spending</option><option value="recently_active">Recently active</option><option value="repeat">Most paid orders</option></Select><Button variant="secondary">Filter</Button>
      </form>
      <Pagination path="/workspace/users" q={searchParams} total={total}/>
      {rows.length === 0 ? <Empty>No users match this filter.</Empty> : (
        <Table min={860}>
          <thead><tr><Th>User</Th><Th>Source</Th><Th>Plan</Th><Th>Access</Th><Th>Joined / activity</Th><Th>Purchases</Th><Th>Manage</Th></tr></thead>
          <tbody>
            {rows.map((r) => {
              const id = r.id as string;
              return (
                <tr key={id}>
                  <Td>{r.email ? <Link className="font-medium text-blue-700 underline" href={"/workspace/users/"+id}>{String(r.email)}</Link> : <Link href={"/workspace/users/"+id}><Badge>Guest history</Badge></Link>}{r.display_name ? <div className="text-xs text-gray-500">{String(r.display_name)}</div> : null}</Td>
                  <Td><SourceBadge value={r.source as string} />{r.campaign ? <div className="mt-1 text-xs text-gray-500">{String(r.campaign)}</div> : null}</Td>
                  <Td>{r.plan_name ? <><Badge tone="amber">{String(r.plan_name)}</Badge><div className="mt-1 text-xs text-gray-500">until {ist(r.plan_ends_at as string)}</div></> : <span className="text-gray-400">None</span>}</Td>
                  <Td>{r.source === "ads" ? <Badge tone="green">full (ads)</Badge> : <StatusBadge value={r.ads_access_status as string} />}</Td>
                  <Td className="whitespace-nowrap text-xs text-gray-500">{ist(r.created_at as string)}<div>Last activity: {r.last_seen?ist(r.last_seen as string):"Not measured"}</div></Td><Td>{Number(r.paid_orders)} paid · {inr(Number(r.spent))}</Td>
                  <Td>
                    <details>
                      <summary className="cursor-pointer text-sm font-medium text-violet-700">Manage</summary>
                      <div className="mt-2 space-y-2">
                        {r.source !== "ads" && (
                          <div className="flex flex-wrap gap-1.5">
                            {r.ads_access_status !== "approved" && <form action={setAccess}><Hidden name="user" value={id} /><Hidden name="status" value="approved" /><Hidden name="back" value={back} /><SubmitButton small variant="success">Approve access</SubmitButton></form>}
                            {r.ads_access_status === "pending" && <form action={setAccess}><Hidden name="user" value={id} /><Hidden name="status" value="rejected" /><Hidden name="back" value={back} /><SubmitButton small variant="danger" confirm="Reject this request?">Reject</SubmitButton></form>}
                            {r.ads_access_status === "approved" && <form action={setAccess}><Hidden name="user" value={id} /><Hidden name="status" value="none" /><Hidden name="back" value={back} /><SubmitButton small variant="danger" confirm="Revoke full access for this user?">Revoke access</SubmitButton></form>}
                          </div>
                        )}
                        <form action={grantPremium} className="flex flex-wrap items-center gap-1.5">
                          <Hidden name="user" value={id} /><Hidden name="back" value={back} />
                          <Select name="plan" defaultValue="" aria-label="Plan to grant" className="!w-36 !py-1 !text-xs"><option value="" disabled>Choose plan</option>{(plans ?? []).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</Select>
                          <SubmitButton small confirm="Give this user the plan for free? It extends any plan they already have.">Grant premium</SubmitButton>
                        </form>
                      </div>
                    </details>
                  </Td>
                </tr>
              );
            })}
          </tbody>
        </Table>
      )}
    </>
  );
}
