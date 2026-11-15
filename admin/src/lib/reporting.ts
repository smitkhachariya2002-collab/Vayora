export type ReportQuery=Record<string,string|undefined>;
export function dateValue(s?:string){if(!s||!/^\d{4}-\d{2}-\d{2}$/.test(s))return null;const d=new Date(s+"T00:00:00Z");return Number.isFinite(d.getTime())&&d.toISOString().slice(0,10)===s?s:null;}
export function range(q:ReportQuery){let from=dateValue(q.from),to=dateValue(q.to);const today=new Date(Date.now()+19800000).toISOString().slice(0,10);
if(q.period==="today")from=to=today;
if(q.period==="7"||q.period==="30"){to=today;from=new Date(new Date(today+"T00:00:00Z").getTime()-(Number(q.period)-1)*86400000).toISOString().slice(0,10);}
if(q.period==="month"){to=today;from=today.slice(0,8)+"01";}
if(from&&to&&from>to)[from,to]=[to,from];return {from,to};}
export function pageNumber(s?:string){return Math.max(1,Math.floor(Number(s)||1));}
export function queryLink(path:string,q:ReportQuery,patch:ReportQuery){return path+"?"+new URLSearchParams(Object.entries({...q,...patch}).filter(([,v])=>!!v) as [string,string][]).toString();}

