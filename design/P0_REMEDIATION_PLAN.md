# HandyTrust — P0 Production QA Remediation Plan

**Status: IMPLEMENTED (2026-08-17).** All fixes described below and detailed in the new §13 "Implementation Results" have been applied to the codebase, tested (Firestore Rules emulator, Cloud Functions unit tests, full Flutter test suite, live browser verification where reachable), and are ready for review. **Nothing has been deployed to production Cloud Functions, no live Paystack credentials were used, and no real-money transaction occurred at any point.** All testing ran against the local Firestore emulator, local Node unit tests, and the local `handytrust` project's Auth/Firestore in read-only/non-financial ways only (same disposable test accounts as the source audit). See §13 for the full implementation record; sections 1-12 below are preserved as originally written (analysis-only, pre-implementation) per the instruction not to rewrite historical findings.

---

**Original status (superseded by §13, preserved for history):** ANALYSIS ONLY. No application code, Firestore/Storage rules, or Cloud Functions have been modified. Nothing has been deployed. No Cloud Functions have been enabled. No live Paystack credentials were used or introduced.
**Source audit:** `design/FULL_PRODUCTION_QA_AUDIT.md` (+ `design/qa_audit_working_files/`).
**This document's method:** every claim in the source audit was independently re-verified against the current codebase during this investigation (not copied on trust) — `firestore.rules` (full 662 lines), `lib/core/services/job_service.dart` (full 1070 lines), `functions/index.js`'s payment/escrow sections (lines 1-524, 900-1010), and `lib/models/job_model.dart` were re-read directly by the lead investigator. Two additional refinements to the original P0-1 finding were discovered during this deeper pass (see §2.4) that materially change the recommended fix — the original audit's "just delete the duplicate rule block" recommendation is **not sufficient on its own**.

---

## 1. Executive Summary

**What is currently unsafe:** The Firestore security rules governing the payment → escrow → payout pipeline trust client-asserted state at three independent points, and — two refinements independently confirmed during this investigation (re-verified twice, by two separate re-reads of the current code, not just carried over from the source audit) — the picture is worse than originally described:
1. Even the *intended, correctly-scoped* `escrow_releases` rule block never verifies the job actually reached a paid/completed state — only that the caller is the job's customer and the document ID matches the job ID. Combined with `processEscrowRelease` (the Cloud Function that fires the real Paystack transfer) never re-checking job status either, and a customer-writable `agreedAmount` field with no type or bound validation, **the full exploit chain requires no real payment step at all** — a job only needs to reach `inChat` with an artisan assigned (which can be a second, colluding account) for a fabricated payout to be issuable.
2. The duplicate `escrow_releases` rule block doesn't even require the document ID to match the job ID, meaning the exploit is **repeatable per job**, not single-shot — a client can create multiple release documents for the same job, each independently triggering a real transfer, until that block is deleted.

Separately, and not itself a security exploit: this investigation found **no refund mechanism exists anywhere in the codebase** — cancelling a job after real payment is captured, or resolving a dispute in the customer's favor, currently has no automated (or even manual/admin) path to return the customer's money. This is a business-critical architecture gap, flagged for a dedicated design pass (§2.5, §11), not patched as part of this P0 rules fix.

**Why it is unsafe:** Firestore security rules are the *only* enforcement boundary between an authenticated client and the database once Cloud Functions execute using the Admin SDK (which bypasses rules entirely) — the Dart app's own validation (`JobService`'s `allowedTransitions`, `canInitPayment`, etc.) is a convenience/audit-trail layer, not a security boundary, because any client holding a legitimate user's ID token can call the Firestore SDK (or raw REST API) directly, bypassing the shipped app UI entirely. The rules as written do not require server-side, Paystack-verified proof of payment before allowing the state transitions and document creations that a legitimate payout depends on.

**What prevents immediate real-money exploitation today:** All 15 Cloud Functions (including `processEscrowRelease`, the only function that actually calls Paystack's `/transfer` endpoint) are currently undeployed — confirmed via a live `firebase functions:list` against the production project during the original audit, returning zero functions. The Firestore rules themselves ARE live in production today (rules deploy independently of Cloud Functions and don't require the Blaze plan), so the *document-fabrication* half of the exploit chain (creating fake `escrow_releases`/`payments` documents, or self-locking escrow) is possible against production right now — it just has no effect yet because nothing is listening to actually move money. The moment `processEscrowRelease` is deployed, this becomes a live, real-money vulnerability with no additional client-side changes needed to exploit it.

**What must happen before production:** All items in §4 (Firestore rules changes) and the `processEscrowRelease` hardening in §3 must be implemented and verified via the regression test plan in §7 — ideally using local Firestore Rules emulator tests, since this project currently has no such test infrastructure (confirmed absent: no `@firebase/rules-unit-testing` dependency anywhere, no `*.rules.test.*` files, no `emulators` block in `firebase.json`) — **before** Cloud Functions are deployed to production or live Paystack keys are introduced, per the deployment sequence in §8.

---

## 2. P0-1 Root Cause

### 2.1 Vulnerability A — Duplicate/conflicting `escrow_releases` Firestore rule blocks

**Exact rule/file:** `firestore.rules`, two separate `match /escrow_releases/{...}` blocks:
- Lines 443-450 (comment header at 422-442 explicitly states: *"Previously had no match block at all... Made explicit here per design/PAYOUT_RACE_CONDITION_AUDIT.md"*):
```
match /escrow_releases/{releaseId} {
  allow read: if false;
  allow create: if isSignedIn() &&
    releaseId == request.resource.data.jobId &&
    getJob(request.resource.data.jobId).customerId == request.auth.uid &&
    request.resource.data.status == 'pending';
  allow update, delete: if false;
}
```
- Lines 514-521 (a second, independent block for the identical collection path, under the header comment "Escrow release queue (processed by Cloud Function)"):
```
match /escrow_releases/{id} {
  allow read: if isAdmin();
  allow create: if isSignedIn() &&
    jobExists(request.resource.data.jobId) &&
    getJob(request.resource.data.jobId).customerId == request.auth.uid;
  allow update: if isAdmin();
  allow delete: if false;
}
```
**Relevant collection:** `escrow_releases` (top-level).
**Current behavior:** Firestore evaluates ALL `match` blocks that match a given document path and grants access if ANY of them allows the operation (rules are OR'd, not overridden by declaration order or specificity). The second block requires only `jobExists(jobId) && customerId == auth.uid` — no `releaseId == jobId` constraint (allowing arbitrary, non-canonical release-document IDs) and no `status == 'pending'` constraint (allowing a client to directly create a document in ANY status, including `'processing'` or something a downstream function might treat as further along than it should be). The looser block's permissions win for any write the stricter block would reject.
**Attack path:** A customer (or a modified client using a legitimate customer's ID token) calls `escrow_releases.add({jobId: <their job>, status: 'pending', ...})` — an auto-generated document ID — which is rejected by block 1 (`releaseId != jobId`) but accepted by block 2. This defeats the "exactly one release document per job, ever" invariant that `JobService.confirmComplete` and `_releaseEscrow`'s fixed-jobId-as-releaseId scheme (`design/PAYOUT_RACE_CONDITION_AUDIT.md`'s fix) depend on — `processEscrowRelease` fires unconditionally on every new document in the collection (see §2.4), so two documents for one job means two real Paystack transfers.
**Security impact:** Enables a duplicate payout for a job that was legitimately paid for once.
**Affected workflow:** Escrow release / artisan payout.

### 2.2 Vulnerability B — `payments` collection create rule has no ownership, amount, or job-linkage validation

**Exact rule/file:** `firestore.rules:409-420`:
```
match /payments/{paymentId} {
  allow read: if isSignedIn() && (
    resource.data.payerId   == request.auth.uid ||
    resource.data.artisanId == request.auth.uid ||
    isAdmin()
  );
  allow create: if isSignedIn() &&
    request.resource.data.payerId == request.auth.uid &&
    request.resource.data.status in ['pending', 'escrowHeld'];
  allow update: if isAdmin();
  allow delete: if false;
}
```
**Relevant collection:** `payments` (top-level).
**Current behavior:** The create rule checks only that the caller is asserting themselves as `payerId` and that `status` is one of two client-writable-looking values — it does not check `getJob(jobId).customerId == request.auth.uid` (i.e., does not require the caller to actually be that job's customer), does not validate `amount` is a positive number or bears any relation to the job's `agreedAmount`, and does not restrict `artisanId` to the job's real artisan. Critically, `status: 'escrowHeld'` — a value that should only ever be reachable server-side, after `_lockEscrow` (`functions/index.js:127-170`) confirms a real Paystack charge — is directly settable by the client on document creation.
**Attack path:** Any signed-in, non-anonymous user calls `payments.add({payerId: self, jobId: <any job>, artisanId: <any artisan>, amount: <any number>, status: 'escrowHeld'})`. This is accepted by rules with zero relationship to the target job required.
**Security impact:** Directly controls the amount `processEscrowRelease` will pay out for that job (see §2.4's amount-resolution logic) — this is the second of two independent ways to control the fabricated payout amount (the other being `agreedAmount`, §2.4).
**Affected workflow:** Payment initiation / escrow amount source-of-truth.

### 2.3 Vulnerability C — Customer can self-transition `paymentPending → escrowLocked` directly via Firestore

**Exact rule/file:** `firestore.rules:395`, inside `_isValidJobTransition` (`:368-406`):
```
(cur == 'paymentPending' && nxt == 'escrowLocked'   && (isAdmin() || isCust)) ||
```
**Relevant collection:** `jobs` (top-level), `status` field.
**Current behavior:** This is the exact transition `_lockEscrow` (`functions/index.js:127-170`, called only from the Paystack webhook's `charge.success` handler and from `verifyPayment`) is supposed to perform server-side, transactionally, after confirming a real charge. The rule additionally grants this transition to `isCust` (the job's own customer) with no constraint on `paymentReference` or any other field being genuine.
**Attack path:** Customer's job reaches `paymentPending` (a normal, legitimate state to reach — no payment has occurred yet at this point in the real flow, this is simply "ready to pay"). Customer writes `jobs/{id}.update({status: 'escrowLocked', paymentReference: '<anything>'})` directly. Accepted by rules. `JobService.lockEscrow` (`lib/core/services/job_service.dart:479-486`) is a live Dart method performing exactly this write shape; it is only called today from the `kDebugMode`-gated demo payment path (`lib/core/services/payment_service.dart:15-42`, `PaymentService.simulatePayment`), but **the enforcement boundary is the Firestore rule, not which app screens currently invoke the method** — a raw SDK/REST call using a legitimate customer's ID token bypasses the shipped app UI entirely and is unaffected by `kDebugMode` (a client-side, compile-time-only Dart constant with zero server-side meaning).
**Secondary failure mode (data integrity, not just security):** if the real customer DOES pay for real after a fake client-side lock already changed the job's status away from `paymentPending`, `_lockEscrow`'s own transaction (`functions/index.js:140-143`) throws `Cannot lock escrow: job is in state escrowLocked`, the webhook handler returns HTTP 500 (`:58`), and the real, successful charge is never reconciled to the job — money captured for real, with the job's Firestore state already claiming (falsely) to be escrow-locked, and no `admin_alerts` entry generated (only a `console.error` line).
**Security impact:** A customer can move their own job into a "paid" state with zero real payment, unlocking every downstream step (`inProgress`, `submitted`, `completed`, and ultimately payout) that assumes payment already happened.
**Affected workflow:** Job state machine / payment gating.

### 2.4 Refinement discovered during this investigation — the "correct" rule block AND `processEscrowRelease` itself never check job status, making Vulnerabilities A-C compoundable into a payment-free, escrow-lock-free exploit

This is the most important finding of this remediation-planning pass and changes the required fix.

**Claim, independently re-verified by direct reading of both files in this session:**

1. Block 1 of the `escrow_releases` rule (`firestore.rules:443-450`, quoted in §2.1 above) — the block that is supposed to be the *correct*, hardened one — requires only `releaseId == jobId`, `getJob(jobId).customerId == request.auth.uid`, and `status == 'pending'`. **It does not check `getJob(jobId).status` at all.** This means even after deleting the duplicate block 2 entirely, a customer could still create `escrow_releases/{jobId}` while their job is sitting at, e.g., `inChat` — long before any payment, `escrowLocked`, `inProgress`, or `submitted` state has ever been reached.

2. `functions/index.js`'s `processEscrowRelease` (`:395-524`, the Firestore-triggered function that actually calls Paystack's `/transfer` endpoint) reads the job (`:420`), checks only that `job.artisanId` exists (`:426-430`) — **it never checks `job.status`** — and then resolves the payout amount (`:435-440`):
   ```js
   const paySnap = await db.collection('payments').where('jobId', '==', jobId).limit(1).get();
   const amount = paySnap.empty ? job.agreedAmount : paySnap.docs[0].data().amount;
   ```
   If no `payments` document exists at all for the job, it silently falls back to `job.agreedAmount` — no payment record required whatsoever.

3. `job.agreedAmount` is writable by either the customer or the artisan any time the job is `inChat`, via a dedicated negotiation rule (`firestore.rules:142-148`):
   ```
   allow update: if isSignedIn() &&
     (resource.data.customerId == request.auth.uid || resource.data.artisanId == request.auth.uid) &&
     request.resource.data.diff(resource.data).affectedKeys()
       .hasOnly(['agreedAmount', 'lastUpdatedAt', 'lastUpdatedBy', 'updateVersion']) &&
     resource.data.status == 'inChat' &&
     resource.data.get('agreementStatus', 'negotiating') != 'confirmed';
   ```
   Unlike the `quotes` subcollection's creation rule two sections above it (`firestore.rules:310-311`, which correctly requires `amount is number && amount > 0`), **this negotiation rule performs no type or bound check on `agreedAmount` at all** — confirmed by direct re-read; `lib/models/job_model.dart:140` also declares `agreedAmount` as a plain nullable `double?` with no client-side bound.

**Combined, minimal exploit chain requiring zero real payment and zero escrow-lock step:**
1. Attacker controls two accounts: a customer account, and an artisan account (the artisan account need not be "fake" in the sense of failing verification — it just needs to be an account the attacker also controls, so the Paystack payout lands in bank details they control).
2. Customer posts a job, matches with their own artisan account (`requested → matched`, legitimate transition, artisan just needs to be `isArtisanEligible` — approved + verified, or a beta-tester-flagged account; this is the normal matching bar, not itself a bypass).
3. Job moves `matched → inChat` (customer-initiated, normal).
4. Customer (or artisan — the rule allows either party) writes an arbitrarily large `agreedAmount` via the negotiation rule above. No counterparty confirmation is required for this specific write (only the later `agreementStatus == 'confirmed'` checkpoint gates the `inChat → paymentPending` transition, which this chain never needs to reach).
5. Customer creates `escrow_releases/{jobId}` directly: `{jobId, status: 'pending', requestedAt: now, requestedBy: self}`. Passes block 1's rule as re-analyzed above — no job-status check exists to stop this at `inChat`.
6. `processEscrowRelease` fires: `job.artisanId` is present (from step 2) ✓ → no `payments` document exists → falls back to `job.agreedAmount` (the arbitrary value from step 4) → checks `artisan_private/{artisanId}` has bank details (the attacker's own colluding artisan account, so yes) → creates a Paystack transfer recipient → **fires a real Paystack transfer for the fabricated amount.**

This chain never touches `paymentPending`, `escrowLocked`, `payments`, or the earlier-described Vulnerability C at all — it is **strictly smaller and easier** than the exploit chain the original audit described, and it means Vulnerabilities A/B/C above, while each independently real and worth fixing, are not individually sufficient to describe (or fully close) the actual attack surface. **Fixing only "the duplicate rule block" and "the payments rule," as the original audit's recommended fix suggested, would leave this chain fully open.**

**Security impact:** Real, unbounded (subject only to the recipient artisan's Paystack account transfer limits) fund drain from the platform's Paystack balance, reachable with a two-account setup and no real payment step at all.
**Affected workflow:** The entire escrow-release/payout pipeline's trust model.

### 2.5 Additional finding — no refund mechanism exists anywhere in the codebase

Not part of the original three P0-1 sub-findings, but directly relevant to "affected workflow" and explicitly in scope per this investigation's brief ("refund paths, cancellation paths"):

- `PaymentStatus.refunded` (`lib/models/payment_model.dart:3`) is a **modeled but never-triggered** enum value — grepped across the entire codebase (`lib/` and `functions/`) for "refund"/"Refund"; the only hits are the enum declaration itself and its incidental appearance in `wallet_screen.dart`/`transaction_card.dart` (display-only, for rendering a status badge that nothing ever sets) and `audit_log_model.dart` (a generic string field, not refund logic).
- `firestore.rules:402-404` permits cancelling a job from `escrowLocked` (i.e., **after real money has been captured**) by either the customer or the artisan, with no admin gate: `(cur == 'requested' || 'matched' || 'inChat' || 'paymentPending' || 'escrowLocked') && nxt == 'cancelled' && (isCust || isArt)`.
- `JobService.cancelJob` (`lib/core/services/job_service.dart:757-767`) only writes `status: cancelled`, `cancelledBy`, `cancellationReason`, `cancelledAt` — no payment-reversal logic of any kind.
- Dispute resolution (`JobService.resolveDisputeWithRecord`, `:829-884`) only writes `status: resolved` on the job and `status: resolved|dismissed` on the dispute record — no financial consequence is coded anywhere for either outcome.
- No "issue refund" action exists in the admin dashboard (`lib/screens/admin/admin_dashboard_screen.dart` — grepped, zero matches).

**Practical consequence:** once escrow is genuinely locked (real customer money captured), the system has exactly one automated exit path for that money — pay the artisan on job completion. There is currently no automated or even manually-triggerable way to return a customer's captured payment if the job is cancelled or a dispute resolves in the customer's favor. This is a business-critical gap independent of the security vulnerabilities above, and is called out explicitly in §11 as needing architectural design work, not a rules patch.

---

## 3. Correct Security Architecture

### 3.1 Governing principle

**The client must never be trusted as the authority that money was actually paid.** Concretely, this means:
- Every field that asserts "payment happened" (`payments.status == 'escrowHeld'`, `jobs.status == 'escrowLocked'`, `escrow_releases` existing at all) must be either (a) writable only by server-side code running under the Admin SDK (which bypasses Firestore rules by design — Cloud Functions, not client rule exceptions), or (b) if a client-writable path must exist for a specific, deliberate UX reason (e.g. the manual "customer confirms completion early" release path), it must be narrowly scoped with an explicit precondition on the job's *already-legitimately-reached* state, and the money-moving Cloud Function on the other end must **independently re-verify** that precondition rather than trusting the mere existence of the document as proof.
- This second point matters even after the rules are fixed: rules and Cloud Function logic are two separate pieces of code that can drift out of sync (exactly what happened here — the rules were tightened per `design/PAYMENT_SAFETY_HARDENING_REPORT.md` while `processEscrowRelease` was never updated to also stop trusting `job.agreedAmount` as a fallback). Defense in depth means the function that actually moves money should not rely solely on the rules having been written correctly.

### 3.2 State-transition table (target/corrected — differences from current behavior are marked)

| State | Allowed transition | Actor | Required validation |
|---|---|---|---|
| `requested` | → `matched` | Customer | Artisan is eligible (approved + verified, or beta-tester-flagged) — **unchanged** |
| `matched` | → `inChat` | Customer | — **unchanged** |
| `inChat` | → `paymentPending` | Customer | Agreement confirmed by both parties; schedule confirmed if job requires one — **unchanged** |
| `inChat` (side-write, no status change) | `agreedAmount` update | Customer or Artisan | **CHANGED: add `request.resource.data.agreedAmount is number && request.resource.data.agreedAmount > 0`** (currently unbounded — see §2.4) |
| `paymentPending` | → `escrowLocked` | **Admin (Cloud Function via Admin SDK) ONLY** | **CHANGED: remove `isCust` — a real Paystack charge must be verified (webhook `charge.success` or `verifyPayment` callable) before this transition; a client must never be able to assert this directly** |
| `escrowLocked` | → `inProgress` | Artisan | — unchanged |
| `inProgress` | → `submitted` | Artisan | — unchanged |
| `submitted` | → `completed` (via `JobService.confirmComplete`, which also creates the `escrow_releases` doc atomically) | Customer | — unchanged transition; **the accompanying `escrow_releases` document creation gains the check below** |
| `submitted` (system) | → `completed` (via `autoReleaseEscrow` cron, `_releaseEscrow`) | System (Admin SDK) | — unchanged, already correctly transactional |
| (any of `escrowLocked`/`inProgress`/`submitted`) | → `disputed` | Customer | — unchanged |
| `disputed` | → `resolved` | Admin | **GAP (not a rules bug, an architecture gap, see §2.5): no financial consequence is currently coded for either outcome — flagged for design, not patched here** |
| (`requested`/`matched`/`inChat`/`paymentPending`/`escrowLocked`) | → `cancelled` | Customer or Artisan | **GAP (§2.5): cancelling from `escrowLocked` (post-payment) has no refund mechanism — flagged for design, not patched here. The transition itself is not a security bug; the missing refund is a business-logic gap.** |
| — | `payments` document create | **Server only (Cloud Functions, Admin SDK)** | **CHANGED: `initializePaystackTransaction` already creates this doc server-side today (`functions/index.js:954-965`) — the client-facing create rule is not needed for any legitimate flow and should be closed (`allow create: if false`)** |
| — | `escrow_releases/{jobId}` document create | Customer (matching the job's `customerId`) **or** Admin/system | **CHANGED: add `getJob(jobId).status == 'submitted'` to the existing `releaseId == jobId` / `status == 'pending'` checks — this is the missing precondition identified in §2.4** |
| — | `escrow_releases` status `pending` → `processing`/`completed`/`failed` | **Server only (Cloud Functions, Admin SDK)** | unchanged — already correctly `if false` for client update |

### 3.3 Client vs. trusted-backend responsibility (summary)

| Operation | Client-authorized? | Server/Cloud-Function-only? | Notes |
|---|---|---|---|
| Create job | ✅ Client (customer) | — | Must start at `requested` — unchanged, already correct |
| Negotiate `agreedAmount` | ✅ Client (either party) | — | Needs numeric/positive bound added (§3.2) |
| `paymentPending → escrowLocked` | ❌ **Remove client path** | ✅ Only via `_lockEscrow` (Admin SDK) | This is the core fix for Vulnerability C |
| Create `payments` doc | ❌ **Remove client path entirely** | ✅ Only via `initializePaystackTransaction` (Admin SDK) | Already how the real flow works; rule is currently over-permissive for no functional reason |
| Update `payments.status` | ❌ (already `isAdmin()`-only) | ✅ | Already correct |
| Create `escrow_releases/{jobId}` | ✅ Client (customer), **narrowly**, only when `job.status == 'submitted'` | ✅ Also via `_releaseEscrow` (auto-release cron, Admin SDK) | Preserves the legitimate "customer manually confirms early" UX while closing the status gap |
| `escrow_releases` status progression past `pending` | ❌ | ✅ Only `processEscrowRelease` | Already correct |
| `processEscrowRelease`'s amount source | N/A (function-internal) | **Must require a real `payments` doc with `status == 'escrowHeld'`; remove the `job.agreedAmount` fallback entirely** | See §3.4 — closing the rules gap alone is not sufficient without this |
| Job cancellation | ✅ Client (either party, current states) | — | Not itself unsafe; the *absence* of a refund step downstream is the actual gap (§2.5, flagged for design) |
| Dispute raise/resolve | ✅ raise (customer); resolve = Admin | — | Same caveat — no financial consequence coded either way |

### 3.4 `processEscrowRelease` hardening (defense in depth, beyond the rules fix)

Per the governing principle in §3.1, the rules fix alone (§4) is necessary but should not be treated as sufficient on its own for a function that moves real money. Recommended changes to `processEscrowRelease` (`functions/index.js:395-524`), to be implemented in the same change as the rules fix since they close the same vulnerability from two independent layers:

1. After loading `job` (`:420-425`), add: `if (!['submitted', 'completed'].includes(job.status)) { fail with a new failureReason: 'job_not_in_payable_state'; return; }` — this is the server-side mirror of the rules-side status check in §3.2, so a future rules regression (or a currently-undiscovered rules gap) doesn't independently reopen this vulnerability.
2. Replace the amount-resolution block (`:435-440`) — remove the `job.agreedAmount` fallback entirely. Require a `payments` document with `status == 'escrowHeld'` (the value only ever set server-side after a real Paystack charge, once §4's `payments`-create-rule fix is in place) matching the `jobId`; if none exists, fail with `failureReason: 'no_verified_payment_on_record'` rather than falling back to any job-resident field.
3. (Lower priority, not blocking) Consider narrowing the `payments` query to also match on the job's actual `artisanId`/expected amount range as an additional sanity check, though this becomes largely redundant once (1) and (2) above are in place and `payments` documents can only originate from `initializePaystackTransaction`.

### 3.5 Idempotency and duplicate-prevention (confirming what already works, and what still needs closing)

**Already correct, verified during this pass — no change needed:**
- `_lockEscrow` (`functions/index.js:127-170`): transactional read-check-write, requires `job.status == 'paymentPending'` before locking. Correct.
- `_releaseEscrow` (`:207-272`, the 14-day auto-release cron body): transactional, checks both `job.status == 'submitted'` and `!releaseSnap.exists` before writing. Correct.
- `JobService.confirmComplete` (`lib/core/services/job_service.dart:324-378`): correctly transactional, uses the fixed `escrow_releases.doc(jobId)` ID, checks non-existence first. Correct.
- `processEscrowRelease`'s atomic `pending → processing` claim (`functions/index.js:408-417`): genuinely protects against the same document being processed twice by a platform-level retry. Correct.

**Still needs closing (covered above):**
- The rules gap that lets a client bypass all of the above by writing directly to `escrow_releases`/`payments`/`jobs.status` in ways the transactional Dart/Cloud-Function code paths would never themselves produce.
- `initializePaystackTransaction` has no idempotency guard against a second concurrent payment session for the same job (originally flagged as P1-5 in the source audit, not P0, but relevant here — see §9 for why it's included in this remediation pass's scope as a fix-adjacent item, not a blocking one).

---

## 4. Required Firestore Rules Changes

All four changes below were independently re-verified by a second investigation pass in this session (not just carried over from the source audit) and one additional refinement was found: `payments.amount` is never cross-checked against `job.agreedAmount` at ANY stage (`initializePaystackTransaction`, `verifyPayment`, `_lockEscrow`, `processEscrowRelease`) — meaning, prior to the fixes below, a customer could also fabricate a `payments` document directly (not just via `agreedAmount`) since the `payments` create rule has no job-ownership check either; this is closed by change 4.3 below. Also confirmed: the duplicate `escrow_releases` block doesn't even require `releaseId == jobId`, so it permits creating **multiple** non-canonical release documents for the same job, each independently firing a real payout — i.e. the exploit is repeatable, not single-shot, until block 2 is deleted.

### 4.1 `escrow_releases` — delete the duplicate block, add the missing job-status precondition to the remaining one

**Remove entirely** (`firestore.rules:513-521`):
```
    // ─── Escrow release queue (processed by Cloud Function) ─────────────────
    match /escrow_releases/{id} {
      allow read: if isAdmin();
      allow create: if isSignedIn() &&
        jobExists(request.resource.data.jobId) &&
        getJob(request.resource.data.jobId).customerId == request.auth.uid;
      allow update: if isAdmin();
      allow delete: if false;
    }
```

**Replace** the remaining block (`firestore.rules:443-450`) with:
```
    match /escrow_releases/{releaseId} {
      allow read: if isAdmin();   // folded in from the deleted block above — admin dashboard/ops visibility
      allow create: if isSignedIn() &&
        releaseId == request.resource.data.jobId &&
        getJob(request.resource.data.jobId).customerId == request.auth.uid &&
        request.resource.data.status == 'pending' &&
        getJob(request.resource.data.jobId).status == 'submitted';   // NEW — the missing precondition (§2.4)
      allow update, delete: if false;
    }
```
This preserves the legitimate "customer manually confirms completion" UX (`JobService.confirmComplete` still works exactly as before, since it only ever calls this when the job is already `submitted`) while closing the "any status" gap identified in §2.4. It also implicitly closes the "multiple release docs per job" amplification, since only the fixed-ID (`releaseId == jobId`) block remains.

### 4.2 Job status transitions — remove client-writable `paymentPending → escrowLocked`

**Change** `firestore.rules:395`, inside `_isValidJobTransition`:
```
        (cur == 'paymentPending' && nxt == 'escrowLocked'   && (isAdmin() || isCust)) ||
```
**to:**
```
        (cur == 'paymentPending' && nxt == 'escrowLocked'   && isAdmin()) ||
```
`isAdmin()` here is not "an admin user in the app" — it is the mechanism by which Admin-SDK-executed Cloud Functions (`_lockEscrow`, called only from the Paystack webhook and `verifyPayment`) are permitted, since Admin SDK calls bypass rules entirely regardless of what this line says; this line's practical effect once `isCust` is removed is that **no ordinary client write can ever perform this transition**, which is exactly the intent. (A literal human admin manually forcing this transition through the Admin Dashboard would also still work, if that's ever a legitimate ops need — that path already goes through `JobService.adminForceStatus`, which requires `ctx.isAdminOverride` and an audit-logged reason, unaffected by this change.)

### 4.3 `payments` — remove the client create path entirely

**Change** `firestore.rules:415-417`:
```
      allow create: if isSignedIn() &&
        request.resource.data.payerId == request.auth.uid &&
        request.resource.data.status in ['pending', 'escrowHeld'];
```
**to:**
```
      allow create: if false;   // payments docs are created exclusively by initializePaystackTransaction (Admin SDK) — see functions/index.js:954-965
```
**Rationale:** confirmed during this investigation that the real payment flow already creates this document entirely server-side — `initializePaystackTransaction` (`functions/index.js:954-965`) writes the initial `payments` doc via the Admin SDK, which bypasses rules regardless. The client-facing `create` rule is not required by any legitimate flow today and is pure attack surface. **Known side effect, flagged explicitly per the "do not silently break things" instruction:** this will also disable `PaymentService.simulatePayment` (`lib/core/services/payment_service.dart:15-42`), the ungated demo/fake-payment path already flagged as P2-2 in the source audit (dead code today — not wired to any button — but currently capable of a direct client write to `payments`). Since that path directly conflicts with the "never trust client-asserted payment state" principle this whole remediation is built around, disabling it via this rule change is treated as a feature of the fix, not a regression — but the engineer implementing this should also action the source audit's P2-2 recommendation (delete `PaymentService.simulatePayment`, or explicitly gate it in a way that doesn't rely on Firestore rules permissiveness) in the same change, so the dead code doesn't sit there permanently broken/confusing. The already-correctly-double-`kDebugMode`-gated `DemoEscrowScreen`/`DemoEscrowService` path (source audit's positive-example, §Finding 6) does **not** write to `payments` at all (confirmed in the original payment-escrow audit pass) and is unaffected by this change.

### 4.4 `agreedAmount` negotiation rule — add type/positivity validation

**Change** `firestore.rules:142-148`:
```
      allow update: if isSignedIn() &&
        (resource.data.customerId == request.auth.uid ||
         resource.data.artisanId  == request.auth.uid) &&
        request.resource.data.diff(resource.data).affectedKeys()
          .hasOnly(['agreedAmount', 'lastUpdatedAt', 'lastUpdatedBy', 'updateVersion']) &&
        resource.data.status == 'inChat' &&
        resource.data.get('agreementStatus', 'negotiating') != 'confirmed';
```
**to** (adds one line, matching the existing pattern already used in the `quotes` creation rule at `firestore.rules:310-311`):
```
      allow update: if isSignedIn() &&
        (resource.data.customerId == request.auth.uid ||
         resource.data.artisanId  == request.auth.uid) &&
        request.resource.data.diff(resource.data).affectedKeys()
          .hasOnly(['agreedAmount', 'lastUpdatedAt', 'lastUpdatedBy', 'updateVersion']) &&
        request.resource.data.agreedAmount is number &&
        request.resource.data.agreedAmount > 0 &&
        resource.data.status == 'inChat' &&
        resource.data.get('agreementStatus', 'negotiating') != 'confirmed';
```
This is defense-in-depth (closes the "unbounded amount" vector even after 4.1-4.3 remove the direct exploit paths that would have used it) rather than the primary fix — no upper bound is proposed here since that's a product/business decision (e.g. a maximum job value), not a security requirement; flagged as an optional follow-up for whoever owns product decisions, not blocking.

### 4.5 Fields that must be immutable / server-controlled (summary, cross-referencing 4.1-4.4)

| Field | Must be | Enforced by |
|---|---|---|
| `payments.status == 'escrowHeld'` | Server-only | 4.3 (create: false, entirely server-side now) |
| `escrow_releases` existence at all | Server-only, OR client-created narrowly when `job.status == 'submitted'` | 4.1 |
| `jobs.status == 'escrowLocked'` | Server-only (Admin SDK) | 4.2 |
| `escrow_releases.status` past `'pending'` | Server-only | Already correct (`update, delete: if false`), unchanged |
| `payments.amount`, `payments.artisanId`, `payments.jobId` | Server-only (consequence of 4.3 — the whole document is now server-created) | 4.3 |
| `jobs.agreedAmount` | Client-writable but bounded (type + positivity) | 4.4 |

### 4.6 `processEscrowRelease` hardening (Cloud Function change, not a rules change — repeated here for completeness since it must ship in the same remediation)
See §3.4 for full detail: add a `job.status in ['submitted', 'completed']` check, and remove the `job.agreedAmount` fallback in the amount-resolution logic, requiring a real `payments` document with `status == 'escrowHeld'` instead. Once 4.3 makes `payments` documents exclusively server-created, this becomes a trustworthy source of truth for the payout amount — no separate cross-check against `agreedAmount` is required for *security* purposes (the `payments.amount` figure is, by construction, exactly what Paystack actually charged). A cross-check against `agreedAmount` for *fraud-detection* purposes (e.g. flagging a customer who paid noticeably less than what was negotiated with the artisan, which is a customer-vs-artisan dispute concern rather than a platform-security concern) is a reasonable follow-up but out of scope for this P0 remediation.

---

## 5. P0-2 Root Cause — `/portfolio-project` Flutter Web crash

### 5.1 Exact crash path

`lib/routes/router.dart:383-392`:
```dart
GoRoute(
  path: '/portfolio-project',
  builder: (context, state) {
    final extra = state.extra as Map<String, dynamic>? ?? {};
    return PortfolioProjectScreen(
      artisanId: extra['artisanId'] as String,   // ← crash: null as String
      existing: extra['existing'] as PortfolioProjectModel?,
    );
  },
),
```
`state.extra` is `null` whenever this route is entered other than via an in-app `context.push('/portfolio-project', extra: {...})` call. `extra` then evaluates to `{}` (the `?? {}` only guards the outer cast, not the inner key lookup), so `extra['artisanId']` is `null`, and `null as String` throws `type 'Null' is not a subtype of type 'String'` synchronously inside `builder` — i.e., during `build()`, uncaught. **This is the sole unguarded `extra[...]` cast in the entire router file** — every other `GoRoute` reading from `extra` uses a nullable cast with a fallback (e.g. `extra['category'] as String? ?? ''`), confirmed by re-reading all such call sites.

### 5.2 Affected route
`/portfolio-project` (`PortfolioProjectScreen`, the artisan portfolio add/edit-project form).

### 5.3 Affected platforms
**Flutter Web only.** Confirmed by reading `android/app/src/main/AndroidManifest.xml` (only a `MAIN`/`LAUNCHER` intent-filter, no `VIEW`/`BROWSABLE` filter, no App Links `<data>` config) and `ios/Runner/Info.plist` (no `CFBundleURLTypes`, no Associated Domains entitlement) — **no deep-link surface exists on either mobile platform today**, so this crash is unreachable via a mobile deep link and only reachable via Flutter Web (browser refresh, typed/bookmarked URL, back/forward history restore landing on this entry).

### 5.4 Affected users
Any signed-in, email-verified, non-suspended user — **not just artisans**. The router applies no role-specific guard to `/portfolio-project` (unlike `/admin/*`); the crash occurs entirely client-side in `build()`, before any Firestore call, so it precedes and is independent of the `firestore.rules` artisan-ownership check that would otherwise apply to the underlying `portfolio_projects` write.

### 5.5 Root cause (one-sentence)
A non-nullable cast on a Flutter Web route's `extra:`-only payload, with zero fallback, breaks the moment the route is reached by any path other than an in-app push — the single inconsistency against an otherwise-consistent nullable-cast convention used everywhere else in the same file.

### 5.6 Proposed fix
Two options were evaluated:
- **Option A (larger):** move `artisanId`/`existing` off `extra` onto path/query params; for edit mode, fetch the `PortfolioProjectModel` by ID instead of passing the Dart object through navigation state. This requires a new `PortfolioService.getProject(projectId)` method and a new provider (neither exists today), touching 4 files, and introduces a new async-loading UI state that doesn't exist today. A legitimate longer-term improvement (would also make edit-mode genuinely deep-linkable/bookmarkable), but disproportionate scope for a P0 crash fix.
- **Option B (recommended):** keep `extra`-based navigation (both real call sites — `portfolio_manager_screen.dart:238-239` create, `:325-326` edit — already always supply `artisanId` correctly), add a null-safe guard in the route builder that renders a small, new fallback widget ("This page can't be opened directly — please go to Portfolio Manager") instead of crashing when `artisanId` is absent.

**Recommendation: Option B.** Smallest safe fix, single file (`router.dart`) plus one small new stateless widget, zero risk to the two working call sites, matches the source audit's own stated acceptance criterion ("Screen loads normally, or at minimum shows a graceful can't-open-this-directly state"). Option A is a legitimate separate follow-up task (and, if undertaken later, should also cover the same `extra`-only pattern on `/artisans/:jobId`, `/artisan/:uid`, `/demo-payment/:jobId`, `/open-jobs`, already noted as P3s in the source audit) — not bundled into this P0 fix.

### 5.7 Regression tests
This repo currently has no widget-test or `go_router`-specific test harness (confirmed: `test/` contains only pure Dart unit tests; `test/admin_exit_navigation_test.dart`'s own header comment explicitly notes the lack of a router test harness and works around it by testing extracted pure logic instead of the router itself). The same workaround pattern applies cleanly here — and better, since this route's builder needs no Firebase auth state or Riverpod provider tree to test in isolation (both `go_router` and `flutter_test` are already dependencies; no new dev-dependency needed).

Proposed new file **`test/portfolio_project_route_test.dart`**, an isolated `GoRouter` widget test with three cases:
1. Direct navigation with no `extra` → asserts `tester.takeException()` is `null` and the new fallback widget's text is found (this is the test that reproduces and currently fails against the unfixed code).
2. Navigation with `extra: {'artisanId': 'uid123'}` → asserts `PortfolioProjectScreen` renders in create mode with that `artisanId`.
3. Navigation with `extra: {'artisanId': 'uid123', 'existing': <model>}` → asserts the screen renders in edit mode with fields pre-filled from `existing`.

---

## 6. P0-3 Root Cause — Forgot-password false success

### 6.1 Exact failure path (full control-flow trace)

1. User taps submit → `ForgotPasswordScreen._submit()` (`lib/screens/auth/forgot_password_screen.dart:29-46`) validates the form, sets `_loading=true`, awaits `AuthNotifier.sendPasswordReset(email)`.
2. Inside the notifier (`lib/providers/auth_provider.dart:94-102`), `AuthService.sendPasswordReset` (`lib/core/services/auth_service.dart:56-58`, a bare pass-through to `FirebaseAuth.sendPasswordResetEmail` with no try/catch of its own) is awaited.
3. **If it throws `FirebaseAuthException`**: caught by the notifier's `on FirebaseAuthException catch (e)` (provider:99-101), which sets `state.error` to a friendly message and `state.isLoading=false` — **and returns normally, without rethrowing.** The `Future` the screen is awaiting completes without an attached error.
4. Back in the screen, the `await` at line 39 therefore does not throw. Control falls straight through to line 40: `setState(() => _sent = true)` — executed **unconditionally** whenever step 3's await didn't throw, which is true both for a genuine success and for the swallowed-exception case.
5. The screen's own `catch (e)` (line 41) is **structurally unreachable** for `FirebaseAuthException` specifically — not "catching the wrong thing," simply never invoked, because the exception was fully absorbed one call-frame earlier inside the notifier.
6. `_sent=true` → the build method (line 71) renders "Check your inbox," regardless of whether an email was actually queued.

**Root cause, one sentence:** `AuthNotifier.sendPasswordReset` catches `FirebaseAuthException` and stores it in its own state without rethrowing, while the calling screen treats "the await didn't throw" as its sole success signal instead of checking the notifier's error state.

### 6.2 Expected behavior per scenario

| Scenario | Current behavior | Required behavior |
|---|---|---|
| Valid, registered email | Success screen (correct today, by accident of the bug's shape) | Success screen — unchanged |
| Syntactically invalid email | Mostly blocked client-side by the existing regex validator before any network call; anything that slips through and gets Firebase's `invalid-email` back is **swallowed → false success today** | Client-side block preferred (already mostly works); anything reaching Firebase and getting `invalid-email` must show "Please enter a valid email address." — never success |
| Nonexistent/unregistered email | Depends on this Firebase project's Authentication → Settings → **Email Enumeration Protection** toggle (not visible in this repo — must be checked in Firebase Console). If enabled (Firebase's modern default), `sendPasswordResetEmail` genuinely succeeds for a nonexistent account **by design**, for privacy — today's apparent "false success" for this specific case may actually be correct, intentional platform behavior, not a bug. If disabled (legacy), Firebase throws `user-not-found`, currently mapped by `friendlyError` to the login-specific "Email or password is incorrect." (wrong copy for a screen with no password field), currently masked by the same swallow bug | Must not reveal account existence either way — treat `user-not-found` as a **success-equivalent** (generic "Check your inbox" copy), not as a generic error. This is a required carve-out in the fix, not just "let every FirebaseAuthException show an error." |
| Network failure | `network-request-failed` swallowed → **false success today** | "No internet connection. Please check your network." (mapping already exists in `friendlyError`, just needs to actually surface) — no success, retry enabled |
| Rate limit (`too-many-requests`) | **The audit's literal headline scenario** — swallowed → false success | "Too many attempts. Please try again later." — no success |
| Rapid/duplicate submissions | Button is disabled while `_loading=true` (blocks double-tap-on-button, already correct); **gap**: the email field's `onFieldSubmitted` is not gated by `_loading`, so repeated Enter-key submits mid-request are not blocked the same way | Add an `if (_loading) return;` guard as the first line of `_submit()` — small, independent, worth bundling into the same fix |

### 6.3 Proposed fix

Two options, evaluated against the existing convention in `login_screen.dart`/`register_screen.dart` (both of which already use a `Future<bool>`-returning notifier method + read `.error` on failure — `sendPasswordReset` is the one outlier with a `void` return and no status signal):

- **Option (a) — rethrow in the notifier.** Smallest textual diff, but introduces a **new regression**: the screen's existing `catch (e)` sets `_error = e.toString()`, which would then render the **raw** Firebase exception string, bypassing the friendly translation the notifier just computed — reintroducing exactly the "raw exception text shown to users" pattern flagged elsewhere in the source audit (P1-7/P2-11). Not recommended as-is.
- **Option (b), recommended — change `sendPasswordReset` to return `Future<bool>`, matching `signIn`/`signUp`'s existing convention exactly**, and have the screen check the return value + read `ref.read(authNotifierProvider).error` on failure instead of relying on "did the await throw." This also gives a single, natural place to implement the `user-not-found` privacy carve-out (treat as success in the notifier itself, so the screen never has to special-case it). The screen's outer `try/catch` remains as-is, as the safety net for any non-`FirebaseAuthException` type that still propagates uncaught (e.g. a stray `PlatformException`).

**Testability prerequisite (small, recommended to bundle into this fix):** `AuthService` has eager field initializers (`final FirebaseAuth _auth = FirebaseAuth.instance;`) that make it impossible to subclass/fake for a pure unit test without triggering a real Firebase call. Extracting a minimal `IAuthService` interface (just the methods `AuthNotifier` actually calls) and having `AuthNotifier` depend on the interface rather than the concrete class costs one interface + one constructor signature change, and is what makes the regression test below possible without adding a mocking package or emulator dependency this repo doesn't currently have.

### 6.4 Regression tests
Proposed new file **`test/auth_provider_password_reset_test.dart`**, a pure-Dart unit test (matching this repo's existing convention of testing extracted logic directly rather than via widget/emulator tests) using a `_FakeAuthService implements IAuthService`:
1. Genuine success → `sendPasswordReset` returns `true`, `state.error` stays `null`.
2. `FirebaseAuthException(code: 'too-many-requests')` injected → returns `false`, `state.error` == the friendly rate-limit message. **This is the exact case that reproduces P0-5** — it fails today (would assert `false` but the current code has no return value to assert against at all, i.e. this test cannot even be written against the current `void`-returning signature, which is itself confirmation of the gap).
3. `FirebaseAuthException(code: 'network-request-failed')` injected → returns `false` with the network-specific message.
4. `FirebaseAuthException(code: 'user-not-found')` injected → returns `true` with `error` staying `null` (the privacy carve-out).

---

## 7. Security Regression Test Plan

**Infrastructure gap that must be addressed first:** this project has zero Firestore Rules test coverage today — confirmed by two independent checks in this session: no `@firebase/rules-unit-testing` dependency in `functions/package.json` (the only `package.json` in the repo), no `*.rules.test.*` files, no `emulators` block in `firebase.json`. **Implementing the rules changes in §4 without also adding this test infrastructure means shipping a security fix with zero automated proof it actually closes the gaps, and zero regression protection against the fix being silently reverted or weakened later.** This is a required, not optional, part of the remediation — recommended as a new dev-dependency (`@firebase/rules-unit-testing`, Node-side) plus a minimal `firestore` entry in `firebase.json`'s `emulators` block (Firestore emulator only — this does not require the Blaze plan, does not deploy anything, and does not touch production data; it runs entirely locally).

### 7.1 Negative tests — prove a malicious client CANNOT do each of the following (all run against the Firestore emulator, loaded with the fixed rules)

1. **Fabricate a payment** — attempt `payments.add({payerId: self, jobId: <job>, amount: 100000, status: 'escrowHeld'})` as a signed-in user who is NOT that job's customer → expect `PERMISSION_DENIED` (closed by §4.3, `create: if false` for all callers).
2. **Manipulate payment amount** — same as above but as the job's actual customer → expect `PERMISSION_DENIED` (§4.3 blocks ALL client creates, not just non-owners — the whole document is server-only now).
3. **Manipulate payment status** — attempt `payments.doc(<id>).update({status: 'escrowHeld'})` on an existing `pending` payment as its own payer → expect `PERMISSION_DENIED` (already-correct `allow update: if isAdmin()`, unchanged; test exists to lock in current-correct behavior, not just the new changes).
4. **Manipulate escrow status directly** — attempt `jobs.doc(<id>).update({status: 'escrowLocked', paymentReference: 'fake'})` as the job's own customer, with the job genuinely at `paymentPending` → expect `PERMISSION_DENIED` (closed by §4.2).
5. **Release escrow without legitimate payment** — attempt `escrow_releases.doc(<jobId>).set({jobId, status: 'pending', ...})` as the job's own customer, with the job's actual `status` at `inChat` (not `submitted`) → expect `PERMISSION_DENIED` (closed by §4.1's new `job.status == 'submitted'` clause). Repeat with job status at every other non-`submitted` value (`requested`, `matched`, `paymentPending`, `escrowLocked`, `inProgress`) to cover the full state space, not just one example.
6. **Duplicate an escrow release** — as the job's customer, with job genuinely `status == 'submitted'`: (a) create `escrow_releases.doc(<jobId>)` successfully once (should succeed — this is the legitimate path), (b) attempt to create a second document for the same job under a **different**, auto-generated ID → expect `PERMISSION_DENIED` (proves the deletion of the duplicate block in §4.1 actually closes the amplification path found during this investigation, not just the single-fabrication path).
7. **Modify an existing escrow release** — attempt `escrow_releases.doc(<jobId>).update({status: 'completed'})` or `.delete()` as any non-admin caller → expect `PERMISSION_DENIED` (already-correct, unchanged; regression-lock it).
8. **Modify another user's payment** — attempt to `update`/read a `payments` document where the caller is neither `payerId` nor `artisanId` nor admin → expect `PERMISSION_DENIED` (already-correct read rule, unchanged; regression-lock it).
9. **Bypass ownership on `agreedAmount`** — attempt to set `agreedAmount` on a job where the caller is neither `customerId` nor `artisanId` → expect `PERMISSION_DENIED` (already-correct, unchanged; regression-lock it).
10. **Bypass ownership to set an unbounded/invalid `agreedAmount`** — as a legitimate party to the job (customer or artisan), attempt `agreedAmount: -500`, `agreedAmount: 0`, and `agreedAmount: "not a number"` → expect `PERMISSION_DENIED` for all three (closed by §4.4).
11. **Bypass role restrictions** — as a non-admin user, attempt to write directly to `admins/{ownUid}` to self-grant admin → expect `PERMISSION_DENIED` (already-correct — `write: if false` — regression-lock it, since this is the trust anchor the entire `isAdmin()` helper depends on).
12. **Trigger a payout after a self-fabricated `escrow_releases` doc, end-to-end** — combine tests 4 and 5's blocked writes into the full documented exploit chain from §2.4 (job → `inChat` → set arbitrary `agreedAmount` → attempt `escrow_releases` create) and confirm the chain is broken at the earliest possible point (step 5, since `job.status` is `inChat` not `submitted`) — this is the single test that most directly proves the fix, and should be written first.

### 7.2 Positive/legitimate flow tests — prove the real flows still work after the fix

13. Full happy path via emulated Cloud Functions (or, if wiring the emulator to actually invoke `processEscrowRelease` is out of scope for this pass, at minimum via direct Firestore emulator writes performed *as if* by the Admin SDK, i.e. with rules bypassed, matching what the real function does): job created → matched → inChat → agreement confirmed by both parties → `paymentPending` → `_lockEscrow`-equivalent write → `escrowLocked` → `inProgress` → `submitted` → `JobService.confirmComplete`-equivalent write creates `escrow_releases/{jobId}` with `status: 'pending'` → succeeds.
14. Customer manually confirms completion while `submitted` (the legitimate client-write path §4.1 preserves) → `escrow_releases.doc(jobId).set({jobId, status:'pending', ...})` as that job's customer → **succeeds** (this is the critical "did we accidentally also break the real feature" check — must pass, not just the negative tests).
15. `agreedAmount` negotiation with a valid positive number, by either party, while `inChat` and not yet confirmed → succeeds.
16. Auto-release cron path (`_releaseEscrow`) — since this runs entirely under the Admin SDK, it is unaffected by any rules change; a Cloud-Functions-level test (Node, using `firebase-functions-test` or a direct unit test of the transaction logic) should confirm it still behaves as documented in §3.5 (unchanged, already correct) — include as a regression-lock even though this remediation doesn't touch this function's logic itself.

### 7.3 P0-2 and P0-3 regression tests
Already specified in full in §5.7 and §6.4 above — `test/portfolio_project_route_test.dart` (3 cases) and `test/auth_provider_password_reset_test.dart` (4 cases), both pure Dart/`flutter_test`, no emulator required.

---

## 8. Deployment Sequence

**Do not skip or reorder steps. Do not enable live Paystack credentials before step 9 passes.**

1. **Remediate P0s** — implement the Firestore rules changes (§4), the `processEscrowRelease` hardening (§3.4/§4.6), the P0-2 router fix (§5.6), and the P0-3 auth-provider fix (§6.3), per the files listed in §10.
2. **Run automated tests** — `flutter analyze`, `flutter test` (must still show the full existing 85-test suite passing, plus the two new Dart test files from §5.7/§6.4).
3. **Run Firestore Rules tests** — the new emulator-based suite from §7.1/§7.2, run locally against the Firestore emulator (`firebase emulators:exec` or equivalent) — no production project touched, no Blaze plan required.
4. **Run Flutter Web regression tests** — `flutter build web` must still succeed; manually re-verify (or re-run, if the harness/session used for the original audit is still available) the live pre-auth browser testing already captured in `design/qa_audit_working_files/07_live_auth_testing.md`, since the auth-provider changes in §6 touch code on the critical path of every auth screen, not just forgot-password.
5. **Verify audit accounts** — the two disposable test accounts from the original audit (customer `dannyrotimi11+htaudit1@gmail.com`, artisan `dannyrotimi11+htaudit2@gmail.com`) should be email-verified by this point (pending user action noted in the source audit); if not yet verified, verify them now, since step 6 depends on authenticated access.
6. **Run authenticated live testing** — the full customer/artisan workflow live-testing pass the original audit could not complete (job posting → quote → agreement → the *fixed* payment/escrow flow → completion → review), still against the Spark-plan project with Cloud Functions undeployed, to confirm the pre-payment/negotiation/state-machine UI still works end-to-end with the tightened rules in place (this catches any legitimate flow the rules changes might have inadvertently broken, before any real infrastructure risk is introduced).
7. **Deploy Cloud Functions to the appropriate environment** — this requires the Firebase project to be upgraded to the Blaze plan (a separate, non-code prerequisite, out of scope for this document) — deploy to a **staging/test project first if one exists or can be created**, not directly to `handytrust` production, if at all avoidable. If no staging project is feasible, deploy to `handytrust` but with Paystack **test-mode** secrets only (step 8) — never live secrets at this stage.
8. **Test Paystack test-mode transactions** — using Paystack's official test card numbers/test bank accounts, run a real (test-mode) payment through the full flow: initialize → charge → webhook → escrow lock → work submission → manual and auto-release paths → payout — confirming `processEscrowRelease` fires a real (test-mode) transfer only when a genuine, server-recorded payment exists, and confirming every negative test from §7.1 that could be exercised via the live app UI (not just direct SDK calls) also fails cleanly when attempted through the actual app.
9. **Run payment/escrow regression** — re-run the full §7 test suite (rules + Cloud Functions) against this now-deployed-to-test-mode environment, not just the local emulator, to catch any environment-specific drift (secrets, region config, IAM permissions) the emulator can't surface.
10. **Perform final security audit** — a follow-up pass (ideally by a second reviewer, or Claude with a fresh context, per this project's own established pattern of independent re-verification) specifically re-attempting the exploit chain in §2.4 and the amplification in §2.1 against the test-mode-deployed environment, to confirm the fix holds under real (test-mode) infrastructure, not just rules-emulator theory.
11. **Only then consider production/live Paystack credentials** — and only after explicit, separate sign-off, since this document's scope ends at "safe to test with test-mode Paystack," not "safe for real money" — that determination should be made only after step 10 passes cleanly with no findings.

---

## 9. Risk Assessment

| Finding | Severity | Exploitability | Current exposure | Production impact | Fix priority | Regression requirement |
|---|---|---|---|---|---|---|
| P0-1 (all sub-findings, §2.1-2.4) | **Critical** | High — requires only two accounts (one customer, one verified artisan, real or colluding) and standard Firestore SDK calls; no special tooling or timing window needed | **Live today at the rules layer** (rules are deployed independent of Cloud Functions), but **inert** — no Cloud Function currently consumes the fabricated documents, so no real transfer fires yet | Direct, unbounded real-money loss the moment `processEscrowRelease` is deployed with live Paystack keys, with no additional attacker action needed at that point | **P0 — fix before any Cloud Functions deployment, not just before going live** | §7.1 tests 1-2, 4-6, 12 must all pass; §7.2 tests 13-14 must also pass (prove nothing legitimate broke) |
| P0-2 (`/portfolio-project` crash) | **Critical** (per source audit's severity, on reliability/crash grounds — not a security/financial issue) | Trivial — any signed-in, verified user, one browser refresh | Live today on Flutter Web for any user who refreshes on this route | Reputational/support-burden risk, not financial; a hard crash is a poor first impression and generates support tickets | **P0 — fix before beta/wider testing** | §7.3 (`test/portfolio_project_route_test.dart`) |
| P0-3 (forgot-password false success) | **Critical** (per source audit's severity, on user-trust/support-burden grounds) | Trivial to moderate — fires on any real Firebase-side rejection (rate-limit is the easiest to trigger, just by retrying) | Live today; the success-trigger mechanism was live-confirmed in the original audit | Users silently never receive a password reset they were told was sent, with no recovery path visible to them — real support burden and trust erosion, not financial | **P0 — fix before beta/wider testing** | §7.3 (`test/auth_provider_password_reset_test.dart`) |
| Refund/cancellation gap (§2.5, discovered this pass) | **High** (business-critical, not itself a security exploit) | N/A — not an attack, a missing feature; triggers on any legitimate cancellation-after-payment or customer-favorable dispute resolution | Live today — any real cancelled-after-payment job leaves customer money uncredited with zero automated recovery path | Direct customer-trust and possibly regulatory/consumer-protection exposure (money taken, not returned, no process to get it back) once real payments exist | **Must be designed before real-money go-live — not a P0 rules patch, see §11** | New feature, new tests — out of scope for this remediation's regression suite, tracked separately |
| `payments.amount` never cross-checked against `agreedAmount` (refinement, §4.6) | Medium | Requires a genuine (non-fabricated) payment at an amount the customer chooses independent of what was negotiated | Live today | Customer-vs-artisan payment disputes (underpayment), not a platform-security issue once §4.3 makes `payments` server-only | Recommended follow-up, not blocking this P0 remediation | Not included in §7's regression suite — track separately if prioritized |
| `initializePaystackTransaction` no idempotency guard (source audit P1-5) | Medium | Requires two concurrent payment sessions for the same job | Live today | Customer double-charged with no auto-refund (compounds the refund gap above) | Recommended to bundle into the same remediation pass given the overlap with §2.5, but not strictly a P0 | Not included in §7's regression suite as specified — recommend adding if bundled |

---

## 10. Files To Modify

| File | Why | Type of change | Security-critical? |
|---|---|---|---|
| `firestore.rules` | §4.1-4.4 — the core of the P0-1 fix | Delete one `match` block; modify 3 existing rule conditions (add clauses, remove one clause) | **Yes — highest priority in this entire remediation** |
| `functions/index.js` | §3.4/§4.6 — `processEscrowRelease` hardening (job-status check, remove `agreedAmount` fallback) | Modify one function (~10-15 line change within `processEscrowRelease`, lines 395-524) | **Yes — defense-in-depth for P0-1, should ship in the same change as the rules fix** |
| `lib/routes/router.dart` | §5.6 — P0-2 fix (null-safe guard on `/portfolio-project`) | Modify one `GoRoute` builder (lines 383-392) | No (crash/reliability, not security) |
| *(new)* small fallback widget (e.g. `lib/widgets/cannot_open_directly.dart` or inline in `router.dart`) | §5.6 — the "can't be opened directly" UI the P0-2 fix renders | New file (small, ~20-30 lines) | No |
| `lib/providers/auth_provider.dart` | §6.3 — P0-3 fix (`sendPasswordReset` returns `Future<bool>`, `user-not-found` privacy carve-out) | Modify one method signature + body (lines 94-102) | **Yes-adjacent — auth flow correctness, not a data-security boundary, but user-trust-critical** |
| `lib/screens/auth/forgot_password_screen.dart` | §6.3 — P0-3 fix (check returned bool + read `.error` instead of relying on "await didn't throw") | Modify `_submit()` (lines 29-46); optionally add the `_loading` guard on `onFieldSubmitted` noted in §6.2 | No |
| `lib/core/services/auth_service.dart` | §6.3 — testability prerequisite: extract `IAuthService` interface | New interface + `implements` clause; no behavioral change to existing methods | No (enables testing, doesn't change runtime behavior) |
| *(new)* `test/portfolio_project_route_test.dart` | §5.7 | New file | No |
| *(new)* `test/auth_provider_password_reset_test.dart` | §6.4 | New file | No |
| *(new)* Firestore Rules emulator test suite (e.g. `firestore-tests/escrow_payout.test.js` or similar, exact location per whatever Node test runner is chosen) | §7.1/§7.2 | New file(s) + new dev-dependency (`@firebase/rules-unit-testing`) + `firebase.json` `emulators` block addition | **Yes — this is the proof the P0-1 fix actually works, treat as part of the fix, not optional tooling** |
| `firebase.json` | Add a minimal `emulators` block (Firestore only) to support the new rules test suite | Small addition, does not affect existing `firestore`/`storage`/`functions`/`hosting` config | No (local dev/test tooling only, no production behavior change) |
| `lib/core/services/payment_service.dart` | Recommended to action alongside §4.3 (source audit's P2-2: delete or properly gate `simulatePayment`, since §4.3 will break its Firestore write regardless) | Delete the method, or gate it consistently with `DemoEscrowScreen`'s pattern | No longer security-critical once §4.3 ships (the rules already stop it), but leaving it silently broken is poor hygiene |

---

## 11. Do-Not-Change List

Per the instruction to prevent unnecessary changes, the following are **explicitly out of scope** for this remediation unless a future investigation proves otherwise:

- **`JobService`'s Dart-side state machine (`allowedTransitions`, `canConfirmAgreement`, `canRespondToAgreement`, `canInitPayment`) and its transactional write methods** (`lib/core/services/job_service.dart`) — verified correct and well-designed throughout this investigation (atomic audit-log writes, correct idempotency in `confirmComplete`, correct `updateVersion` optimistic-concurrency handling). This layer is a convenience/audit-trail layer, not the security boundary, but its logic itself is sound and should not be touched.
- **`_lockEscrow`, `_releaseEscrow`, and the Paystack webhook handler's transaction logic** (`functions/index.js:127-272`) — independently re-verified as correctly transactional with proper idempotency guards. Not part of the vulnerability.
- **`processEscrowRelease`'s idempotency claim mechanism** (`functions/index.js:408-417`, the atomic `pending → processing` flip) — correct, do not touch; only the job-status check and amount-resolution fallback (§3.4/§4.6) need to change within this function.
- **`quotes` subcollection rules** (`firestore.rules:294-338`) — already correctly scoped (amount type/positivity checked on create, post-acceptance edits locked down); the broader sweep in this investigation found no exploitable gap here. Do not modify.
- **`admins/{uid}` rule** (`firestore.rules:524-527`, `write: if false`) — already correct and is the trust anchor `isAdmin()` depends on everywhere else. Do not modify.
- **`EscrowService` (`lib/core/services/escrow_service.dart`) and `PaymentService.simulatePayment`** — both already flagged as dead/demo code in the source audit (P2-1, P2-2). This remediation's scope is fixing the *live* attack surface (which does not run through either of these classes today); their cleanup/deletion is a legitimate follow-up (and §4.3 will incidentally break `simulatePayment`'s Firestore write, per §10's note) but rewriting or "fixing" them is not required to close P0-1.
- **Cloud Functions region configuration, secret values, Blaze-plan billing status** — explicitly out of scope per the task's constraints (do not deploy, do not enable Cloud Functions, do not introduce live Paystack credentials). These are prerequisites for later deployment-sequence steps (§8), not part of this remediation's code changes.
- **The Dart-side `PaymentModel`/`JobModel` schemas themselves** — no field additions/removals are required by any fix in this plan; all changes are to rules, one Cloud Function's internal logic, and Dart control-flow (not data shape).
- **Refund/cancellation-after-payment architecture** (§2.5) — deliberately **not** designed or patched in this document. This is flagged as needing a genuine architecture/product decision (does refund happen automatically via a Paystack refund API call on cancellation? Does it require admin approval? Is there a partial-refund/dispute-split concept?) rather than a quick patch, and bundling it into the P0 rules fix would risk exactly the "broad rewrite" the task explicitly asked to avoid. Recommend a separate, dedicated design pass before real money is accepted in production (see §12's final checklist item).

---

## 12. Final Implementation Checklist

*(For the follow-up implementation phase — after this plan is reviewed and explicitly approved. Nothing below has been done yet.)*

**P0-1 (Firestore rules + Cloud Function):**
- [ ] Delete the duplicate `escrow_releases` block (`firestore.rules:513-521`)
- [ ] Add `getJob(...).status == 'submitted'` to the remaining `escrow_releases` create rule; change its `read` from `if false` to `if isAdmin()` (§4.1)
- [ ] Remove `isCust` from the `paymentPending → escrowLocked` transition (`firestore.rules:395`) (§4.2)
- [ ] Change `payments` create rule to `if false` (`firestore.rules:415-417`) (§4.3)
- [ ] Add type/positivity check to the `agreedAmount` negotiation rule (`firestore.rules:142-148`) (§4.4)
- [ ] Add `job.status` check to `processEscrowRelease` (`functions/index.js:420-430`) (§3.4)
- [ ] Remove the `job.agreedAmount` fallback in `processEscrowRelease`'s amount resolution; require a real `payments` doc with `status == 'escrowHeld'` (`functions/index.js:435-440`) (§3.4)
- [ ] Set up Firestore Rules emulator test infrastructure (`@firebase/rules-unit-testing`, `firebase.json` `emulators` block)
- [ ] Write and pass all 16 tests in §7.1/§7.2
- [ ] Delete or properly gate `PaymentService.simulatePayment` (source audit P2-2, incidentally broken by 4.3)

**P0-2 (Flutter Web crash):**
- [ ] Implement the null-safe guard + fallback widget for `/portfolio-project` (`lib/routes/router.dart:383-392`) (§5.6)
- [ ] Write and pass the 3 tests in `test/portfolio_project_route_test.dart` (§5.7)

**P0-3 (forgot-password):**
- [ ] Extract `IAuthService` interface from `AuthService` (§6.3 testability prerequisite)
- [ ] Change `AuthNotifier.sendPasswordReset` to return `Future<bool>`, with the `user-not-found` privacy carve-out (§6.3)
- [ ] Update `ForgotPasswordScreen._submit()` to check the returned bool + read `.error` (§6.3)
- [ ] (Recommended, small) add the `_loading` guard to the email field's `onFieldSubmitted` (§6.2 scenario f)
- [ ] Write and pass the 4 tests in `test/auth_provider_password_reset_test.dart` (§6.4)
- [ ] Manually verify (in Firebase Console → Authentication → Settings) whether Email Enumeration Protection is enabled for this project, since it determines whether the `user-not-found` code path is even reachable in practice (§6.2, scenario c)

**Before moving past this analysis phase:**
- [ ] This document (`design/P0_REMEDIATION_PLAN.md`) reviewed and explicitly approved by the user
- [ ] Refund/cancellation-after-payment architecture (§2.5/§11) scoped as a separate, dedicated design task — not bundled into P0-1's implementation
- [ ] `flutter analyze` / `flutter test` / `flutter build web` all still pass after implementation, per §8 step 2
- [ ] Deployment sequence in §8 followed in order — no step skipped, no live Paystack credentials introduced before step 9 passes

---

## 13. Implementation Results (2026-08-17)

Everything in this section describes what was actually done, re-verified against the real diff — not a restatement of the plan above. Sections 1-12 are the pre-implementation analysis and are left as originally written.

### 13.1 P0-1 — exact root cause → exact fix, as implemented

**Root cause (confirmed unchanged from §2, plus the §2.4 refinement):** `firestore.rules` trusted client-asserted state at multiple points in the payment/escrow pipeline, and `processEscrowRelease` (`functions/index.js`) never independently re-verified any of it — it would derive a payout amount from a customer-writable `job.agreedAmount` field if no `payments` record existed, with no check that the job had ever actually been paid for.

**Fix, as implemented — `firestore.rules`:**
1. Deleted the duplicate `escrow_releases` match block (`jobExists(...) && customerId==auth.uid`, no `releaseId==jobId` pin, no status check) — this was the block that allowed non-canonical, repeatable release documents.
2. The remaining `escrow_releases` block now additionally requires `getJob(request.resource.data.jobId).status == 'submitted'` on create, and its `read` rule changed from `if false` to `if isAdmin()` (folding in the deleted block's admin-read capability).
3. `jobs`' `_isValidJobTransition`: the `paymentPending → escrowLocked` branch no longer grants `isCust` — only `isAdmin()` (i.e., only Admin-SDK/Cloud-Function writes, which bypass rules regardless — this line's only practical effect is removing the client's ability to self-assert this transition).
4. `payments`' create rule changed from a loosely-validated client-writable rule to `allow create: if false` — the entire document is now server-only, matching how the real flow (`initializePaystackTransaction`) already worked.
5. The `agreedAmount` negotiation update rule gained `request.resource.data.agreedAmount is number && request.resource.data.agreedAmount > 0` (defense-in-depth; the primary fix is items 1-4 removing the paths that would have exploited an unbounded amount at all).

**Fix, as implemented — `functions/index.js`:**
1. `processEscrowRelease` now verifies, in order, before ever calling Paystack: the release document's own ID matches its `jobId` field (defense-in-depth mirror of the rules' `releaseId==jobId` pin); the job exists; the job has an `artisanId`; **the job's status is `submitted` or `completed`** (`_isJobPayable`, new pure exported helper) — fails closed with `failureReason: 'job_not_in_payable_state'` otherwise; **a `payments` document exists with `jobId` matching AND `status == 'escrowHeld'`** — fails closed with `failureReason: 'no_verified_payment_on_record'` if not (**the `job.agreedAmount` fallback has been removed entirely — this was the core of the exploit and it no longer exists in any form**); the payment's `amount` is a positive number; and the payment's `amount` matches `job.agreedAmount` within floating-point tolerance (`_amountsMatch`, new pure exported helper) — fails closed with `failureReason: 'payment_amount_mismatch'` otherwise.
2. `initializePaystackTransaction` no longer trusts the client-supplied `amount`/`artisanId` at all. It now reads the job document server-side, requires `request.auth.uid == job.customerId`, requires `job.status == 'paymentPending'`, and derives the charged amount **exclusively** from `job.agreedAmount` — the client's `amount` field is not read at all (the callable still accepts `jobId`/`email` from the client; `amount`/`artisanId` are no longer part of its trusted input surface). All new validation failures throw `HttpsError` (not plain `Error`) with specific codes (`unauthenticated`/`invalid-argument`/`not-found`/`permission-denied`/`failed-precondition`) so the client receives an actionable, non-generic message — this was not required by the P0 scope (source audit P1-3) but was adopted for internal consistency within the function being rewritten, not applied elsewhere in the file.

**Companion fix — `lib/screens/payment/payment_screen.dart`:** the payment-amount `TextField` (previously editable, pre-filled from `job.agreedAmount`) is now `readOnly: true` with explanatory helper text. Once the server stops trusting a client-supplied amount, leaving the field editable would silently discard whatever the customer typed — itself a misleading-UI bug this fix would otherwise have introduced.

**Dead-code removal (source audit P2-2, executed as part of this fix since it's a direct casualty of the `payments` create-rule change):** `lib/core/services/payment_service.dart` (`PaymentService.simulatePayment`, the ungated fake-payment path that wrote directly to `payments` with `status: 'escrowHeld'`) has been **deleted**, along with the two dead Riverpod providers that only ever wrapped it (`simulatePaymentProvider`, `paymentServiceProvider`/`paymentNotifierProvider`) in `lib/providers/payment_provider.dart`. `customerPaymentsProvider`/`artisanPaymentsProvider` (used by the Wallet screen) were preserved unchanged. Confirmed via grep before deletion that nothing else referenced any of the removed symbols.

### 13.2 P0-2 — exact root cause → exact fix, as implemented

**Root cause (confirmed, unchanged from §5):** `lib/routes/router.dart`'s `/portfolio-project` route builder performed a non-nullable `extra['artisanId'] as String` cast with no fallback — the sole such unguarded cast among every `extra`-reading route in the file.

**Fix, as implemented:** the route builder now reads `artisanId` as `String?`; if null (true on any direct/refreshed/bookmarked navigation), it renders a new `CannotOpenDirectlyScreen` (`lib/widgets/cannot_open_directly_screen.dart`) instead of constructing `PortfolioProjectScreen` — a small, reusable widget showing "This page can't be opened directly" with a button back to `/portfolio`. Both real call sites (`portfolio_manager_screen.dart`, create and edit) are unaffected, since they always supply `artisanId`.

### 13.3 P0-3 — exact root cause → exact fix, as implemented

**Root cause (confirmed, unchanged from §6):** `AuthNotifier.sendPasswordReset` caught `FirebaseAuthException` and stored it in its own state without rethrowing; the calling screen's sole success signal was "did the await throw," which was never true for a caught exception.

**Fix, as implemented:**
1. `lib/core/services/auth_service.dart`: extracted an `IAuthService` interface (`currentUser`, `createAccount`, `signIn`, `sendEmailVerification`, `sendPasswordReset`, `signOut` — exactly the methods `AuthNotifier` calls) that `AuthService` now `implements`. This exists solely to make `AuthNotifier` unit-testable with a fake, since `AuthService` has eager `FirebaseAuth.instance`/`FirebaseFirestore.instance` field initializers that make it otherwise impossible to construct in a plain Dart test.
2. `lib/providers/auth_provider.dart`: `AuthNotifier._authService` is now typed `IAuthService` (the concrete `AuthService` still flows through `authServiceProvider` unchanged — no other provider needed to change). `sendPasswordReset` now returns `Future<bool>`, matching `signIn`/`signUp`'s existing convention: returns `true` on genuine success, `false` with a friendly `state.error` on any real `FirebaseAuthException` — **except** `user-not-found`, which is treated as success (matching Firebase Auth's own privacy-preserving intent for password reset: never reveal whether an account exists). A non-`FirebaseAuthException` also now returns `false` with a generic friendly message rather than propagating uncaught.
3. `lib/screens/auth/forgot_password_screen.dart`: `_submit()` now checks the returned bool and only sets `_sent = true` on genuine success; on failure it reads `ref.read(authNotifierProvider).error` instead of showing raw exception text. Added `if (_loading) return;` as the first line of `_submit()`, closing the gap where the email field's `onFieldSubmitted` (Enter key) wasn't gated by the same loading check the button already had.

### 13.4 Files modified

| File | Change |
|---|---|
| `firestore.rules` | P0-1 — 4 rule changes (§13.1) |
| `functions/index.js` | P0-1 — `processEscrowRelease` hardening, `initializePaystackTransaction` rewrite, `HttpsError` import, 2 new exported pure helpers (`_isJobPayable`, `_amountsMatch`) |
| `functions/package.json` | Added `test` script (`node --test test/`) |
| `functions/test/escrow_release_guards.test.js` | **New.** Unit tests for the 2 new pure helpers |
| `firebase.json` | Added `emulators.firestore` (port 8090) + `emulators.ui.enabled: false` block |
| `firestore-tests/package.json` | **New.** Dev-only `@firebase/rules-unit-testing` dependency |
| `firestore-tests/escrow_payout.test.js` | **New.** 26-case Firestore Rules emulator test suite (§13.5) |
| `lib/routes/router.dart` | P0-2 — null-safe guard on `/portfolio-project` |
| `lib/widgets/cannot_open_directly_screen.dart` | **New.** P0-2 fallback widget |
| `lib/core/services/auth_service.dart` | P0-3 — `IAuthService` interface extraction |
| `lib/providers/auth_provider.dart` | P0-3 — `sendPasswordReset` returns `Future<bool>` |
| `lib/screens/auth/forgot_password_screen.dart` | P0-3 — checks returned bool, `_loading` guard on Enter-submit |
| `lib/screens/payment/payment_screen.dart` | P0-1 companion — amount field made read-only |
| `lib/core/services/payment_service.dart` | **Deleted.** Dead, ungated fake-payment path (source audit P2-2) |
| `lib/providers/payment_provider.dart` | Removed the 3 dead providers that only wrapped the deleted service; `customerPaymentsProvider`/`artisanPaymentsProvider` unchanged |
| `test/portfolio_project_route_test.dart` | **New.** 3-case P0-2 regression test |
| `test/auth_provider_password_reset_test.dart` | **New.** 6-case P0-3 regression test |

**Not modified**, matching §11's Do-Not-Change list exactly: `lib/core/services/job_service.dart`, `_lockEscrow`/`_releaseEscrow`/the webhook handler, `processEscrowRelease`'s idempotency claim transaction, the `quotes` subcollection rules, the `admins/{uid}` rule, `verifyPayment` (its existing `metadata.jobId` cross-check was already correct), any refund/cancellation logic, any Cloud Functions deployment/region/secret configuration.

### 13.5 Tests added and executed — full results

**Firestore Rules emulator suite** (`firestore-tests/escrow_payout.test.js`, new infrastructure — none existed before this task): run via `firebase emulators:exec --only firestore --project handytrust-rules-test "cd firestore-tests && npm test"` against the local emulator on port 8090.
**Result: 26/26 passed, 0 failed.** Covers every negative case from §7.1 (fabricate/manipulate a payment, force `escrowLocked`, release from every non-`submitted` status individually, duplicate a release under a different ID, modify/delete an existing release, mismatched release/job ID, unbounded/invalid `agreedAmount`, self-grant admin) plus the exact documented exploit chain (§2.4) end-to-end, two exploit variants (forged payment, incorrect job ID), a concurrent-release-attempt test, and every positive/legitimate-flow case from §7.2 (full happy path through every job state, the legitimate manual-release path, valid negotiation, admin read access).

**Cloud Functions unit tests** (`functions/test/escrow_release_guards.test.js`, new): run via `node --test functions/test/escrow_release_guards.test.js`. **Result: 19/19 passed, 0 failed.** Directly exercises the two new pure guard functions (`_isJobPayable`, `_amountsMatch`) extracted from `processEscrowRelease` — every job status in the state machine individually confirmed payable/non-payable, and 5 amount-comparison boundary cases. This verifies the exact fail-closed logic actually shipped in `processEscrowRelease`, not a reimplementation of it.

**Flutter/Dart test suite** (`flutter test`): **Result: 94/94 passed** (the pre-existing 85 + 3 new P0-2 tests + 6 new P0-3 tests). No regressions in any pre-existing test (job state machine, artisan eligibility/beta-tester, admin audit log, admin navigation).

**`flutter analyze`**: 12 issues, 0 errors — identical set to the pre-implementation baseline (1 unused-import warning, 11 informational lints), confirmed no new issues introduced by this change.

**`flutter build web`**: succeeded, output in `build/web`. Only pre-existing WASM-compatibility informational warnings (unrelated `flutter_secure_storage_web` package, not touched by this change).

**Live browser verification** (Playwright, against the newly rebuilt `build/web`, served locally — same method as the source audit's live-testing pass):
- **P0-3 (forgot-password) happy path: CONFIRMED LIVE.** Submitted a real password-reset request for the existing disposable test account; the app correctly showed "Check your inbox," zero page errors captured.
- **P0-3 failure-path (rate-limit false-success): NOT independently re-forced live**, same reasoning as the source audit — would require ~15-20 rapid requests against Firebase Auth's real rate limiter, deliberately not attempted to avoid abuse-flagging the real project. Verified instead via the 6 new unit tests, which directly assert the exact `too-many-requests`/`network-request-failed`/`user-not-found` code paths against the actual `AuthNotifier` code (not a reimplementation).
- **P0-2 (`/portfolio-project` crash): NOT live-browser-verified.** Both disposable test accounts from the source audit (customer and artisan) remain email-unverified at the time of this implementation — the same blocker the source audit reported, still unresolved. Reaching `/portfolio-project` requires an authenticated session (the router redirects unauthenticated users to `/login` before the route builder ever runs), so this could not be exercised in a real browser this session. **Verified instead via `test/portfolio_project_route_test.dart`**, which constructs an isolated `GoRouter` using the exact fixed builder code and confirms `tester.takeException()` is `null` (this assertion fails against the pre-fix code, reproducing the crash) plus correct create/edit-mode rendering — this is a permanent, repeatable regression guard, arguably stronger evidence than a one-time manual click, but it is CODE-LEVEL/AUTOMATED-TEST-CONFIRMED, not CONFIRMED LIVE in a real browser. A live-browser re-verification of this specific fix is recommended once account verification is complete, as a cheap final confirmation before this is considered fully closed.

### 13.6 Answering the required security-standard questions

> "If I were a malicious authenticated customer with direct access to the client and Firestore SDK, could I cause a real Paystack transfer without making a legitimate payment?"

**No** — confirmed by the emulator test suite's exact reproduction of the documented exploit chain (test 12 and its two variants), which fails closed at the `escrow_releases` create step (job not `submitted`) in every attempted variant, and by `processEscrowRelease`'s independent server-side re-verification (job-status check + no-`agreedAmount`-fallback + amount cross-check), which would additionally block any theoretical path that somehow got past the rules. This holds specifically against the Firestore SDK / rules layer, which was the actual vulnerability; it does not constitute a full production penetration test against a live Blaze-plan deployment with real Cloud Functions running, which remains a required step in §8 before real money is ever accepted (unchanged from the original plan).

> "Can two concurrent executions cause two payouts for the same escrow?"

**No** — for two independent, reinforcing reasons, both verified: (1) `firestore.rules` now permits at most one `escrow_releases` document per job, ever (fixed `releaseId == jobId`, and a second write to the same document ID is evaluated as an `update`, which is unconditionally `false` — confirmed directly by the "concurrent release attempts" emulator test); (2) `processEscrowRelease`'s pre-existing atomic `pending → processing` claim transaction (unmodified, already correct, re-verified during this pass) ensures that even if the same document were somehow processed twice, only one invocation's transaction can win the claim — the other retries, observes `'processing'`, and returns without calling Paystack.

### 13.7 Remaining security risks (not fixed in this pass, by design)

- **Refund/cancellation-after-payment remains intentionally out of scope and requires a separate design phase.** No refund mechanism was implemented, extended, or stubbed. This was confirmed to still be entirely absent from the codebase during the original analysis (§2.5) and nothing in this implementation pass changes that. It needs a genuine architecture/product decision (automatic Paystack refund vs. admin-approved vs. partial/dispute-split) before real money is accepted, independent of the P0 fixes in this pass.
- **`initializePaystackTransaction` still has no idempotency guard** against two concurrent payment sessions for the same job (source audit P1-5) — unchanged by this pass; a double-charge is still possible if a customer opens two payment sessions, though it can no longer combine with any of the P0-1 exploit paths to produce an unauthorized payout, since the amount/ownership trust model is now server-derived either way.
- **The Paystack webhook's HMAC signature check** (`paystackWebhook`, source audit P1-4, `JSON.stringify(req.body)` instead of `req.rawBody`) was not touched — out of this pass's P0 scope, still a real (if probabilistic) money-path risk once Functions are deployed.
- **This fix has not been tested against a real, deployed Cloud Functions environment or real (even test-mode) Paystack traffic** — all verification in this pass is local (Firestore emulator + Node unit tests + Flutter tests). §8's deployment sequence (staging deploy → Paystack test-mode transactions → final security audit → only then real credentials) remains the required path before any of this is considered production-verified, and none of those later steps have been performed.
- **`processEscrowRelease`'s `BANK_CODES` table** (unrelated to this P0 pass, pre-existing, self-disclosed in its own code comment) remains unverified against Paystack's live bank list for newer fintech entries — not touched, not in scope.

### 13.8 Confirmations

- **Refunds:** confirmed out of scope, nothing implemented (§13.7).
- **Deployment/live Paystack:** confirmed — no `firebase deploy` of any kind was run, no Cloud Functions were enabled, no live or test-mode Paystack API call was made at any point in this session, and no real-money transaction occurred. All Cloud Functions changes were verified via local syntax check (`node --check`) and local unit tests only.
- **Production readiness:** **not claimed.** Per §8's deployment sequence, live authenticated testing (customer/artisan/admin workflows through the fixed rules) and a real test-mode Paystack integration test are both still outstanding — this implementation closes the specific P0 vulnerabilities and proves it locally, but does not by itself constitute a production-readiness sign-off.
