# Part 8 — Escrow Workflow

The single highest-stakes subsystem in the codebase — real money. Spans `functions/index.js` (Cloud Functions, Paystack integration), `JobService` (job-side state), and `PaymentModel`/`payments` collection (payment-side records).

## Data model — genuinely single-payment, no milestones
Confirmed directly in `job_model.dart` and `payment_model.dart`: a job has exactly **one** `agreedAmount` and **one** `paymentReference`; `PaymentModel` mirrors this with one `amount`/`status`/`paystackReference` per job. **There is no milestone or material-payment data model anywhere in this codebase** — no `milestones` subcollection, no partial-payment concept. Every "deposit," "partial payment," or "release" event in this system operates on the job's single, whole amount.

## Deposit
1. Customer taps pay (Job Detail, or — a verified gap — the chat screen's "Pay Now" button regardless of Agreement Confirmation state; see Part 6/9) → `PaymentScreen` → `PaystackService.initializeTransaction` → the `initializePaystackTransaction` Cloud Function callable.
2. That function calls Paystack's transaction-initialize REST API server-side, creates a `payments/{id}` doc at `status: 'pending'`, and returns the checkout URL.
3. `PaymentWebviewScreen` loads that URL for the customer to actually pay (card/bank/USSD/bank transfer channels, per the `channels` array passed to Paystack).
4. **Authoritative confirmation is the webhook, not the client.** `paystackWebhook` (an `onRequest` Cloud Function, HMAC-SHA512 signature-verified against `PAYSTACK_SECRET_KEY`) receives Paystack's own `charge.success` event and calls `_lockEscrow`, which transitions the job to `escrowLocked` and the payment doc to `escrowHeld` inside one transaction. A client-callable `verifyPayment` exists as a secondary confirmation path (cross-checks Paystack's own transaction metadata against the client-supplied `jobId` as a fraud guard before calling the same `_lockEscrow`), but the webhook is the one Paystack itself drives.

## Partial payment ❌ — does not exist
No partial-charge, deposit-then-balance, or split-payment flow was found anywhere. A job is paid in full or not paid at all.

## Release
Two independent trigger paths, both ending at the same payout mechanism (as of the most recent Cloud Functions work in this repository):
1. **Customer confirms** (`JobService.confirmComplete`) — job → `completed` and an `escrow_releases/{id}` doc created, atomically, in the same transaction.
2. **48-hour auto-release** (`autoReleaseEscrow`, an hourly scheduled function) — finds every job at `status: 'submitted'` with `autoReleaseAt <= now`, calls `_releaseEscrow` for each. **This path previously did not create an `escrow_releases` doc at all** — it updated the job and payment records directly. That gap has been closed in the current codebase: `_releaseEscrow` now creates the same record path 1 creates, so both paths funnel through one payout consumer. This fix is recent enough that it should be treated as unverified against a live auto-release event, not just unverified against a live payout (see below).

## Actual payout to the artisan — the newest code in this repository
`processEscrowRelease`, a Firestore-triggered Cloud Function firing on `escrow_releases` document creation:
1. Reads the job for `artisanId`, reads the linked `payments` doc for the true paid amount (not `agreedAmount`, which could in principle diverge).
2. Reads `artisan_private/{artisanId}` for bank details. If missing, marks the release `failed` with reason `no_bank_details` and sends the artisan an in-app notification pointing them at `/bank-details`.
3. **Resolves and verifies the account** against Paystack's account-resolution API before trusting it — compares the bank's own returned account-holder name against what the artisan typed at signup. This exists specifically as a safety net for the next point.
4. Creates (or reuses, cached on `artisan_private`) a Paystack Transfer Recipient — requires a numeric Paystack bank code, which the bank-details form does not collect (it only stores a display name like "Guaranty Trust Bank (GTBank)"). A static name→code lookup table was added to bridge this; **its accuracy was not verified against Paystack's live bank list from within this environment** — the account-resolution step in point 3 is the actual defense against a wrong code, not the table itself.
5. Initiates the transfer (`POST /transfer`). Marks the release `processing`, not `completed` — completion is confirmed asynchronously.
6. `paystackWebhook` was extended (same function, same signature verification, additional `event.event` branches) to handle `transfer.success`/`transfer.failed`/`transfer.reversed`, marking the release `completed` or `failed` and, on success, notifying the artisan.
7. A daily reconciliation sweep (`reconcileStuckEscrowReleases`) flags any release still `pending`/`processing` after 2 hours into `admin_alerts` — no admin UI was found consuming that alert type specifically (Part 5).

**This entire payout path has never executed against a real transaction** — it was built and syntax-checked (`node -c`) but not deployed, and cannot be from this environment. Treat it as implemented-but-unverified, not proven.

## Complaint / dispute (escrow-specific angle)
A dispute (Part 6) freezes the job at `disputed` from `escrowLocked`, `inProgress`, or `submitted` — the money's fate is then entirely an admin decision (`resolveDisputeWithRecord`). No automated partial-refund-vs-release split logic exists; resolution is a single status transition with a free-text `resolution` field, not a structured refund action.

## Refund ❌ — no distinct refund mechanism exists
No Paystack Refund API call was found anywhere in `functions/index.js`. `_releaseEscrow`'s only outcome is paying the artisan; there is no code path that returns money to the customer. A dispute resolved "in the customer's favor" has no corresponding automated money movement — only a status field change.

## Automatic release / timers
- **48-hour** auto-release window from `submitted`, set via `autoReleaseAt` at the moment escrow locks (`_timestampsForStatus` in `JobService`, and independently in the Cloud Function's `_lockEscrow` — confirmed to agree at 48 hours in the version of the code currently in this repository; a code comment in `JobService` documents that this was previously a 7-day/48-hour mismatch between two implementations and has since been reconciled to 48 hours everywhere it's set).
- **14-day** dispute window from `submitted` (`disputeWindowEndsAt`) — set but, as far as could be confirmed by reading the scheduled functions, nothing currently reads or enforces this value (no scheduled function or rule was found checking it) — it appears to be recorded for display/future use, not currently acted on.
- **2-hour** stuck-release threshold in the new reconciliation sweep.

## Status changes summary (escrow-relevant fields only)
`payments.status`: `pending → escrowHeld → released` (or `failed` at various points). `escrow_releases.status`: `pending → processing → completed` (or `failed` with a specific `failureReason`).

## Cloud Functions inventory for this workflow
`paystackWebhook`, `autoReleaseEscrow`, `initializePaystackTransaction`, `verifyPayment`, `processEscrowRelease`, `reconcileStuckEscrowReleases` — six functions, all in `functions/index.js`, no separate files.
