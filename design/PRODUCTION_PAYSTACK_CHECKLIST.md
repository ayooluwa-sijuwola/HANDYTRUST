# Production Paystack Readiness Checklist

Audit only — no code changes in this document, no real credentials used or required to produce it (every claim below is verified by reading the actual `PaystackService`/Cloud Functions source, not by running a live transaction).

---

## Customer payment — verified

- **Payment starts correctly**: `PaymentScreen._initiatePayment` → `PaystackService.initializeTransaction` → `initializePaystackTransaction` (Cloud Function, `PAYSTACK_SECRET_KEY` held as a Functions secret, never sent to the client) → real Paystack `transaction/initialize` call → WebView opens the real `authorizationUrl`. ✅ Ready.
- **Transaction verification works**: `PaymentWebviewScreen` detects the Paystack callback redirect → `PaystackService.verifyTransaction` → `verifyPayment` (Cloud Function) calls Paystack's real `transaction/verify/{reference}` endpoint — **does not trust the client's claim of success**, checks Paystack's own response. Additionally cross-checks `data.metadata.jobId` against the caller-supplied `jobId` (prevents a signed-in user from reusing someone else's successful reference to lock escrow on a job they don't own — a real anti-fraud check, already in place). ✅ Ready.
- **Escrow lock happens only after successful payment**: `_lockEscrow` is only ever called from inside `verifyPayment`, gated on `data.status === 'success'` from Paystack's own API — not from anything client-supplied. ✅ Ready.

## Artisan payout — verified, with one critical finding

- **Release creates a payout record**: both release paths (`JobService.confirmComplete`, customer-manual; `_releaseEscrow`, the auto-release cron) create an `escrow_releases/{id}` document. ✅ Ready.
- **Cloud Function triggers transfer**: `processEscrowRelease` (Firestore trigger on `escrow_releases` creation) resolves/creates a Paystack Transfer Recipient (with account-name verification against Paystack's own resolve endpoint before ever sending money) and initiates a real Transfer. ✅ Ready.
- **Failed payouts are handled visibly**: `escrow_releases.status` moves to `failed` with a `failureReason` on missing bank details, recipient-verification failure, or a `transfer.failed`/`transfer.reversed` webhook; the artisan gets a `payout_blocked` in-app notification + push (Group 9's unified pipeline) when bank details are missing or verification fails. `reconcileStuckEscrowReleases` (daily cron) catches anything stuck in `pending`/`processing` >2h and writes to `admin_alerts` (now readable by admins, Group 10). ✅ Ready.

### 🔴 CRITICAL — duplicate payouts CAN happen under a real, if narrow, race condition

Task 1 asked specifically to verify duplicate payouts cannot happen. **They can.** Traced precisely:

- `JobService.confirmComplete` (customer-manual release) is correctly transactional: it reads the job, calls `assertValidTransition(from, JobStatus.completed)` — which throws if `from` isn't `submitted` — and only then writes, all inside one Firestore transaction. A second call after the first succeeds cannot create a second `escrow_releases` doc, because the transition check fails once status is already `completed`.
- `_releaseEscrow` (the auto-release cron's release path, `functions/index.js`) is **not** transactional and has **no status precondition on write**: it does a plain `jobRef.get()` followed by a plain `jobRef.update({status: 'completed', ...})`, with nothing checking that `status` is still `'submitted'` at write time.

**The race**: `autoReleaseEscrow` (hourly cron) queries jobs where `status == 'submitted' AND autoReleaseAt <= now`, then calls `_releaseEscrow` for each match. If a customer's `confirmComplete` transaction commits *after* the cron's query returned that job but *before* `_releaseEscrow`'s update executes — a window of anywhere from milliseconds to several seconds, especially when the cron is processing a batch of stuck jobs via `Promise.allSettled` — **both paths create their own `escrow_releases` document**. `processEscrowRelease` fires unconditionally on every new document in that collection, with no check for "has this job already been paid out." Two documents → two real Paystack Transfers → a duplicate payout of real money to the artisan.

**Likelihood**: low. `autoReleaseAt` is 14 days out, so the race only opens in the narrow hour-long cron window right as that 14-day deadline expires, and only if the customer happens to confirm manually in that exact same window. **Severity**: high — real, unrecoverable money movement.

**Recommended fix** (not implemented in this audit-only pass, per this phase's explicit "do not rewrite architecture" — but this is a small, targeted addition, not a rewrite): wrap `_releaseEscrow`'s job read + status update in a Firestore transaction with an explicit `if (job.data().status !== 'submitted') return;` guard, mirroring the exact pattern `JobService.confirmComplete` already uses on the Dart side. This closes the race with a few lines, no architectural change.

## artisan_private bank details — verified
Stored at `artisan_private/{uid}` (`bankName`/`accountName`/`accountNumber`), owner/admin-read-only per `firestore.rules`. `processEscrowRelease` fails safely (not silently) when missing or unverifiable. ✅ Ready, contingent on the `BANK_CODES` table verification below.

---

## What needs live testing (cannot be verified by reading source alone)

1. **Paystack sandbox end-to-end run**: initialize → pay with a sandbox test card → verify → escrow lock → confirm completion → payout → transfer webhook → `escrow_releases` reaches `completed`. Nothing in this program has executed a real (even sandbox) Paystack call.
2. **`BANK_CODES` table** (`functions/index.js`) — the file's own comment already flags this as unverified against Paystack's live `GET /bank?country=nigeria`. Must be checked before real payouts.
3. **Webhook signature verification** (`paystackWebhook`'s HMAC check against `PAYSTACK_SECRET_KEY`) — logic is correct on read, but needs a live webhook call (sandbox or Paystack's webhook test tool) to confirm the deployed secret matches what Paystack sends.
4. **The duplicate-payout race above** — recommend either fixing it before launch, or at minimum writing a targeted integration test against the Firebase emulator (this repo currently has no emulator-based test setup — a standing gap noted since early in this program).

## Manual test cases (sandbox, no real credentials)

| # | Steps | Expected result |
|---|---|---|
| 1 | Post a job, negotiate, confirm agreement, initiate payment with a Paystack test card | Payment succeeds, job reaches `escrowLocked`, `payments` doc shows `escrowHeld` |
| 2 | Use a Paystack test card configured to decline | `PaymentWebviewScreen` shows the "Payment Not Completed" result view (Group 7), job stays `paymentPending`, no escrow lock |
| 3 | Complete a job, customer confirms manually | `escrow_releases` doc created once, `processEscrowRelease` fires once, artisan receives one transfer |
| 4 | Complete a job, artisan has no bank details on file | `escrow_releases` fails with `no_bank_details`, artisan gets `payout_blocked` notification |
| 5 | Attempt to reuse a successful payment reference against a different `jobId` | `verifyPayment` rejects with the metadata-mismatch error |
| 6 | (If feasible in sandbox) trigger `autoReleaseEscrow` and `confirmComplete` for the same job within the same minute | Confirms or refutes the critical race condition above with a real reproduction |
