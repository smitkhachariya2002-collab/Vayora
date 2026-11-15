"use client";
import { useEffect, useState } from "react";
import { APK_URL, ADS_APK_URL } from "@/lib/downloads";
import { fromAd, trackWebEvent } from "@/components/MetaPixel";

/** Download button. People who came from an ad get the ads build; the tap is sent to Meta as a Lead. */
export default function DownloadButton({ apk = APK_URL, adsApk = ADS_APK_URL, label = "Download APK", className = "btn px-8 py-3" }: { apk?: string; adsApk?: string; label?: string; className?: string }) {
  const [href, setHref] = useState(apk);
  useEffect(() => { if (fromAd()) setHref(adsApk); }, [adsApk]);
  const onClick = () => { void trackWebEvent("Lead"); };
  return <a href={href} onClick={onClick} className={className} download>{label}</a>;
}


