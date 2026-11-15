import Link from "next/link";
import { requireAdmin, allowedChannels } from "@/lib/admin";
import { ist, rowsOf } from "@/lib/format";
import { PageHeader, Card, Table, Th, Td, Empty, AudienceBadge, StatusBadge, SourceBadge, LinkButton, Select, Hidden, Badge, ErrorNote } from "@/components/admin/ui";
import { SubmitButton } from "@/components/admin/client";
import { reviewChannel, setHidden } from "../actions";

export default async function Channels() {
  const { sb, role, user } = await requireAdmin();
  const owner = role === "owner";
  const allowed = await allowedChannels(sb, role, user.id);
  let q = sb.from("channels").select("id,name,category,audience,status,review_status,hidden,members_count,created_by,created_at").order("created_at", { ascending: false }).limit(300);
  if (allowed) q = q.in("id", allowed.length ? allowed : ["00000000-0000-0000-0000-000000000000"]);
  const [req, list] = await Promise.all([owner ? sb.rpc("admin_channel_requests") : Promise.resolve({ data: [], error: null }), q]);
  const requests = rowsOf(req.data);
  const channels = (list.data ?? []).filter((c) => c.review_status !== "pending");
  return (
    <>
      <PageHeader title="Channels" sub="Approve new channels and choose whether ads users, organic users, or both can see them.">
        {owner && <LinkButton href="/workspace/channels/new" variant="primary">New channel</LinkButton>}
      </PageHeader>
      <ErrorNote error={req.error ?? list.error} />

      {owner && (
        <div className="mb-6">
          <h2 className="mb-2 text-sm font-semibold text-gray-900">Channel requests ({requests.length})</h2>
          {requests.length === 0 ? <Empty>No channels are waiting for approval.</Empty> : (
            <div className="grid gap-3 md:grid-cols-2">
              {requests.map((r) => (
                <Card key={r.id as string}>
                  <div className="flex gap-3">
                    <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-violet-100 text-lg font-bold text-violet-700">{String(r.name ?? "?").charAt(0).toUpperCase()}</div>
                    <div className="min-w-0">
                      <div className="font-semibold text-gray-900">{String(r.name)}</div>
                      {r.description ? <p className="mt-0.5 text-sm text-gray-600">{String(r.description)}</p> : null}
                      <p className="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-gray-500">
                        by {String(r.creator_name ?? "user")} ({String(r.creator_email ?? "no email")}) · <SourceBadge value={r.creator_source as string} /> · {ist(r.created_at as string)}
                        {r.category ? <Badge>{String(r.category)}</Badge> : null}
                      </p>
                    </div>
                  </div>
                  <div className="mt-3 flex flex-wrap items-end gap-2">
                    <form action={reviewChannel} className="flex flex-wrap items-end gap-2">
                      <Hidden name="id" value={r.id as string} /><Hidden name="approve" value="1" />
                      <label className="text-xs font-medium text-gray-700">Audience
                        <Select name="audience" defaultValue="all" className="mt-1 !w-40">
                          <option value="all">Both ads and organic</option><option value="organic">Organic only</option><option value="ads">Ads only</option>
                        </Select>
                      </label>
                      <SubmitButton variant="success">Approve</SubmitButton>
                    </form>
                    <form action={reviewChannel}>
                      <Hidden name="id" value={r.id as string} /><Hidden name="approve" value="0" />
                      <SubmitButton variant="danger" confirm={`Reject "${r.name}"? The creator will see it as not approved.`}>Reject</SubmitButton>
                    </form>
                  </div>
                </Card>
              ))}
            </div>
          )}
        </div>
      )}

      <h2 className="mb-2 text-sm font-semibold text-gray-900">All channels</h2>
      {channels.length === 0 ? <Empty>No channels yet.</Empty> : (
        <Table min={760}>
          <thead><tr><Th>Channel</Th><Th>Category</Th><Th>Audience</Th><Th>Status</Th><Th>Review</Th><Th>Members</Th><Th>Created</Th><Th></Th></tr></thead>
          <tbody>
            {channels.map((c) => (
              <tr key={c.id}>
                <Td>
                  <Link href={`/workspace/channels/${c.id}`} className="flex items-center gap-2 font-medium text-gray-900 hover:text-violet-700">
                    <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-violet-100 text-sm font-bold text-violet-700">{c.name.charAt(0).toUpperCase()}</span>{c.name}
                  </Link>
                  {c.hidden && <div className="mt-1"><Badge tone="red">Hidden</Badge></div>}
                </Td>
                <Td>{c.category ?? "—"}</Td>
                <Td><AudienceBadge value={c.audience} /></Td>
                <Td><StatusBadge value={c.status} /></Td>
                <Td><StatusBadge value={c.review_status} /></Td>
                <Td>{c.members_count}</Td>
                <Td className="whitespace-nowrap text-xs text-gray-500">{ist(c.created_at)}</Td>
                <Td>
                  <div className="flex flex-wrap gap-1.5">
                    <LinkButton href={`/workspace/channels/${c.id}`} small>Edit</LinkButton>
                    {owner && (
                      <form action={setHidden}>
                        <Hidden name="type" value="channel" /><Hidden name="id" value={c.id} /><Hidden name="hidden" value={c.hidden ? "0" : "1"} />
                        <SubmitButton small variant={c.hidden ? "secondary" : "danger"} confirm={c.hidden ? undefined : `Hide "${c.name}" and its posts from the app?`}>{c.hidden ? "Unhide" : "Hide"}</SubmitButton>
                      </form>
                    )}
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

