import { requireAdmin } from "@/lib/supabase";
export default async function Dashboard() {
 const {client,owner}=await requireAdmin();
 const {count:channels}=await client.from("channels").select("*",{count:"exact",head:true});
 const {count:posts}=await client.from("posts").select("*",{count:"exact",head:true});
 const installs=owner?await client.from("installs").select("source,utm_campaign,created_at").order("created_at",{ascending:false}).limit(1000):null;
 return <><h1>Vayora dashboard</h1><div className="grid"><section>Channels: {channels??0}</section><section>Posts: {posts??0}</section>
 {owner&&<><section>Ads installs: {installs?.data?.filter(i=>i.source==="ads").length??0}</section>
 <section>Organic installs: {installs?.data?.filter(i=>i.source==="organic").length??0}</section></>}</div>
 {owner&&<><small>Install counts cover the most recent 1,000 installs.</small><table><thead><tr><th>Source</th><th>Campaign</th><th>Installed</th></tr></thead><tbody>
 {installs?.data?.map((i,index)=><tr key={index}><td>{i.source}</td><td>{i.utm_campaign??"—"}</td><td>{i.created_at}</td></tr>)}</tbody></table></>}</>;
}
