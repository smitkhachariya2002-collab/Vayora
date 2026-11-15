import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { requireAdmin } from "@/lib/admin";
import { Flash, SignOut } from "@/components/admin/client";
import Nav from "./Nav";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Vayora Admin", robots: { index: false, follow: false } };

export default async function PanelLayout({ children }: { children: React.ReactNode }) {
  const { sb, user, role } = await requireAdmin();
  const { data: counts } = await sb.rpc("admin_nav_counts");
  return <div className="admin-workspace">
    <a href="#admin-content" className="admin-skip">Skip to content</a>
    <aside className="admin-sidebar">
      <Link href="/workspace" className="admin-brand">
        <span className="admin-brand-mark"><svg width="25" height="25" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M7 18h10a4 4 0 0 0 .6-7.95A6 6 0 0 0 6 9a4.5 4.5 0 0 0 1 9Z" /><path d="m10 10 5 3-5 3z" /></svg></span>
        <span>Vayora<span className="admin-brand-caption">ADMIN WORKSPACE</span></span>
      </Link>
      <Nav owner={role === "owner"} counts={(counts ?? {}) as Record<string, number>} />
      <div className="admin-account">
        <div className="flex min-w-0 items-center gap-3">
          <span className="admin-avatar">{(user.email?.[0] ?? "A").toUpperCase()}</span>
          <div className="min-w-0"><p className="truncate text-xs text-slate-200" title={user.email ?? ""}>{user.email}</p><p className="mt-1 text-[11px] capitalize text-slate-400">{role} administrator</p></div>
        </div>
        <SignOut />
      </div>
    </aside>
    <div className="admin-main">
      <header className="admin-topbar">
        <div><span className="text-sm font-semibold text-slate-800">Administration</span><span className="ml-3 hidden text-xs text-slate-400 sm:inline">Content, community & growth</span></div>
        <div className="flex items-center gap-3"><Link href="/" target="_blank" rel="noreferrer" className="text-xs font-medium text-slate-600 hover:text-blue-700">View website â†—</Link><span className="rounded-full border border-blue-200 bg-blue-50 px-3 py-1 text-[11px] font-semibold capitalize text-blue-800">{role}</span></div>
      </header>
      <main id="admin-content" className="admin-content" tabIndex={-1}>
        <Suspense fallback={null}><Flash /></Suspense>
        {children}
        <footer className="mt-10 flex flex-wrap items-center justify-between gap-2 border-t border-slate-200 pt-5 text-[11px] text-slate-400"><span>Vayora Â· Admin workspace</span><span>Dates and totals in India time (IST)</span></footer>
        <div className="mt-5 md:hidden"><SignOut /></div>
      </main>
    </div>
  </div>;
}
