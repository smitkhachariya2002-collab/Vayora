# Vayora UPI Intent payments

## Discovery and existing decisions

Vayora is a Flutter Android app with a Kotlin platform bridge, Supabase Auth/Postgres/Edge Functions, and a Next.js owner panel in /admin. Customers buy database-backed plans. At this base the Trial is ₹49 / 7 days; all prices/durations remain server data and may change. Accounts start as anonymous guests; verified email/password is configured, with a Google option retained for later provider setup. The admins table defines owners; private.is_owner() protects payment administration.

Existing authorized payee: 2728412a@bandhan / AS Enterprice. The attachment's [yourid@bank] and [Your brand name] are placeholders, not replacement settings. No payee value is hard-coded into the app. The owner-selected payment_settings.activation_mode remains instant by default or manual. Instant applies to eligible signed-in accounts regardless of acquisition source, with the existing maximum three auto-activations per rolling 24 hours. Organic ads-content approval is a separate rule. Orders remain open 24 hours; client SUCCESS auto-activation requires age under two hours.

## Server lifecycle and permissions

Migration maps initiated → pending and success → paid, retaining every row and snapshot. States: pending, submitted, review, paid, failed, cancelled, rejected, revoked. A trigger fills API-created order id, reference, buyer, plan price × 100, duration and empty result fields. No rounding/additional paise. Reference is 28 alphanumeric characters. Members cannot INSERT/UPDATE/DELETE/TRUNCATE orders; guests cannot order; owner-only RLS exposes administration. API clients cannot call activation functions.

Checkout serializes per buyer, reads/locks the active plan, reuses a current same-plan snapshot under 24 hours, and cancels obsolete/different/expired open snapshots. Catalog changes never rewrite an existing order/subscription. A hidden plan blocks new checkout.

report_payment_result (alias report_result) saves raw answer and parsed status before its activation exception block. Errors preserve evidence with result_note; client_report events retain reports even if a later report replaces the latest raw_response. upi_response is a generated alias. Validation checks optional txnRef, alphanumeric transaction ID 6–40 characters, cross-order reuse and two-hour age. Accepted manual/limited results go to review; failed results become failed; unknown results preserve pending status. All activation uses the stored amount/duration.

private.activate_payment checks amount/identifiers and invokes private.activate_subscription under locks. Paid retries do not extend again. verified_at, verification_source and reviewed_by track provenance. Transaction IDs and bank UTRs share one private permanent reservation registry; rejected/revoked identifiers remain blocked. Organic first purchase requests owner ads access as before.

UTR submission accepts exactly 12 digits on pending/failed/cancelled (and review/submitted retries), moves to submitted and grants nothing. Owner Approve/Mark paid requires a 12-digit bank UTR; Reject requires a reason. Revoke requires a reason, revokes that order's subscription, removes its purchased duration from later stacked renewals and logs it. Other purchased plan time remains. The existing half-hour cron invokes the replaced 24-hour pending-order cleanup.

## Android and durable reporting

The activity uses FlutterFragmentActivity and an unconditionally registered ActivityResultLauncher. Its own picker queries installed upi://pay handlers and shows their names/icons; selection launches a package-specific intent. A system chooser is a fallback only when discovery is empty but Android can resolve the URI. Failed result launches fall back to startActivity.

Order/account identifiers are committed to native preferences before launch. Results prefer the response extra, then an extra containing Status=, then explicit NO_RESPONSE plus result code. The raw response is committed before notifying Flutter. No SMS listeners are started. Account-filtered native recovery and the app-level queue survive screen loss; startup/login/resume retry, refresh the session and use exponential backoff capped at 60 seconds while work remains. An accepted report or Order not found clears its saved copy; network/auth failures retain it. Results from another account wait for that account.

The payment screen polls every five seconds for about ten minutes and refreshes on resume. An open-order id is saved before UPI launch and restored when opening the latest payment screen. No-app results open a dialog with the configured UPI ID to copy, then the order screen offers UTR entry. History includes reference, amount, date, state and UTR. Access/success is displayed only from server state.

## Trusted provider hook

Existing upi-webhook remains compatible. New provider-payment accepts POST with X-Provider-Timestamp (Unix seconds, ±300 seconds) and X-Provider-Signature: sha256=<64 hex digits>, HMAC-SHA256 of the exact raw body. Web Crypto performs verification. With no PROVIDER_WEBHOOK_SECRET it returns 503. Configure the secret only in Supabase Edge Function secrets and with your bank/provider. verify_jwt=false is intentional: the provider HMAC authenticates the request, then a server-only service-role client invokes the restricted RPC.

Body:
```json
{"order_id":"<order UUID>","status":"SUCCESS","amount_paise":4900,"utr":"123456789012","provider_ref":"<provider event reference>"}
```
Status supports SUCCESS/PAID/FAILURE/FAILED/PENDING. Amount mismatch moves to review; paid/revoked/rejected repeats do not grant access. The signature contract authenticates the raw body, not the timestamp; permanent transaction reservations and paid idempotency are essential replay safeguards. Bank credentials/service keys never go into the client.

A UPI-app SUCCESS comes from the customer's phone and can be forged. Reference/format/age/uniqueness checks reduce risk; they do not prove settlement. Instant mode intentionally trusts this input, as authorized by the owner. Verify all flagged payments against your bank and revoke fraudulent ones. Only bank/provider status confirmation provides independent receipt evidence.

## ₹1 test procedure (owner-operated staging)

1. Deploy migrations and functions to the test backend and use a matching signed app. Keep production plan prices intact.
2. Add an active ₹1 test plan with one-day duration through the owner Plans page. Choose manual mode for the first test.
3. Sign in as a test buyer, choose the plan, check that the UPI screen shows exactly ₹1.00 and the correct payee, and pay once. Never share a PIN, OTP or bank password.
4. Return to Vayora. A client SUCCESS in manual mode must show verification pending/review, without Premium. Find the same reference and ₹1 credit in your bank, then enter its 12-digit bank UTR and Mark paid in admin. Confirm one-day access and one subscription.
5. Repeat status checks and report submission; expiry must not extend again. Test another order with the same identifier; it must be blocked.
6. Revoke with a reason and confirm only that purchase's time is removed. Repeat with instant mode if you accept its client-response risk; the order must carry Verify against bank.
7. Test cancelling the picker, no installed UPI handler, killing/reopening Vayora while paying, and an expired login. Check queue recovery and the same order. Disable the temporary test plan afterward. A refund, if desired, is a separate bank action.

## What to ask the bank/provider

Ask for a merchant UPI transaction-status API or signed credit webhook for this VPA, containing the merchant order reference, exact amount/currency, final status and unique bank UTR. Ask about merchant onboarding/eligibility, signing/secret rotation, timestamp/replay handling, retries, sandbox and reconciliation. A personal VPA does not imply that these APIs are available. Adapt their verified callback to the documented HMAC/RPC contract. SMS or the customer app response is not bank verification.

## Verification and rollout

PR evidence records SQL, Flutter, Edge Function and Android checks plus the signed artifact URL. CI uses fictional/local payments. No real ₹1 transfer is performed automatically. Physical-device tests—chosen UPI app opening/closing, process death during real payment and expired login during payment—need an installed signed app and a real UPI app; report these as not performed here.

This PR is stacked on #8 and #7. Apply their migrations before this one and deploy matching backend + app together because stored status names changed. This branch does not deploy production. The signed APK is a review build until that rollout. Keep the permanent signing key; no regeneration is needed.
