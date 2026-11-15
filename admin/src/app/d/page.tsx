import SiteShell from "@/components/SiteShell";
import DownloadButton from "./DownloadButton";

export const metadata = { title: "Download Vayora" };


export default function Download() {
  return (
    <SiteShell>
      <main className="mx-auto max-w-md px-4 py-16 text-center space-y-4">
        <div className="mx-auto h-20 w-20 rounded-3xl bg-brand grid place-items-center text-2xl font-bold text-white">VY</div>
        <h1 className="text-3xl font-bold text-slate-900">Get Vayora for Android</h1>
        <p className="text-slate-600">Private cloud storage, approved creator channels and Premium plans. Storage allowances and content access depend on your account, plan and admin-selected audience.</p>
        <DownloadButton />
        <p className="text-xs text-slate-500">If your phone asks, allow “install unknown apps” for your browser. Android 7.0 or newer.</p>
      <p className="text-xs text-slate-500">By using Vayora, follow our <a href="/terms" className="underline">Terms</a> and <a href="/community-guidelines" className="underline">Community Guidelines</a>. Read our <a href="/privacy" className="underline">Privacy Policy</a>. Optional ad measurement is your choice.</p></main>
    </SiteShell>
  );
}
