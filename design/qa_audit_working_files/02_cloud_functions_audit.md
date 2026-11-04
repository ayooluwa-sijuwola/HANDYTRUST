# Cloud Functions Audit (from general-purpose agent)

## HandyTrust Cloud Functions — Production-Readiness Audit

**Scope confirmed:** `functions/index.js` is the only source file (1256 lines, read in full). `functions/` has no other `.js` files outside `node_modules`. `functions/package.json` deps: `firebase-admin ^12.6.0` (resolved 12.7.0), `firebase-functions ^5.1.1` (resolved 5.1.1), `axios ^1.7.7` (resolved 1.18.0), `@google/generative-ai ^0.21.0`, `engines.node: "20"`. `node --check functions/index.js` → **syntax OK**. `firebase.json` declares `functions[0].runtime: "nodejs20"`, `source: "functions"`, `codebase: "default"` — no runtime/engine mismatch.

**Deployment status — verified, not just inferred:** ran `firebase functions:list` (read-only, authenticated CLI, project `handytrust` active) → **"No functions found in project handytrust."** All 15 exported functions are currently undeployed. This matches the prior `design/BLAZE_DEPLOYMENT_READINESS_PLAN.md` / `design/BILLING_DEPENDENCY_AUDIT.md` findings, independently re-confirmed via the CLI call above.

---

### Full function inventory

| Function | Trigger | Region | Client caller | Auth check | Secrets | Failure handling |
|---|---|---|---|---|---|---|
| `paystackWebhook` | `onRequest` | default (`us-central1`, unspecified) | N/A — called by Paystack's servers | HMAC-SHA512 signature check against `PAYSTACK_SECRET_KEY` | `PAYSTACK_SECRET_KEY` | Returns HTTP 400 on bad signature, 500 internal error, 200 "OK" on handled/skippable cases |
| `autoReleaseEscrow` | `onSchedule('every 1 hours')` | default | N/A (cron) | N/A | none | `Promise.allSettled`, per-job errors don't abort sweep |
| `processEscrowRelease` | `onDocumentCreated('escrow_releases/{releaseId}')` | default | fires on doc creation from `JobService.confirmComplete` (Dart) or `_releaseEscrow` | N/A (Admin SDK, transactional pending->processing claim for idempotency) | `PAYSTACK_SECRET_KEY` | Every failure path writes status:'failed' + failureReason, notifies artisan; never throws unhandled |
| `onNotificationCreated` | `onDocumentCreated('notifications/{notifId}')` | default | fires on any notifications/* write | N/A | none | try/catch around messaging.send(), logs and swallows |
| `reconcileStuckEscrowReleases` | `onSchedule('every 24 hours')` | default | N/A (cron) | N/A | none | Writes admin_alerts docs; no try/catch around loop itself |
| `onJobCompleted` | `onDocumentUpdated('jobs/{jobId}')` | default | fires on job status writes | N/A | none | No top-level try/catch |
| `onArtisanRatingChanged` | `onDocumentUpdated('artisans/{artisanId}')` | default | fires from ReviewScreen writes | N/A + self-write guard | none | No try/catch |
| `onArtisanVerificationChanged` | `onDocumentUpdated('artisans/{artisanId}')` | default | fires from VerificationService approve/reject | N/A + self-write guard | none | No try/catch |
| `onAdminGranted` | `onDocumentCreated('admins/{uid}')` | default | **No client caller found** — no in-app UI writes to /admins/{uid}; manual/Console-only | N/A | none | try/catch, swallows |
| `onAdminRevoked` | `onDocumentDeleted('admins/{uid}')` | default | Same — no client caller found | N/A | none | try/catch, swallows |
| `onDisputeCreated` | `onDocumentCreated('disputes/{disputeId}')` | default | fires from dispute_service.dart writes | N/A | none | No try/catch |
| `initializePaystackTransaction` | `onCall` | default | lib/core/services/paystack_service.dart:25 | request.auth required; validates jobId/amount shape | `PAYSTACK_SECRET_KEY` | Throws plain Error (see Code Defects) |
| `verifyPayment` | `onCall` | default | lib/core/services/paystack_service.dart:52 | request.auth required; cross-checks Paystack's metadata.jobId against client jobId | `PAYSTACK_SECRET_KEY` | Throws plain Error (see Code Defects) |
| `analyzeJob` | `onCall` | default | lib/providers/ai_provider.dart:51-52 | request.auth required; bounds description/images | `GEMINI_API_KEY` | Throws plain Error; caller maps FirebaseFunctionsException codes but never sees real code |
| `adminDeleteUser` | `onCall` | default | lib/screens/admin/admin_dashboard_screen.dart:4474 | request.auth required; checks /admins/{uid} doc; blocks self-deletion | none | Throws plain Error; caller already shows generic message |

No function specifies explicit region — all default to us-central1, while Firestore's actual location is eur3 (Europe) — added cross-region latency once deployed.

---

### Deep dive on 6 key functions

**`adminDeleteUser`** (index.js:1140-1256) — Full server-side deletion: writes audit log FIRST, deletes real Firebase Auth account (tolerates auth/user-not-found), best-effort-deletes 3 Storage prefixes, deletes users/{uid}, artisans/{uid}, verifications/{uid}, artisan_private/{uid} in one batch, then subcollection fan-out (favorites, portfolio_projects, notifications, collectionGroup('favorites') for other users pointing at this artisan), chunked at 450 writes/batch. Deliberately does NOT touch jobs/payments/reviews/disputes/escrow_releases (correct by design). Logic is sound; only defect is generic-Error throw pattern (below).

**`processEscrowRelease`** (index.js:395-524) — The only function that actually moves money to an artisan. Idempotency = transactional pending->processing claim read directly from Firestore (not the frozen event snapshot — correctly reasoned, since that snapshot is always 'pending'). Verifies artisan bank details via Paystack /bank/resolve before creating transfer recipient, then calls Paystack /transfer. Every failure branch (no_bank_details, unknown_bank, account_verification_failed, recipient_creation_failed, paystack_transfer_failed) writes status:'failed' + failureReason and notifies artisan — no silent failure once it runs. BANK_CODES map (lines 302-323) self-flagged as unverified against Paystack's live bank list for newer fintechs (Kuda/Moniepoint/Opay/PalmPay) — pre-existing disclosed risk.

**`reconcileStuckEscrowReleases`** (index.js:587-606) — Daily sweep, queries escrow_releases where status in [pending,processing] and requestedAt <= now-2h, writes admin_alerts doc per stuck release. Composite index IS defined in firestore.indexes.json:13-19. No try/catch around the for loop (minor robustness gap).

**Admin custom-claim functions (`onAdminGranted`/`onAdminRevoked`, lines 790-808)** — Mirror /admins/{uid} Firestore doc into custom claims. firestore.rules' isAdmin() reads the Firestore doc directly (so Admin Dashboard access doesn't depend on these). BUT storage.rules' isAdmin() reads the CLAIM — so until these are deployed AND admin's ID token refreshes, admin-gated Storage ops will silently fail even for real admins. No in-app UI writes to /admins/{uid} at all — granting admin currently requires manual Firestore write outside the app.

**Payment initialize/verify** (lines 913-1010) — PAYSTACK_SECRET_KEY correctly kept server-side only. verifyPayment correctly refuses to lock escrow unless Paystack's own metadata.jobId matches client-supplied jobId (closes escrow-hijack path). Both call same _lockEscrow helper (line 127) as webhook's charge.success handler, transactionally requires job in paymentPending before flipping — correctly guarded against replay/race.

**Notification-sending (`onNotificationCreated`, lines 555-580)** — Single unified push path. Reads ONE fcm_tokens/{uid} token per user (single-device only, no multi-device fan-out — design limitation, not a bug). try/catch swallows per-user send failures. No dead-token cleanup on INVALID_ARGUMENT/NOT_FOUND (minor).

---

### CODE DEFECTS (real bugs, not infra blockers)

**1. [P1] Every `onCall` function throws plain `Error` instead of `functions.https.HttpsError` — custom validation messages are silently discarded by the SDK and replaced with generic "INTERNAL" error before reaching the client.**

Confirmed by reading the SDK itself: `functions/node_modules/firebase-functions/lib/common/providers/https.js:477-480`:
```js
if (!(err instanceof HttpsError)) {
    httpErr = new HttpsError("internal", "INTERNAL");
}
```
`index.js` never imports/uses `HttpsError` (zero grep matches). Affected throw sites:
- `initializePaystackTransaction`: index.js:917, 921, 924
- `verifyPayment`: index.js:981, 985, 1001, plus `_lockEscrow` internal throws (138, 142) propagate uncaught
- `analyzeJob`: index.js:1040, 1047, 1050, 1089
- `adminDeleteUser`: index.js:1142, 1146, 1151, 1158

**Concrete scenario:** customer enters invalid amount, calls initializePaystackTransaction. Function throws Error('amount must be a positive number.'). Client (payment_screen.dart:326) renders "Payment could not be started: [firebase_functions/internal] INTERNAL" — never the actual reason, because SDK replaced the message. Same for analyzeJob: ai_provider.dart's `_messageForCode(e.code)` switch (lines 82-93) can never select validation-specific messages since every error arrives as code:'internal'. Fix: import HttpsError from firebase-functions/v2/https and throw new HttpsError('invalid-argument'/'unauthenticated'/'permission-denied', '...') at each site.

**2. [P0/P1 — money path] `paystackWebhook` verifies HMAC signature against `JSON.stringify(req.body)` instead of the raw request body.**

index.js:32-35:
```js
const hash = crypto.createHmac('sha512', process.env.PAYSTACK_SECRET_KEY)
  .update(JSON.stringify(req.body))
  .digest('hex');
```
`req.body` is already-parsed-then-re-serialized JSON. JSON.stringify() does not guarantee byte-identical output to what Paystack originally sent (key order, whitespace, numeric formatting can differ) — Paystack computes its signature over the exact raw bytes transmitted. Firebase Functions v2 onRequest exposes `req.rawBody` (Buffer) specifically to avoid this. **Concrete scenario:** legitimate charge.success webhook arrives; if re-stringification produces different bytes than Paystack's original payload, hash !== x-paystack-signature header and function returns 400 "Invalid signature" — silently dropping a real payment confirmation, leaving escrow un-locked despite a successful charge, with only console.error as trace. Fix: use `req.rawBody` instead of `JSON.stringify(req.body)`. Severity depends on how often round-trip actually diverges — not verifiable without live traffic, but sits directly in the money path.

No other logic defects found in escrow, trust-score, or notification code — transactional idempotency patterns in `_lockEscrow`, `_releaseEscrow`, and `processEscrowRelease`'s claim step are correctly reasoned (read-check-write inside runTransaction, fixed-ID collision prevention, self-write-guarded triggers).

---

### INFRASTRUCTURE BLOCKED (not code defects)

All 15 functions are logically deployable — node --check passes, deps pinned compatible with Node 20, firebase.json runtime matches package.json engines.node exactly. Blocker is the Firebase **Spark plan**:

- Confirmed via live read-only `firebase functions:list`: **zero functions currently deployed** to project handytrust.
- 2nd-gen Cloud Functions (all 15 use firebase-functions/v2) categorically require Blaze plan to deploy — applies uniformly regardless of whether a function makes outbound calls.
- PAYSTACK_SECRET_KEY and GEMINI_API_KEY referenced via Secret Manager in 4 functions — live values could not be verified from this environment (separate prerequisite from Blaze upgrade).
- Firestore composite indexes needed by the two scheduled functions ARE already declared in firestore.indexes.json — no additional hidden index blocker once Blaze is enabled.

Deployment status verified as "0 deployed" directly; the Spark-plan attribution as the CAUSE rests on prior audit's direct deploy-attempt evidence, not independently re-tested this session (no billing-plan check attempted, per read-only constraint).
