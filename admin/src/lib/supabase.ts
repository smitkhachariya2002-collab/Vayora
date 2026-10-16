import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

export async function db() {
  const jar = await cookies();
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) throw new Error("Supabase environment variables are not configured");
  return createServerClient(url, key, {
    cookies: {
      getAll: () => jar.getAll(),
      setAll(values) {
        try { values.forEach(({ name, value, options }) => jar.set(name, value, options)); }
        catch { /* Server components cannot set cookies; actions can. */ }
      },
    },
  });
}

export async function requireAdmin(owner = false) {
  const client = await db();
  const { data: { user }, error } = await client.auth.getUser();
  if (error || !user || user.is_anonymous) redirect("/login");
  const { data: admin } = await client.from("admins").select("role").eq("user_id", user.id).single();
  if (!admin || (owner && admin.role !== "owner")) redirect("/login?error=Admin+access+required");
  return { client, user, owner: admin.role === "owner" };
}
