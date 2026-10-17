# Mobile account and payment UI validation

GitHub-only continuation of PR #6, using Flutter 3.35.7 / Dart 3.9.

## Requested flows

- Profile uses a pinned, 168px expanded SliverAppBar with the warm diagonal gradient, initial avatar, editable name, active-plan badge and Settings action.
- Ads and organic users share this Profile UI. Server entitlements remain authoritative.
- Guest login prompt, member email/plan row, approved creator Upload action and hidden free-mode payment history.
- Owned channels precede joined channels. Approval status is private to the creator's Profile; Add Channel requires login.
- Policies, support email subject, logout and delete-account confirmation reuse existing endpoints.
- Premium benefits appear once from the selected plan's perks (fallback provided); compact animated selection rows preserve live prices and durations.
- Button labels cover unselected, guest, member and launching states. Plan selection stays mounted through login.
- One top banner: active plan takes priority over the newest open order.
- Free mode or no active plans uses the free-account card. Free mode hides all plans/prices/UPI actions.
- Payment details target an explicit order ID. Polling runs every five seconds for ten minutes per opened status; resume/manual checks remain available. Server success refreshes my_status.
- Success, pending, failed, cancelled and reversed messages are distinct; history shows newest-first own orders, local date/time, amount, reference and status.
- No UPI app gets a dedicated dialog; payment cancellation remains governed by the existing reported server state.

## Automated checks

flutter analyze: zero issues. flutter test: all 39 functional/widget tests pass. The PR description records final workflow results and the APK download. Normal tests cover account creation/login, source attribution, consent, mode visibility, channels, compact plans, payment-state copy, banner priority, button labels, guest navigation, owned approved uploads, private media paths and payment polling.
The normal command skips 84 screenshot cases; the visual workflow runs all 84 and three additional component captures, then rechecks the generated goldens.

Visual evidence: 36 previous-screen captures plus 87 redesigned images (the original 36 screen variants, 48 account/payment variants, and three components).
Phone widths: 360 and 430, text scales 1.0 and 1.6. Component checks additionally cover 2.0.
Account variants: guest/member/premium Profile, Settings, paid/free Premium, pending/success/failed/cancelled/reversed Payment, Payment history.

## Protected behavior and explicit limits

No changes to supabase/**, admin/**, mobile/android/**, mobile/lib/app_state.dart or mobile/lib/upi.dart.
The existing order creation, UPI URI, native result persistence, report retries, payment verification, access rules, approvals and free-mode switch remain unchanged.

The current database signup trigger leaves display_name empty. To honor the explicit UI-only / no-database-change instruction, Profile displays User- plus the first eight user-ID characters when empty; Edit saves to the existing profiles.display_name column. This PR does not alter the database trigger.

New post supports photo posts through the existing device photo picker and private media bucket. Only owned approved active channels get upload controls. It creates an unpublished draft, uploads to the existing creator/post path, then publishes; failed attempts are cleaned up where possible and remain unpublished. This does not add a video picker or change storage policies.

Cloud upload/folders/rename/delete remain unavailable; this task does not add cloud APIs.
Both login options remain visible; Google provider setup stays separate. Generated APKs are connected testing builds. Permanent release signing remains a separate step.

Screenshots use deterministic fictional fixtures and no production account/payment operations.
