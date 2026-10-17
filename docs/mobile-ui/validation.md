# Mobile redesign validation

Validated with the repository's pinned Flutter 3.35.7 / Dart 3.9 toolchain in GitHub Actions.

- `flutter analyze`: no issues.
- `flutter test`: 25 functional/widget tests pass. The 36 screenshot cases are intentionally skipped in this normal command and run in the dedicated visual workflow.
- Visual workflow: 36 baseline captures; 39 redesigned reference images (36 screen/size combinations and three component images). All redesigned images are generated and checked again against their references.
- Phone sizes: 360 × 900 and 430 × 900, each with text scales 1.0 and 1.6. Theme buttons and post cards also cover text scale 2.0.
- Screen coverage: Explore, Post, Player, Premium, Payment status/history, Cloud, Channels, Profile and Login.
- Regression coverage: existing-account login, guest signup retaining its user ID, duplicate-email feedback, password reset callback, attribution, free-mode presentation, channel validation, channel photo replacement/rollback, player retry and the existing UPI tests.
- Before/after screenshots are linked in [the review document](README.md).

The final GitHub workflow run and normal/ads APK download links are included in the PR description.

## Protected behavior

The PR diff was checked against base commit `b4031746e4f36df5a7f7fdeee9fc5ef75018641c`. There are no changes to:

- `mobile/lib/app_state.dart` or `mobile/lib/upi.dart`
- Android native handlers or signing configuration
- `supabase/**` (database schema, migrations, RLS, access functions and payment functions)
- `admin/**`

Media entitlement conditions and signed URL requests continue to use the existing gates. Payments still use the existing order creation, UPI invocation and result-reporting methods. Screenshot tests use fictional data and a simulated video decoder, not the live backend.

## Remaining setup and existing limitations

The generated normal and ads APKs are connected testing builds. Permanent release signing remains a separate configuration step.

Both login options remain visible; this UI change does not configure Google's OAuth provider. Email authentication uses the existing setup.

Cloud allowance is shown, while upload, folder, rename and delete operations remain unavailable because their backing feature was not implemented in the original app. This UI-only PR does not add storage APIs or change access rules.
