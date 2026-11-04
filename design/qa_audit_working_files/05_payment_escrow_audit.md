# HandyTrust Payment/Escrow Pipeline — P0 Code-Level Audit

Scope: functions/index.js (full 1256 lines), lib/core/services/job_service.dart (1070 lines), escrow_service.dart, paystack_service.dart, payment_service.dart, demo_escrow_service.dart, lib/providers/escrow_provider.dart, demo_payment_provider.dart, lib/screens/payment/*.dart, firestore.rules (662 lines, full read), firebase.json. All findings CODE-LEVEL ONLY — nothing executed, no Paystack API or production Firestore touched.

## FINDING 1 (CRITICAL) — Duplicate/conflicting escrow_releases Firestore rule blocks let any customer trigger a real, unpaid payout

**Category:** Escrow authority / access control / fund-safety

firestore.rules has TWO separate top-level `match /escrow_releases/{...}` blocks, both direct children of `match /databases/{database}/documents {`:

- Lines 443-450 (intended, hardened rule per design/PAYMENT_SAFETY_HARDENING_REPORT.md Task 5):
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
- Lines 514-521, an older/leftover block for the SAME collection:
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
Firestore ORs overlapping match blocks for the same path — a write is permitted if ANY matching block allows it. Block 2 requires only jobExists(jobId) && customerId==self: no releaseId==jobId constraint, no status=='pending' constraint. Fully neutralizes the fixed-ID/status-guard invariant block 1 was built to enforce.

Compounding this, processEscrowRelease (functions/index.js:395-524) — the Firestore-triggered function that fires a real Paystack transfer — never checks jobs.status at all. Only requires job.artisanId present (:426), and derives amount as `paySnap.empty ? job.agreedAmount : paySnap.docs[0].data().amount` (:435-440) — falls back to job's negotiated agreedAmount if no payments document exists, with NO verification that any money was ever actually captured.

**Minimal reproducible exploit chain (fully reachable via ordinary client SDK, no app-code changes needed):**
1. Customer creates a job, gets matched with an artisan (own second account or consenting artisan) — status: matched.
2. Customer/artisan move to inChat; customer writes agreedAmount to an arbitrary value via negotiation rule (firestore.rules:142-148, requires only status=='inChat').
3. Customer writes directly to escrow_releases/{anyRandomId} = {jobId, status:'pending', requestedAt, requestedBy:self} — allowed by permissive block 2. No payment was ever initiated.
4. processEscrowRelease fires on creation, finds no payments doc, falls back to job.agreedAmount, resolves/creates transfer recipient, calls real Paystack /transfer endpoint (:486-522) for that amount from HandyTrust's live Paystack balance.

Second independent variant: duplicate payout for a legitimately-paid job — because block 2 doesn't enforce releaseId==jobId, a customer can create a SECOND escrow_releases document (different, non-jobId ID) after a legitimate release already exists, defeating "one release per job, ever." processEscrowRelease fires unconditionally on every new doc — two real transfers for one job.

**What could go wrong:** Direct, unauthenticated-by-payment fund drain from company's Paystack balance; or duplicate real transfers for a single legitimately-paid job. Single most severe issue in the codebase.

**Severity:** P0
**Verification type:** CODE-LEVEL ONLY. Rules-OR-semantics is standard documented Firestore behavior. Recommend confirming with Rules Playground or emulator before treating as theoretical.

## FINDING 2 — payments collection creation rule has no ownership tie to the job, arbitrary amount + status:'escrowHeld' settable on create

**Category:** Escrow authority / access control

firestore.rules:409-420:
```
match /payments/{paymentId} {
  allow create: if isSignedIn() &&
    request.resource.data.payerId == request.auth.uid &&
    request.resource.data.status in ['pending', 'escrowHeld'];
```
No getJob(jobId).customerId == request.auth.uid check, and status allowed to be escrowHeld ON CREATE — a value that should only be reachable server-side after _lockEscrow (functions/index.js:127-170) confirms a real Paystack charge.

**What could go wrong:** Any signed-in, non-anonymous user (not necessarily the job's customer) can plant a payments document pointing at any jobId, with arbitrary amount and status:'escrowHeld'. processEscrowRelease's amount lookup (functions/index.js:435-440) queries payments by jobId only (no payerId/status filter) — a planted document directly controls payout amount for that job, combined with Finding 1's release-doc gap.

**Severity:** P0 (compounds Finding 1; also independently a data-integrity issue)
**Verification type:** CODE-LEVEL ONLY.

## FINDING 3 — Customer can self-transition paymentPending -> escrowLocked directly via Firestore, bypassing Paystack entirely

**Category:** Escrow authority / job state machine

firestore.rules:395, inside _isValidJobTransition (:368-406):
```
(cur == 'paymentPending' && nxt == 'escrowLocked' && (isAdmin() || isCust)) ||
```
Same transition _lockEscrow (functions/index.js:127-170, called only from Paystack webhook and verifyPayment) performs server-side after confirming a real charge — but rule ALSO grants it to isCust (job's own customer), no further constraint on paymentReference or any other field. JobService.lockEscrow (job_service.dart:479-486) and EscrowNotifier.lockEscrow (escrow_provider.dart:119-123) are live Dart methods performing exactly this write; not called from any real (non-demo) screen today (only escrow_provider.dart itself and PaymentService.simulatePayment, demo-only, call _job.lockEscrow) — but the SECURITY BOUNDARY IS firestore.rules, not app code. A modified client, compromised device, or direct Firestore SDK/REST call using a legitimate customer's ID token can perform this write regardless of shipped app behavior.

**What could go wrong:** Customer flips own job to escrowLocked with fabricated paymentReference, zero real payment. Downstream startWork/submitCompletion/confirmComplete proceed exactly as if payment happened, ending in real payout per Finding 1's amount-fallback logic — WITHOUT needing to exploit escrow_releases rule gap at all, just legitimate confirmComplete path. Additionally, if real customer DOES pay for real after fake client-side lock already flipped status, _lockEscrow's transaction (functions/index.js:140-143) throws "Cannot lock escrow: job is in state escrowLocked", webhook handler returns HTTP 500 (:58), real successful charge never reconciled to the job — money captured for real, escrow never reflects it, no admin_alerts entry written (only console.error).

**Severity:** P0
**Verification type:** CODE-LEVEL ONLY.

## FINDING 4 — No idempotency guard on initializePaystackTransaction; double-charge scenario has no alerting

**Category:** Idempotency / failure handling

functions/index.js:913-974. Each call creates a brand-new payments document and fresh Paystack transaction reference, no check for existing pending/escrowHeld payment on same jobId. Client-side payment_screen.dart disables button via _loading flag but only protects single-session double-tap, not retried network call/second device/tab/independent webview sessions.

**What could go wrong:** Two successful Paystack charges for same job. First charge.success webhook locks escrow normally; second's _lockEscrow (functions/index.js:140-143) throws (status no longer paymentPending), webhook returns 500, Paystack retries then gives up — second charge is real money debited from customer with NO automatic refund and NO admin_alerts record, only console.error.

**Severity:** P1
**Verification type:** CODE-LEVEL ONLY.

## FINDING 5 — Legacy EscrowService.confirmComplete uses auto-generated escrow_releases IDs (dead code today, but a landmine)

lib/core/services/escrow_service.dart:102-110:
```dart
Future<void> confirmComplete(String jobId) async {
    await transitionTo(jobId, JobStatus.completed);
    await _db.collection('escrow_releases').add({   // auto-ID, not jobId-keyed
      'jobId': jobId, 'requestedAt': Timestamp.now(), 'status': 'pending',
    });
  }
```
Exactly the pre-hardening pattern design/PAYOUT_RACE_CONDITION_AUDIT.md describes as root cause of duplicate payouts. NOT transactional — job-status write and escrow_releases write are two separate operations; if second fails, job left completed with no release ever queued (silently stuck). Confirmed via grep: EscrowService never instantiated anywhere in lib/ — dead code today. Would be rejected by correct block A (releaseId==jobId) but ACCEPTED by permissive block B (Finding 1) — if ever wired up again, reintroduces duplicate-payout bug immediately, rules would not stop it.

**Severity:** P2 (dead code today; becomes P0 the moment anything calls it)
**Verification type:** CODE-LEVEL ONLY.

## FINDING 6 — Demo/simulated payment path (DemoEscrowScreen) well-defended (NOT currently exploitable) — noted as pattern to watch

lib/screens/payment/demo_escrow_screen.dart:107-129 gates entire build() behind if(!kDebugMode), "not available" placeholder in release. Only call site pushing this route with autoStart:true (payment_screen.dart:339) is itself gated behind kDebugMode (:323). Genuinely unreachable in production including Flutter Web. Flagging only: initState's addPostFrameCallback(_startPayment) (:60-63) has NO kDebugMode check itself (only build() does) — future refactor risk if build-gate logic changes without checking initState too.

**Severity:** P3 (no current exploit; structural fragility for future changes)

## FINDING 7 — No handling for Paystack transfer OTP-required responses

functions/index.js:499-507: `status: resp.data.data.status === 'success' ? 'processing' : resp.data.data.status`. If Paystack account has "Enable OTP for transfers" on, transfer-initiate returns status:'otp' requiring follow-up /transfer/finalize_transfer with OTP sent to a human — no code anywhere handles this. Releases would land in status 'otp' indefinitely; reconcileStuckEscrowReleases only matches status in ['pending','processing'] — 'otp'-stuck releases NEVER flagged by reconciliation sweep.

**What could go wrong:** Silent, invisible payout failure for every transfer, depending on Paystack account configuration invisible from code.
**Severity:** P1 (contingent on Paystack account settings)
**Verification type:** INFRASTRUCTURE BLOCKER — cannot verify actual Paystack account's OTP-for-transfers setting from this environment; verify directly in Paystack dashboard.

## Job state machine reference

JobService.allowedTransitions (job_service.dart:36-52) and firestore.rules' _isValidJobTransition (:368-406) define the same 11-state machine, consistent with each other: requested -> matched -> inChat -> paymentPending -> escrowLocked -> inProgress -> submitted -> completed, with disputed/resolved/cancelled as side branches. completed/resolved/cancelled terminal (correctly blocks second release attempt from completed job).

**Client write path:** jobs.status NOT proxied exclusively through Cloud Function anywhere except initial paystackWebhook/verifyPayment-driven lock (itself ALSO directly writable by customer per Finding 3). Every other transition is a plain client Firestore write gated only by _isValidJobTransition — JobService's in-app validation is convenience/audit-trail only, NOT a security boundary.

## Idempotency mechanisms that ARE correctly implemented (for balance)

- _lockEscrow (functions/index.js:127-170): transactional read-check-write on job.status=='paymentPending', correct.
- _releaseEscrow (:207-272, 14-day auto-release cron body): transactional, checks both job.status=='submitted' and !releaseSnap.exists — matches design/PAYMENT_SAFETY_HARDENING_REPORT.md fix.
- processEscrowRelease's atomic pending->processing claim (:408-417) genuinely protects against same document processed twice by platform-level retry.
- JobService.confirmComplete (job_service.dart:324-378): correctly transactional, uses escrow_releases.doc(jobId) fixed ID, checks non-existence first.
- transfer.success/transfer.failed webhook handling (:83-116) correctly guards duplicate-notification-only side effects on redelivery.

All of this is UNDERMINED by the firestore.rules gaps in Findings 1-3, which allow the invariants these transactions depend on to be bypassed entirely via paths outside the transactional code.

## Secrets
PAYSTACK_SECRET_KEY referenced only via process.env in functions/index.js (Functions v2 secret), sourced from Secret Manager. No .env in functions/. Grep across lib/ for PAYSTACK/secretKey/sk_live/sk_test/pk_live/pk_test found no hardcoded key material. Clean.

## Deployment status
All functions correctly exported/configured. Whether deployed/live not verifiable by static reading alone — cross-reference with Cloud Functions inventory agent's finding: `firebase functions:list` confirmed ZERO functions deployed to production. This means Findings 1-3 (rules-level) are exploitable via raw Firestore writes RIGHT NOW regardless of function deployment (rules are live independent of functions), but processEscrowRelease itself (which fires the actual Paystack transfer) is currently NOT deployed, so the exploit chain currently stops at "fake escrow_releases doc created" without an actual payout firing — UNTIL processEscrowRelease is deployed, at which point this becomes live-exploitable with real money. This is a P0 that must be fixed BEFORE Cloud Functions (and definitely before Paystack live keys) go live.

## Recommended immediate fix (for remediation phase, NOT applied now)
Delete the second `match /escrow_releases/{id}` block at firestore.rules:514-521 entirely (or merge its read:isAdmin() into block 1) — closes Finding 1. Add `jobExists(...) && getJob(...).customerId == request.auth.uid` to payments create rule (Finding 2). Remove isCust from paymentPending->escrowLocked transition in firestore.rules:395 and corresponding Dart callers, restrict to isAdmin() only (Finding 3) — real locks should only come from Admin-SDK-executed Cloud Functions, which bypass rules regardless.
