import { Field, Input, Textarea, Select } from "@/components/admin/ui";

/** IST value for <input type="datetime-local"> from a UTC timestamp. */
export const toIstLocal = (utc: string | null | undefined) =>
  utc ? new Date(new Date(utc).getTime() + 5.5 * 3600 * 1000).toISOString().slice(0, 16) : "";

export default function PostFields({ p, channels }: { p?: Record<string, any> | null; channels?: { id: string; name: string }[] }) {
  return (
    <>
      <Field label="Title"><Input name="title" defaultValue={p?.title ?? ""} required maxLength={160} /></Field>
      <Field label="Description"><Textarea name="description" rows={3} defaultValue={p?.description ?? ""} /></Field>
      <div className="grid gap-3 sm:grid-cols-2">
        {channels && (
          <Field label="Channel">
            <Select name="channel_id" required defaultValue=""><option value="" disabled>Choose a channel</option>{channels.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</Select>
          </Field>
        )}
        <Field label="Audience">
          <Select name="audience" defaultValue={p?.audience ?? "all"}><option value="all">Everyone</option><option value="organic">Organic only</option><option value="ads">Ads only</option></Select>
        </Field>
        <Field label="Status" hint="Draft posts are not shown in the app">
          <Select name="status" defaultValue={p?.status ?? "draft"}><option value="draft">Draft</option><option value="published">Published</option><option value="scheduled">Scheduled</option></Select>
        </Field>
        <Field label="Publish at (IST)" hint="Only used when the status is Scheduled">
          <Input type="datetime-local" name="publish_at" defaultValue={toIstLocal(p?.publish_at)} />
        </Field>
      </div>
    </>
  );
}
