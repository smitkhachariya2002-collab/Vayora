import SiteShell from "@/components/SiteShell";

export const metadata = { title: "Report Content" };
const email = process.env.NEXT_PUBLIC_SUPPORT_EMAIL || "help.vayora@gmail.com";

export default function Report() {
  return (
    <SiteShell>
      <main className="prose-doc mx-auto max-w-3xl px-4 py-12 text-sm">
        <h1>Report Content</h1>
        <p>The fastest way: open the post in Vayora, tap <b>⋮ → Report</b> and choose a reason (sexual or nude, violence, hate or harassment, copyright, spam or scam, other). You can also block a channel from the same menu.</p>
        <p>Reports are reviewed by our team, and content that breaks our <a href="/community-guidelines">Community Guidelines</a> is hidden.</p>
        <h2>Cannot use the app?</h2>
        <p>Email <a href={`mailto:${email}`}>{email}</a> with the link to the post or channel, the reason, and (for copyright) your name and proof that you own the work.</p>
        <h2>Need help with something else?</h2>
        <p>Write to the same address with your account email and, for payments, your order reference (it starts with OB).</p>
      </main>
    </SiteShell>
  );
}
