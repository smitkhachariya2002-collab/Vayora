# Admin live controls

Everything below is changed in the admin panel and reaches the app within seconds. No app update is needed.

| Admin action | Where | What the app does |
|---|---|---|
| Change a plan's price or duration | Plans → plan card → Save plan | New buyers see the new price and duration. Existing subscribers keep their plan until it ends. Orders already created keep their own price. |
| Hide, show or add a plan | Plans | The plan disappears from or appears in the Premium list. |
| Change the UPI ID or payee (old → new) | Payments → UPI settings → Save settings | The next payment opens the UPI app with the new ID. Unpaid orders made with the old ID are replaced when the user checks out again. Each order records the UPI ID it used (Payments → order → Payment details). |
| Remove the UPI ID | Payments → UPI settings → Clear UPI ID | Payments turn off. The app shows prices with a disabled "Payments unavailable" button and a "Payments paused" notice. |
| Turn payments off | Payments → untick "Enable UPI payments" | Same as removing the UPI ID. |
| Activation mode | Payments → UPI settings | Instant: plan turns on after a valid UPI success (bank check afterwards). Manual: waits for you to verify the bank payment. |
| Free mode | Plans → Free mode | No prices anywhere; logged-in users get 15 GB; ads users get full access; organic users can request it. |
| Free plans for organic / ads / everyone | Plans → Free plans | That group sees the price crossed out, a FREE badge and "Activate for free". Everyone else pays by UPI as usual. |
| Per-plan free flag | Plans → plan card → "Free when free plans are on" | Unticked plans always need payment. |
| Turn free plans off | Plans → Free plans → Off | No new free claims. Claimed plans run until their end date. |

## Rules enforced by the database

- `claim_free_plan` re-checks eligibility on the server, needs a logged-in (non-guest) account, refuses when the user already has an active plan, and allows one claim per user per plan per promotion. A new promotion starts each time free plans are switched on from Off.
- Organic users who claim a free plan go to Approvals, the same as after a paid purchase. Ads users need no approval.
- A free claim creates a subscription with source `free_promo` and a row in `free_plan_claims`. It creates no payment order, so revenue and Meta purchase events are unchanged.
- `create_order` refuses plans that are free for the user and records `upi_id_used` / `payee_used` on every new order.
- Every change to plans, UPI settings, free mode and free plans is written to `settings_audit` (Payments → Change history). Only the owner can read it.
- The Play build is unchanged: it stays on the free account card and never shows UPI or free plan claims.

Tests: `supabase/tests/admin_live_controls.test.sql`, `mobile/test/live_controls_test.dart`.

## Website plans page inside the app

Plans → **Plans page in the app** switches the Premium tab of the website/ads APK between the in-app list and the website page `https://vayora-eta.vercel.app/subscribe` shown inside the app (WebView). The page only displays plans. When the user taps Pay, the page sends the chosen plan to the app, and the app runs its normal checkout: the UPI app chooser, the result returned to the app, and automatic activation for the plan's duration (or the free claim when the plan is free for that user). The WebView can only load `/subscribe` and `/d` on the website.

The Google Play build never shows this page, because selling digital content through a web page inside a Play app breaks Google Play's Payments policy.

The WebView plugin needs Android 7.0 or newer, so the app's minimum Android version is now 7.0 (minSdk 24).
