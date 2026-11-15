import Link from "next/link";
import MetaPixel from "./MetaPixel";
import PrivacyChoices,{PrivacyChoicesButton} from "./PrivacyChoices";
import DownloadButton from "@/app/d/DownloadButton";
const email=process.env.NEXT_PUBLIC_SUPPORT_EMAIL||"help.vayora@gmail.com";
export function Logo(){return <Link href="/" className="flex items-center gap-3 text-xl font-semibold tracking-tight"><span className="grid h-10 w-10 place-items-center rounded-xl bg-teal-700"><svg width="28" height="28" viewBox="0 0 108 108" aria-hidden="true"><g fill="white"><rect x="26" y="47" width="56" height="26" rx="13"/><circle cx="50" cy="48" r="16"/><circle cx="65" cy="52" r="12"/></g><path fill="#137781" d="M49 46v19l16-9.5z"/></svg></span>Vayora</Link>;}
export default function SiteShell({children,bare=false}:{children:React.ReactNode;bare?:boolean}){
 if(bare)return <div className="min-h-screen"><MetaPixel/>{children}<PrivacyChoices/></div>;
 return <div className="site min-h-screen flex flex-col">
  <MetaPixel/>
  <header className="sticky top-0 z-20 border-b border-white/10 bg-[#08151d]/95 backdrop-blur">
   <div className="mx-auto flex h-20 max-w-6xl items-center justify-between gap-4 px-5"><Logo/><nav aria-label="Main navigation" className="flex items-center gap-5 text-sm text-slate-300"><Link href="/#features" className="hidden hover:text-white md:inline">Discover</Link><Link href="/#pricing" className="hidden hover:text-white sm:inline">Premium</Link><Link href="/report-content" className="hidden hover:text-white md:inline">Support</Link><DownloadButton className="btn" label="Get the app"/></nav></div>
  </header>
  <div className="flex-1">{children}</div>
  <footer className="border-t border-white/10 bg-[#061118] text-sm text-slate-300">
   <div className="mx-auto grid max-w-6xl gap-10 px-5 py-14 md:grid-cols-[1.5fr_1fr_1fr]">
    <div><Logo/><p className="mt-5 max-w-sm leading-relaxed text-slate-400">Your personal cloud and creator channels. More room for the things you keep. More ways to discover what you love.</p><p className="mt-4 text-xs text-slate-500">Vayora by As Enterprice</p></div>
    <div><h2 className="font-semibold text-white">Help & information</h2><ul className="mt-4 space-y-3"><li><Link href="/d">Download for Android</Link></li><li><Link href="/report-content">Support & report content</Link></li><li><Link href="/delete-account">Delete account</Link></li><li><a href={`mailto:${email}`}>{email}</a></li></ul></div>
    <div><h2 className="font-semibold text-white">Policies & choices</h2><ul className="mt-4 space-y-3"><li><Link href="/privacy">Privacy Policy</Link></li><li><Link href="/terms">Terms and Conditions</Link></li><li><Link href="/refund">Refund Policy</Link></li><li><Link href="/community-guidelines">Community Guidelines</Link></li><li><PrivacyChoicesButton/></li></ul></div>
   </div><div className="mx-auto flex max-w-6xl flex-wrap justify-between gap-3 border-t border-white/10 px-5 py-6 text-xs text-slate-500"><span>© {new Date().getFullYear()} Vayora. All rights reserved.</span><span>For adults aged 18 and over.</span></div>
  </footer><PrivacyChoices/>
 </div>;
}

