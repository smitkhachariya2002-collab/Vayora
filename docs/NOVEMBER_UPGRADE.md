# Vayora cinematic, media and engagement upgrade

Source: owner-supplied Flixvault change specification, 24 November 2026. Adapt to Vayora identity and preserve existing records. Baseline app 1.0.12+21; production branch a2787055e62b00a0e517bce967b310ab1fd03c94.

## Implementation checklist

- [ ] Bunny Stream create/TUS, full-playback signing, bounded HLS preview, encoding sync, owner deletion and orphan cleanup.
- [ ] Bunny Storage private cloud upload/download, quota enforcement and existing Supabase-file compatibility.
- [ ] Single/bulk admin uploader and optional cover failure isolation.
- [ ] Cinematic orange app and dark admin; Explore default; poster grids, player, compact channels and plan UX.
- [ ] Google identity conflict recovery without deleting paid guest data.
- [ ] Paid install verification, retry and state restriction with explicit evidence handling.
- [ ] Meta SDK IDs, consent, server/SDK install deduplication, delivery statuses.
- [ ] Payment callback/reference fixes, 72-hour expiry, submitted/success protection, UTR submission and paginated reports.
- [ ] FCM registration, foreground notifications, deep links, campaigns, schedules, frequency/quiet-hour rules and admin history.
- [ ] Privacy disclosure, tests, migration rehearsal, deployment and signed next-version artifacts.

## Configuration deferred by owner

- Bunny credentials and resource configuration will be entered last; no placeholder secrets or premature storage switch.
- Firebase configuration will also be added later (explicit owner reply). Prepare guarded initialization and server sender; do not claim delivered notifications before a real configured test.
- State-level IP classification needs trustworthy geographic evidence. Do not guess state from public IP prefixes or accept client-submitted state as verification.

## Preservation constraints

Keep com.vayora.app / com.vayora.play and existing signing identity. Do not copy Flixvault version code 54 or its package. Preserve account entitlements, files, posts and current UPI ID. New provider objects must retain backend ownership and access checks. Uploaded main video directory tokens must never be exposed as a supposedly limited preview.

## Latest owner clarification
Apply the five-section Bunny/media/UPI specification to Vayora only. Puffle is untouched. Preserve existing account, guest purchase, channel approval, Ads/Organic and Premium rules. Do not introduce a new install-verification gate as part of this media upgrade. The requested Puffle version code 18 cannot be reused for Vayora, whose released code is already 21; choose an unused higher Vayora version after checking releases.

Latest instruction: preserve the current Vayora app/admin theme colors. Dark-orange recoloring is explicitly superseded. Font and encoding fixes must not alter the palette.
