import Editor from "../../../dashboard/[section]/[id]/page";
export default async function Page({params,searchParams}:{params:Promise<{id:string}>;searchParams:Promise<{ok?:string;error?:string}>}){const {id}=await params;return <Editor params={Promise.resolve({section:"posts",id})} searchParams={searchParams}/>}
