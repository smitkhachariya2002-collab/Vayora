# Vayora parity rollout

All code remains in one PR after PR #6, with commits A–F. New schema/functions must deploy with this release; do not use the new APK against an unmigrated backend to judge cloud/payment changes.

## Direct Android release

GitHub Actions uses the existing permanent ANDROID_KEYSTORE_BASE64 and ANDROID_KEYSTORE_PASSWORD. Alias defaults to vayora and key password defaults to the keystore password; optional ANDROID_KEY_ALIAS/ANDROID_KEY_PASSWORD override them. A missing or invalid key fails the release, rather than silently replacing it. The production environment may require its configured reviewer.

Download the **Vayora-apks** artifact: Vayora.apk (organic), Vayora-ads.apk (Meta first touch), Vayora-play.aab (Play upload). SIGNING-CERT.txt and SHA256SUMS.txt verify the generated files. Keep the permanent keystore and password securely backed up. A development APK signed with a different key needs a one-time uninstall before installing the permanent release; sign back into your existing account afterward.

## Backend and owner settings

Merge/deploy only after the final checks pass. The Supabase deployment workflow applies the migrations and deploys Edge Functions. No credentials belong in Dart or NEXT_PUBLIC_* variables except the public project URL/publishable key.

UPI live row was separately verified as 2728412a@bandhan / AS Enterprice / enabled / instant at the owner's request. Payments → Activation mode selects instant or manual. Instant client responses can be forged; review every “Verify against bank” badge and use reason-required Revoke if needed. The three-per-user rolling-24h limit sends later attempts to manual review. Never infer bank settlement from the client flag.

Optional provider alerts remain off: set UPI_WEBHOOK_ENABLED=true and UPI_WEBHOOK_SECRET only after connecting your provider. Sign timestamp.raw-body with HMAC-SHA256 and send the matching headers defined in upi-webhook.

Email remains available. Keep email confirmation on, SMTP configured, production site https://vayora-eta.vercel.app and callbacks com.vayora.app://login-callback and com.vayora.play://login-callback allowed. Google remains visible with a friendly coming-soon message when disabled. To enable later, configure the Google provider and its exact Supabase callback in Google Cloud, then test on a device.

## Meta and download links

Admin → Meta: save pixel ID, API token, website https://vayora-eta.vercel.app/d, optional test event code, then enable. API version defaults to v26.0, verified against Meta's current official SDK; v19.0 from the reference is not pinned into a new integration. Token stays in a private table. Review last sent/failures and Send test event before using real campaigns.

The /d download page offers optional advertising measurement. To capture download clicks, add the server-only SUPABASE_SERVICE_ROLE_KEY to the Vercel project. It is never returned to browsers. Upload the signed Vayora-ads.apk through the existing admin APK uploader before sharing /d. A signed app's Download button does not publish the APK automatically.

Install matching uses an unused same-IP click within 48 hours and never overrides first-touch source. Shared/NAT IPs are approximate attribution, not identity proof. App events wait for the stored policy consent; raw clicks without a match expire after seven days. Dispatch retries five times and then shows failures for owner review.

Share links use https://vayora-eta.vercel.app/p/<id>. For verified Android app links, set Vercel ANDROID_SIGNING_SHA256 to the public colon-separated fingerprint from SIGNING-CERT.txt (comma-separated certificates allowed), then redeploy. This is a public certificate fingerprint, not a signing secret. Until configured, the links still fall back to /d. Play uses Google's app-signing certificate once available, which may differ from the upload key.

## Play

See [Play setup](play-setup.md). It stays free/no-UPI until owner-confirmed Google approval, service account, product mappings, tax configuration and licensed-device testing. Verified Play sessions get 15 GB; a Dart flag alone cannot grant quota. Production Google subscription lifecycle notifications and external refund reconciliation remain rollout prerequisites before enabling paid Play billing.

## Validation evidence

The PR records exact final CI runs, SQL/Flutter totals, signed artifacts and screenshots after verification. Tests use disposable local Supabase and fictional fixtures. No real payment or Meta event is sent by CI. The live database only received the explicitly authorized payment-settings update; the PR migrations are not silently deployed from this branch.

Security checks include member/guest distinction, first-touch immutability, source/audience RLS, approved creator writes, media paths, cloud quota/ownership/cycles/deletion, payment modes/limits/revocation, session-bound Play verification and restricted service RPCs. Database advisors also run in CI. Private tables intentionally have RLS with no client policies; owner/member RPCs explicitly check authorization. Signed media URLs last one hour as requested; URLs already issued retain their lifetime, while refreshed app state closes playback on lost access.

## Free-tier capacity

The 15 GB / 2 TB values are per-account application allowances, enforced by the database. Supabase Free includes 1 GB total file storage, 5 GB egress and a 50 MB file limit; setting an allowance does not provision that capacity. The free plan can test the flow but cannot physically supply each user those advertised volumes. No infrastructure upgrade or new charge is authorized here. Resolve capacity before selling a storage guarantee. See [current Supabase limits](https://supabase.com/pricing).
