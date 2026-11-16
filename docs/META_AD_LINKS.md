# Vayora 1.0.12 (21): ad destinations

## Google Play destination

Use this complete URL as the website destination in a Meta Traffic or Engagement campaign:

https://play.google.com/store/apps/details?id=com.vayora.play&referrer=utm_source%3Dmeta%26utm_medium%3Dpaid_social%26utm_campaign%3Dvayora_launch

This requires build 21 to be available to the audience in Play Console. While the app is in open testing, testers must join the test and be eligible for its country/region. Uploading the AAB alone does not make it available.

Keep this URL unchanged within a campaign. Create a new static utm_campaign value for a new campaign; percent encode the whole referrer query. Do not put a second raw ampersand-delimited query inside referrer.

The native app reads Google Play Install Referrer 2.2, stores the first successful result on the device, and submits source, medium, campaign and click/install timestamps to a private server table. A successful Play referrer takes precedence over APK fallback. Unavailable Play services retry. Existing account access and source rules are preserved, and lower-confidence evidence cannot replace higher-confidence attribution. This is campaign attribution, not proof of payment or a Meta-reported install match.

## Direct APK destination

https://vayora-eta.vercel.app/campaign/meta?utm_source=meta&utm_medium=paid_social&utm_campaign=vayora_launch

This campaign page downloads Vayora-ads.apk. The ordinary public website downloads Vayora.apk (organic). Both direct APK files use com.vayora.app; Google Play uses com.vayora.play. A direct APK uses the built-in Meta fallback and cannot recover per-ad Play referrers or claim individual click matching.

## Meta setup before advertising

Open https://vayora-eta.vercel.app/workspace/meta and enter your Pixel/Dataset ID and Conversions API token, then verify and send a test event using an Events Manager test code. Remove the test code before live delivery. The token stays on the server. Link the app to the dataset in Meta if sending app events. Advertising events require the user's sharing preference. Delivery is disabled until credentials are configured.

Use manual Traffic/Engagement destinations for these URLs. Native Meta App Installs objective / encrypted Meta install payload decoding is not included. Attribution capture does not itself enable Meta optimization or guarantee Ads Manager matching.

Plans and UPI are retained. The owner-requested instant activation trusts the UPI app success response and may activate unpaid plans. It is not bank verification. Only independently bank-verified orders qualify for verified Purchase revenue; UPI-success-only activations are excluded from that revenue.

## Release checks and limits

The release workflow checks Flutter tests in direct and Play modes, static analysis, APK signatures, AAB signature, package identity and version code 21. Attribution tests cover encoded parameters, organic vs Meta, caching, retry, APK fallback, preservation of existing account sources and secret isolation. Meta payload tests cover both package IDs and consent. Physical-device Google login, Play referrer delivery and UPI payment completion must still be checked on a phone. No live Meta dataset can be verified until credentials are entered.
