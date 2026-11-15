"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";

type Item = { href: string; label: string; icon: string; count?: string; owner?: boolean };
const groups: { label: string; items: Item[] }[] = [
  { label: "Workspace", items: [
    { href: "/workspace", label: "Overview", icon: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z" },
    { href: "/workspace/channels", label: "Channels", icon: "M4 7h16v14H4z M8 3l4 4 4-4 M9 12l6 3-6 3z", count: "channels" },
    { href: "/workspace/posts", label: "Videos & posts", icon: "M3 5h18v14H3z M10 9l5 3-5 3z" },
    { href: "/workspace/approvals", label: "Approvals", icon: "M12 3l8 4v6c0 4-8 8-8 8s-8-4-8-8V7z M8 12l3 3 5-6", count: "approvals", owner: true },
  ] },
  { label: "Community", items: [
    { href: "/workspace/users", label: "Users", icon: "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8 M17 4a4 4 0 0 1 0 7 M22 21v-2a4 4 0 0 0-3-4", owner: true },
    { href: "/workspace/requests", label: "Requests", icon: "M4 4h16v13H8l-4 4z M8 8h8 M8 12h5", count: "requests", owner: true },
  ] },
  { label: "Business", items: [
    { href: "/workspace/analytics", label: "Analytics", icon: "M4 20V10 M10 20V4 M16 20v-8 M22 20H2", owner: true },
    { href: "/workspace/payments", label: "Payments", icon: "M3 5h18v14H3z M3 9h18 M7 15h4", count: "payments", owner: true },
    { href: "/workspace/plans", label: "Premium plans", icon: "M3 6l4 12h10l4-12-6 4-3-7-3 7z M7 21h10", owner: true },
    { href: "/workspace/meta", label: "Meta Pixel", icon: "M4 20V10 M10 20V4 M16 20v-8 M22 20H2", owner: true },
  ] },
  { label: "Settings", items: [
    { href: "/workspace/admins", label: "Administrators", icon: "M12 3l8 4v6c0 4-8 8-8 8s-8-4-8-8V7z M12 8v5 M12 16h.01", owner: true },
  ] },
];
export default function Nav({ owner, counts }: { owner: boolean; counts: Record<string, number> }) {
  const path = usePathname();
  return <nav className="admin-nav" aria-label="Admin sections">
    {groups.map(group => {
      const items = group.items.filter(item => owner || !item.owner);
      if (!items.length) return null;
      return <div key={group.label} className="admin-nav-group">
        <p className="admin-nav-label">{group.label}</p>
        {items.map(item => {
          const active = item.href === "/workspace" ? path === "/workspace" : path.startsWith(item.href);
          const count = item.count ? counts[item.count] ?? 0 : 0;
          return <Link key={item.href} href={item.href} aria-current={active ? "page" : undefined} className={"admin-nav-link " + (active ? "is-active" : "")}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={item.icon} /></svg>
            <span>{item.label}</span>
            {count > 0 && <span className="admin-nav-count" aria-label={`${count} waiting`}>{count}</span>}
          </Link>;
        })}
      </div>;
    })}
  </nav>;
}

