import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";

export type Role = "owner" | "content";

/** Signed-in admin or redirect. The database re-checks the role inside every RPC and policy. */
export async function requireAdmin(ownerOnly = false) {
  const sb = await supabaseServer();
  const { data } = await sb.auth.getUser();
  if (!data.user) redirect("/workspace/login");
  const { data: role } = await sb.rpc("admin_role");
  if (role !== "owner" && role !== "content") redirect("/workspace/login?error=" + encodeURIComponent("This account is not an admin."));
  if (ownerOnly && role !== "owner") redirect("/workspace?error=" + encodeURIComponent("That page is only available to the owner."));
  return { sb, user: data.user, role: role as Role };
}

/** Channel ids a content admin may manage; null = all (owner). */
export async function allowedChannels(sb: Awaited<ReturnType<typeof supabaseServer>>, role: Role, userId: string): Promise<string[] | null> {
  if (role === "owner") return null;
  const { data } = await sb.from("admin_channel_access").select("channel_id").eq("user_id", userId);
  return (data ?? []).map((r) => r.channel_id as string);
}

/** Redirect back with a flash message. Call it last: redirect() throws. */
export function flash(path: string, error: { message: string } | null | undefined, ok: string): never {
  const sep = path.includes("?") ? "&" : "?";
  redirect(path + sep + (error ? "error=" + encodeURIComponent(error.message) : "ok=" + encodeURIComponent(ok)));
}

export const str = (fd: FormData, k: string) => String(fd.get(k) ?? "").trim();
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
