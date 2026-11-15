import Link from "next/link";
import { requireAdmin, allowedChannels } from "@/lib/admin";
import { ist } from "@/lib/format";
import { PageHeader, Table, Th, Td, Empty, AudienceBadge, StatusBadge, LinkButton, Select, Input, Badge, Button, ErrorNote, Hidden } from "@/components/admin/ui";

import { approveVideo } from "../actions";
import { SubmitButton } from "@/components/admin/client";

type Q = { channel?: string; audience?: string; status?: string; q?: string };
const NONE = "00000000-0000-0000-0000-000000000000";

export default async function Posts({ searchParams: pending }: { searchParams: Promise<Q> }) {
 const searchParams=await pending;
  const { sb, role, user } = await requireAdmin();
  const allowed = await allowedChannels(sb, role, user.id);
  let cq = sb.from("channels").select("id,name").order("name");
  if (allowed) cq = cq.in("id", allowed.length ? allowed : [NONE]);
  let pq = sb.from("posts").select("id,title,audience,status,hidden,publish_at,created_at,channel_id,channels(name),post_items(thumbnail_key,is_premium)").order("created_at", { ascending: false }).limit(200);
  if (allowed) pq = pq.in("channel_id", allowed.length ? allowed : [NONE]);
  if (searchParams.channel) pq = pq.eq("channel_id", searchParams.channel);
  if (searchParams.audience) pq = pq.eq("audience", searchParams.audience);
  if (searchParams.status) pq = pq.eq("status", searchParams.status);
  if (searchParams.q?.trim()) pq = pq.ilike("title", `%${searchParams.q.trim().replace(/[%_]/g, "")}%`);
  const [{ data: channels }, { data: posts, error }] = await Promise.all([cq, pq]);

  const keys = (posts ?? []).map((p) => (p.post_items as { thumbnail_key: string | null }[])?.find((i) => i.thumbnail_key)?.thumbnail_key).filter(Boolean) as string[];
  const thumbs: Record<string, string> = {};
  if (keys.length) {
    const { data } = await sb.storage.from("media").createSignedUrls(keys, 3600);
    for (const s of data ?? []) if (s.path && s.signedUrl) thumbs[s.path] = s.signedUrl;
  }
  return (
    <>
      <PageHeader title="Posts" sub="Review uploaded videos, choose their audience, then approve them. Draft videos stay hidden from viewers."><div className="flex gap-2"><LinkButton href="/workspace/posts/bulk" variant="primary">Bulk upload</LinkButton><LinkButton href="/workspace/posts/new">New post</LinkButton></div></PageHeader>
      <ErrorNote error={error} />
      <form className="mb-4 grid grid-cols-2 gap-2 md:grid-cols-5">
        <Select name="channel" defaultValue={searchParams.channel ?? ""} aria-label="Channel"><option value="">All channels</option>{(channels ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</Select>
        <Select name="audience" defaultValue={searchParams.audience ?? ""} aria-label="Audience"><option value="">Any audience</option><option value="all">Both ads and organic</option><option value="organic">Organic only</option><option value="ads">Ads only</option></Select>
        <Select name="status" defaultValue={searchParams.status ?? ""} aria-label="Status"><option value="">Any status</option><option value="draft">Pending / draft</option><option value="published">Published</option><option value="scheduled">Scheduled</option></Select>
        <Input name="q" defaultValue={searchParams.q ?? ""} placeholder="Search title" aria-label="Search title" />
        <Button variant="secondary">Filter</Button>
      </form>
      {(posts ?? []).length === 0 ? <Empty>No posts match. Create one with “New post”.</Empty> : (
        <Table min={760}>
          <thead><tr><Th></Th><Th>Title</Th><Th>Channel</Th><Th>Audience</Th><Th>Status</Th><Th>Premium</Th><Th>Date</Th><Th>Approval</Th></tr></thead>
          <tbody>
            {(posts ?? []).map((p) => {
              const items = (p.post_items ?? []) as { thumbnail_key: string | null; is_premium: boolean }[];
              const t = items.find((i) => i.thumbnail_key)?.thumbnail_key;
              const ch = p.channels as unknown as { name?: string } | { name?: string }[] | null;
              return (
                <tr key={p.id}>
                  <Td className="w-20">
                    <div className="grid h-12 w-20 place-items-center overflow-hidden rounded-md bg-gray-100 text-[10px] text-gray-400">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      {t && thumbs[t] ? <img src={thumbs[t]} alt="" className="h-full w-full object-cover" /> : "No image"}
                    </div>
                  </Td>
                  <Td><Link href={`/workspace/posts/${p.id}`} className="font-medium text-gray-900 hover:text-violet-700">{p.title}</Link>{p.hidden && <div className="mt-1"><Badge tone="red">Hidden</Badge></div>}{items.length === 0 && <div className="mt-1"><Badge tone="amber">No media yet</Badge></div>}</Td>
                  <Td>{(Array.isArray(ch) ? ch[0]?.name : ch?.name) ?? "—"}</Td>
                  <Td><AudienceBadge value={p.audience} /></Td>
                  <Td><StatusBadge value={p.status} />{p.status === "scheduled" && p.publish_at && <div className="mt-1 text-xs text-gray-500">{ist(p.publish_at)}</div>}</Td>
                  <Td>{items.some((i) => i.is_premium) ? <Badge tone="amber">Premium</Badge> : <span className="text-gray-400">Free</span>}</Td>
                  <Td className="whitespace-nowrap text-xs text-gray-500">{ist(p.created_at)}</Td>
                  <Td>{p.status === "draft" && items.length > 0 ? (
                    <form action={approveVideo} className="flex flex-wrap gap-2">
                      <Hidden name="id" value={p.id} />
                      <Select name="audience" defaultValue={p.audience} aria-label="Video audience">
                        <option value="all">Both ads and organic</option><option value="ads">Ads only</option><option value="organic">Organic only</option>
                      </Select>
                      <SubmitButton small variant="success">Approve video</SubmitButton>
                    </form>
                  ) : p.status === "draft" ? <Badge tone="amber">Waiting for media</Badge> : <StatusBadge value={p.status} />}</Td>
                </tr>
              );
            })}
          </tbody>
        </Table>
      )}
    </>
  );
}

