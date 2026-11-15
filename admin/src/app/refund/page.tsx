import SiteShell from "@/components/SiteShell";

export const metadata = { title: "Refund Policy" };
const email = process.env.NEXT_PUBLIC_SUPPORT_EMAIL || "help.vayora@gmail.com";

export default function Refund() {
  return (
    <SiteShell>
      <article className="prose-doc mx-auto max-w-3xl px-4 py-12 text-sm">
        <h1>Refund Policy</h1>
        <p className="text-slate-500">Last updated: 15 November 2026</p>
        <h2>1. Digital service</h2>
        <p>Vayora plans give you cloud storage and premium access for a fixed period. Because access starts as soon as your payment is confirmed, plans are generally non-refundable once activated.</p>
        <h2>2. When we refund or correct</h2>
        <p>After checking our records and your payment reference, we will refund or correct:</p>
        <ul>
          <li>You were charged but your plan was not activated within 24 hours.</li>
          <li>You were charged more than once for the same order.</li>
          <li>You were charged an amount different from the price shown at purchase.</li>
        </ul>
        <h2>3. How to ask</h2>
        <p>Email <a href={`mailto:${email}`}>{email}</a> with your order reference (it starts with OB), the UPI transaction ID or UTR, the date and the amount. Approved refunds go back to the original UPI account, normally within 7 working days.</p>
        <h2>4. Cancelling</h2>
        <p>Plans do not renew automatically, so there is nothing to cancel. Your plan simply ends on its end date. If we end a plan because of a breach of our <a href="/terms">Terms</a> or <a href="/community-guidelines">Community Guidelines</a>, no refund is due.</p>
        <h2>5. Google Play purchases</h2>
        <p>If you buy through Google Play (where available), refunds follow Google Play’s refund policy and are handled by Google.</p>
      <h2>6. Your legal rights</h2><p>This policy does not limit any refund, remedy or cancellation rights that cannot be excluded under applicable consumer law. Contact us if a payment or plan does not match what you were shown.</p></article>
    </SiteShell>
  );
}

