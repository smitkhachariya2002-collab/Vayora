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

## Plans in the app (website page) and who can see them

The website/ads app has no built-in plans list. Premium always opens the website page `https://vayora-eta.vercel.app/subscribe` inside the app (WebView). The page shows the plans; when the user taps Pay, the app runs its normal checkout: the UPI app chooser, the result returned to the app, and automatic activation for the plan's duration on success (nothing on failure). Free plans are claimed the same way. The WebView can only load `/subscribe` and `/d`.

Plans → **Show plans in app** decides who sees plans:

| Setting | Ads users | Organic users |
|---|---|---|
| Everyone | see and can buy | see and can buy |
| Ads users only | see and can buy | no plans, no Premium button, no subscribe prompts |
| Organic users only | no plans | see and can buy |
| Nobody | no plans | no plans |

- The server enforces it: `create_order` and `claim_free_plan` refuse users outside the chosen group, and hidden plans are never free.
- Users who already bought a plan keep seeing it (plan name, end date, payment history) until it ends.
- Admins always see plans, so you can test.
- The Google Play build never shows plans.

The WebView plugin needs Android 7.0 or newer (minSdk 24).
