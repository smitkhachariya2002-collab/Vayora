import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  const base = process.env.NEXT_PUBLIC_SITE_URL ?? "https://vayora-eta.vercel.app";
  return { rules: [{ userAgent: "*", allow: "/", disallow: ["/admin", "/subscribe"] }], sitemap: `${base}/sitemap.xml` };
}
