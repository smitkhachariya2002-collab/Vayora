import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {title:"Vayora",description:"Cloud storage and creator channels for India",icons:{icon:[{url:"/favicon.ico"},{url:"/icon-192.png",sizes:"192x192",type:"image/png"}],apple:"/icon-192.png"}};
export default function RootLayout({children}:{children:React.ReactNode}) {
 return <html lang="en"><body>{children}</body></html>;
}
