Vayora 1.0.10 - Plans, UPI intent and instant access

BUILDS
Vayora.apk: organic/direct Android app, com.vayora.app, version code 19.
Vayora-ads.apk: direct campaign variant, same package/signing; use only for Meta acquisition.
Vayora-play.aab: com.vayora.play, version code 19; includes plans and UPI checkout.
The website, admin, and account data are shared by these builds.
New payment orders use the UPI ID currently set in Admin > Payments: 2728412a@bandhan.

INSTANT ACTIVATION
The owner explicitly requested instant access and accepted the risk of unpaid plans.
A matching SUCCESS callback with a transaction ID can activate a plan immediately.
This does NOT prove receipt in the bank. Phone callbacks can be forged.
Orders remain bank-unverified until independently checked. Unverified activations
are not sent as verified Meta Purchase revenue. Duplicate callbacks do not extend
the same purchase twice. Failed/cancelled/mismatched responses do not unlock plans.
Manual mode remains available in Admin > Payments. Provider webhooks are not configured.
This behavior is server controlled; installing a new APK/AAB is not needed to apply it.

PLAY CONSOLE
Upload Vayora-play.aab, not an APK. Package must match com.vayora.play.
Version code 19 must not have been used before. Upload signing certificate must
match the certificate registered for this Play listing.
The UPI-enabled AAB is NOT certified as Play compliant or approved. Alternative
billing enrollment/integration obligations, review access, Data safety, content
rating and Console acceptance still need to be completed. There are no published
videos in production yet; upload content you own before recruiting testers.
Do an internal-track device test, including a real UPI app handoff, before open testing.
Google Ads is excluded. Existing accounts and purchases are preserved.

IMAGE ASSETS
icon-512.png: 512 x 512 opaque PNG; current cloud/play branding.
feature-1024x500.png: 1024 x 500 opaque PNG.
phone-screenshots/: three 1080 x 1920 opaque PNGs rendered from the current
Flutter app widgets and palette, using illustrative plan/account state.
These are widget captures, not screenshots of a live device or completed payment.
Review them against the actual Play-installed app before submitting the listing.
The 2 TB account shown illustrates a granted Gold plan, not a free allowance.
Inter-OFL.txt contains the font license. Reproduction sources are in source/.

LINKS
Website: https://vayora-eta.vercel.app
Admin: https://vayora-eta.vercel.app/workspace
Privacy: https://vayora-eta.vercel.app/privacy
Deletion: https://vayora-eta.vercel.app/delete-account
Support: help.vayora@gmail.com
Source: https://github.com/smitkhachariya2002-collab/Vayora/tree/feature/puffle-parity-no-google-ads

CONSENT UPDATE
First launch now has one Accept and continue button and no sharing switches.
It explicitly enables analytics and Meta sharing as described on screen.
No measurement starts before acceptance is saved and synced. Users can later
withdraw either choice in Profile > Measurement preferences. Existing users
see the updated notice before their saved choice is changed. Google Ads excluded.
