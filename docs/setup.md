# GitHub-only setup and deployment

## 1. Configure GitHub Actions

Repository Settings → Secrets and variables → Actions. Enter secrets there,
never in chat, source, logs, issues, or a pull request.

Secrets:
- SUPABASE_ACCESS_TOKEN: Supabase personal access token for CLI deployment.
- SUPABASE_DB_PASSWORD: this project's database password.
- SUPABASE_PUBLISHABLE_KEY: safe client key, kept in Actions configuration.
- ANDROID_KEYSTORE_BASE64: base64 of one fixed Android release keystore.
- ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD.

Variables:
- SUPABASE_PROJECT_REF = fzloulsjhkdxwagonsgt
- SUPABASE_URL = https://fzloulsjhkdxwagonsgt.supabase.co
- ANDROID_RELEASE_ENABLED = true only after all signing values are configured.

The workflow does not generate a new signing key per build. Create a release key
once using Android Studio's Generate Signed Bundle/APK flow, retain a secure
backup, then store its values in GitHub Secrets. Do not send the key to this chat.

Create a GitHub environment named production if you want deployment approvals.
No credentials are needed for the disposable SQL test runner or debug APK checks.

## 2. Review the pull request checks

The preparation workflow generates and commits Android platform files and
dependency lockfiles into the build branch using the repository GITHUB_TOKEN.
The SQL tests run against a new runner database, not the live project.
After checks pass and review is complete, merge the one core-flow PR.
The Supabase deploy workflow then links the fixed project, pushes migrations,
deploys delete-account, and lists migration history. It never resets production.

## 3. Configure Supabase Auth

In Authentication settings enable anonymous sign-ins and manual identity linking.
Register the redirect URL: com.vayora.app://login-callback.
Enable Google and configure its OAuth credentials in Supabase and Google Cloud.
Use the callback URL Supabase supplies. Set the production site URL after Vercel
deployment. The repository config enables these features only on test runners;
the workflow intentionally does not overwrite live OAuth/provider settings.

## 4. Create the first owner

After migrations are deployed, sign up as Perfumwala@gmail.com on the admin login
page and confirm the email. Then run the SQL below in Supabase SQL Editor.
It only promotes the intended email after confirmation and refuses silent failure.

```sql
do $$
declare owner_id uuid;
begin
  select id into owner_id from auth.users
  where lower(email) = lower('Perfumwala@gmail.com')
    and email_confirmed_at is not null and not coalesce(is_anonymous,false);
  if owner_id is null then
    raise exception 'Sign up and confirm Perfumwala@gmail.com first';
  end if;
  insert into public.admins(user_id,role) values(owner_id,'owner')
  on conflict(user_id) do update set role='owner';
end $$;
```

No automatic email-based promotion is installed. All subsequent privileged actions
require a real admin row. Additional content admin membership can be granted in
SQL by an owner; there is no public admin-invitation endpoint in this milestone.

## 5. Deploy the admin to Vercel

Import this private repository. Set Root Directory to admin and framework Next.js.
Set:
- NEXT_PUBLIC_SUPABASE_URL = https://fzloulsjhkdxwagonsgt.supabase.co
- NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = the project's publishable key
- SUPABASE_SECRET_KEY = server-only secret if later server administration needs it

Current admin pages use the signed-in user's session and RLS, not a service key.
Never prefix a secret key with NEXT_PUBLIC_.

After owner setup, open Settings and choose the operating mode. Hybrid is seeded.
Open Payments, enter your real UPI ID and payee name, and enable payments only
when ready. UPI checkout stays disabled until these are configured.

## 6. Build APKs

After merging and setting signing secrets, enable ANDROID_RELEASE_ENABLED and run
Android verification and APKs. Download Vayora-apks with Vayora.apk and Vayora-ads.apk.
Both use the same application ID and signing key. The normal APK has no referrer;
the ads APK has the fixed paid-social referrer. First touch means replacing an
already attributed install does not change its source.

## 7. Physical-device verification

Test fresh installs, guest consent, account upgrades preserving UUID, existing
account login, Google callback, trailer completion, organic approval, verified
UPI payment, cancellation/app kill/resume recovery, downloads/rotation, and account
deletion. SQL/Flutter unit tests cannot prove real UPI apps or OAuth providers work.
Debug artifacts without a configured publishable key display a setup message.

The full cloud browser/upload flow, Meta tracking, report reasons/details UI,
creator mobile uploads, and detailed policy/public-form milestone remain future work.
