# Royal Violet visual refresh

Three commits: Part 1 Explore cleanup; Part 2 centralised Royal Violet; Part 3 editable branding and generated exports.

No flow, logic, database or payment changes.

The owner chose Theme A and approved darkening surfaces immediately behind small white control text to meet AA. Base primary/gradient tokens keep the requested colours; controlPrimary and actionGradient encode the contrast adjustment. Status green/amber/red and premium-only gold retain their meanings.

Explore categories start 16px below the app bar. Channel suggestions remain below categories, with no heading or empty information card. Latest, posts, refresh, paging and empty states are retained.

SVG sources are in mobile/assets/branding. Exports are generated reproducibly in GitHub Actions using pinned flutter_launcher_icons/flutter_native_splash versions. All Android flavors inherit the same main launcher resources; no application IDs, link filters, UPI queries or signing keys change.

Before/after captures use the exact previous production commit b48dca986eb169d9705240be3c508d242976ff60, identical fictional data, Poppins fonts, two phone widths and larger text. Asset mask previews are explicitly labelled as previews. Native launcher/splash screenshots are captured separately on an Android emulator.

Package configuration references: [launcher icons](https://pub.dev/packages/flutter_launcher_icons/versions/0.14.4), [native splash](https://pub.dev/packages/flutter_native_splash/versions/2.4.7).
