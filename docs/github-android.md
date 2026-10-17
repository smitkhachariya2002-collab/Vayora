# Build and sign Vayora entirely on GitHub

Android Studio and a local Android SDK are not required. All compilation happens in GitHub Actions.

## Installable testing APKs now

Open the Android verification and APKs workflow run for the latest PR or main commit. Download the Vayora-test-apks artifact, unzip it, and transfer Vayora-test.apk to your Android phone. Vayora-ads-test.apk uses the ads first-touch source. Both APKs contain the public Supabase client configuration and connect to the existing live project. Creating a test account or requesting an email happens only when you use the installed app.

These are debug-signed testing APKs. The GitHub runner's debug signing key can change between runs; switching builds may require uninstalling the old test app. Do not distribute these as permanent releases. Both APK variants use the same package ID, so install one at a time. First-touch attribution stays immutable; an existing account keeps its source.

## One-time permanent signing, through GitHub only

If you already have a published Vayora APK, reuse its original key instead of generating another one.

1. In Settings > Secrets and variables > Actions, add ANDROID_KEYSTORE_PASSWORD as a repository secret. Use a strong password of at least 12 characters; save it privately.
2. Once this workflow is merged, open Actions > Prepare Android signing key > Run workflow. Select main and type CREATE_NEW_KEY in confirmation.
3. Download the Vayora-signing-backup artifact from the completed run immediately. It expires after one day.
4. Unzip it. Save vayora-release.jks and its password securely in two backed-up locations outside the repository.
5. Open ANDROID_KEYSTORE_BASE64.txt locally and copy its entire contents directly to a GitHub repository secret named ANDROID_KEYSTORE_BASE64. The file encodes the password-protected keystore. Never put either file in chat, source, issues, or logs.
6. The alias defaults to vayora. The key password defaults to ANDROID_KEYSTORE_PASSWORD. Only set ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD when importing a different existing key.
7. Delete the temporary signing artifact from its workflow run after confirming your backups and secret are saved.
8. Under Actions Variables, create ANDROID_RELEASE_ENABLED with value true.
9. Open Actions > Android verification and APKs > Run workflow > main.
10. After verify and release both succeed, download Vayora-apks. It contains Vayora.apk and Vayora-ads.apk, signed with the same permanent key.

The signing workflow refuses to replace a key already saved in ANDROID_KEYSTORE_BASE64. Run it only once. It uploads only the password-protected keystore and its base64 encoding, never the password. Do not enable release before saving the key.

## Public client settings

mobile/config/public.json contains the URL and modern publishable client key intended to ship in the APK. It grants no owner/server privileges; database RLS still determines access. Server keys, SMTP passwords, and signing credentials are never included. Release builds can override the URL/key with the existing SUPABASE_URL variable and SUPABASE_PUBLISHABLE_KEY secret.

## Verify email login on the phone

Use a separate email you control. Sign up, open the confirmation email on the phone, then log in. Log out, request Forgot password, open the newest reset link on the phone, save a new password, then log in again. SMTP delivery and physical Android callback handling are not proven by the build passing.

Google stays visible but requires Google OAuth credentials before it works. Email testing does not require Google configuration. Infrastructure plan settings and app_mode are not changed by these workflows.
