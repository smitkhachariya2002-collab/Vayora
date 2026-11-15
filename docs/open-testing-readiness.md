# Open testing readiness â€” 16 November 2026

## Verified release
- Version 1.0.9, version code 17; Play package com.vayora.play, direct package com.vayora.app.
- Published APK and AAB SHA-256 match release checksums.txt.
- Google bundletool 1.18.3 validates the published AAB.
- Compile/target API 36; minimum API 24 (Android 7).
- AAB signature verifies. Original Vayora SHA-256 certificate: C6:D9:BD:A7:AC:AF:C6:83:DB:39:9A:3D:87:9A:12:5A:05:A7:8C:BB:C7:1B:C2:56:BF:E7:B7:6F:5C:35:E7:6B.
- Certificate validity ends 9 October 2056. Self-signed/timestamp warnings are expected for Android upload certificates; Play Console must still confirm the registered upload identity.
- All 12 native libraries have load segment alignment >=16 KB; bundle configuration requests PAGE_ALIGNMENT_16K.
- Final Actions run 43753128092 passed analysis, direct tests, Play tests, release builds and signing verification.
- PLAY_STORE=true is supplied for the AAB; prices, UPI purchase entry and plans checkout are hidden by the Play UI guards.
- No AD_ID, storage/media, location, contacts or camera permission in merged Play manifest. Permissions include internet, network state, wake lock, notifications and billing.
- Google Ads/Firebase Analytics are excluded. Firebase encoder transitive utility classes do not constitute Firebase Analytics integration.
- App includes first-open consent, optional analytics/Meta controls, content reporting/blocking and member account deletion.

## Not ready to declare open testing complete
- Live database has one published channel but zero posts/videos.
- Paid mode is active, free plan claims are disabled, and new accounts have no automatic free quota. Play purchase UI is hidden, so provide usable test-account entitlements or deliberately configure a free trial mode before recruiting testers.
- A physical device / Play-installed test has not been performed in this audit. Install through internal testing first; check first-open consent, guest-to-email signup, login/reset callback, upload/download/rename/delete, video playback/report/block and deletion using disposable test accounts/content.
- Existing Play Console upload certificate, used version codes, app setup, listing screenshots, content rating, Data safety, reviewer access and open-testing eligibility were not accessible in this audit.
- For affected newer personal developer accounts, Google requires 12 testers opted into closed testing for 14 consecutive days and production access before open testing is available.

## Console preparation
Upload Vayora-play.aab (not the direct APK). The listing must use com.vayora.play and accept version code 17; if 17 is already used, rebuild with a higher code. Verify upload certificate and enable Play App Signing. Use current screenshots of this release, not old screenshots. Provide reviewer credentials with functional content and storage access. Complete Data safety using the actual account, files, purchase history, optional activity/device identifiers and optional Meta sharing practices; do not claim no data collection. Public privacy policy: https://vayora-eta.vercel.app/privacy ; deletion: https://vayora-eta.vercel.app/delete-account . The app has no in-app ad placements; external Meta acquisition campaigns are separate.

Reference policies:
- https://support.google.com/googleplay/android-developer/answer/11926878
- https://support.google.com/googleplay/android-developer/answer/14151465
- https://developer.android.com/guide/practices/page-sizes

## Suggested release notes
<en-IN>
Vayora now has a refreshed visual theme, gentle interface motion, personal cloud storage and creator channels. This test includes privacy choices, account controls and stability improvements.
</en-IN>
