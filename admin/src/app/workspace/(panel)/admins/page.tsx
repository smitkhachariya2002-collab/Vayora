import { requireAdmin } from "@/lib/admin";
import { ist, rowsOf } from "@/lib/format";
import { PageHeader, Card, Table, Th, Td, Field, Input, Select, Hidden, Badge, ErrorNote } from "@/components/admin/ui";
import { SubmitButton } from "@/components/admin/client";
import { inviteAdmin, removeAdmin } from "../actions";

export default async function Admins() {
  const { sb, user } = await requireAdmin(true);
  const [{ data, error }, { data: channels }] = await Promise.all([
    sb.rpc("admin_list_admins"),
    sb.from("channels").select("id,name").eq("review_status", "approved").order("name"),
  ]);
  const rows = rowsOf(data);
  const owners = rows.filter((r) => r.role === "owner").length;
  return (
    <>
      <PageHeader title="Admins" sub="Owners can do everything. Content admins manage only the channels you assign and their posts." />
      <ErrorNote error={error} />
      <Table>
        <thead><tr><Th>Email</Th><Th>Role</Th><Th>Channels</Th><Th>Added</Th><Th></Th></tr></thead>
        <tbody>
          {rows.map((r) => {
            const me = r.user_id === user.id;
            const lastOwner = r.role === "owner" && owners <= 1;
            return (
              <tr key={r.user_id as string}>
                <Td className="font-medium text-gray-900">{String(r.email)}{me && <span className="ml-2 text-xs font-normal text-gray-500">(you)</span>}</Td>
                <Td><Badge tone={r.role === "owner" ? "purple" : "blue"}>{String(r.role)}</Badge></Td>
                <Td>{r.role === "owner" ? "All channels" : ((r.channels as string[]) ?? []).join(", ") || "None"}</Td>
                <Td className="whitespace-nowrap text-xs text-gray-500">{ist(r.created_at as string)}</Td>
                <Td>
                  {me || lastOwner ? <span className="text-xs text-gray-400">{lastOwner ? "Last owner" : ""}</span> : (
                    <form action={removeAdmin}><Hidden name="user" value={r.user_id as string} /><SubmitButton small variant="danger" confirm={`Remove ${r.email} as an admin?`}>Remove</SubmitButton></form>
                  )}
                </Td>
              </tr>
            );
          })}
        </tbody>
      </Table>
      <Card title="Invite or update an admin" sub="If the person has no account yet, they get an invite email." className="mt-4 max-w-2xl">
        <form action={inviteAdmin} className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Email"><Input type="email" name="email" required /></Field>
            <Field label="Role"><Select name="role" defaultValue="content"><option value="content">Content admin</option><option value="owner">Owner</option></Select></Field>
          </div>
          <fieldset>
            <legend className="mb-1 text-sm font-medium text-gray-700">Channel access (content admins need at least one)</legend>
            {(channels ?? []).length === 0 ? <p className="text-sm text-gray-500">No approved channels yet.</p> : (
              <div className="grid gap-1 sm:grid-cols-2">
                {(channels ?? []).map((c) => <label key={c.id} className="flex items-center gap-2 text-sm text-gray-800"><input type="checkbox" name="channels" value={c.id} /> {c.name}</label>)}
              </div>
            )}
          </fieldset>
          <SubmitButton confirm="Give this person admin access?">Save admin</SubmitButton>
        </form>
      </Card>
    </>
  );
}
