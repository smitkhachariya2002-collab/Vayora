# Core-flow delivery checklist

✅ = implemented; ⏳ = external setup or verification required; ⚠️ = deliberate deviation or partial delivery.
Check the PR's GitHub Actions results for actual validation status.

1. ✅ Automatic anonymous session; ⏳ enable live anonymous sign-ins.
2. ✅ Persistent install UUID and claim secret.
3. ✅ Referrer parsing and immutable install/user attribution.
4. ✅ Normal and ads APK release variants; ⏳ signing configuration.
5. ✅ Versioned consent on device and in database, Explore default.
6. ✅ Email login, guest upgrade, Google linking/login, attribution after login, logout to new guest; ⏳ real OAuth callback verification.
7. ✅ Profiles, installs, consents and attribution RPCs.
8. ✅ Ads access from source or owner approval.
9. ✅ Channel/post/item audience RLS.
10. ✅ Pending user channels, approved admin channels, member-only join.
11. ✅ Private media and database-gated signed URLs.
12. ✅ Free/premium/ads/organic playback paths and trailer-end upgrade prompt. Hybrid mode requires a paid plan for full premium videos; the exclusive free-only override grants eligible members full playback.
13. ✅ Post details, Trailer/Play, related posts, sharing/channel/report/download actions, and a report reason/details dialog.
14. ✅ Status RPC and refresh after login/payment/resume.
15. ✅ Five seeded plans with fixed durations/prices and no auto-renew.
16. ✅ Subscription entitlement and extensions.
17. ✅ Owner-only UPI settings; ⏳ owner supplies real UPI details.
18. ✅ Own-order read-only access; privileged state changes.
19. ✅ Member-only server-priced orders, reuse/cancel and serialization.
20. ✅ UPI chooser MethodChannel, exact fields and missing-app handling.
21. ✅ Native disk persistence plus Dart retry queue on startup/resume/status polling.
22. ⚠️ Client success remains pending even after valid parsing. Bank verification by owner is required; untrusted phone responses cannot activate purchases.
23. ✅ Internal idempotent activation, amount checks, unique UTR, stacked duration.
24. ✅ Owner mark/revoke and scheduled stale-order cancellation.
25. ✅ Organic plan activation requests approval.
26. ✅ Polling/history, plan checkout, and an open-order banner.
27. ✅ Owner operating modes; hybrid free+paid is the owner-confirmed launch default.
28. ✅ Exclusive-free override, ads-approved entitlement, request access and 15 GiB/2 TiB quotas.
29. ✅ Hybrid, free-only and paid modes; owner approval stays independent of payment.
30. ✅ Core admin pages, approvals, users/grants, plans, payments/sales/repeat buyers, channel approvals, post uploads, mode controls, and repeat-buyer payment-history links.
31. ✅ Main-only migration/function deployment workflow; ⏳ production secrets and first merge.
32. ✅ Disposable Supabase SQL test workflow and security assertions.
33. ✅ Flutter verification and both signed release build definitions; ⏳ supply one fixed release key and configure the client key.

Not claimed complete: live deployment, physical-device UPI/OAuth tests, owner promotion,
public launch, full cloud file manager, Meta tracking, or the later public-site/forms milestone.
