"use client";
import { APK_URL } from "@/lib/downloads";
import { trackWebEvent } from "@/components/MetaPixel";

/** Public downloads always use the organic build. Campaign pages choose explicitly. */
export default function DownloadButton({ apk = APK_URL, label = "Download APK", className = "btn px-8 py-3" }: { apk?: string; label?: string; className?: string }) {
  return <a href={apk} className={className} download onClick={async (e) => {
    // Give the browser/server deduplicated Lead a bounded chance to start before navigation.
    // Tracking never prevents an APK download, even when Meta or Supabase is unavailable.
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    const eventId = crypto.randomUUID();
    await Promise.race([
      trackWebEvent("Lead", eventId).catch(() => {}),
      new Promise<void>((resolve) => setTimeout(resolve, 800)),
    ]);
    window.location.assign(apk);
  }}>{label}</a>;
}
