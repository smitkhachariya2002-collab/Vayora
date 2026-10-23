# Vayora

Android cloud storage and creator channels for users across India.

- GitHub: private repository `smitkhachariya2002-collab/Vayora`
- Supabase: `fzloulsjhkdxwagonsgt` (Mumbai server region; nationwide access)
- Android application ID: `com.vayora.app` (website/ads APKs) and `com.vayora.play` (Google Play AAB)
- Owner: `Perfumwala@gmail.com`
- Support: `help.vayora@gmail.com`

## Current milestone

Guest onboarding, consent, install attribution, audience rules, channels, posts,
signed media playback, plan/order backend, manual bank verification, server-switched free and paid modes, admin pages, and GitHub Actions.

See [setup](docs/setup.md), [access rules](docs/access.md), and
[delivery checklist](docs/checklist.md). Cloud uploads and the full public-site/Meta
milestone are not included. Cloud quota is exposed by the backend; cloud writes
remain closed until atomic upload reservations are implemented.

## GitHub-only development

All source changes go through the core-flow pull request and GitHub Actions.
Production schema changes exist only in `supabase/migrations/` and are deployed
by `supabase-deploy.yml` on main. Never reset the live database.

Checks run SQL security tests against a disposable Supabase runner, Flutter
analysis/tests and a debug APK build, and Next.js lint/typecheck/production build.
Release APKs require signing secrets and the release-enabled variable.

Do not commit credentials, keystores, environment files, or raw payment responses.
