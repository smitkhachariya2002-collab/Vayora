# Vayora Bunny activation

Only Vayora is changed. Keep com.vayora.app, com.vayora.play, the existing signing identity, Supabase fzloulsjhkdxwagonsgt and https://vayora-eta.vercel.app. Existing account, guest-purchase, approval, audience and Premium rules remain authoritative.

## Add server secrets last
In the Vayora Supabase dashboard, open Edge Functions > Secrets. Do not put these credentials in Flutter, browser code, GitHub source or a chat message.

Stream:
- BUNNY_STREAM_LIBRARY_ID
- BUNNY_STREAM_API_KEY
- BUNNY_STREAM_CDN_HOST (the library's .b-cdn.net hostname)
- BUNNY_STREAM_TOKEN_KEY (matching CDN token-authentication key)

Use a dedicated Stream library. Enable token authentication and disable public/direct original downloads. Use ordinary HLS segments, not byte ranges referencing a complete MP4. The app creates videos server-side after existing channel/post permissions are checked. Both uploaders use resumable 32 MiB TUS chunks for main videos and trailers. All four Stream secrets are required before switching new videos from Supabase.

Private cloud (a separate Storage zone and pull zone):
- BUNNY_STORAGE_HOST (the actual regional storage endpoint, e.g. storage.bunnycdn.com)
- BUNNY_STORAGE_ZONE
- BUNNY_STORAGE_PASSWORD (the zone password, not the Stream API key)
- BUNNY_STORAGE_CDN_HOST (the private pull zone .b-cdn.net hostname)
- BUNNY_STORAGE_TOKEN_KEY

Enable token authentication on the cloud CDN. Keep the Storage zone private and prevent direct/public origin access. All five values are required before new personal files switch. Legacy Supabase files retain their original download path; no bulk migration or deletion runs.

## Processing and publishing
The first configured Stream reservation enables the private one-minute processing job. The job requires successful signed HLS playback and an explicit 401/403 for the unsigned manifest before recording readiness. A requested publication waits until main video and any attached trailer are ready. Existing creator drafts are never automatically approved. Publication time is assigned by the server.

A Premium preview without a playable trailer contains at most 120 seconds of independently signed segment links. It never includes the main video directory token. Byte-range source playlists are rejected for generated previews.

## Cleanup
Settings > Storage Cleanup is owner-only. Scan, review thumbnails/size/date/reasons, and confirm one, selected, or all eligible videos. Each deletion rechecks both main and trailer references and the actual provider upload time. Videos younger than 24 hours, active reservations and uncertain lookups are kept. Removing a post/channel detaches its Bunny assets into a queue; the processing job removes them only after the same checks. No fixed cost-saving estimate is invented.

## Required checks after adding real credentials
1. Upload and play a free video from both a creator and admin.
2. Upload a Premium video with a trailer; confirm non-entitled eligible viewers receive only the trailer.
3. Upload a Premium video without a trailer and verify the generated preview stops within two minutes. Confirm no URL can fetch an unlisted segment/full playlist.
4. Confirm creator posts remain drafts until review, and Ads/Organic isolation and existing Premium rules are unchanged.
5. Confirm unsigned manifests/originals and private cloud downloads are denied while authorized signed URLs work and expire.
6. Interrupt and resume main/trailer uploads in both uploaders; fail a thumbnail upload and confirm the video is retained.
7. Check attached/recent videos cannot be removed by cleanup; remove a disposable test post and observe queued cleanup.
8. Confirm legacy Supabase videos and personal files remain readable and quota cannot be exceeded.

No live Bunny transmission or provider test is claimed before configuration and these checks. Firebase is also prepared for later configuration; automatic notification templates are disabled by default.
