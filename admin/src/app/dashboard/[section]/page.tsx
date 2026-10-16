import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/supabase";
import { changeAccess,grantPlan,markPaid,revokePayment,saveMode,saveUpi,savePlan,saveChannel,savePost } from "../../actions";
type Row=Record<string,string|number|boolean|null>;
function Hidden({name,value}:{name:string;value:string}) {return <input type="hidden" name={name} value={value}/>;}
function Audience({value="all"}:{value?:string}){return <select name="audience" defaultValue={value}><option>all</option><option>organic</option><option>ads</option></select>;}
function Access({id}:{id:string}){return <form action={changeAccess}><Hidden name="user_id" value={id}/><select name="status"><option value="approved">Approve</option><option value="rejected">Reject</option><option value="none">Revoke</option></select><button>Save access</button></form>;}
export default async function Page({params,searchParams}:{params:Promise<{section:string}>;searchParams:Promise<Record<string,string|undefined>>}) {
 const {section}=await params,query=await searchParams;
 if(!["channels","posts","approvals","users","plans","payments","settings"].includes(section))notFound();
 const {client,owner}=await requireAdmin(!["channels","posts"].includes(section));
 if(section==="settings"){
  const {data:m}=await client.from("app_mode").select().single();
  return <><h1>Operating mode</h1><form action={saveMode} className="panel"><select name="mode" defaultValue={m?.free_mode?"free":m?.free_access_enabled?"hybrid":"paid"}>
    <option value="hybrid">Free access + paid upgrades</option><option value="free">Free only · hide paid plans</option><option value="paid">Paid premium · free posts remain available</option></select><button>Save mode</button></form>
    <p>Ads accounts get ads access automatically. Organic accounts need owner approval for ads content.</p></>;
 }
 if(section==="users"||section==="approvals"){
  const {data,error}=await client.rpc("admin_users");if(error)throw new Error(error.message);
  const users=(data as Row[]).filter(u=>(section!=="approvals"||u.ads_access_status==="pending")&&(!query.q||String(u.email).toLowerCase().includes(query.q.toLowerCase())));
  const {data:plans}=await client.from("plans").select("id,name");
  return <><h1>{section==="approvals"?"Approvals":"Users"}</h1><form><input name="q" placeholder="Search email" defaultValue={query.q}/><button>Search</button></form>
    {users.map(u=><section key={String(u.id)}><h2>{String(u.email??"Guest")}</h2><p>{String(u.source)} · {String(u.campaign??"No campaign")} · {String(u.ads_access_status)} · Plan ends {String(u.plan_ends_at??"—")}</p>
    <Access id={String(u.id)}/><form action={grantPlan}><Hidden name="user_id" value={String(u.id)}/><select name="plan_id">{plans?.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select><button>Grant premium</button></form></section>)}</>;
 }
 if(section==="plans"){
  const {data:plans}=await client.from("plans").select().order("position");
  return <><h1>Plans</h1>{plans?.map(p=><form className="panel" action={savePlan} key={p.id}><Hidden name="id" value={p.id}/>
   <input name="name" aria-label="Plan name" defaultValue={p.name} required/><input name="price_inr" aria-label="Price INR" type="number" step="0.01" min="1" defaultValue={p.price_inr} required/>
   <input name="duration_days" aria-label="Days" type="number" min="1" defaultValue={p.duration_days} required/>
   <textarea name="perks" aria-label="Perks" defaultValue={(p.perks as string[]).join("\n")}/>
   <label><input name="active" type="checkbox" defaultChecked={p.active}/>Visible</label><button>Save plan</button></form>)}</>;
 }
 if(section==="payments"){
  const {data:settings}=await client.from("payment_settings").select().single();
  let orders=client.from("payment_orders").select("*,plans(name)").order(query.sort==="amount"?"amount_paise":"created_at",{ascending:false}).limit(200);
  if(query.status)orders=orders.eq("status",query.status);
  if(query.plan)orders=orders.eq("plan_id",query.plan);
  if(query.from)orders=orders.gte("created_at",query.from);
  if(query.to)orders=orders.lt("created_at",query.to+"T23:59:59.999Z");
  const {data}=await orders;
  const {data:sales}=await client.rpc("admin_plan_sales"),{data:buyers}=await client.rpc("admin_buyers");
  return <><h1>Payments</h1><form action={saveUpi} className="panel"><input name="upi_id" placeholder="UPI ID" defaultValue={settings?.upi_id??""} required/>
   <input name="payee_name" placeholder="Payee name" defaultValue={settings?.payee_name??""} required/><label><input type="checkbox" name="enabled" defaultChecked={settings?.enabled}/>Enable UPI</label><button>Save UPI</button></form>
   <p>Verify receipt in your bank before marking paid. A phone response is not bank verification.</p>
   <form><select name="status"><option value="">All statuses</option>{["created","pending","success","failed","cancelled","revoked"].map(s=><option key={s}>{s}</option>)}</select>
    <input name="plan" placeholder="Plan ID" defaultValue={query.plan}/><input type="date" name="from" aria-label="From"/><input type="date" name="to" aria-label="To"/>
    <select name="sort"><option value="date">Newest first</option><option value="amount">Highest amount first</option></select><button>Filter</button></form>
   {data?.map(o=><section key={o.id}><h2>{o.reference} · ₹{o.amount_paise/100}</h2><p>{o.plans?.name} · {o.status} · {o.reason}</p>
    {o.status!=="success"&&o.status!=="revoked"&&<form action={markPaid}><Hidden name="order_id" value={o.id}/><input name="utr" placeholder="Verified bank UTR" required pattern="[A-Za-z0-9]{6,40}"/><button>Mark paid</button></form>}
    {o.status==="success"&&<form action={revokePayment}><Hidden name="order_id" value={o.id}/><input name="reason" placeholder="Reason" required/><button>Revoke</button></form>}</section>)}
   <h2>Sales by plan</h2><pre>{JSON.stringify(sales,null,2)}</pre><h2>Repeat buyers</h2><pre>{JSON.stringify(buyers,null,2)}</pre><small>Orders show at most 200 matching rows.</small></>;
 }
 const {data:channels}=await client.from("channels").select().order("created_at",{ascending:false});
 if(section==="channels"){
  const channelForm=(c?:Record<string,string>)=><form action={saveChannel} className="panel" key={c?.id??"new"}>
   <Hidden name="id" value={c?.id??""}/><input name="name" placeholder="Channel name" defaultValue={c?.name} required/>
   <textarea name="description" placeholder="Description" defaultValue={c?.description}/><Audience value={c?.audience}/>
   <select name="status" defaultValue={c?.status??"active"}><option>active</option><option>hidden</option></select>
   {owner&&<select name="review_status" defaultValue={c?.review_status??"approved"}><option>pending</option><option>approved</option><option>rejected</option></select>}<button>{c?"Save channel":"Create channel"}</button></form>;
  return <><h1>Channels</h1>{channelForm()}{channels?.map(c=>channelForm(c))}</>;
 }
 const {data:posts}=await client.from("posts").select().order("created_at",{ascending:false}).limit(100);
 const postForm=(p?:Record<string,string>)=><form action={savePost} className="panel" key={p?.id??"new"}>
  <Hidden name="id" value={p?.id??""}/><input name="title" placeholder="Post title" defaultValue={p?.title} required/>
  <textarea name="description" placeholder="Description" defaultValue={p?.description}/><select name="channel_id" defaultValue={p?.channel_id}>{channels?.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select><Audience value={p?.audience}/>
  <select name="status" defaultValue={p?.status??"draft"}><option>draft</option><option>scheduled</option><option>published</option></select><input name="publish_at" type="datetime-local" aria-label="Publish at" defaultValue={p?.publish_at?.slice(0,16)}/>
  <p><label>Main media <input type="file" name="media" accept="video/*,image/*"/></label></p>
  <p><label>Trailer <input type="file" name="trailer" accept="video/*"/></label></p><p><label>Thumbnail <input type="file" name="thumbnail" accept="image/jpeg,image/png,image/webp"/></label></p>
  <label><input type="checkbox" name="premium"/>Premium media</label><button>Save post</button></form>;
 return <><h1>Posts</h1><p>Uploads are limited to 50 MB per file. Adding media appends an item to the post.</p>{postForm()}{posts?.map(p=>postForm(p))}</>;
}
