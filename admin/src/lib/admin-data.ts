import type {SupabaseClient} from "@supabase/supabase-js";
export type Row={ [key:string]:unknown };
export const str=(v:unknown)=>v==null?"":String(v);
export function rows(v:unknown):Row[]{return Array.isArray(v)?v as Row[]:[]}
export async function rpcRows(client:SupabaseClient,name:string){const {data,error}=await client.rpc(name);if(error)throw new Error(error.message);return rows(data)}
export function object(v:unknown):Row{return v&&typeof v==="object"&&!Array.isArray(v)?v as Row:{}}
export function check(error:{message:string}|null){if(error)throw new Error(error.message)}
