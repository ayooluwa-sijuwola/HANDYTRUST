# Escrow Timing Audit

Backend correctness task — no UI changes in this document or its implementation. Traced every write to every escrow-related timestamp across `JobService` (Dart), Cloud Functions (Node), `JobModel`, Firestore rules, and indexes.

---

## Task 1 — Complete escrow lifecycle, every timestamp

```
Payment initiated (customer, PaymentScreen)
  → JobService.initPayment: status → paymentPending
↓
Paystack charge.success webhook
  → _lockEscrow (functions/index.js):
      status → escrowLocked
      escrowLockedAt = now                              [Firestore server time]
      autoReleaseAt   = now + 48h                        ← ROOT CAUSE, see below
↓
Artisan starts work
  → JobService.startWork: status → inProgress            (no new timestamps)
↓
Artisan submits completed work
  → JobService.submitCompletion → updateJobStatus(submitted)
      → _timestampsForStatus(JobStatus.submitted):
          submittedAt         = now
          disputeWindowEndsAt = now + 14 days             ← shown to the customer,
                                                              enforces nothing
↓
  ┌─ Customer confirms completion ─────────────────────────────────────┐
  │   JobService.confirmComplete: status → completed                  │
  │     completedAt = now                                             │
  │     writes escrow_releases/{id} {status: 'pending', ...}          │
  │       → processEscrowRelease (Firestore trigger) → Paystack       │
  │         Transfer → escrow_releases doc updated by the             │
  │         transfer.success/failed webhook                           │
  └─────────────────────────────────────────────────────────────────────┘
  ┌─ Customer raises a dispute instead ────────────────────────────────┐
  │   JobService.raiseDisputeWithRecord: status → disputed             │
  │     (no timestamp on the job related to release; job leaves        │
  │      'submitted', so the query below can never match it again —    │
  │      disputing correctly halts auto-release, by construction)      │
  └─────────────────────────────────────────────────────────────────────┘
  ┌─ Customer does nothing ─────────────────────────────────────────────┐
  │   autoReleaseEscrow (Cloud Function, hourly cron):                  │
  │     WHERE status == 'submitted' AND autoReleaseAt <= now            │
  │     → _releaseEscrow: status → completed, completedAt = now,        │
  │       writes escrow_releases/{id} {status: 'pending', ...}          │
  │       → same processEscrowRelease trigger as the manual path        │
  └─────────────────────────────────────────────────────────────────────┘
```

**Every timestamp involved**: `escrowLockedAt`, `autoReleaseAt`, `submittedAt`, `disputeWindowEndsAt`, `completedAt`. Of these, only **`autoReleaseAt`** is ever read by code that moves money (`autoReleaseEscrow`'s query). `disputeWindowEndsAt` is read by exactly one place: `_DisputeCountdownBanner` in `job_detail_screen.dart` — a display-only widget. They have never been the same field, and nothing keeps them in sync.

## Root cause

`autoReleaseAt` is computed **once, at escrow-lock time**, as `escrowLockedAt + 48h` — in two independent, hand-synced implementations (`functions/index.js`'s `_lockEscrow`, and `job_service.dart`'s `_timestampsForStatus` for the `escrowLocked` case, which a comment explicitly says "must match... exactly"). It is never recomputed later.

The `autoReleaseEscrow` cron only fires once `status == 'submitted'`. If an artisan takes longer than 48 hours between escrow lock and submission — normal for any job that isn't finished same-day — `autoReleaseAt` has already passed *before* the job even reaches `submitted`. The very next hourly cron run releases the funds, typically within an hour of submission, while `disputeWindowEndsAt` (set at that same submission moment, to 14 days out) tells the customer they have nearly two weeks left. The 14-day figure is enforced nowhere; only the stale 48-hours-post-lock figure is, and by the time it matters it has almost always already expired.

**Confirmed not a problem for**: raising a dispute (halts the cron match immediately, since it requires `status == 'submitted'`), Firestore rules (the `submitted`→`completed`/`disputed` transitions have no field-diff restriction that would block fixing this — `allow update: if isSignedIn() && _isValidJobTransition(jobId);` on the general job-status path has no `hasOnly()` clause), and the composite index (`status ASC, autoReleaseAt ASC` — matches the cron query regardless of *when* `autoReleaseAt` is written, only that it exists once queried).

---

## Task 2 — Canonical model recommendation

**Option A — timer begins at submission.** **Option B — timer begins at escrow lock** (i.e., keep today's anchor, and instead make the *displayed* countdown match it).

| | Option A (submission-anchored) | Option B (lock-anchored) |
|---|---|---|
| Customer protection | Guarantees a full, meaningful review window every time — the customer can only fairly evaluate work once it exists. | Structurally can't guarantee this — a slow (but legitimate) job can already have consumed most or all of the window before the customer has anything to review. This is the exact bug. |
| Artisan fairness | Predictable, identical window after every submission regardless of how long the job took — an artisan who takes 3 days to do a good job isn't penalized relative to one who takes 3 hours. | Rewards slow jobs with a *shorter* effective customer-review period, which sounds artisan-favorable but actually increases dispute/chargeback risk and platform-trust damage for exactly the jobs that most need a fair review. |
| Marketplace expectations | Matches how comparable marketplaces anchor review/release windows to delivery, not to when payment was collected. | Not aligned with typical expectations; "you have until 48h after you paid" regardless of delivery timing is an unusual model to explain to either side. |
| Implementation complexity | **Low.** The `submitted` transition is already 100% client-side (`JobService.submitCompletion`); the Cloud Function's cron already reads whatever `autoReleaseAt` holds. Fix is: stop writing `autoReleaseAt` at lock time, write it (alongside `disputeWindowEndsAt`, same value, same write) at submission time instead. No Cloud Function write-path changes needed for submission — only removing the now-wrong write at lock. | Would require either (a) shortening the customer-facing promise from 14 days down to something the 48h-from-lock figure can actually deliver on — a real reduction in what customers are told, with no clear justification — or (b) recomputing the lock-time deadline forward whenever work is still in progress, which is strictly more moving parts than Option A for a worse guarantee. |

**Recommendation: Option A**, using the **existing 14-day figure** as the single canonical duration — it's already the number designed and shown to customers; the bug is the anchor point, not the duration. This is the smallest, most conservative fix that actually delivers the protection already promised, requires no new number to be invented or justified, and needs no Firestore rules or index changes.

**Chosen model**: at the moment a job transitions to `submitted`, write **both** `disputeWindowEndsAt` and `autoReleaseAt` from the same computation (`now + 14 days`), in the same transaction, so they can never diverge again. Stop writing `autoReleaseAt` at escrow-lock time entirely — it was the source of the bug and nothing else depends on it existing before submission (the cron's query requires `status == 'submitted'`, so its absence before that point is inert).

**Deliberately not done**: renaming/consolidating `disputeWindowEndsAt` and `autoReleaseAt` into one field, or changing what `_DisputeCountdownBanner` reads — both would touch UI files, out of scope for this backend-only task. `disputeWindowEndsAt` stays the field the UI reads; `autoReleaseAt` stays the field the cron reads; they're just guaranteed identical now because one code path writes both at once.

**Related gap noticed, not fixed here** (different problem than what was asked): there's no timeout protecting a customer if an artisan never starts work or never submits after escrow is locked — a job can sit in `escrowLocked` or `inProgress` indefinitely. Worth a follow-up audit, but it's a distinct scenario from the submitted→completed auto-release timing this task addresses.

Implementation follows in this same change — see the final report for exactly what was written where.
