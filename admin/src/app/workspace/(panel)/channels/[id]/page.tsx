import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { PageHeader, Card, Field, Input, Textarea, Select, Hidden, LinkButton, StatusBadge } from "@/components/admin/ui";
import { SubmitButton } from "@/components/admin/client";
import { saveChannel } from "../../actions";
import IconUpload from "./IconUpload";

const CATS = ["Movies", "Music", "Education", "Gaming", "Lifestyle", "Tech", "Other"];

export default async function ChannelEdit({ params: pending }: { params: Promise<{ id: string }> }) {
 const params=await pending;
  const isNew = params.id === "new";
  const { sb, role } = await requireAdmin(isNew);
  let c: Record<string, any> | null = null;
  let iconUrl: string | null = null;
  if (!isNew) {
    const { data } = await sb.from("channels").select("*").eq("id", params.id).maybeSingle();
    if (!data) notFound();
    c = data;
    const { data: can } = await sb.rpc("can_manage_channel", { p_channel: params.id });
    if (!can) notFound();
    if (c?.icon_url) {
      const { data: s } = await sb.storage.from("channel-icons").createSignedUrl(c.icon_url, 3600);
      iconUrl = s?.signedUrl ?? null;
    }
  }
  return (
    <>
      <PageHeader title={isNew ? "New channel" : `Edit ${c?.name}`} sub={isNew ? "Channels created here are approved immediately." : undefined}>
        {c && <StatusBadge value={c.review_status} />}
        {c && <LinkButton href={`/workspace/posts/bulk?channel=${c.id}`} variant="primary">Bulk upload to channel</LinkButton>}<LinkButton href="/workspace/channels">Back to channels</LinkButton>
      </PageHeader>
      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <form action={saveChannel} className="space-y-3">
            <Hidden name="id" value={c?.id ?? ""} />
            <Field label="Name"><Input name="name" defaultValue={c?.name ?? ""} required minLength={2} maxLength={80} /></Field>
            <Field label="Description"><Textarea name="description" rows={3} defaultValue={c?.description ?? ""} /></Field>
            <div className="grid gap-3 sm:grid-cols-2">
              <Field label="Category">
                <Select name="category" defaultValue={c?.category ?? ""}>
                  <option value="">None</option>{CATS.map((x) => <option key={x}>{x}</option>)}
                </Select>
              </Field>
              <Field label="Tags" hint="Separate with commas"><Input name="tags" defaultValue={(c?.tags ?? []).join(", ")} /></Field>
              <Field label="Audience" hint="Who can see this channel and its posts">
                <Select name="audience" defaultValue={c?.audience ?? "all"}>
                  <option value="all">Everyone</option><option value="organic">Organic only</option><option value="ads">Ads only</option>
                </Select>
              </Field>
              <Field label="Status" hint="Draft channels are not shown in the app">
                <Select name="status" defaultValue={c?.status === "draft" ? "draft" : "published"}>
                  <option value="published">Published</option><option value="draft">Draft</option>
                </Select>
              </Field>
            </div>
            <SubmitButton>{isNew ? "Create channel" : "Save channel"}</SubmitButton>
            {role === "content" && <p className="text-xs text-gray-500">Changing the name or description sends the channel back for review.</p>}
          </form>
        </Card>
        <Card title="Picture" sub={isNew ? "Save the channel first, then add a picture." : "Square image, up to 2 MB."}>
          {!isNew && c && <IconUpload channelId={c.id} current={iconUrl} />}
        </Card>
      </div>
    </>
  );
}
