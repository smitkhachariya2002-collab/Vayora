# Access decisions

The owner confirmed mutually exclusive modes controlled by app_mode.free_mode.
The launch seed is false (paid mode). There is no hybrid mode.

| Rule | Paid mode: false | Free mode: true |
|---|---|---|
| Plans/prices/UPI in mobile | Shown | Hidden |
| Ads account before purchase | Free posts + trailers | Full videos after login |
| Organic ads access | Active plan AND owner approval | Request full access, then owner approval |
| Full premium videos | Active plan; organic users also require owner approval | Ads access after login |
| Cloud for permanent account | 2 TiB with plan, otherwise 0 | 15 GiB for every logged-in account |
| Guest cloud | 0 | 0 |

Stored subscriptions remain recorded when switching modes; paid-mode entitlement
returns when switching back if the subscription has not expired. A paid subscription
does not bypass organic approval in free mode. The app subscribes to operating-mode
changes through Supabase Realtime and refreshes its status. Resuming also refreshes
status. Playback pauses if a mode change removes entitlement. The database enforces
new access decisions immediately; previously issued signed URLs remain valid until
expiry, so this is not DRM or immediate revocation of an already copied URL.

## Attribution and permissions

An install stores its source once. A separate immutable per-user first source
survives switching accounts and install reattribution. The app uses a random
install UUID and a second secret saved on device. The original referrer is
app-reported and distinguishes APK distributions, not verified Meta conversions.
Client IP is never accepted from a mobile argument.

RLS protects every exposed table. Admins can browse content; content admins can
mutate only channels they created or have been assigned. Only owners change
payments, plans, operating mode, approvals and subscription grants. User-created
channels stay pending until owner review. Guest status and access cannot be
changed through editable profile metadata.

## Payment integrity

Amounts and durations are snapshotted by the database. Orders are serialized per
user. Activation is idempotent, checks the amount and unique bank UTR, and extends
remaining subscription duration. Phone UPI responses are untrusted: even a
well-formed SUCCESS stays pending until the owner verifies receipt in the bank.

This deliberately differs from reference point 22. Formatting and matching IDs
cannot prove a transfer occurred. No provider verification API is integrated.

## Storage and policy copy

Media uses creator/post/file keys in a private bucket. Full signed URLs require
a permanent account and entitlement; trailers require ads access. Public buckets
contain images and APKs. Uploads are limited to 50 MiB. Cloud writes remain closed
until atomic quota reservations and upload finalization are implemented.

Policies are starter copy requiring owner review before public launch.
