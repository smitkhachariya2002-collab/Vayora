import Link from "next/link";
import {requireAdmin} from "@/lib/admin";
import {inr,rowsOf} from "@/lib/format";
import {range,type ReportQuery} from "@/lib/reporting";
import {ReportFilters} from "@/components/admin/ReportFilters";
import {PageHeader,Stat,Card,Table,Th,Td,Empty,ErrorNote} from "@/components/admin/ui";
export default async function Analytics({ searchParams: pending }: { searchParams: Promise<ReportQuery> }){
 const q=await pending;
const {sb}=await requireAdmin(true);const dates=range(q);
const [report,plans]=await Promise.all([sb.rpc("admin_analytics",{p_from:dates.from,p_to:dates.to,p_source:q.source||null,p_plan:q.plan||null}),sb.from("plans").select("code,name").order("position")]);
const r=(report.data??{}) as Record<string,unknown>;const n=(key:string)=>Number(r[key]??0);
return <><PageHeader title="Analytics" sub="Inclusive dates in India time. Revenue uses plan activation date. User activity covers people who allow app analytics."/><ReportFilters q={q} plans={plans.data??[]}/><ErrorNote error={report.error}/>
<div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
<Stat label="Bank-verified revenue" value={inr(n("verified_revenue"))}/><Stat label="Awaiting bank verification" value={inr(n("unverified_revenue"))}/><Stat label="Paid orders" value={n("paid_orders")}/><Stat label="Paying users" value={n("paying_users")}/>
<Stat label="New users (including guests)" value={n("new_users")}/><Stat label="New email registrations" value={n("new_registrations")}/><Stat label="Active users" value={n("active_users")}/><Stat label="Returning users" value={n("returning_users")}/>
<Stat label="Sessions" value={n("sessions")}/><Stat label="Repeat buyers" value={n("repeat_buyers")}/></div>
<p className="my-4 text-xs text-gray-500">Plan filters apply to payments; acquisition and activity reflect the chosen dates and source. Returning users have an earlier session within retained history. Repeat buyers have at least two paid orders across their account history. This is an admin-only report, not an ad-provider audience or event. Select an email to compare past plans and prices. Guests are counted by account, never grouped by missing email. Actual ad spend and ROAS are reported in Meta Ads Manager.</p>
<div className="grid gap-4 xl:grid-cols-2">
<Card title="Revenue by day">{rowsOf(r.daily).length?<Table><thead><tr><Th>Day (IST)</Th><Th>Orders</Th><Th>Activated</Th><Th>Verified</Th></tr></thead><tbody>{rowsOf(r.daily).map((x,i)=><tr key={i}><Td>{String(x.day)}</Td><Td>{Number(x.orders)}</Td><Td>{inr(Number(x.activated_revenue))}</Td><Td>{inr(Number(x.verified_revenue))}</Td></tr>)}</tbody></Table>:<Empty>No payments in this range.</Empty>}</Card>
<Card title="Plans">{rowsOf(r.plans).map((x,i)=><div key={i} className="flex justify-between border-b py-3 text-sm"><span>{String(x.plan_name)} Â· {Number(x.orders)} orders</span><strong>{inr(Number(x.verified_revenue))} verified</strong></div>)}</Card>
<Card title="New users by source">{rowsOf(r.sources).map((x,i)=><div key={i} className="flex justify-between py-2"><span>{String(x.source)}</span><strong>{Number(x.new_users)}</strong></div>)}</Card>
<Card title="Consented app activity"><Table><thead><tr><Th>Event</Th><Th>Events</Th><Th>Users</Th></tr></thead><tbody>{rowsOf(r.events).map((x,i)=><tr key={i}><Td>{String(x.event_name)}</Td><Td>{Number(x.events)}</Td><Td>{Number(x.users)}</Td></tr>)}</tbody></Table></Card>
<Card title="Repeat buyers in this range" className="xl:col-span-2"><Table><thead><tr><Th>Account</Th><Th>Orders in range</Th><Th>Lifetime orders</Th><Th>Spend in range</Th></tr></thead><tbody>{rowsOf(r.repeat_customers).map((x,i)=><tr key={i}><Td><Link className="text-blue-700 underline" href={"/workspace/users/"+String(x.user_id)}>{String(x.email)}</Link><div className="text-xs text-gray-500">{String(x.user_id)}</div></Td><Td>{Number(x.orders_in_range)}</Td><Td>{Number(x.lifetime_paid_orders)}</Td><Td>{inr(Number(x.spent))}</Td></tr>)}</tbody></Table></Card></div></>;}
