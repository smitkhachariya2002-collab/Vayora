import SiteShell from "@/components/SiteShell";

export const metadata = { title: "Terms and Conditions" };
const email = process.env.NEXT_PUBLIC_SUPPORT_EMAIL || "help.vayora@gmail.com";

export default function Terms() {
  return (
    <SiteShell>
      <article className="prose-doc mx-auto max-w-3xl px-4 py-12 text-sm">
        <h1>Terms and Conditions</h1>
        <p className="text-slate-500">Last updated: 15 November 2026</p>

        <h2>1. Introduction</h2>
        <p>Welcome to Vayora. These terms are an agreement between you and Vayora (“we”, “us”). By installing or using the app or this website you agree to these service terms. Please also read our <a href="/privacy">Privacy Policy</a>, <a href="/refund">Refund Policy</a> and <a href="/community-guidelines">Community Guidelines</a>. Optional usage analytics and Meta advertising measurement require separate choices; accepting these terms does not turn them on.</p>

        <h2>2. Who can use Vayora</h2>
        <p>On first opening the app, one popup links to these terms and the Privacy Policy. You must confirm acceptance and that you are at least 18. Separate, initially unchecked switches in that popup control optional Vayora usage analytics and Meta/Facebook measurement. You can accept these terms while leaving both off. The popup explains the data shared, recipients and purpose; the Privacy Policy describes retention and withdrawal. You can change optional choices later in Profile → Measurement preferences. Google Ads is not used.</p>
        <ul>
          <li>You must be at least 18 years old.</li>
          <li>You must follow all applicable local and national laws.</li>
          <li>You must not be barred from using online services under applicable law.</li>
          <li>We may suspend or end accounts that break these terms.</li>
        </ul>

        <h2>3. Your account</h2>
        <ul>
          <li>You can buy an available plan as a guest and add email and password to the same account later. A saved account is needed for channel creation, joining channels and uploads. Ads-app guests can play eligible free content and Premium previews; organic-app users must sign in for playback.</li>
          <li>You are responsible for your password and for activity on your account. Do not share your login.</li>
          <li>Give us accurate information and tell us if you think someone else is using your account.</li>
        </ul>

        <h2>4. Your content</h2>
        <h3>4.1 Ownership</h3>
        <p>You keep ownership of what you upload. You give us a limited, non-exclusive licence to store, process and display it as needed to run Vayora (for example to show your channel to other users).</p>
        <h3>4.2 Your responsibility</h3>
        <p>You are responsible for everything you upload, post or share. You confirm that you have the right to share it and that it follows our <a href="/community-guidelines">Community Guidelines</a>. We do not review everything users upload and do not take responsibility for user content, but we act on reports.</p>
        <h3>4.3 Prohibited content</h3>
        <p>Do not upload or share illegal content, sexual content involving minors, non-consensual or explicit sexual content, content that promotes violence or hatred, malware, scams, or material you do not have the right to share.</p>

        <h2>5. Channels</h2>
        <ul>
          <li>Only Premium members with a saved account can create channels. New channels and videos require admin review. Admin-selected audience rules apply to both channels and their content; an organic Premium plan does not automatically unlock ads-only channels.</li>
          <li>Channel owners are responsible for their channels and their content.</li>
          <li>We may hide, restrict or remove a channel, or suspend its owner, if the rules are broken.</li>
        </ul>

        <h2>6. Copyright</h2>
        <p>Only upload content you own or have permission to use. If you believe content infringes your rights, tell us on the <a href="/report-content">Report Content</a> page with a link and details. We may remove content and suspend repeat infringers. Downloading content does not give you ownership of it.</p>

        <h2>7. Cloud storage</h2>
        <p>Guests have no cloud storage. Free accounts receive a limited quota, and Premium plans increase it. If a plan ends, your existing files stay but you may not be able to add more files above the free quota. Keep your own backup of important files.</p>

        <h2>8. Premium plans and payments</h2>
        <ul>
          <li>Plans are for a fixed period, priced in Indian Rupees, and start after payment is confirmed. Plans do not renew automatically.</li>
          <li>The price and duration shown at the time of purchase apply to that order.</li>
          <li>On the website and direct-download versions, payment is made with UPI to our UPI ID. If you install from Google Play, purchases follow Google Play’s rules where available.</li>
          <li>Refunds are described in our <a href="/refund">Refund Policy</a>.</li>
          <li>We may end a plan if the account breaks these terms.</li>
        </ul>

        <h2>9. Acceptable use</h2>
        <ul>
          <li>Do not break the law, hack, disrupt or overload the service, or try to get around its limits.</li>
          <li>Do not misuse other people’s information or send spam.</li>
          <li>Do not fake payments, tamper with the app, or use it to commit fraud.</li>
        </ul>

        <h2>10. Third-party services and links</h2>
        <p>Vayora relies on third-party services (see the Privacy Policy) and may contain links to other websites. We do not control them and are not responsible for their content or policies.</p>

        <h2>11. Ending your use</h2>
        <p>You can delete your account at any time (see <a href="/delete-account">Delete Account</a>). We may remove content or suspend accounts that break these terms. Some records are kept as explained in the Privacy Policy.</p>

        <h2>12. Disclaimer and limit of liability</h2>
        <p>Vayora is provided “as is” and “as available”. We work to keep it running, but we do not promise it will be uninterrupted or error-free. To the extent the law allows, we are not liable for loss or damage from your use of the service, from user content, or from interruptions or loss of data.</p>

        <h2>13. Changes</h2>
        <p>We may update these terms. The date above shows the latest version. Continued use of Vayora after a change means you accept it.</p>

        <h2>14. Contact</h2>
        <p>Questions about these terms: <a href={`mailto:${email}`}>{email}</a>.</p>
      <h2>Content audiences and channel review</h2><p>Premium is required to create a channel. Channels and user-uploaded videos are reviewed, and the admin selects whether they are available to ads users, organic users or both. A Premium plan does not override audience restrictions. Organic users require the applicable admin approval for ads-only content.</p><p>Nothing in these terms limits rights that cannot be excluded under applicable law.</p></article>
    </SiteShell>
  );
}

