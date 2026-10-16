import {requireAdmin} from "@/lib/supabase";
import {signOut} from "../actions";
import {Logo,Button} from "@/components/ui";
import Navigation from "@/components/navigation";
export const dynamic="force-dynamic";
export default async function Layout({children}:{children:React.ReactNode}){
 const {client,user,owner}=await requireAdmin();
 const {count:channels}=await client.from("channels").select("*",{count:"exact",head:true}).eq("review_status","pending");
 const counts=owner?await Promise.all([
 client.from("profiles").select("*",{count:"exact",head:true}).eq("ads_access_status","pending"),
 client.from("payment_orders").select("*",{count:"exact",head:true}).in("status",["created","pending"]),
 client.from("support_requests").select("*",{count:"exact",head:true}).eq("status","open")]):[];
 const items=[{label:"Dashboard",href:"/dashboard"},{label:"Channels",href:"/dashboard/channels",count:channels??0},{label:"Posts",href:"/dashboard/posts"},...(owner?[{label:"Approvals",href:"/dashboard/approvals",count:counts[0]?.count??0},{label:"Payments",href:"/dashboard/payments",count:counts[1]?.count??0},{label:"Meta Pixel",href:"/dashboard/meta"},{label:"Users",href:"/dashboard/users",count:counts[0]?.count??0},{label:"Requests",href:"/dashboard/requests",count:counts[2]?.count??0},{label:"Plans",href:"/dashboard/plans"},{label:"Admins",href:"/dashboard/admins"}]:[])];
 return <div className="min-h-screen bg-gray-50"><aside className="border-b border-gray-200 bg-white md:fixed md:inset-y-0 md:left-0 md:z-20 md:flex md:w-60 md:flex-col md:border-r md:border-b-0"><div className="border-b border-gray-100 px-6 py-5"><Logo/></div><div className="md:flex-1"><p className="hidden px-6 pt-7 pb-1 text-[10px] font-semibold uppercase tracking-[.18em] text-gray-400 md:block">Manage workspace</p><Navigation items={items}/></div><div className="hidden border-t border-gray-100 p-5 md:block"><p className="truncate text-xs font-medium text-gray-700">{user.email}</p><p className="mt-1 mb-4 text-xs text-gray-400">{owner?"Owner":"Content admin"}</p><form action={signOut}><Button variant="secondary" className="w-full">Sign out</Button></form></div></aside><div className="md:pl-60"><div className="flex items-center justify-between border-b border-gray-200 bg-white px-4 py-3 text-xs text-gray-500 md:px-6"><span>Workspace <span className="mx-2 text-gray-300">/</span> Administration</span><span className="hidden sm:block">India · IST</span><form action={signOut} className="md:hidden"><Button variant="secondary">Sign out</Button></form></div><main className="mx-auto max-w-6xl p-4 md:p-6 lg:py-8">{children}</main><footer className="px-6 pb-6 text-xs text-gray-400">Vayora · Made for creators across India</footer></div></div>;
}