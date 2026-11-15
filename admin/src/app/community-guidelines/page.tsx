import SiteShell from "@/components/SiteShell";

export const metadata = { title: "Community Guidelines" };

export default function Guidelines() {
  return (
    <SiteShell>
      <article className="prose-doc mx-auto max-w-3xl px-4 py-12 text-sm">
        <h1>Community Guidelines</h1>
        <p>Vayora should be a safe, respectful and creative place. These guidelines apply to everyone who uploads content or creates a channel. By using Vayora you agree to follow them. If you create a channel, you are a creator, and creators are responsible for what they share.</p>

        <h2>1. Not allowed</h2>
        <h3>1.1 Sexual content</h3>
        <ul>
          <li>Any sexual content involving minors. This is reported to the authorities.</li>
          <li>Nudity, pornography and sexually explicit material.</li>
          <li>Sexual content shared without the consent of the people shown.</li>
        </ul>
        <h3>1.2 Hate and harassment</h3>
        <p>Content that threatens, harasses or demeans people because of race, caste, gender, religion, nationality, disability, sexual orientation, age or similar traits, or that invades someone’s privacy.</p>
        <h3>1.3 Violence and harm</h3>
        <p>Graphic violence or gore, content that promotes violence, self-harm or dangerous challenges.</p>
        <h3>1.4 Illegal and deceptive content</h3>
        <ul>
          <li>Content that breaks the law, including drugs, fraud, hacking and malware.</li>
          <li>Scams, fake news and misleading or impersonating content.</li>
        </ul>

        <h2>2. Ownership and copyright</h2>
        <ul>
          <li>Only upload content you own or have permission to use.</li>
          <li>Do not share copyrighted movies, music, shows or other material without permission.</li>
          <li>If you receive a copyright complaint, you must act on it.</li>
        </ul>

        <h2>3. Respect your audience</h2>
        <ul>
          <li>Treat viewers and other creators respectfully.</li>
          <li>Respond sensibly when users report issues with your content.</li>
          <li>Do not encourage harmful actions.</li>
        </ul>

        <h2>4. Things creators must not do</h2>
        <ul>
          <li><b>Fake engagement:</b> paying others to promote your channel or generating fake activity.</li>
          <li><b>Spam:</b> posting repetitive, unrelated or meaningless content in bulk.</li>
          <li><b>Misleading links:</b> promising content and sending viewers elsewhere.</li>
          <li><b>Plagiarism:</b> copying content from others without their approval.</li>
        </ul>

        <h2>5. Reporting</h2>
        <p>In the app open the post, tap ⋮ then Report, and pick a reason. You can also block a channel. If you cannot use the app, use the <a href="/report-content">Report Content</a> page. Our team reviews reports and hides content that breaks these rules.</p>

        <h2>6. What happens if rules are broken</h2>
        <ul>
          <li>Content may be hidden, removed or restricted.</li>
          <li>A channel may be restricted or deleted.</li>
          <li>Repeated or serious violations lead to account suspension or termination.</li>
          <li>Where the law requires, we report serious cases to the authorities.</li>
        </ul>
        <p>We may take other reasonable action not listed here to keep Vayora safe. Being a creator means being responsible: respect the rules, make great content and grow your community the right way.</p>
      </article>
    </SiteShell>
  );
}
