# Vayora v1.0.9 conversion — work in progress

## Resumed verification

Approval access worked on retry. Flutter tests now pass: 62 passed, 6 skipped. Local PostgreSQL startup was repaired by using a fresh cluster after a stale shared-memory process. All 16 original migrations and the v1.0.9 conversion now execute successfully against a local database with synthetic platform scaffolding and original seed data. Fixed the nonexistent posts.review_status mapping and removed new-schema seed audit entries before restoring historical audit rows. This is only a schema/seed rehearsal: populated account/payment fixtures, RLS tests, rollback verification and Supabase-platform validation remain required. No live database or deployment changes have been made.

User request: clone Puffle v1.0.9's design and full functionality for Vayora, omit Google Ads everywhere, preserve existing Vayora records and convert them to the new structure.

Reference: `smitkhachariya2002-collab/Puffle`, tag `v1.0.9`, commit `d3c6bc380dabe050bf03c64515ae257e35630b9c`.
Working branch: `feature/puffle-parity-no-google-ads`. Changes are local and not yet committed, pushed or deployed.

## Completed locally

- Copied the reference mobile and web/admin applications, rebranded as Vayora, retained the Vayora Supabase URL and publishable key.
- Removed Google Ads admin routes, website Google tags and calls, Firebase analytics dependencies, native measurement integration and Google consent controls. Meta consent remains separate and optional.
- Preserved Vayora Android signing configuration and app IDs (`com.vayora.app`, `com.vayora.play`); version `1.0.9+15` exceeds the previous build number 14.
- Retained Vayora's Next.js 16.4.2 and React 19.3.1 versions, adapted cookies/page props/proxy from the reference's Next.js 14 structure.
- Website production build and TypeScript checks passed. The build used public Vayora connection settings and `next build --webpack` because restricted-process Turbopack failed locally.
- Flutter analysis initially reported informational lint/deprecation findings only. Automatic fixes applied to 16 findings. Flutter tests initially passed 61, skipped 6 and failed one rebranding assertion; that expected letter was corrected from P to V. Rerun required.
- Removed Puffle's signing fingerprint from Android asset links; Vayora's real fingerprint must be supplied through `ANDROID_SIGNING_SHA256`.

## Database: draft only, do not apply

The live database has NOT been changed. At inspection it contained 55 profiles, 51 installs, 1 owner, 1 channel, 5 plans, 10 payment orders, 8 subscriptions, 1 support request and no posts/cloud files. These counts may change and must be rechecked before cutover.

`supabase/upgrade/DRAFT_puffle_v109_preserving_upgrade.sql` is an unverified conversion draft, intentionally outside the automatic migration directory. It archives original schemas, creates the reference schema without Google's migration, copies records with their original IDs and checks payment amounts/subscription dates. Auth users and storage objects are intended to stay in place. This is a coordinated cutover, not an additive backward-compatible migration: old clients may require an update.

The draft is assembled from `supabase/upgrade/prelude.sql`, Puffle v1.0.9 migrations except Google Ads, and `supabase/upgrade/convert.sql`. The workspace-level `build_upgrade.py` rebuilds it. No production reset or migration was performed.

## Remaining work

1. Complete local PostgreSQL rehearsal and fix all schema/conversion issues. Local tooling is in the sibling `migration-tools` folder; `rehearse.mjs` uses synthetic auth/storage/cron/http support. First rehearsal found a missing auth.deleted_at test column, now added; subsequent embedded PostgreSQL restarts exited before diagnostics. Obtain startup logs and fix this. No live data has been exported.
2. Add populated synthetic legacy fixtures, execute conversion and verify row/ID/amount/expiry/role/UTR preservation and RLS as anonymous, member, content-admin and owner. Ensure backup/rollback scripts restore triggers, cron jobs, policies and grants. Test aborted conversion leaves the original schema intact.
3. Review schema permissions and archived-schema access, storage path compatibility, legacy install claims, all table mappings, financial deletion behavior, promo mappings, Play settings, pending-payment handling and authorization. Rehearse with Supabase itself before live cutover.
4. Port the matching v1.0.9 Edge Functions excluding google-send. Existing functions still target the previous Vayora schema and must not be deployed with the new schema unchanged.
5. Replace/adapt old CI workflows and SQL tests for the new applications. Original Vayora workflows still refer to removed files and old tests. Preserve the existing signing secrets; never generate a replacement signing key or release a debug-signed APK.
6. Pin Flutter direct dependencies to the tested lockfile, rerun analysis/tests, build and verify signed APK/AAB with the existing key. Update download links only to verified Vayora artifacts. Current source points to the existing Vayora storage download paths; those objects have not been updated.
7. Review no-Google checks, update inherited browser smoke tests and privacy tests for the removed controls/new routes, and perform desktop/mobile visual and functional QA. Remaining references to Google Play/Google Fonts are unrelated to Google Ads; source-based Google campaign selection can be removed for clarity.
8. Prepare reviewed commit/PR, run CI, coordinate database/Edge Function/web/app cutover, verify live flows and preserve rollback access. Keep migration draft outside `supabase/migrations` until validation passes.

## Execution blocker

Automatic approval review refused the next local database diagnostic command because the account usage limit was reached. The tool said retry at 12:17 PM (15 Nov 2026, user timezone Asia/Calcutta), explicitly stating this was a review failure rather than an unsafe-action determination. Do not bypass the approval check. Local file edits/read-only inspection remain possible; privileged verification/deployment has not continued.
