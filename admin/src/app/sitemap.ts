import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  const base = process.env.NEXT_PUBLIC_SITE_URL ?? "https://vayora-eta.vercel.app";
  return ["", "/d", "/privacy", "/terms", "/refund", "/community-guidelines", "/delete-account", "/report-content"].map((p) => ({ url: base + p }));
}
