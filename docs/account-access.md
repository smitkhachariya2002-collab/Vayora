# Account and access contract

This PR follows the owner’s latest rules. Approval controls the ads audience and
trailers. In paid mode, an active subscription independently unlocks premium
items in visible posts. In free mode, permanent ads users and approved organic
members get premium playback; all permanent members receive 15 GiB cloud quota.
The server starts in paid mode (free_mode=false).

## Account lifecycle
- Startup creates an anonymous Supabase session, persists a UUID and random
  install claim secret, records the install once, then attributes the account.
- The install secret is an existing security extension to record_install and
  attribute_user. A UUID alone cannot claim another installation.
- First-touch source is immutable on both install and account records. Signing
  into an older account keeps that account's source.
- Email signup calls updateUser with the Android confirmation redirect. Google
  links the guest when Sign up is selected; Log in switches to an existing
  account. The button reads Continue with Google.
- Forgot password sends a recovery email; passwordRecovery opens the new-password
  screen. Logout creates and attributes a fresh guest.
- Policy acceptance is stored on device and synced per user to consents.
- The existing release workflow builds normal and paid-social APKs from the
  same code, application ID and fixed signing key.

## Database enforcement
Existing RLS on channels/posts/items and private media objects delegates to
security-definer helpers with empty search_path. New helpers separate approval
from subscription, redact plan status in free mode, and enforce immutable source.
Client roles cannot write source, approval, subscriptions or payment state.
Organic plan activation queues none/rejected accounts for review; a renewal
preserves an existing approval. Owner rejection/revocation hides ads posts and
trailers while retaining paid playback of visible all/organic posts.
Full free items require a permanent account (rule 4); anonymous ads users may
read trailer keys. Admin/post creator overrides remain unchanged.
UPI order prices, response handling, UTR verification, idempotence and owner bank
verification remain unchanged. Only the requested access-review transition changes.

## Status and playback
my_status includes every requested field plus existing quota/display fields and
is_admin. Screens use it, refresh after login/payment/resume, poll for expiry and
approval updates, and react to realtime mode changes. Playback refreshes status
before requesting a signed URL. Hidden audience detail screens and open players
close/deny access when status changes. New URLs are checked through Storage RLS.
Previously issued signed URLs remain bearer capabilities for their short 60-second
issuance lifetime; already buffered/downloaded bytes cannot be recalled.

Paid ads guests can start trailers directly. Trailer completion asks for login
and then plans only when paid mode is active and premium is absent. Free mode
shows login/free-access wording and no prices or payment UI.

## Verification and external setup
Database suites run on a disposable Supabase runner; Flutter analysis, tests and
debug APK build run only in GitHub Actions. Core payment security tests remain.
The new SQL matrix covers guest trailers, Storage RLS, immutable attribution,
same-ID conversion/history, existing-account attribution, approval/revocation,
expiry, free-mode playback/quota/catalog/orders and my_status fields.
Flutter tests cover startup, guest upgrade, existing login, logout, reset callback,
and server-driven screen decisions with an HTTP fixture.

Live Google login requires OAuth credentials configured in Supabase/Google Cloud.
Signed release APKs require the existing signing secrets and publishable client
key. These external credentials are not created by this PR. A physical device
must verify email/Google callbacks and real UPI app round trips before launch.
Production migrations run only through the main-branch deployment workflow after
review and merge; this PR does not mutate the live database.

The SQL workflow also performs real Auth/REST round trips against its local mail
server: guest email upgrade/confirmation preserving UUID and consent, existing
account attribution, fresh guest logout, and recovery confirmation callbacks.
No Auth credentials or confirmation links are printed.
