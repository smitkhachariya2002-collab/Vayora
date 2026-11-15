import { requireAdmin, allowedChannels } from "@/lib/admin";
import { PageHeader, Card, LinkButton, Empty } from "@/components/admin/ui";
import { SubmitButton } from "@/components/admin/client";
import { createPost } from "../../actions";
import PostFields from "../PostFields";

export default async function NewPost() {
  const { sb, role, user } = await requireAdmin();
  const allowed = await allowedChannels(sb, role, user.id);
  let q = sb.from("channels").select("id,name").eq("review_status", "approved").order("name");
  if (allowed) q = q.in("id", allowed.length ? allowed : ["00000000-0000-0000-0000-000000000000"]);
  const { data: channels } = await q;
  return (
    <>
      <PageHeader title="New post" sub="Save the details first, then add the video on the next screen."><LinkButton href="/workspace/posts">Back to posts</LinkButton></PageHeader>
      {(channels ?? []).length === 0 ? <Empty>Create and approve a channel first. Posts live inside channels.</Empty> : (
        <Card className="max-w-2xl">
          <form action={createPost} className="space-y-3">
            <PostFields channels={channels ?? []} />
            <SubmitButton>Create post</SubmitButton>
          </form>
        </Card>
      )}
    </>
  );
}
