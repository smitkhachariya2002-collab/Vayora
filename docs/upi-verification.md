# Plans and UPI verification - 16 November 2026

Verified releases: organic Vayora.apk 1.0.9 (17), and Vayora-plans-upi.aab 1.0.9 (18). Both enable plans and native UPI intent checkout.

## Passed
- All five active plans have configured prices and durations: Trial INR 1 / 1 day; Silver INR 129 / 7 days; Gold INR 259 / 30 days; Platinum INR 599 / 180 days; Diamond INR 999 / 365 days.
- Payments are enabled; UPI ID and payee are configured; plans are visible to everyone in paid mode.
- 26 Dart tests covering plan UI, URI parameters/encoding, response parsing and persistent retry queue passed.
- Native Android response tests passed for direct and play variants in Actions run 43803857246.
- Published AAB build 18 checksum, Google bundletool validation, package, UPI intent queries and callback activity verified.
- Live database checks for all plan prices, no response, untrusted success, amount mismatch, verified provider activation, provider permission restrictions and duplicate callbacks passed in transactions that were rolled back.
- Manual admin approval activates once and rejects duplicate approval. No test payment or subscription records persisted.
- Disposable populated upgrade rehearsal including the new verification regression passed in Actions run 43803250827.

## Fix deployed
The inherited instant report_result path trusted a client SUCCESS response. Migration verify_upi_before_activation removes client-only activation; it queues review until provider or admin verification. This server fix applies to both already published downloads.

## Operational limits
Both upi-webhook and provider-payment report disabled/unconfigured. Automatic bank confirmation is therefore not connected. Admin must independently verify the received payment before approving it.
No Android device or installed UPI app was available. Real UPI chooser/handoff, cancellation, return to app, bank transfer and Play-installed behavior have not been exercised on a phone. Automated tests cannot establish bank acceptance or guarantee individual UPI app behavior.
The UPI-enabled Play AAB still requires applicable alternative-billing program compliance and Play Console acceptance; this audit does not certify store approval.
