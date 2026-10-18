import {createClient} from "@supabase/supabase-js";
import {Card,Logo} from "@/components/ui";
import DownloadButton from "./download-button";
export const dynamic="force-dynamic";
export default async function Download(){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 let pixel="";
 if(url&&key){const c=createClient(url,key,{auth:{persistSession:false}});const {data}=await c.rpc("download_meta_config");pixel=String(data?.pixel_id??"");}
 return <main className="mx-auto max-w-lg p-6 py-16"><Logo/><div className="mt-8"><Card>
 <h1 className="mb-3 text-2xl font-semibold">Get Vayora for Android</h1>
 <p className="mb-6 text-sm leading-6 text-gray-500">Explore creator channels across India. Download the latest signed Android app.</p>
 {url&&<DownloadButton url={url+"/storage/v1/object/public/downloads/ads.apk"} pixel={pixel}/>}
 </Card></div></main>;
}
