import type { Metadata } from "next";
import "./globals.css";

const site = process.env.NEXT_PUBLIC_SITE_URL ?? "https://vayora-eta.vercel.app";

export const metadata: Metadata = {
  metadataBase: new URL(site),
  title: { default: "Vayora â€” Cloud storage & creator channels", template: "%s Â· Vayora" },
  description: "Vayora: private cloud storage and creator channels, made for India.",
  openGraph: { siteName: "Vayora", type: "website" },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
