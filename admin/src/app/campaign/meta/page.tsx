import SiteShell from "@/components/SiteShell";
import DownloadButton from "@/app/d/DownloadButton";
import {ADS_APK_URL} from "@/lib/downloads";
export const metadata={title:"Get Vayora",robots:{index:false,follow:false}};
export default function MetaCampaign(){return <SiteShell><main className="mx-auto max-w-xl px-5 py-20 text-center"><p className="site-eyebrow">YOUR CLOUD. YOUR CHANNELS.</p><h1 className="mt-5 text-4xl font-semibold">Discover Vayora</h1><p className="my-7 text-slate-300">Get the Android app from this Meta campaign. Content access follows your account and the current audience rules.</p><DownloadButton apk={ADS_APK_URL} label="Download for Android"/><p className="mt-6 text-sm text-slate-400">Optional measurement is your choice in the app.</p></main></SiteShell>;}
