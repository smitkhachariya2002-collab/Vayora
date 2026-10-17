# Vayora parity delivery

One follow-up PR after #6. Six commits: A core correctness; B payments; C cloud/media/Meta; D UI; E distribution/Play; F signing/CI.

In progress. Requirements map A1–A15, B1–B10, C1–C7, D/E/F will be completed with test evidence before marking this PR ready.

Payment activation: owner-confirmed instant default plus manual mode; max three client auto-activations per user per 24 hours; every auto-activation requires bank verification in admin; used transaction IDs remain blocked after revocation. Provider webhook uses server-side HMAC verification.

Live owner-authorized settings: UPI 2728412a@bandhan, payee AS Enterprice, enabled true, instant selected. No PINs/tokens/keystores in source. The existing deployed payment function stays manual until the reviewed payment migration is deployed.
