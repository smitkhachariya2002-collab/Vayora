# Access decisions

## Launch decision

The owner explicitly chose **free access and paid upgrades together**. This
supersedes the original all-or-nothing MONETISATION switch.

| Mode | free_mode | free_access_enabled | paid_enabled |
|---|---:|---:|---:|
| Hybrid (launch default) | false | true | true |
| Free-only override | true | true | false |
| Paid premium | false | false | true |

Free posts still require a permanent account for full playback.
Ads users can watch trailers while guests. In hybrid mode, premium full videos
require a paid plan; approved organic users can see ads content but still need a
plan for premium videos. In exclusive free-only mode, ads users and approved
organic users get full premium content after login.
Every permanent account gets 15 GiB in hybrid/free modes. An active paid plan
gets 2 TiB and full premium playback, regardless of source.
Organic users need owner approval to see ads-audience channels/posts even after
buying a plan. Buying a plan sets their access request to pending.

## Attribution

An install stores its source once. A separate immutable per-user first source
survives switching accounts and install reattribution. The app uses a random
install UUID and a second secret saved on device; another account cannot claim
an install just by knowing its UUID. The original referrer source is app-reported,
so this distinguishes APK distributions, not cryptographically verified Meta
conversions. Client IP is not accepted from a mobile argument.

RLS protects every exposed table. Admins can browse content; content admins can
only mutate channels they created or have been assigned. Only the owner can
change payments, plans, operating mode, user approvals, or subscription grants.
Profile display fields are editable; access/usage/guest fields are protected.
User channel approval and creator ownership cannot be changed by creators.

## Payment integrity

Amounts and plan durations are snapshotted by the database. Orders are serialized
per user. Activation is idempotent, checks the amount and unique bank UTR, and
extends the remaining subscription duration. Phone UPI responses are untrusted:
even a well-formed SUCCESS response stays pending for bank verification.

This deliberately differs from reference point 22: formatting, matching references
and unique IDs do not prove a transfer occurred. Only owner verification currently
activates a plan. No provider verification API has been integrated.

## Storage

Media keys use creator/post/file paths and a private bucket. Full-video signed URLs
require a permanent account and the item's entitlement. Trailer URLs require ads
access. Public buckets contain thumbnails/icons and APKs only. Maximum upload size
is 50 MiB. Cloud writes are closed in this milestone; no unmetered upload path is
exposed. Existing signed URLs remain usable until expiry; no DRM is claimed.

## Policy copy

The policy pages are starter copy. The product owner must review policies, refund
terms and retention before public launch. They are not a completed legal review.
