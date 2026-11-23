# Vayora 1.0.12 — Meta attribution operations

This update adapts Vayora's existing Supabase Edge Function CAPI architecture and does not copy Cs-Storage migrations or replace the sender with pg_net.

## Source of truth

- private.source_of(user_id) remains the only authority for existing ads/organic audience decisions.
- New private.meta_source, private.parse_install_referrer and private.classify_install_referrer parse and classify real install referrers.
- Existing accounts' acquisition source is immutable. Signing into an existing account updates last-touch campaign dimensions but not its original source.
- APK package: com.vayora.app. Google Play package: com.vayora.play.
- Google Play uses the native Install Referrer service; direct ads APK uses the baked APK_REFERRER build-time value. Service outages retry before a conservative organic fallback.

## Meta Ads link for Google Play

Use a Traffic/Engagement campaign with this manually configured destination URL, rather than the native App Installs app selector (which can provide an encrypted Meta referrer requiring additional app integration):

https://play.google.com/store/apps/details?id=com.vayora.play&referrer=utm_source%3Dmeta%26utm_medium%3Dpaid_social%26utm_campaign%3Dvayora_launch

Reuse the identical link across all ads in one campaign; change the URL-encoded campaign name only for a genuinely new campaign. For direct APK distribution use the existing /campaign/meta download page. This measures first-party install source; Meta Ads Manager attribution still requires external verification.

## Consent and events

- Website Pixel is gated on website advertising consent.
- Browser Lead and server Lead use the same web-prefixed event ID for deduplication.
- Server click recording collects limited UTM and browser click fields only after existing measurement checks.
- App conversions require explicit opted-in advertising preference.
- Purchase values and idempotency are derived from verified backend orders, not untrusted UPI app results.
- CAPI user email and user ID are SHA-256 hashed before delivery.
- Do not add simultaneous auto-reporting Meta SDK install events without SDK/server deduplication. Cs-Storage previously double-counted installs when both sources used different event IDs.

## Admin credential testing

Saving enabled settings calls Meta with candidate Pixel ID/token through the existing trusted Edge Function, before changing the database. The event is named ConnectionCheck, not Purchase or PageView. Rejections block saving and show Meta's error (token redacted). A genuine timeout is marked unverified. Disabling tracking does not call Meta.

This credential check can send a custom event through Meta when the owner initiates a save. A live token test needs the owner's approval; none was initiated by the build.

## Pre-production checks

1. Run disposable SQL pgTAP tests, Flutter analyze/test, Play Android debug compilation, Next.js typecheck/build and Deno Edge Function checks.
2. Install on a physical Google Play device and test Meta referrer, Google Play organic default, missing Play Services and direct APK.
3. Verify signup/account linking, first- and last-touch campaign data and immutable ads/organic audience controls.
4. Test an invalid Pixel/token and a valid Meta Test Event Code in the owner admin. Obtain explicit approval before any live API verification.
5. Test website/app consent opt-out, Lead browser/server dedupe, verified Purchase values and failed-payment exclusion.
6. Review the SQL migration and take a production backup. Do not migrate, change environment settings, or publish APK/AAB until sign-off.

The existing Edge Function uses Graph API v27.0. Do not blindly copy Cs-Storage's older v21.0 endpoint.
