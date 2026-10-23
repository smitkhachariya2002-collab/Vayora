# Play distribution and billing preparation

The `play` flavor must also use `--dart-define=PLAY_STORE=true`. It hides all prices and UPI while server billing is disabled. The `direct` flavor serves the website and ads APKs.

## Free Play cloud

Enable Google Play Integrity for com.vayora.play, link the Cloud project and install through a Play internal test track. Set Supabase Edge secrets GOOGLE_PLAY_SERVICE_ACCOUNT (JSON), PLAY_CLOUD_PROJECT_NUMBER and PLAY_CERTIFICATE_SHA256 (Play app-signing certificate, colon SHA256 or base64url digest). Do not use the upload certificate if Play re-signs the app.

Cloud enrollment uses a one-time server challenge, verified package/certificate/licensing/device verdict and the current Auth session. A client flag cannot grant itself 15 GB. Until Play Console is configured, enrollment remains unavailable; the app still opens, but no unverified cloud quota is granted. Pull down or resume to retry after setup. Direct-download users retain the paid/free server mode.

## Future billing — OFF until owner confirmation

private.play_settings.play_billing_enabled=false and google_approval_confirmed=false. Do not enable either before Google approves the India User Choice Billing program and a licensed test proves both paths end to end.

Map product_id/base_plan_id to an existing plan in public.play_products as owner. Configure the correct inclusive tax_rate_bps with accounting advice; it has no assumed rate. Google-rendered choice comes from BillingClient.enableUserChoiceBilling; the UPI branch collects the buyer's Indian billing state and persists Google's external transaction token.

Google subscriptions are verified against purchases.subscriptionsv2, bound to a SHA256 account ID and mapped server-side to a plan; entitlement ends at Google's verified expiry. Purchase tokens are recovered on resume, and acknowledgement retries after interrupted verification. The server does not trust client purchase success.

play-report runs every 15 minutes through a private generated cron credential. It reports successful Play UPI orders by immutable order ID and buyer state, with separate pre-tax/tax amounts and INR. Failed reports retry; monitor the Google API logs and resolve failures before the 24-hour deadline. GOOGLE_PLAY_SERVICE_ACCOUNT needs Play Android Publisher and Play Integrity access; keep it only in Supabase secrets.

External prerequisites still need real Play Console credentials, product configuration, program approval and licensed-device testing. Production subscription lifecycle notifications/refund reconciliation must be validated with the chosen Google products before enabling paid Play billing. The app and database keep it off meanwhile.

Primary references: [Google choice integration](https://developer.android.com/google/play/billing/alternative/alternative-billing-with-user-choice-in-app), [purchase verification](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2/get), [external reporting](https://developers.google.com/android-publisher/api-ref/rest/v3/externaltransactions), [integrity nonces](https://developer.android.com/google/play/integrity/classic).
