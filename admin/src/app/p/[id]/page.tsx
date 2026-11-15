import type { Metadata } from "next";
import { createClient } from "@supabase/supabase-js";
import SiteShell from "@/components/SiteShell";

export const dynamic = "force-dynamic";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function preview(id: string) {
  const key = process.env.SUPABASE_SECRET_KEY;
  if (!key || !UUID.test(id)) return null;
  const sb = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, key, { auth: { persistSession: false } });
  const { data } = await sb.rpc("public_post_preview", { p_id: id });
  return (data as { title: string; description?: string; channel: string } | null) ?? null;
}

export async function generateMetadata({ params: pending }: { params: Promise<{ id: string }> }): Promise<Metadata> {
 const params=await pending;
  const p = await preview(params.id);
  return p ? { title: p.title, description: p.description ?? `Shared from ${p.channel} on Vayora` } : { title: "Vayora post" };
}

export default async function Post({ params: pending }: { params: Promise<{ id: string }> }) {
 const params=await pending;
  const p = await preview(params.id);
  return (
    <SiteShell>
      <main className="mx-auto max-w-md px-4 py-14 text-center space-y-3">
        <h1 className="text-xl font-bold">{p?.title ?? "Open this post in Vayora"}</h1>
        {p && <p className="text-sm text-muted">{p.channel}</p>}
        {p?.description && <p className="text-sm">{p.description}</p>}
        <a href="/d" className="btn mt-4">Get the app</a>
      </main>
    </SiteShell>
  );
}
