# A–F review status

The PR contains six implementation commits after merged PR #6. Validation on the reviewed source passes: **262 SQL checks**, real guest/email/recovery and concurrent-quota API tests, **43 regular Flutter tests**, the separate Play hidden-payment test, **99 visual checks**, all Edge Function type checks, admin lint/type/build/responsive review and native Android compilation. GitHub rechecks the final formatted tree.

| Items | Status |
|---|---|
| A1–A15 | Implemented and covered by core database, UI, provider-off, playback renewal and source/access tests. |
| B1–B10 | Implemented. Both payment activation modes, limits, UTR reuse, revoke, audit and order rules pass. The provider webhook is intentionally off until configured. |
| C1–C7 | Implemented and checked. Meta credentials, a published ads APK, Vercel click secret and app-link certificate still require owner configuration. Meta delivery tests cover zero accepted events, successful delivery and event expiry without external requests. |
| D | Dark/orange/gold screens pass at 360px/430px and normal/enlarged text, including Profile, App Setting, Premium, payment states, Cloud and video posting. |
| E | Direct/Play flavors and gated Google verification/reporting are prepared. Billing stays OFF. Play Console credentials, product mappings, program approval and real-device billing/lifecycle/refund verification remain rollout prerequisites. |
| F | Version 0.2.0+2 and permanent-signing APK/APK/AAB workflow are prepared. **Blocked:** the release job receives ANDROID_KEYSTORE_BASE64 and ANDROID_KEYSTORE_PASSWORD as empty; no signed release artifact has been produced. Native Android compilation passes. |

The PR description carries current check links and screenshots. It remains draft while signing is blocked. New migrations from this PR have not been deployed to production. Supabase Free cannot physically supply the configured per-user 15 GB/2 TB volumes; see [capacity and setup](parity-setup.md#free-tier-capacity).
