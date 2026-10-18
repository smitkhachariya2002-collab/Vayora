# Live plan management
This change is stacked on PR #7 and must follow its migrations. Existing plan IDs/codes and foreign keys remain intact.
Plans are edited only by the owner in /plans. New codes accept lowercase letters/numbers and cannot change; new plans default hidden.
Prices are whole INR; migration deliberately fails rather than silently rounding any existing fractional price. Perks convert from the existing JSON array to text[].
Guest API access includes active plans even in free mode; mobile free/disabled-Play UI still hides prices and checkout remains blocked server-side.
Realtime listens to plans and a public, data-free plan_catalog revision. The latter is necessary because an UPDATE that hides a plan fails guest RLS and may not be delivered. Every event refetches active rows; reconnect/resume and pull-to-refresh also refetch.
Checkout locks the plan while creating an order and snapshots its current price/duration. On the next tap it replaces an open order with mismatched snapshots. Catalog edits never rewrite existing order amounts/durations or subscription expiry. Inactive plans block new orders. UPI response validation, activation, limits, reversal and webhook code are unchanged.
Run all SQL security/regression tests and mobile tests. Mobile visual CI captures the same open Premium widget before/after a change notification and asserts selection clearing after hide. Browser CI edits/adds plans through real owner server actions and checks actual anonymous Postgres Changes delivery for price edits and hiding.
Review evidence is committed under docs/plan-management/admin and docs/mobile-ui/screenshots/after/plans-live-*.png. Fictional data only. No production migration is applied by this PR.
