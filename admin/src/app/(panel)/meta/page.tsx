import Section from "../../dashboard/[section]/page";
export default async function Page({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}){return <Section params={Promise.resolve({section:"meta"})} searchParams={searchParams}/>}
