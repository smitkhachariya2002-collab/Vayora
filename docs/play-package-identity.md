# Android distribution identities

Version 0.3.8, versionCode 11.

| Artifact | Gradle flavor | Application ID / auth callback scheme |
|---|---|---|
| Vayora.apk | direct | com.vayora.app |
| Vayora-ads.apk | direct with install attribution | com.vayora.app |
| Vayora-play.aab | play | com.vayora.play |

Kotlin namespace and MainActivity class stay com.vayora.app; the installed package ID is set per flavor. FileProvider uses the runtime packageName plus .files. Manifest callback scheme and file authority use the applicationId placeholder. AndroidX-generated receiver permissions are verified in the compiled manifests.

Dart selects the callback from PLAY_STORE by default, and CI explicitly supplies the matching ANDROID_APP_ID. Email confirmation, password reset and browser-based Google OAuth all use the same authCallback. Supabase local config allows both exact URLs. Release CI adds only these URLs to live Auth configuration, preserves the existing allowlist/settings and reads them back. It reports whether Google is currently enabled without exposing OAuth/SMTP secrets; it does not silently enable an unconfigured provider. Google's web OAuth callback remains https://fzloulsjhkdxwagonsgt.supabase.co/auth/v1/callback.

Play Integrity and Android Publisher API endpoints now expect the Play-only package. Configure Play Console / Cloud access and the Play App Signing certificate for com.vayora.play. Upload-key SHA and Play App Signing SHA can differ. The website assetlinks route supports ANDROID_PLAY_SIGNING_SHA256 separately, falling back to ANDROID_SIGNING_SHA256; deploy the admin change and set the correct Play App Signing SHA for verified HTTPS post links.

Release proof is generated from the actual AAB using checksum-pinned bundletool 1.18.3 dump manifest. PACKAGE-IDENTITY.txt prints package and versionCode and verifies all three artifacts' callbacks, own authorities and permissions. Full Play-AndroidManifest.xml, signing report, checksums and live Auth callback report are included in the AAB artifact. No UPI validation or activation logic changes.

A package name already bound to a Play Console app cannot be renamed by uploading an AAB. Upload this bundle to a Console app for com.vayora.play. Do not upload the direct APK or the older com.vayora.app bundle.
