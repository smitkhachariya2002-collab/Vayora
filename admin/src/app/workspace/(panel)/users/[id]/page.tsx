import Link from 'next/link';
import {requireAdmin,UUID} from '@/lib/admin';
import {notFound} from 'next/navigation';
import {PageHeader,Card,Stat,Table,Th,Td,Badge,ErrorNote,Empty} from '@/components/admin/ui';
import {rowsOf,inr,ist} from '@/lib/format';
export default async function Customer({ params: pending }: { params: Promise<{id:string}> }){
 const params=await pending;
 const {sb}=await requireAdmin(true);if(!UUID.test(params.id))notFound();
 const [{data,error},profile]=await Promise.all([sb.rpc('admin_customer_purchases',{p_user:params.id}),sb.from('profiles').select('display_name').eq('id',params.id).maybeSingle()]);
 const r=(data??{}) as Record<string,unknown>;const history=rowsOf(r.history);
 return <><PageHeader title={profile.data?.display_name||String(r.email||'Guest purchase history')} sub={String(r.email||'Guest account')+' - Admin-only purchase history. Repeat-buyer status is not shared as an advertising label.'}/>
 <ErrorNote error={error}/><div className="mb-5 grid gap-3 sm:grid-cols-3"><Stat label="Paid orders" value={Number(r.paid_orders??0)}/><Stat label="Total paid order value" value={inr(Number(r.spent??0))}/><Stat label="Customer" value={Number(r.paid_orders??0)>=2?'Repeat buyer':'First-time / no purchase'}/></div>
 <Card title="Plan purchases" sub="Compare each paid purchase with the previous paid order on this account. Higher/lower means order price; plan features and duration may differ.">{!history.length?<Empty>No paid orders for this account.</Empty>:<Table><thead><tr><Th>Purchased (IST)</Th><Th>Plan</Th><Th>Amount</Th><Th>Previous plan</Th><Th>Change</Th><Th>Bank check</Th></tr></thead><tbody>{history.map((o,i)=><tr key={String(o.id??i)}><Td>{ist(String(o.activated_at))}</Td><Td>{String(o.plan_name)}</Td><Td>{inr(Number(o.amount_inr))}</Td><Td>{o.previous_plan?String(o.previous_plan)+' · '+inr(Number(o.previous_amount_inr)):'—'}</Td><Td><Badge>{String(o.change)}</Badge></Td><Td>{o.bank_verified?'Verified':'Awaiting verification'}</Td></tr>)}</tbody></Table>}</Card>
 <p className="mt-4 text-sm text-gray-500">Account: {params.id}. A guest who adds an email keeps the same account and history. Other accounts using a different email are not merged.</p><Link className="mt-4 inline-block underline" href={'/workspace/payments?q='+params.id}>View all payment statuses for this account</Link>
 </>;
}
