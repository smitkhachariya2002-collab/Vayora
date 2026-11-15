import Link from "next/link";
import {Input,Select,Button} from "./ui";
import {queryLink,type ReportQuery} from "@/lib/reporting";
export function DateFields({q}:{q:ReportQuery}){return <>
<Select name="period" defaultValue={q.period??""} aria-label="Date range"><option value="">Custom / all time</option><option value="today">Today</option><option value="7">Last 7 days</option><option value="30">Last 30 days</option><option value="month">This month</option></Select>
<label className="text-xs text-gray-500">From (IST)<Input type="date" name="from" defaultValue={q.from??""}/></label><label className="text-xs text-gray-500">Through (IST)<Input type="date" name="to" defaultValue={q.to??""}/></label></>;}
export function ReportFilters({q,plans=[]}:{q:ReportQuery;plans?:{code:string;name:string}[]}){return <form className="mb-4 grid gap-3 sm:grid-cols-3 lg:grid-cols-6"><DateFields q={q}/>
<Select name="source" defaultValue={q.source??""} aria-label="Install source"><option value="">All install sources</option><option value="ads">Ads</option><option value="organic">Organic</option></Select>
<Select name="plan" defaultValue={q.plan??""} aria-label="Plan"><option value="">All plans</option>{plans.map(p=><option key={p.code} value={p.code}>{p.name}</option>)}</Select><Button variant="secondary">Apply filters</Button></form>;}
export function Pagination({path,q,total,size=50}:{path:string;q:ReportQuery;total:number;size?:number}){const page=Math.max(1,Number(q.page)||1);return <div className="my-4 flex items-center gap-4 text-sm"><span>{total} results · Page {page} of {Math.max(1,Math.ceil(total/size))}</span>{page>1&&<Link className="underline" href={queryLink(path,q,{page:String(page-1)})}>Previous</Link>}{page*size<total&&<Link className="underline" href={queryLink(path,q,{page:String(page+1)})}>Next</Link>}</div>;}

