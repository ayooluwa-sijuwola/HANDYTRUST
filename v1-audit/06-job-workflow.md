# Part 6 — Job Workflow (Complete Lifecycle)

Single authoritative source: `JobService` (`lib/core/services/job_service.dart`), mirrored server-side by `firestore.rules`' `_isValidJobTransition()`. Every write to `/jobs` goes through this one service — confirmed no screen or provider writes to the collection directly.

## The actual `JobStatus` enum (11 values — not the brief's example vocabulary)
```
requested → matched → inChat → paymentPending → escrowLocked → inProgress → submitted → completed
                                                        ↓                        ↓
                                                    disputed ──────────────→ resolved
Any of requested/matched/inChat/paymentPending/escrowLocked → cancelled
```
There is no `draft`, `visible`, `archived`, `scheduled`, `travelling`, or `working` status — the brief's example vocabulary for this part does not match the actual enum. `Draft` doesn't exist (a job is created already-`requested`, with no unpublished intermediate state). `Archived` doesn't exist — `completed`/`resolved`/`cancelled` are all terminal (`JobStatus.isTerminal`), but nothing moves a job out of the main `jobs` collection into any archival location; a "completed" job remains a live, queryable document indefinitely.

## Sub-states within `inChat` (added by the most recent work in this codebase)
`agreementStatus: negotiating | pendingArtisanConfirmation | confirmed | changesRequested` — a fine-grained state that only has meaning while `status == inChat`, deliberately not a new top-level `JobStatus` value (mirrors the pre-existing `progressStage` pattern within `inProgress`). See the dedicated section below.

## Sub-states within `inProgress`
`progressStage: accepted | onTheWay | workStarted | quarterDone | halfDone | threeQuartersDone | almostFinished | completed` — manually advanced by the artisan, purely a UI/status label with no location data attached to any value.

---

## State-by-state

### `requested`
- **Who triggers entry**: customer, via job posting (`create`, not a transition).
- **DB changes**: new `jobs/{jobId}` doc.
- **Notifications**: none on creation itself.
- **UI**: visible to the posting customer and to any approved+verified artisan browsing the Open Jobs Feed.
- **Rules**: `create` requires `customerId == request.auth.uid` and `status == 'requested'`.

### `matched`
- **Trigger**: customer accepts a quote (`JobService.acceptQuote`, delegated from `QuoteService.acceptQuote`).
- **DB changes**: `status`, `artisanId` set, `matchedAt` server timestamp, every competing quote closed — all in one transaction.
- **Notifications**: `quote_accepted` to the winning artisan.
- **Rules**: `cur=='requested' && nxt=='matched' && isCust && artisanId is a non-empty string && isArtisanEligible(artisanId)`.

### `inChat`
- **Trigger**: `JobService.openChat` (customer-triggered, per `EscrowNotifier.openChat`'s role assignment).
- **DB changes**: status only.
- **What happens inside this status, without a further status transition**: price negotiation (`agreedAmount`, editable), appointment slot proposal/confirmation, and — as of the most recent work — the full Agreement Confirmation checkpoint (below).
- **Rules**: `cur=='matched' && nxt=='inChat' && isCust`.

### The Agreement Confirmation checkpoint (within `inChat`, no `JobStatus` change)
Added specifically because chat-based informal agreement was judged unsafe for a trust marketplace — the checkpoint makes "we're done negotiating" an explicit, two-party, auditable action instead of an inference from conversation history.
- `negotiating`/`changesRequested` → `pendingArtisanConfirmation`: customer confirms (`JobService.confirmAgreementAsCustomer`) — locks a scope summary and price, notifies the artisan. Blocked if already pending/confirmed, or if the caller isn't the job's customer.
- `pendingArtisanConfirmation` → `confirmed`: artisan accepts (`acceptAgreementAsArtisan`) — only the job's matched artisan (UID match against `artisanId`) can do this, only while pending.
- `pendingArtisanConfirmation` → `changesRequested`: artisan requests changes with a required reason (`requestAgreementChanges`) — resets both parties' confirmation flags, notifies the customer.
- **Business rule with real consequence**: `paymentPending` is unreachable unless `agreementStatus == 'confirmed'` — enforced independently in both `JobService.initPayment` (a dedicated transaction, not the generic status-update path) and `_isValidJobTransition`'s `inChat→paymentPending` branch.
- **Verified UI gap**: this checkpoint's existence is not surfaced in the chat screen at all — `chat_screen.dart`'s "Pay Now" button still renders and is tappable whenever `status=='inChat'`, with no read of `agreementStatus`. A customer can reach the payment screen before confirming, and would only be blocked when the actual payment-initiation write is attempted.
- **Migration behavior, confirmed by design**: every field here is optional; a job with no `agreementStatus` at all reads as `negotiating` everywhere (Dart default and Firestore rules' `.get(path, 'negotiating')`), so no existing job document errors — but any job that predates this feature is blocked from payment until it goes through the real confirm/accept flow, with no automatic credit for prior informal chat agreement.

### `paymentPending`
- **Trigger**: `JobService.initPayment`, gated as above.
- **DB changes**: status + `agreedAmount` set.
- **Rules**: `cur=='inChat' && nxt=='paymentPending' && isCust` (+ the agreement gate).

### `escrowLocked`
- **Trigger**: **not** a direct client action — the Paystack webhook (`paystackWebhook`, Cloud Function) calls `_lockEscrow` on a confirmed `charge.success` event. A client-callable `verifyPayment` path exists as a secondary confirmation route but funnels into the same `_lockEscrow` function.
- **DB changes**: `status`, `paymentReference`, `escrowLockedAt`, `autoReleaseAt` (48 hours out) — plus the corresponding `payments` doc set to `escrowHeld`.
- **Notifications**: `escrowLocked`-event push to both parties (`_sendNotification`).
- **Rules**: `cur=='paymentPending' && nxt=='escrowLocked' && (isAdmin() || isCust)` — but in practice this write happens via the Admin SDK from a Cloud Function, which bypasses client rules entirely; the rule exists for the rarer client-initiated confirm path.

### `inProgress`
- **Trigger**: artisan taps "Start Work" (`JobService.startWork`).
- **DB changes**: status, `startedAt`.
- **UI**: unlocks the `progressStage` sub-state tracker.
- **Rules**: `cur=='escrowLocked' && nxt=='inProgress' && isArt`.

### `submitted`
- **Trigger**: artisan submits completion proof (`JobService.submitCompletion`).
- **DB changes**: status, `submittedAt`, `disputeWindowEndsAt` (+14 days), plus completion/before photo URLs and optional notes.
- **Notifications**: `submitted`-event push to the customer.
- **Rules**: `cur=='inProgress' && nxt=='submitted' && isArt`.

### `completed`
- **Trigger, two independent paths — a real, verified inconsistency**:
  1. Customer confirms (`JobService.confirmComplete`) — writes the job status change **and** creates an `escrow_releases/{id}` doc, atomically, in one transaction.
  2. The 48-hour auto-release scheduler (`autoReleaseEscrow`, Cloud Function) — until the most recent Cloud Functions work, this path updated the job and payment records directly **without** creating an `escrow_releases` doc at all, meaning any payout consumer watching only that collection would never fire for an auto-released job. This has been fixed in the version of `functions/index.js` currently in this repository (`_releaseEscrow` now creates the same record path 1 creates) — flagged here because it was a real, previously-unnoticed divergence between two paths that both claim to do the same thing.
- **Notifications**: `completed`-event push to the artisan ("payment released").
- **Rules**: `cur=='submitted' && nxt=='completed' && isCust`.

### `disputed`
- **Trigger**: customer only, from `escrowLocked`, `inProgress`, or `submitted` (`JobService.raiseDisputeWithRecord`) — writes the job status change and a new `disputes/{id}` doc atomically. Confirmed customer-only at **two independent points**, not just one: the `jobs` transition rule (`... && nxt=='disputed' && isCust`) and the separate `disputes` collection's own `create` rule (`getJob(...).customerId == request.auth.uid`) — both agree, no discrepancy between them. `job_detail_screen.dart`'s "Raise Dispute" button is likewise only rendered in the customer branch of the submitted-state action buttons. An artisan's only dispute-adjacent action anywhere in the codebase is *responding* to one the customer already raised (`DisputeService.respondToDispute`), never raising one themselves.
- **Notifications**: dispute-event push to the artisan; an `admin_alerts` doc created (`onDisputeCreated`/`_alertAdminDispute` triggers).

### `resolved`
- **Trigger**: admin only (`JobService.resolveDisputeWithRecord`) — writes the job status and updates the `disputes` doc's own status (`resolved` or `dismissed`, per a `dismiss` flag) atomically.
- **Rules**: `cur=='disputed' && nxt=='resolved' && isAdmin()`.

### `cancelled`
- **Trigger**: customer or artisan, from any of `requested`/`matched`/`inChat`/`paymentPending`/`escrowLocked`.
- **DB changes**: status, `cancelledBy`, `cancellationReason`, `cancelledAt`.
- **Rules**: matches the code exactly.

---

## Every mutation is audit-logged
`JobService._buildAuditEntry` writes an immutable entry to `jobs/{jobId}/auditLogs/{logId}` inside the same transaction as every status/field mutation — actor ID, actor role, action type, before/after status, before/after version, and a sanitized delta of what changed. Firestore rules make this subcollection permanently immutable (`allow update: if false; allow delete: if false`). No job mutation found anywhere in the codebase bypasses this.
