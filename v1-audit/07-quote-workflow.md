# Part 7 — Quote Workflow

Owned entirely by `QuoteService` (`lib/core/services/quote_service.dart`) for everything except the accept action's job-mutation half, which is correctly delegated to `JobService` (documented in that service's own code comment: "the quote outcome is inseparable from the job's transition... if these were two writes, a failure between them could leave the job matched with competing quotes still 'pending'").

## Data model
`jobs/{jobId}/quotes/{artisanId}` — **document ID is literally the artisan's UID**, which structurally enforces "one active quote per artisan per job" at the data-model level: a second submission overwrites the same document rather than creating a competing one, with no possibility of an artisan accidentally having two live quotes on the same job.

Fields: `laborCost`, `materialsCost` (amount = the sum, stored redundantly for backward compatibility), `durationDays`, optional `notes`, `status`, plus a **denormalized snapshot** of the artisan's name/rating/trust tier/verification/trust score taken at submission time — this avoids an N+1 read when the customer's quote-inbox UI renders a list of quotes, at the cost of that snapshot going stale if the artisan's real stats change after the quote is submitted (no refresh mechanism found for already-submitted quotes).

## Who creates
Any artisan whose account satisfies `isArtisanEligible()` (approved + `id_verified`/`trusted`) — enforced by rules, not just the client. `submitQuote` first reads the artisan's own profile to build the denormalized snapshot, then writes.

## Who edits
The artisan, and only while their own quote is `status: 'pending'` — same `submitQuote` method handles both create and edit (detects an existing doc and preserves its original `createdAt`).

## Who deletes
**No delete exists.** Confirmed directly: `firestore.rules`' quotes subcollection has `allow delete: if false` unconditionally — quotes are never deleted, only transitioned through statuses (`withdrawn`, `closed`, `rejected`).

## Acceptance
`QuoteService.acceptQuote` — reads every currently-`pending` quote on the job, then calls `JobService.acceptQuote` with the full competing-quote-ID list. That method, in one transaction: transitions the job `requested → matched`, sets `artisanId`, marks the accepted quote `accepted`, and marks every competing quote `closed`. A code comment documents a known, accepted edge case: a quote submitted *after* the competing-quotes snapshot was taken but before the transaction commits won't be closed by this pass — the comment states this self-resolves because the UI only ever shows quotes for jobs still in `requested` status, so a late quote against an already-matched job becomes invisible on the next read rather than a lingering inconsistency.

## Rejection
`QuoteService.rejectQuote` — customer declines a single quote without accepting any other. Quote-only write, no job mutation, only valid while the quote is still `pending`.

## Negotiation
Not part of the quote document itself — post-acceptance price negotiation happens via the job's `agreedAmount` field (chat-based, see Part 9) and, as of the most recent work in this codebase, is formally closed out by the Agreement Confirmation checkpoint (Part 6), not by any further quote-document mutation. A quote is a one-time initial offer; everything after acceptance is job-level, not quote-level.

## Expiration ❌ — does not exist
No expiry timestamp, no scheduled function, and no UI countdown was found anywhere for a pending quote. A quote submitted today and never acted on remains `pending` indefinitely unless the customer explicitly accepts/rejects it or the artisan withdraws it.

## Notifications (all confirmed by direct reading of `QuoteService`)
- `quote_received` → customer, on a new (not edited) quote submission.
- `quote_withdrawn` → customer, on withdrawal.
- `quote_rejected` → artisan, on single-quote rejection.
- `quote_accepted` → the winning artisan, on acceptance. **No notification found for the artisans whose competing quotes were closed as a side effect of another quote's acceptance** — they are not told their quote lost; they would only discover it by revisiting the job or noticing its `status` field changed.

## Withdrawal
`QuoteService.withdrawQuote` — artisan-only, only while `pending`. Sends `quote_withdrawn` to the customer.
