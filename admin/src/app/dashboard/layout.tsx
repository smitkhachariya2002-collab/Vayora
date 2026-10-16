import Link from "next/link";
import { requireAdmin } from "@/lib/supabase";
import { signOut } from "../actions";
export const dynamic="force-dynamic";
export default async function Layout({children}:{children:React.ReactNode}) {
 const {owner}=await requireAdmin();
 const pages=owner?["channels","posts","approvals","users","plans","payments","settings"]:["channels","posts"];
 return <main><nav><Link href="/dashboard">Vayora dashboard</Link>
 {pages.map(p=><Link key={p} href={"/dashboard/"+p}>{p[0].toUpperCase()+p.slice(1)}</Link>)}
 <form action={signOut}><button>Sign out</button></form></nav>{children}</main>;
}
