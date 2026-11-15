"use client";
import { APK_URL } from "@/lib/downloads";
import { trackWebEvent } from "@/components/MetaPixel";

/** Public downloads always use the organic build. Campaign pages choose explicitly. */
export default function DownloadButton({ apk = APK_URL, label = "Download APK", className = "btn px-8 py-3" }: { apk?: string; label?: string; className?: string }) {
  return <a href={apk} onClick={() => { void trackWebEvent("Lead"); }} className={className} download>{label}</a>;
}
