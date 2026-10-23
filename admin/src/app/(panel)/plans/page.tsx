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
 const claims=await client.rpc("admin_free_plan_claims");const claimed=(claims.data??{}) as {organic?:number;ads?:number};
 const freeFor=String(mode.data?.free_plans_for??"none");
 return <>
 <PageHeader title="Plans" subtitle="Prices and perks shown on the app's Premium page. Changes appear in the app immediately." action={<LinkButton href="/plans?new=1#new-plan">+ Add plan</LinkButton>}/>
 <Flash ok={q.ok} error={q.error||plans.error?.message||mode.error?.message||impact.error?.message||claims.error?.message}/>
 <Card className="mb-6"><form action={workspaceAction} className="space-y-4">
 <Hidden name="operation" value="saveMode"/><Hidden name="return_to" value="/plans"/>
 <SectionTitle>Free mode</SectionTitle><p className="text-sm leading-6 text-gray-500">When ON, plans and prices are hidden in the app. Logged-in users get a 15 GB allowance. Organic users request full access.</p>
 <Field label="Service mode"><Select name="free_mode" defaultValue={mode.data?.free_mode?"true":"false"}><option value="false">OFF · Paid mode</option><option value="true">ON · Free mode</option></Select></Field>
 <Submit>Save mode</Submit></form></Card>
 <Card className="mb-6"><form action={workspaceAction} className="space-y-4">
 <Hidden name="operation" value="saveFreePlans"/><Hidden name="return_to" value="/plans"/>
 <SectionTitle>Free plans</SectionTitle><p className="text-sm leading-6 text-gray-500">Give plans for free to one group while the others pay by UPI. Users in the free group see the price crossed out, a FREE badge and an &ldquo;Activate for free&rdquo; button; the plan runs for its full duration. Each user can claim each plan once per promotion. Organic users still need your approval for full access. Only plans with &ldquo;Free when free plans are on&rdquo; ticked are free.</p>
 <Field label="Free plans for"><Select name="free_plans_for" defaultValue={freeFor}><option value="none">Off · everyone pays</option><option value="organic">Organic users only · ads users pay</option><option value="ads">Ads users only · organic users pay</option><option value="everyone">Everyone</option></Select></Field>
 <p className="text-xs text-gray-500">Free plans claimed in this promotion: organic {Number(claimed.organic??0)} · ads {Number(claimed.ads??0)}. Turning this off stops new claims; plans already claimed run until they end. Free mode (above) overrides this.</p>
 <Submit confirm="Change who gets plans for free? Users in the free group will get plans without paying.">Save free plans</Submit></form></Card>
 {q.new&&<div id="new-plan" className="mb-6 max-w-2xl"><PlanEditor plan={{}}/></div>}
 <div className="grid gap-5 lg:grid-cols-2">{(plans.data??[]).map(plan=>{
 const count=(impact.data as {plan_id:string;active_subscribers:number;orders:number}[]|null)?.find(i=>i.plan_id===plan.id);
 return <PlanEditor key={plan.id} plan={plan} subscribers={Number(count?.active_subscribers??0)} orders={Number(count?.orders??0)}/>;
 })}</div></>;
}
