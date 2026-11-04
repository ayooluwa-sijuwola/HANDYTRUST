# Payout Race Condition Audit — Phase 12.5

Traced every place that creates `escrow_releases`, every place that consumes it, and every place a real Paystack Transfer is initiated. This document describes the state **as found** (the bug) and locates where the fix (Task 2/3) now lives — the fix itself is described in `design/PAYMENT_SAFETY_HARDENING_REPORT.md`.

---

## Every place that creates an `escrow_releases` document

| Path | File | Trigger | Transactional (as found) | Idempotency check (as found) |
|---|---|---|---|---|
| Customer manual completion | `lib/core/services/job_service.dart` → `JobService.confirmComplete` | Customer taps "Confirm Completion" in `job_detail_screen.dart` | ✅ Yes — one Firestore transaction, job status write + release doc write + audit log write, all atomic | ⚠️ Only indirect: `assertValidTransition(from, completed)` requires the job to currently be `submitted`. Auto-ID release doc (`.doc()`) — no check that a release already exists. |
| Auto-release (14-day timeout) | `functions/index.js` → `autoReleaseEscrow` (hourly cron) → `_releaseEscrow` | Scheduled, no user action | ❌ **No** — plain `jobRef.get()` then `jobRef.update()` then `escrow_releases.add()`, three separate unguarded operations | ❌ **None** — no re-check of job status at write time, no check for an existing release before creating one |

**These are the only two places `escrow_releases` documents are created.** No other file, Cloud Function, or admin action writes to this collection.

## Every place that consumes an `escrow_releases` document / initiates a real transfer

| Function | File | Fires on | Guarantees exactly-once (as found) |
|---|---|---|---|
| `processEscrowRelease` | `functions/index.js` | `onDocumentCreated('escrow_releases/{releaseId}')` — **any** new document, unconditionally | ❌ **No** — reads the frozen creation-time event snapshot, no re-check of the release doc's own current status before proceeding to call Paystack. Cloud Functions triggers are at-least-once delivery; a platform-level retry (or, separately, two documents existing for one job) would both reach this function and both call Paystack's `/transfer` endpoint. |
| `paystackWebhook` (`transfer.success`/`transfer.failed`/`transfer.reversed` handler) | `functions/index.js` | Paystack webhook, also at-least-once delivery | ⚠️ Partial — updating `escrow_releases.status` on a redelivered webhook is naturally idempotent (same value written twice is harmless), but the artisan notification (`payout_completed`) was **not** guarded, so a redelivered `transfer.success` would send a duplicate "payment sent" notification. Not a money-duplication risk (Paystack itself only transfers once; this handler only records the confirmation) but a real UX/robustness gap. |

---

## Root cause, precisely

`_lockEscrow` (the escrow-lock path, for comparison — already correct) wraps its job read and write in one Firestore transaction with an explicit status precondition (`if (status !== 'paymentPending') throw`). `_releaseEscrow` (the auto-release path) never received the same treatment — it was written before `confirmComplete`'s transactional pattern existed and was never brought up to match it. Two independent gaps compounded:

1. **No transaction / no status check** in `_releaseEscrow` — it could act on a job that had already moved past `submitted` (e.g., a customer's `confirmComplete` beat it to the punch) without noticing.
2. **Auto-generated IDs** for `escrow_releases` documents in both creation paths — nothing about the document ID itself prevented two documents from existing for the same `jobId`. Even if #1 had been fixed alone, two *separate* Firestore transactions, each individually checking "is the job still `submitted`" and each seeing `true` at the exact same moment (a genuine concurrent-read scenario, not just a logic bug), could still each proceed to create their own release document — the status check alone cannot fully close a true race between two transactions that don't contend on the same document.

The combination of both gaps is what made a duplicate payout possible, not either alone.

## Where the fix lives (implemented — see the final report for detail)
- `JobService.confirmComplete` (Dart) and `_releaseEscrow` (Node.js) now both key the release document by `jobId` (not an auto-generated ID) and both check-then-create inside a transaction. Two transactions racing for the *same document ID* is exactly what Firestore's optimistic-concurrency transaction retry mechanism is built to make safe — this is a structural guarantee, not a timing hope.
- `processEscrowRelease` now atomically claims the release document (`pending` → `processing`) as its first action, before any Paystack call, so a second invocation of the same function for the same document (however it might occur) exits immediately.
- `paystackWebhook`'s `transfer.success` handler now checks the release is not already `completed` before sending the artisan notification.
- `firestore.rules` now has an explicit `escrow_releases` rule (previously had none at all) — the customer's own `confirmComplete` client write is scoped to their own job, the fixed `jobId`-as-`releaseId` scheme, and the correct initial status; every other operation is `false`.

## Duplicate-payout impact if this had reached production
Real, unrecoverable money sent twice to an artisan for one job, with no automatic reconciliation (the existing `reconcileStuckEscrowReleases` daily sweep only catches releases *stuck* in `pending`/`processing` — a *second successful* transfer wouldn't look stuck, it would look like two normal, completed payouts). This is the highest-severity class of bug found across this entire program.
