import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { PageHeader, Card, LinkButton, Hidden, StatusBadge, Badge } from "@/components/admin/ui";
import { SubmitButton } from "@/components/admin/client";
import { savePost, deletePost, setHidden } from "../../actions";
import PostFields from "../PostFields";
import MediaEditor, { type Item } from "./MediaEditor";

export default async function PostEdit({ params: pending }: { params: Promise<{ id: string }> }) {
 const params=await pending;
  const { sb, role } = await requireAdmin();
  const { data: p } = await sb.from("posts").select("*, channels(name)").eq("id", params.id).maybeSingle();
  if (!p) notFound();
  const { data: can } = await sb.rpc("can_edit_post", { p_post: params.id });
  if (!can) notFound();
  const { data: items } = await sb.from("post_items").select("*").eq("post_id", params.id).order("position");
  const keys = (items ?? []).map((i) => i.thumbnail_key).filter(Boolean) as string[];
  const thumbs: Record<string, string> = {};
  if (keys.length) {
    const { data } = await sb.storage.from("media").createSignedUrls(keys, 3600);
    for (const s of data ?? []) if (s.path && s.signedUrl) thumbs[s.path] = s.signedUrl;
  }
  await Promise.all((items??[]).filter(i=>i.bunny_video_id&&!i.thumbnail_key).map(async i=>{const {data}=await sb.functions.invoke('bunny-stream-url',{body:{item_id:i.id,thumbnail:true}});if(data?.url)thumbs[i.id]=data.url;}));
  const ch = p.channels as { name?: string } | null;
  return (
    <>
      <PageHeader title={p.title} sub={`In ${ch?.name ?? "channel"}`}>
        <StatusBadge value={p.status} />{p.hidden && <Badge tone="red">Hidden</Badge>}
        <LinkButton href="/workspace/posts">Back to posts</LinkButton>
      </PageHeader>
      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="Details">
          <form action={savePost} className="space-y-3">
            <Hidden name="id" value={p.id} />
            <PostFields p={p} />
            <SubmitButton>Save post</SubmitButton>
          </form>
        </Card>
        <Card title="Media" sub="The main video or image, an optional trailer for non-premium viewers, and a thumbnail.">
          <MediaEditor owner={role==="owner"} postId={p.id} channelId={p.channel_id} items={(items ?? []) as Item[]} thumbs={thumbs} />
        </Card>
      </div>
      <Card title="Danger zone" className="mt-4">
        <div className="flex flex-wrap gap-2">
          {role === "owner" && (
            <form action={setHidden}>
              <Hidden name="type" value="post" /><Hidden name="id" value={p.id} /><Hidden name="hidden" value={p.hidden ? "0" : "1"} /><Hidden name="back" value={`/workspace/posts/${p.id}`} />
              <SubmitButton variant="secondary" confirm={p.hidden ? undefined : "Hide this post from the app?"}>{p.hidden ? "Unhide post" : "Hide post"}</SubmitButton>
            </form>
          )}
          {role==="owner"&&<form action={deletePost}>
            <Hidden name="id" value={p.id} />
            <SubmitButton variant="danger" confirm="Delete this post and all its video files? This cannot be undone.">Delete post</SubmitButton>
          </form>}
        </div>
      </Card>
    </>
  );
}
