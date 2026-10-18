import {requireAdmin} from "@/lib/supabase";
import PlanEditor from "@/components/plan-editor";
import {workspaceAction} from "@/app/workspace-actions";
import {Submit} from "@/components/interactive";
import {PageHeader,Card,Flash,LinkButton,SectionTitle,Field,Select,Hidden} from "@/components/ui";
export default async function PlansPage({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}){
 const q=await searchParams,{client}=await requireAdmin(true);
 const [plans,mode,impact]=await Promise.all([
 client.from("plans").select("*").order("position").order("created_at"),
 client.from("app_mode").select().single(),client.rpc("admin_plan_impact")]);
 return <>
 <PageHeader title="Plans" subtitle="Prices and perks shown on the app's Premium page. Changes appear in the app immediately." action={<LinkButton href="/plans?new=1#new-plan">+ Add plan</LinkButton>}/>
 <Flash ok={q.ok} error={q.error||plans.error?.message||mode.error?.message||impact.error?.message}/>
 <Card className="mb-6"><form action={workspaceAction} className="space-y-4">
 <Hidden name="operation" value="saveMode"/><Hidden name="return_to" value="/plans"/>
 <SectionTitle>Free mode</SectionTitle><p className="text-sm leading-6 text-gray-500">When ON, plans and prices are hidden in the app. Logged-in users get a 15 GB allowance. Organic users request full access.</p>
 <Field label="Service mode"><Select name="free_mode" defaultValue={mode.data?.free_mode?"true":"false"}><option value="false">OFF · Paid mode</option><option value="true">ON · Free mode</option></Select></Field>
 <Submit>Save mode</Submit></form></Card>
 {q.new&&<div id="new-plan" className="mb-6 max-w-2xl"><PlanEditor plan={{}}/></div>}
 <div className="grid gap-5 lg:grid-cols-2">{(plans.data??[]).map(plan=>{
 const count=(impact.data as {plan_id:string;active_subscribers:number;orders:number}[]|null)?.find(i=>i.plan_id===plan.id);
 return <PlanEditor key={plan.id} plan={plan} subscribers={Number(count?.active_subscribers??0)} orders={Number(count?.orders??0)}/>;
 })}</div></>;
}
