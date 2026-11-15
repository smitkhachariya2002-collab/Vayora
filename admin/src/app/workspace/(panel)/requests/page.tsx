import Link from "next/link";
import { requireAdmin } from "@/lib/admin";
import { ist, rowsOf } from "@/lib/format";
import { PageHeader, Card, Empty, Tabs, Hidden, Badge, ErrorNote } from "@/components/admin/ui";
import { SubmitButton } from "@/components/admin/client";
import { closeRequest, deleteAccount, setHidden } from "../actions";

const TABS = [
  { key: "deletion", label: "Account deletion" },
  { key: "report", label: "Content reports" },
  { key: "other", label: "Other requests" },
];

export default async function Requests({ searchParams: pending }: { searchParams: Promise<{ tab?: string }> }) {
 const searchParams=await pending;
  const { sb } = await requireAdmin(true);
  const tab = TABS.some((t) => t.key === searchParams.tab) ? searchParams.tab! : "deletion";
  const { data, error } = await sb.rpc("admin_requests", { p_status: "open" });
  const all = rowsOf(data);
  const rows = all.filter((r) => r.kind === tab);
  const back = `/workspace/requests?tab=${tab}`;
  return (
    <>
      <PageHeader title="Requests" sub="Open requests from the app and the website." />
      <Tabs current={tab} items={TABS.map((t) => ({ ...t, href: `/workspace/requests?tab=${t.key}`, count: all.filter((r) => r.kind === t.key).length }))} />
      <ErrorNote error={error} />
      {rows.length === 0 ? <Empty>No open requests here.</Empty> : (
        <div className="space-y-3">
          {rows.map((r) => {
            const id = r.id as string;
            const who = (r.user_email ?? r.contact_email) as string | null;
            return (
              <Card key={id}>
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0 text-sm">
                    <div className="font-medium text-gray-900">{who ?? "No email given"} <span className="ml-1 text-xs font-normal text-gray-500">{ist(r.created_at as string)}</span></div>
                    {r.reason ? <div className="mt-1"><Badge tone="amber">{String(r.reason)}</Badge></div> : null}
                    {r.details ? <p className="mt-1 whitespace-pre-wrap text-gray-700">{String(r.details)}</p> : null}
                    {r.target_type && r.target_type !== "account" ? (
                      <p className="mt-1 text-xs text-gray-600">
                        About {String(r.target_type)}:{" "}
                        {r.target_title
                          ? <Link className="font-medium text-violet-700 underline" href={r.target_type === "post" ? `/workspace/posts/${r.target_id}` : `/workspace/channels/${r.target_id}`}>{String(r.target_title)}</Link>
                          : "already deleted"}
                      </p>
                    ) : null}
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {tab === "report" && r.target_title && (r.target_type === "post" || r.target_type === "channel") ? (
                      <form action={setHidden}>
                        <Hidden name="type" value={r.target_type as string} /><Hidden name="id" value={r.target_id as string} /><Hidden name="hidden" value="1" /><Hidden name="back" value={back} />
                        <SubmitButton small variant="danger" confirm={`Hide this ${r.target_type} from the app?`}>Hide content</SubmitButton>
                      </form>
                    ) : null}
                    {tab === "deletion" && r.user_id ? (
                      <form action={deleteAccount}>
                        <Hidden name="user" value={r.user_id as string} /><Hidden name="id" value={id} /><Hidden name="back" value={back} />
                        <SubmitButton small variant="danger" confirm={`Permanently delete the account ${who ?? ""} and its files? This cannot be undone.`}>Delete account</SubmitButton>
                      </form>
                    ) : null}
                    <form action={closeRequest}>
                      <Hidden name="id" value={id} /><Hidden name="back" value={back} />
                      <SubmitButton small variant="secondary">Close</SubmitButton>
                    </form>
                  </div>
                </div>
                {tab === "deletion" && !r.user_id ? <p className="mt-2 text-xs text-gray-500">Sent from the website without signing in. Find the user by email on the Users page, or reply by email.</p> : null}
              </Card>
            );
          })}
        </div>
      )}
    </>
  );
}
