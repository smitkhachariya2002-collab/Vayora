import Link from "next/link";
export default function Page() {
 return <main><nav><strong>Vayora</strong><Link href="/login">Admin sign in</Link></nav>
 <h1>Your files. Your favourite creators.</h1><p>Cloud storage and creator channels for users across India.</p>
 <section><h2>Your space for files and creators.</h2><p>Content and storage access follow the current service mode and your approval status.</p></section>
 <p>Support: <a href="mailto:help.vayora@gmail.com">help.vayora@gmail.com</a></p>
 <nav><Link href="/privacy">Privacy</Link><Link href="/terms">Terms</Link><Link href="/refund">Refunds</Link><Link href="/community">Community rules</Link></nav></main>;
}
