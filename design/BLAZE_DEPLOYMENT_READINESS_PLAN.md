# Blaze Deployment Readiness Plan

Read-only planning document. No code, rules, deployment, or billing plan changed while producing this. Builds on `design/STORAGE_UPLOAD_ROOT_CAUSE.md`, `design/ADMIN_DELETE_USER_ROOT_CAUSE.md`, `design/BILLING_DEPENDENCY_AUDIT.md`, and `design/PAYOUT_RACE_CONDITION_AUDIT.md`.

**New finding surfaced while preparing this plan, flagged before anything else:** `firestore.rules` currently defines **two separate `match /escrow_releases/{...}` blocks** (lines 443 and 514) for the same collection. Firestore evaluates multiple matching rule blocks additively (a request is allowed if *any* matching block permits it), so the second, looser block — `allow create: if isSignedIn() && jobExists(...) && getJob(...).customerId == uid` (no check that the document ID equals the job's ID, no check that `status == 'pending'`) — currently coexists with, and partially undermines, the first, correct block that `design/PAYOUT_RACE_CONDITION_AUDIT.md` documents as the fix for the duplicate-payout bug (fixed `jobId`-as-`releaseId` idempotency). The second block also grants `allow update: if isAdmin()`, contradicting the first block's `allow update: if false` / "status transitions past 'pending' are Cloud-Functions-only" invariant. **This must be resolved before Blaze deployment** — see Section 4. Per instruction, this plan documents the finding but does not fix it.

---

## 1. Firebase Cloud Functions

### 1.0 Deployment-wide decisions to make first

| Decision | Current state | Recommendation |
|---|---|---|
| **Region** | No function specifies a region (no `setGlobalOptions`, no per-function `region()`); 2nd-gen functions default to `us-central1`. Firestore's actual location is **`eur3`** (Europe multi-region). | Functions calling Firestore/Storage from `us-central1` against `eur3` data works but adds real cross-region latency to every payment/escrow operation. Recommend deploying to a European region (e.g. `europe-west1`) instead — **but this requires a coordinated client change**: `lib/screens/admin/admin_dashboard_screen.dart`, `paystack_service.dart`, `ai_provider.dart` all call `FirebaseFunctions.instance` with no region, which resolves to `us-central1` by default. Deploying functions to a non-default region without updating every `httpsCallable` call site to `FirebaseFunctions.instanceFor(region: ...)` reproduces the exact `not-found` bug this session already root-caused for `adminDeleteUser` — just for a new reason (region mismatch instead of non-deployment). **If minimizing client-code changes is preferred, deploy to the default `us-central1` and accept the cross-region latency; this plan does not implement either choice.**
| **Codebase** | `firebase.json` declares one `functions` entry, `codebase: "default"`, `runtime: nodejs20`. | No change needed — matches `functions/package.json`'s `engines.node: "20"`. |
| **Secrets** | `PAYSTACK_SECRET_KEY` (4 functions), `GEMINI_API_KEY` (1 function) declared in code via `{ secrets: [...] }` but their live values were not verifiable from this environment (Secret Manager contents aren't readable via the CLI access available here). | Must be set via `firebase functions:secrets:set PAYSTACK_SECRET_KEY` / `GEMINI_API_KEY` **before** deploying the functions that reference them — deployment will fail or the function will error at runtime if a referenced secret doesn't exist. |

### 1.1 All 15 functions

| # | Function | Trigger | Secrets | Region | Deploy command (scoped) |
|---|---|---|---|---|---|
| 1 | `paystackWebhook` | `onRequest` (HTTP) | `PAYSTACK_SECRET_KEY` | default (`us-central1`) unless changed per 1.0 | `firebase deploy --only functions:paystackWebhook` |
| 2 | `autoReleaseEscrow` | `onSchedule` ("every 1 hours") | none | same | `firebase deploy --only functions:autoReleaseEscrow` |
| 3 | `processEscrowRelease` | `onDocumentCreated('escrow_releases/{releaseId}')` | `PAYSTACK_SECRET_KEY` | same | `firebase deploy --only functions:processEscrowRelease` |
| 4 | `onNotificationCreated` | `onDocumentCreated('notifications/{notifId}')` | none | same | `firebase deploy --only functions:onNotificationCreated` |
| 5 | `reconcileStuckEscrowReleases` | `onSchedule` ("every 24 hours") | none | same | `firebase deploy --only functions:reconcileStuckEscrowReleases` |
| 6 | `onJobCompleted` | `onDocumentUpdated('jobs/{jobId}')` | none | same | `firebase deploy --only functions:onJobCompleted` |
| 7 | `onArtisanRatingChanged` | `onDocumentUpdated('artisans/{artisanId}')` | none | same | `firebase deploy --only functions:onArtisanRatingChanged` |
| 8 | `onArtisanVerificationChanged` | `onDocumentUpdated('artisans/{artisanId}')` | none | same | `firebase deploy --only functions:onArtisanVerificationChanged` |
| 9 | `onAdminGranted` | `onDocumentCreated('admins/{uid}')` | none | same | `firebase deploy --only functions:onAdminGranted` |
| 10 | `onAdminRevoked` | `onDocumentDeleted('admins/{uid}')` | none | same | `firebase deploy --only functions:onAdminRevoked` |
| 11 | `onDisputeCreated` | `onDocumentCreated('disputes/{disputeId}')` | none | same | `firebase deploy --only functions:onDisputeCreated` |
| 12 | `initializePaystackTransaction` | `onCall` | `PAYSTACK_SECRET_KEY` | same | `firebase deploy --only functions:initializePaystackTransaction` |
| 13 | `verifyPayment` | `onCall` | `PAYSTACK_SECRET_KEY` | same | `firebase deploy --only functions:verifyPayment` |
| 14 | `analyzeJob` | `onCall` | `GEMINI_API_KEY` | same | `firebase deploy --only functions:analyzeJob` |
| 15 | `adminDeleteUser` | `onCall` | none | same | `firebase deploy --only functions:adminDeleteUser` |

**Dependencies** (`functions/package.json`): `firebase-admin ^12.6.0`, `firebase-functions ^5.1.1`, `axios ^1.7.7` (Paystack REST calls), `@google/generative-ai ^0.21.0` (Gemini), `crypto` (Node built-in, webhook signature verification). All already declared; `npm install` inside `functions/` before first deploy if `node_modules` isn't present.

**Full deploy command** (deploys all 15 at once, since none has been deployed yet and the first deploy also provisions the underlying Cloud Run services / Artifact Registry repo shared by all of them):
```
firebase deploy --only functions
```

- **CURRENT STATUS:** 0 of 15 deployed. Source is complete and was not modified by any investigation in this project.
- **BLOCKER:** Spark plan — confirmed via a real scoped-deploy attempt that failed at the Artifact Registry/Cloud Build API-enablement step (`design/ADMIN_DELETE_USER_ROOT_CAUSE.md`).
- **REQUIRED ACTION:** Upgrade to Blaze → set both secrets → resolve the region decision (1.0) and update client `httpsCallable` call sites to match if a non-default region is chosen → `firebase deploy --only functions`.
- **DEPENDENCIES:** Blaze plan; `PAYSTACK_SECRET_KEY` and `GEMINI_API_KEY` populated with live values; if region changes, coordinated client update (out of scope for this plan — implementation only).
- **VERIFICATION TEST:** `firebase functions:list` shows all 15 with status `ACTIVE`. Trigger each function's cheapest safe test: `adminDeleteUser` — see Section 5; `analyzeJob` — call "Analyze with AI" on Post a Job with a short description, confirm a real (non-`AiServiceException`) suggestion returns; scheduled functions — check `Cloud Functions → Logs` after their first scheduled run rather than waiting a full interval, or trigger a manual run from the Console.
- **PRODUCTION RISK:** Deploying with an unset secret causes that specific function to fail at runtime (not at deploy time, for some secret-referencing functions) — silent until first invocation. Deploying to a region the client doesn't call still returns the identical `not-found` error this session already diagnosed once; must not be mistaken for "still not deployed."

---

## 2. Firebase Storage

- **CURRENT STATUS:** No bucket provisioned at all (`design/STORAGE_UPLOAD_ROOT_CAUSE.md` — confirmed via `firebase deploy --only storage` failing at "fetching default storage bucket," before ever reaching the rules-upload step). `storage.rules` itself is already written and was not found to need changes.
- **BLOCKER:** Same Spark-plan ceiling (current Firebase policy requires Blaze to provision a *new* Storage bucket), compounded by the bucket never having been created via the one-time Console step even independent of billing.
- **REQUIRED ACTION, in order:**
  1. Upgrade to Blaze (Section 0/global prerequisite).
  2. Firebase Console → Build → Storage → "Get started" → **choose a location**. This is a one-time, permanent, human decision the CLI will not make unattended. **Recommend a European location** (e.g. `eur3` or `europe-west1`) to match Firestore's existing `eur3` location — mismatched regions between Firestore and Storage add latency to any operation that touches both (e.g. writing a Firestore doc referencing a freshly-uploaded Storage URL) and, in some configurations, cross-region egress cost.
  3. `firebase deploy --only storage` — deploys the existing, unmodified `storage.rules`.
- **DEPENDENCIES:** Blaze plan; the Console location choice (human-only step); **Section 5's `onAdminGranted`/`onAdminRevoked` functions must also be deployed** — see below.
- **Required Auth custom claims / dependency on `onAdminGranted`/`onAdminRevoked`:** `storage.rules`' `isAdmin()` check reads the Firebase Auth custom claim `admin: true` (confirmed by direct inspection), **not** the `/admins/{uid}` Firestore doc that `firestore.rules`' own `isAdmin()` reads. The claim is set/cleared *only* by `onAdminGranted`/`onAdminRevoked` (Section 5.2), which are themselves undeployed today. **Consequence: provisioning Storage without also deploying those two functions leaves every existing admin's Storage-admin access silently broken** — `isAdmin()` in `storage.rules` will evaluate `false` for every admin until (a) those functions are deployed and (b) each admin's ID token is refreshed (re-login, or up to ~1h automatic refresh — a Firebase Auth constraint, not something a Cloud Function can force). Deploy Storage and Functions **in the same maintenance window**, and have existing admins re-authenticate afterward, to avoid a window where admin Storage operations fail for a confusing, hard-to-diagnose reason.
- **VERIFICATION TEST:**
  1. As a regular signed-in user: upload a profile photo through Settings. Confirm the image renders (not the initial-letter fallback) after a page refresh.
  2. As an artisan: submit verification with a selfie + ID photo. Confirm both thumbnails render in Admin → Verifications.
  3. As an admin (after re-authenticating post-deploy): open the full-screen image viewer on a verification document or dispute-evidence photo — this exercises an admin-scoped Storage read, the specific path gated by the custom claim above.
  4. Post a new job with a required photo — confirm job creation, previously blocked entirely, now succeeds end-to-end.
- **PRODUCTION RISK:** Low for the bucket-provisioning step itself (no existing data to migrate — nothing has ever been stored). Real risk is the admin-claim propagation gap above being mistaken for a Storage misconfiguration when it's actually a stale-token issue — document this for whoever performs the deployment so it isn't re-investigated from scratch.

---

## 3. Payments

- **CURRENT STATUS:** Both Paystack-facing Cloud Functions (`initializePaystackTransaction`, `verifyPayment`) and the webhook endpoint (`paystackWebhook`) are undeployed. In a release build, `payment_screen.dart` surfaces a plain error and stops — no fallback (the debug-only `DemoEscrowScreen` simulation is explicitly disabled outside `kDebugMode`, by design, so it cannot be mistaken for a real payment path in production).
- **Paystack configuration required:**
  - `PAYSTACK_SECRET_KEY` populated as a live Functions secret (test-mode key first, live key only after end-to-end verification — see below).
  - Paystack Dashboard → Settings → API Keys & Webhooks → **Webhook URL** set to the deployed `paystackWebhook` function's HTTPS trigger URL (obtainable from `firebase functions:list` or the Console after deployment; not knowable before first deploy since Cloud Functions URLs are assigned at deploy time).
  - Confirm the Paystack account is configured for `NGN` and has Transfers enabled (required for payouts, Section 4) — Transfers are a separate Paystack account capability from basic charge acceptance and may need separate approval from Paystack.
- **Webhook requirements:** `paystackWebhook` verifies `x-paystack-signature` via HMAC-SHA512 against `PAYSTACK_SECRET_KEY` before processing anything — confirmed already implemented correctly; no action needed beyond the secret being live and matching the same key configured in the Paystack Dashboard (a test-mode secret with a live-mode webhook URL, or vice versa, will fail signature verification and silently reject every event with a 400).
- **Payment confirmation:** dual-path by design — `verifyPayment` (client-callable, fired right after the WebView redirect) and `paystackWebhook`'s `charge.success` handler (independent, asynchronous) both call the same `_lockEscrow`. Whichever arrives first wins; the other is a safety net if the client-side verify call fails to fire (app backgrounded, network drop mid-redirect, etc.).
- **Escrow creation:** `_lockEscrow` transactionally requires the job to be in `paymentPending` status before flipping it to `escrowLocked` — confirmed already correctly guarded (throws if the job is in any other state), preventing a stale/replayed webhook from re-locking an already-progressed job.
- **Failure handling:** `initializePaystackTransaction`/`verifyPayment` throw plain `Error`s with messages, which `cloud_functions` surfaces to the Dart client as `FirebaseFunctionsException`. `PaystackService` (Dart) does **not** currently catch/translate these the way `AiService.analyzeJob` does (Section 1, `design/BILLING_DEPENDENCY_AUDIT.md` #14) — `payment_screen.dart`'s catch block interpolates the raw exception into user-facing text (`'Payment could not be started: $e'`). This is a real, if lower-severity, instance of the same "leaked internals" issue fixed for `adminDeleteUser`. **Flagged here, not fixed** — out of scope ("do not change payment logic").
- **DEPENDENCIES:** Blaze (Section 1) for the 3 functions; live Paystack secret key; Paystack webhook URL configured in the Paystack Dashboard (a manual step outside this codebase, only possible after the function is deployed and has a URL).
- **VERIFICATION TEST:** Full loop with a **real but minimal** transaction (Paystack's test mode first, using Paystack's published test card numbers, before ever touching live-mode keys): Post a Job → agree a price → Pay Now → complete checkout in the WebView → confirm the app returns to Job Detail showing `escrowLocked` → confirm a `payments/{id}` doc exists with `status: escrowHeld` → confirm the Paystack Dashboard's Events log shows the `charge.success` webhook delivered with a `200` response (not a retry-looping failure).
- **PRODUCTION RISK:** Highest-value, highest-risk area to get wrong — this handles real customer money. Do not point the webhook at a live-mode URL, or deploy with a live-mode secret, until the test-mode loop above has been verified at least once.

---

## 4. Escrow — highest priority

### 4.1 Escrow creation
Already covered in Section 3 (`_lockEscrow`). No open issues found beyond what's documented there.

### 4.2 Escrow release (job → `completed`)
Two independent creators of `escrow_releases/{jobId}`, both already using the fixed-`jobId`-as-document-ID idempotency scheme documented in `design/PAYOUT_RACE_CONDITION_AUDIT.md`:
- **Customer manual confirmation** — `JobService.confirmComplete` (Dart), one Firestore transaction, checks the release doc doesn't already exist before creating it. Already correct.
- **Auto-release (14-day timeout)** — `autoReleaseEscrow` → `_releaseEscrow` (Cloud Function), transactional, checks both the job's current status and the release doc's non-existence before writing. Already correct (this was the actual fix `PAYOUT_RACE_CONDITION_AUDIT.md` describes; confirmed present in the current source).

**Required pre-deployment action, not yet done:** resolve the duplicate/conflicting `escrow_releases` rule block in `firestore.rules` (flagged at the top of this document). The second block's looser `create` condition (no `releaseId == jobId` check, no `status == 'pending'` check) and its `allow update: if isAdmin()` both reopen exactly the class of gap the fixed-ID scheme was built to close, if ever exercised by a client that doesn't already enforce the invariant itself (e.g., a future admin UI, a Firestore Console edit, or a bug in a not-yet-written feature). **This is a rules change and is explicitly out of scope for this plan to perform** — documented here so it's fixed deliberately, by choice, before Blaze deployment rather than discovered later.

### 4.3 `processEscrowRelease` — the actual payout
- **CURRENT STATUS:** Undeployed. Since it's a Firestore-trigger (not callable), there is categorically no client-side way to invoke, simulate, or work around it.
- **What happens today without it:** the job correctly reaches `completed`, the `escrow_releases/{jobId}` document correctly exists with `status: pending` — and then **nothing else ever happens**. No error. No stuck-transaction indicator visible to the customer or artisan. The UI has no reason to believe anything went wrong, because from the client's perspective, both writes it's responsible for succeeded.
- **Idempotency (already implemented, confirmed in source):** first action inside the function is a transactional claim — read the release doc, proceed only if `status == 'pending'`, atomically flip to `processing` in the same transaction. A second invocation for the same document (a platform-level at-least-once retry, the only realistic duplicate-trigger scenario for a Firestore-created trigger) finds `status != 'pending'` and exits immediately without calling Paystack again.
- **Duplicate-release protection:** structural, not just logical — enforced by the fixed `jobId`-as-`releaseId` scheme (Section 4.2) plus this function's own claim step. Two release documents for one job cannot exist (subject to the rules fix in 4.2 actually being applied); two calls to Paystack's `/transfer` for one release document cannot both proceed (subject to the claim step, already correct).
- **Failed-payout handling:** every failure path (`unknown_bank`, `account_verification_failed`, `recipient_creation_failed`, `paystack_transfer_failed`) writes `status: 'failed'` with a `failureReason` and sends the artisan an in-app "Payout Blocked"/"Payout Failed" notification (once notification delivery itself is working — Section 6). No silent failure *within* this function once it actually runs; the entire silent-failure problem today is that it never runs at all.
- **Bank code accuracy (real financial risk, separate from deployment):** `BANK_CODES` in `functions/index.js` is a hardcoded map of Nigerian bank names to Paystack numeric codes, explicitly flagged in its own code comment as unverified against Paystack's live `GET /bank?country=nigeria` endpoint from this environment. The function's own `_resolveAndVerifyAccount` step is the real safety net (aborts if the resolved account name doesn't match what the artisan typed) — but a wrong code for one of the newer fintech banks (Kuda/Moniepoint/Opay/PalmPay, called out specifically in the comment as lower-confidence) could still fail closed correctly (transfer aborts) rather than fail open (money sent to the wrong account), *if* the resolve step behaves as designed. **Verify this table against Paystack's live bank list before the first real artisan payout**, independent of the Blaze/Functions deployment itself.

### 4.4 Database state consistency — the verification procedure

**The core problem this section is designed to prevent:** the application can currently reach a state where `jobs/{id}.status == 'completed'` and `escrow_releases/{id}.status == 'pending'` simultaneously and *stay* there indefinitely, with the UI showing "payment released" language to both parties. This is not hypothetical — it is the exact, confirmed, current behavior of this app today, on Spark, for every job a customer or the auto-release timer completes.

**Required verification procedure — run this after every deployment that touches Functions, and periodically thereafter as an operational check, not just once:**

1. **Query for the discrepancy directly.** For every `jobs` document where `status == 'completed'`, look up `escrow_releases/{jobId}`. A completed job's release document must exist (structurally guaranteed by 4.2's transactional design) — the check that actually matters is **its `status` field**:
   - `status == 'pending'` for more than a few minutes after the job's `completedAt` → `processEscrowRelease` never ran or is not yet deployed. **This is the exact silent-failure state described above.**
   - `status == 'processing'` for more than a few minutes → the function ran, claimed the document, and is either still waiting on Paystack or crashed mid-flight after the claim but before recording an outcome — needs investigation, not automatically "probably fine."
   - `status == 'failed'` → correctly surfaced; check `failureReason` and confirm the artisan received the corresponding notification (Section 6).
   - `status == 'completed'` → the only state that means money genuinely moved. **This is what "payout actually processed" must be verified against — never `jobs.status`, which only ever reflects the Firestore-write half of the flow.**
2. **Cross-check against Paystack directly for a sample**, not just Firestore-internal consistency — Firestore could show `escrow_releases.status == 'completed'` correctly, but the corresponding Paystack Transfer should also be independently confirmed via the Paystack Dashboard's Transfers list (matching by `paystackTransferReference`, which is set to the release document's own ID) for at least the first several real payouts after deployment, before trusting the Firestore-side status alone as sufficient ongoing evidence.
3. **This procedure already has a natural home: `reconcileStuckEscrowReleases`** (Section 1, function #5) — it already runs daily and already flags anything stuck in `pending`/`processing` past a 2-hour cutoff into `admin_alerts`, which the Admin Dashboard's "Operational Alerts" card already surfaces. **Once deployed, this existing mechanism *is* the ongoing automated version of step 1 above** — no new code is needed for the recurring check. What's needed is a **one-time manual run of the same query** immediately after first deployment (via the Firebase Console's Firestore query builder, or a throwaway authenticated script — not a new permanent code path) to catch anything that accumulated during however long the app has been running on Spark with jobs silently reaching `completed` with no release ever processed. Every job currently sitting in that state needs a deliberate, informed decision about how to handle its backlog (process the payout retroactively, refund, or flag for manual review) — **not an automatic bulk-release**, since some of that backlog may be old enough that circumstances (job disputes, account changes) have changed since completion.
4. **Do not treat "the app shows no error" as evidence of anything.** This is the central lesson of the current bug: the application has no code path today that would ever show an error for this specific failure mode, on either the customer or artisan side. The only trustworthy signals are the `escrow_releases` document's own `status` field and independent confirmation against Paystack — never the job's own status, and never the absence of a visible error.

- **VERIFICATION TEST (for this section specifically):** immediately after deploying `processEscrowRelease` and before considering the deployment complete, run the step-1 query above against the live database. Confirm zero jobs remain with `status: completed` and a release stuck in `pending`/`processing` older than a few minutes, *or* have an explicit, reviewed plan for the ones that do (see step 3). Then complete one real, small, end-to-end test payout (Section 3's test-mode loop, carried through to actual release) and independently confirm the transfer in the Paystack Dashboard.
- **PRODUCTION RISK:** This is the single highest-risk area identified across every investigation in this project. Unlike a feature that's visibly broken (which no one can accidentally trust), this failure mode looks identical to success from inside the app. Treat the verification procedure above as mandatory, not optional, for the first deployment and for any subsequent change to `processEscrowRelease`, `confirmComplete`, or `_releaseEscrow`.

---

## 5. Admin

### 5.1 `adminDeleteUser`
- **CURRENT STATUS:** Undeployed; source correct; client error handling already fixed to show a clean message instead of leaking internals (`design/ADMIN_DELETE_USER_ROOT_CAUSE.md`).
- **BLOCKER / REQUIRED ACTION / DEPENDENCIES:** Same as any other function — Blaze, then `firebase deploy --only functions:adminDeleteUser` (or the full deploy).
- **VERIFICATION TEST:** Exactly the procedure `design/ADMIN_DELETE_USER_ROOT_CAUSE.md`'s own "Validation" section specifies, re-run post-deploy: open Admin → Users, select a real (non-production-critical, or a dedicated test account) user, Delete, confirm, verify the user disappears from the list, verify the Firebase Auth account is actually gone (Console → Authentication), verify Storage files under `users/{uid}/`, `verifications/{uid}/`, `artisan_portfolio/{uid}/` are gone, verify an `admin_audit_logs` entry with `action: userDeleted` was written, verify `jobs`/`payments`/`reviews`/`disputes` referencing that uid are untouched (by design).
- **PRODUCTION RISK:** Irreversible by design (real Auth deletion). Test against a disposable account first, not a real user, even after deployment is confirmed working.

### 5.2 Admin claims (`onAdminGranted`/`onAdminRevoked`)
Covered in Section 2 (Storage dependency). Additionally: `firestore.rules`' own `isAdmin()` does **not** depend on this claim (reads the Firestore doc directly), so Admin Dashboard access itself was never affected by these two functions being undeployed — only Storage-rules-gated admin operations were.
- **VERIFICATION TEST:** After deploying, grant a *new* test admin (write a doc to `/admins/{uid}`) and confirm — after that account re-authenticates — it can perform a Storage-gated admin action (e.g. open a verification document image). Then revoke and confirm the same action now fails for that account after its next token refresh.

### 5.3 Admin Storage permissions
Same dependency chain as 5.2 — no separate action beyond deploying both `onAdminGranted`/`onAdminRevoked` and Storage rules in the same window (Section 2).

### 5.4 All other existing Admin actions
Confirmed in `design/BILLING_DEPENDENCY_AUDIT.md`: every other Admin Dashboard action (Approve/Reject Artisan, Approve/Reject Verification, Suspend/Reactivate User, Resolve/Dismiss Dispute, Delete Review, Respond & Resolve Support Ticket, Mark Deletion Request Resolved, Beta Tester toggle, Audit Logs, Analytics) is a direct, already-admin-gated Firestore operation with no Cloud Functions or Storage dependency. **No action needed for these as part of Blaze deployment** — they already work today and will be unaffected by the deployment.
- **VERIFICATION TEST:** Not required specifically for Blaze deployment, but worth a quick smoke pass afterward to confirm nothing regressed (none of these code paths change as part of this deployment).

---

## 6. Notifications

| Notification path | Mechanism | Working today (Spark) | Requires Blaze |
|---|---|---|---|
| Quote received/accepted | `NotificationService.send()` — client Firestore write (`quote_service.dart`) | ✅ Yes | No |
| Dispute raised/resolved | Client Firestore write (`dispute_service.dart`) | ✅ Yes | No |
| Verification approved/rejected | Client Firestore write (`verification_service.dart`) | ✅ Yes | No |
| Agreement-flow notices | Client Firestore write (`escrow_provider.dart`) | ✅ Yes | No |
| Review submitted | Client Firestore write (`review_screen.dart`) | ✅ Yes | No |
| Escrow locked / work submitted / payment released | `_sendNotification` inside `onJobCompleted`/`_lockEscrow` (Cloud Functions only — no client equivalent exists) | ❌ No | **Yes** |
| Payout blocked / payout completed | `_sendInAppNotification` inside `processEscrowRelease`/webhook (Cloud Functions only) | ❌ No | **Yes** |
| **Push delivery, for every type above** | `onNotificationCreated` (Firestore-triggered, reads `fcm_tokens`, calls `messaging.send()`) | ❌ No — in-app list entries above still work, but nothing ever reaches a device | **Yes** |

- **CURRENT STATUS:** FCM token registration itself (`local_notification_service.dart`) works today (free, client SDK only) — tokens are being saved even though nothing currently reads them.
- **BLOCKER:** Same Functions deployment blocker as everywhere else.
- **REQUIRED ACTION:** Deploy `onJobCompleted`, `onNotificationCreated` (Section 1) — no separate configuration beyond the standard function deploy.
- **DEPENDENCIES:** None beyond Section 1.
- **VERIFICATION TEST:** Trigger a job through escrow-lock and submission with a device/browser that has notification permission granted; confirm an in-app entry appears for the previously-missing types *and* a push notification is received. Distinguish this from the already-working types by testing a quote and a dispute too — those should have been working before this deployment and must still work identically after (regression check).
- **PRODUCTION RISK:** Low — additive only; no existing working notification path is changed by deploying these two functions.

---

## 7. Storage-dependent flows

All four already covered precisely in Section 2 and `design/BILLING_DEPENDENCY_AUDIT.md` (#9-13). Summary for this section's specific ask:

| Flow | CURRENT STATUS | REQUIRED ACTION | VERIFICATION TEST |
|---|---|---|---|
| Job images | Blocked; also blocks job creation entirely (required field) | Section 2 (bucket + rules deploy) | Post a Job with a photo attached; confirm creation succeeds and the image renders in Job Detail |
| Profile photos | Blocked; every user shows an initial-letter fallback today | Section 2 | Settings → change profile photo; confirm it renders after reload |
| Verification documents | Blocked; no artisan can complete real verification today (Beta Tester toggle is the only current bypass, and is explicitly a controlled test mechanism, not a substitute) | Section 2 | Submit verification with selfie + ID; confirm thumbnails render in Admin → Verifications; Approve; confirm `verificationStatus` updates and (once Section 5.2/1 are deployed) `trustScore` recalculates |
| Portfolio images | Blocked | Section 2 | Artisan → Portfolio → add a project with photos; confirm they render on the artisan's public profile |

No additional action beyond Section 2 is required for these four specifically — they all fail and will all be fixed by the same one bucket-provisioning + rules-deploy step, since they all go through the same `StorageService`.

---

## Deployment sequence summary (highest-level order)

1. Resolve the duplicate `escrow_releases` Firestore rule (Section 4.2) — a deliberate decision and code change, not performed by this plan.
2. Upgrade `handytrust` to Blaze.
3. Set `PAYSTACK_SECRET_KEY` and `GEMINI_API_KEY` as live Functions secrets.
4. Decide the Functions region (Section 1.0) and update client `httpsCallable` call sites to match, if not keeping the `us-central1` default.
5. Provision the Storage bucket via Console (location decision — Section 2) and `firebase deploy --only storage`.
6. `firebase deploy --only functions` (all 15 together — first deploy for all of them, same underlying infrastructure provisioning either way).
7. Configure the Paystack webhook URL in the Paystack Dashboard, pointing at the now-deployed `paystackWebhook` URL (Section 3).
8. Run the Section 4.4 verification procedure against the live database for any backlog accumulated while running on Spark, **before** treating any pre-existing `completed`-but-unreleased job as resolved.
9. Have all existing admins re-authenticate (Section 2/5.2, for the custom-claim propagation).
10. Run every VERIFICATION TEST in this document, in the order listed per section, using test-mode Paystack credentials for the payment/escrow tests specifically, before switching to live-mode keys.
11. Only after step 10 passes in full: switch to a live-mode `PAYSTACK_SECRET_KEY` and repeat the Section 3/4 verification once with a real, minimal transaction.

This plan documents what needs to happen and in what order. No step in this list has been executed as part of producing this document.
