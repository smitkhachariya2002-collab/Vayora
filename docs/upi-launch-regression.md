# UPI launch regression and phone test — 0.3.7+10

## Fixed regression
Android package visibility can return no handlers even when an installed wallet can open the payment URI. The query is now only a chooser hint: zero/one visible handler launches the exact ACTION_VIEW URI; multiple handlers use "Pay with". A throwing visibility query also falls back to an actual launch. Only an ActivityNotFoundException from that launch maps to NO_UPI_APP. A SecurityException or other launch exception maps to LAUNCH_FAILED.

The existing ActivityResultLauncher receives raw wallet response/extras. Active order and account are committed before launch; a returned response is committed natively before replying to Flutter. Existing durable reporting, report_result, validation, activation, retries and polling are unchanged. Launch failures clear the active-launch marker, not the saved order or its payee.

The opening indicator resets before error/fallback UI, on cancellation, and on resume. Duplicate-checkout protection stays enabled until the checkout route completes. Only NO_UPI_APP can show "No UPI app found"; legacy raw-response text and other platform errors cannot. Genuine no-app fallback retains Copy UPI ID and the existing payment status / UTR screen.

## Automated coverage
- Flutter: actual Plans button through waiting launch, NO_UPI_APP, LAUNCH_FAILED, legacy no_upi, cancellation/resume and legacy raw response. Only NO_UPI_APP opens the fallback. The button resets while that dialog is still open, and after its dismissal.
- Flutter: server payee retained without querying owner payment settings, plus existing exact UPI URI, success, status and recovery tests.
- Robolectric API 30/34: zero handlers and throwing discovery still attempt launch; one handler direct; multiple chooser; only actual ActivityNotFoundException produces NO_UPI_APP.
- Existing native API 32/34 tests: arbitrary discovered apps, real/generic URI merge, de-duplication, sorting, raw response and separate extras.
- Compiled debug + normal APK + ads APK + direct/Play merged manifests: generic UPI and HTTPS visibility, all requested package hints, no QUERY_ALL_PACKAGES.
- Permanent signing certificate reused. No backend migration/deployment required.

Android's official guidance supports invoking the intent and catching ActivityNotFoundException:
https://developer.android.com/training/package-visibility/use-cases

## Physical phone test (not performed by CI)
A real phone, an OEM-specific environment and a bank-approved payment cannot be simulated by the unit tests. These checks remain for the tester; CI never charges a bank account.

1. Download Vayora-apks from the successful Android verification and APKs run for PR #16. Extract the ZIP. Install Vayora.apk over the existing app; confirm version 0.3.7. Keep app data.
2. On Android 11 or higher with at least two UPI wallets in the same Android profile, log in to Vayora. Open Profile, select Trial and check its live price is ₹1 before proceeding. If it is a different price, stop and change Trial through owner Plans first; no price is hard-coded in this fix.
3. Tap Pay ₹1 via UPI. Confirm an installed wallet launches or "Pay with" offers eligible wallets. Do not expect wallets in a different work profile to be accessible from the personal profile.
4. First press Back/cancel without approving payment. Return to Vayora. Confirm Opening UPI… is gone, the status stays pending/not completed and no false No UPI app found dialog appears.
5. Return to Profile and start a fresh ₹1 checkout. Pick a wallet, confirm payee AS Enterprice / 2728412a@bandhan and amount ₹1 in the wallet, and approve the payment yourself.
6. On return, Vayora should open Payment status. A valid wallet SUCCESS is sent through the existing report_result path. Confirm success and plan expiry in the app and owner Payments. If the wallet supplies no final result, the existing pending/polling path remains.
7. Repeat installation/testing with Vayora-ads.apk (same package/signature, replaces normal APK). Use a separate fresh test install/device if validating first-touch ads attribution; this fix never resets an existing account's source.
8. Repeat launch/cancellation on a Xiaomi/Oppo/Vivo phone if available and with different eligible wallets. Logcat tag VayoraUpi lists discovered package names only.
9. On a test phone/profile with no eligible wallet, confirm the genuine no-app dialog appears, Copy UPI ID works, Continue opens the status/UTR fallback, and Opening UPI… is cleared.

The archive also contains Vayora-play.aab for Play distribution; it is not an installable APK.
