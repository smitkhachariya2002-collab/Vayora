# Admin workspace redesign

## Routes
The administrator dashboard is now at `/`, with `/channels`, `/posts`, `/approvals`, `/payments`, `/meta`, `/users`, `/requests`, `/plans` and `/admins`.
Existing `/dashboard` links remain supported. The original public landing page is preserved at `/home`.
Channel/post creation and editing use `/channels/new`, `/channels/[id]`, `/posts/new`, and `/posts/[id]`.

## Deployment
Do not apply schema changes from a preview directly to production. Merge only after CI and visual review.
The existing main-only migration workflow applies the additive admin migration and deploys the new `admin-delete-account` and `admin-invite` Edge Functions, alongside the existing self-deletion function.
In Supabase Auth URL configuration, allow the exact production invitation URL `https://vayora-eta.vercel.app/invite`. Keep email confirmation enabled. Local config already lists this callback.
The app uses only the existing browser-safe Supabase URL and publishable key. Never put a service-role key in Next.js public variables.

## Added admin RPCs
- `admin_metrics`: owner aggregates and scoped content-admin counts.
- `admin_directory`: owner-only administrator emails, roles and channel grants.
- `admin_manage_member`: owner-only verified-user role/channel changes; serializes changes and protects the last owner.
- `admin_meta`: owner-only configuration view; returns token presence, never the token.
- `admin_save_meta`: owner-only private configuration write.
- `admin_reorder_post_items`: admin/channel-checked atomic ordering; rejects stale/incomplete lists.
- `admin_payment_summary`: exact owner-only revenue/count aggregates using IST.
- `admin_user_plans`: owner-only active plan labels.

Existing database functions, RLS policies, payment activation, UPI logic and mobile app code are unchanged.
New private Meta settings have no direct user grants. RPCs check the owner and use an empty search path.
The SQL tests cover owner/content/member/anonymous boundaries, last-owner protection, token redaction, directory updates and media ordering.

## External setup / limits
- Meta Pixel settings can be saved, but event delivery is not connected. Health explicitly says Not connected; no events or success claims are fabricated. A production event sender needs a separately scoped integration.
- APK upload uses the existing downloads bucket and its unchanged 50 MB limit. Upload a signed ads build within that limit. The public download path is `/download`.
- Email invitations require the Supabase mail service to deliver successfully; new invitees finish password setup at `/invite`.
- User/report/order/post tables retain explicit recent-row limits. Financial summary and install metrics cover all rows.
- Removing a post/media record does not garbage-collect every orphaned storage object. Account deletion cleans the user's storage before deleting the account.
- Full account deletion requires an open deletion request, is owner-only, protects administrator accounts, and may stop partway if Storage/Auth fails. It never marks an incomplete deletion successful.

## Visual validation
The Admin responsive review workflow creates an ephemeral Supabase stack and synthetic accounts. It captures before/after screens at 375px and 1280px, checks document overflow, verifies create/delete feedback and content-admin isolation, and checks unauthenticated rejection on the admin Edge Functions.
All screenshots and its JSON report are uploaded as `admin-before-after`. No production credentials or customer data are used.
