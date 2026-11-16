"use client";
import { APK_URL } from "@/lib/downloads";
import { trackWebEvent } from "@/components/MetaPixel";

/** Public downloads always use the organic build. Campaign pages choose explicitly. */
export default function DownloadButton({ apk = APK_URL, label = "Download APK", className = "btn px-8 py-3" }: { apk?: string; label?: string; className?: string }) {
  return <a href={apk} onClick={(event) => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) { void trackWebEvent("Lead"); return; }
    event.preventDefault();
    // Give the consent-gated event time to start, while keeping downloads responsive.
    void Promise.race([trackWebEvent("Lead"), new Promise<void>(resolve => setTimeout(resolve, 700))])
      .catch(() => {}).finally(() => { window.location.assign(apk); });
  }} className={className} download>{label}</a>;
}
