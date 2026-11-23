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

## Verification and deployment, 24 November
- Admin/public encoding repairs deployed. Inspected all main live admin sections; no corrupted labels remained. Inter is bundled locally. Existing CSS colors and mobile theme source are preserved.
- Additive media migration and owner-control follow-up applied through Supabase MCP after the populated SQL rehearsal passed. File timestamps now match the applied migration history: 20261123204032 and 20261123205335.
- Production record counts remained 107 profiles, 38 payment orders, 11 subscriptions, 3 channels, 0 posts and 0 cloud files. Access-function hashes were identical before/after.
- Flutter direct suite: 70 passed, 6 skipped; standard Play: 62 passed; plans Play: 70 passed, 6 skipped. All three suites also passed in CI. Admin production build and Edge checks passed; 6 Bunny boundary tests passed.
- Production web/admin deployment 2ef8dcbf799f7050bd075b1399209a18249f455b is READY. No Puffle resources were changed.
- Bunny/FCM credentials remain deferred. No real-provider media or notification success is claimed. Automatic notifications are seeded disabled; Bunny processing starts only on a configured reservation.
- Version 1.0.13 (22) signing workflow is running. GitHub CLI's stored accounts cannot create the Vayora draft release; browser control was stopped because it could not verify the Windows browser URL. Continue checking the pipeline before choosing a delivery fallback.

## Release completed
- Signing and publishing workflow 45263555652 completed successfully. Public release: https://github.com/smitkhachariya2002-collab/Vayora/releases/tag/v1.0.13
- Verified both APKs use the existing certificate and version 1.0.13/code 22; both AAB manifests use com.vayora.play/code 22. The release includes direct organic/ads APKs, standard Play AAB, plans-enabled Play AAB, checksums, setup notes, store artwork and the full ZIP.
- Browser/CLI draft creation was unavailable, but the repository's release pipeline successfully created and published the complete release itself; no publishing blocker remains.
- Website default and campaign downloads now point to the corresponding version 1.0.13 organic/ads APKs.
