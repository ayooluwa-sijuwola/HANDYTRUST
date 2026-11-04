# Workflow Audit — Final Pre-Redesign Consistency Pass

Rewritten after this pass's changes: the chat payment gate now respects agreement confirmation, scheduling is a real sub-state (not just data fields), and the three overlapping timeline widgets are consolidated into one `WorkflowTimeline`. No visual redesign — this documents the corrected product flow the Stitch redesign will be built on top of.

## Current final workflow

### Customer

```
Post Job
   ↓                     [customer posts — status: requested]
Receive Quotes
   ↓                     [artisans submit quotes on the open job]
Accept Quote
   ↓                     [customer accepts one — status: matched]
Negotiation
   ↓                     [customer taps "Continue Negotiation" — status: inChat]
Agreement Confirmation
   ↓                     [customer confirms terms, artisan accepts]
Scheduling               [only for urgency == 'scheduled' jobs — skipped entirely for 'asap']
   ↓                     [artisan proposes a slot, customer confirms one]
Escrow Payment
   ↓                     [customer pays — status: paymentPending → escrowLocked]
Work Progress
   ↓                     [artisan works — status: inProgress]
Completion Confirmation
   ↓                     [artisan submits, customer confirms — status: submitted → completed]
Review
```

### Artisan

```
Verification
   ↓                     [approval + ID verification — gates quoting, not browsing]
Browse Jobs
   ↓                     [open jobs feed, filtered by category]
Submit Quote
   ↓                     [now gated: button disabled + reason shown if not yet eligible]
Selected
   ↓                     [customer accepts — status: matched]
Negotiation
   ↓                     [customer initiates — status: inChat]
Agreement Confirmation
   ↓                     [artisan reviews customer's confirmed terms, accepts or requests changes]
Scheduling               [only for urgency == 'scheduled' jobs]
   ↓                     [artisan proposes a slot]
Work
   ↓                     [status: inProgress, fine-grained progress stages]
Completion Proof
   ↓                     [artisan submits photos — status: submitted]
Payment
```

## Who acts at each stage, what moves it forward, what blocks it

| Stage | Who acts | Action that advances it | What blocks it |
|---|---|---|---|
| Post Job | Customer | Submit the job form | — |
| Receive Quotes | Artisan | Submit a quote | **Now enforced in the UI, not just rules**: `approvalStatus != 'approved'` or `verificationStatus` not verified disables the button with an explicit reason, instead of letting the artisan fill out the form and hit an opaque permission error |
| Accept Quote | Customer | Tap Accept on a quote | Only the job's customer; only while `status == requested` |
| Negotiation (start) | Customer | "Continue Negotiation" (Quote Accepted status card) | **Previously nothing could trigger this at all** — `matched → inChat` had no caller anywhere in the app; every matched job was permanently stuck. Fixed in this pass. |
| Agreement Confirmation | Customer, then artisan | Customer: "Confirm Agreement." Artisan: "Accept Agreement" or "Request Changes." | Customer cannot confirm without an accepted quote; artisan cannot act until the customer has confirmed; artisan cannot act on a job they're not the matched artisan for |
| Scheduling | Artisan proposes, customer confirms | Artisan: propose slots. Customer: confirm one. | Only relevant for `urgency == 'scheduled'` jobs — 'asap' jobs skip this stage entirely, automatically satisfied |
| Escrow Payment | Customer | "Pay Into Escrow" | **Now checked in three places, not one**: `JobService.canInitPayment`, `firestore.rules`' `inChat → paymentPending` transition, and (new in this pass) the chat screen's payment shortcut itself — blocked until `agreementStatus == confirmed` AND (for scheduled jobs) `schedulingStatus == scheduled` |
| Work Progress | Artisan | Advance through progress stages; "Submit Completion" | Only the matched artisan; only while `status == inProgress` |
| Completion Confirmation | Customer | "Confirm & Release Payment" (or "Raise Dispute") | Only the job's customer; 48h auto-release if they never respond |
| Review | Customer | Leave a rating | Only on a `completed` job, only the customer, once per job |

## What this pass fixed vs. what it deliberately left alone

**Fixed:**
- Chat's "Pay Now" button is now agreement-aware — shows "Agreement Required" with an explanation and two real actions (View Agreement, Continue Negotiation) instead of just being available or silently failing.
- Scheduling is now a real, named sub-state (`SchedulingStatus`) that gates payment for jobs that need one, instead of being optional data fields with no workflow meaning.
- Three overlapping timeline widgets (`JobProgressTracker`, `JobTimelineWidget`, `JobProgressTimeline`) are now one `WorkflowTimeline`, which is also the first timeline component aware of the agreement/scheduling sub-stages — the old three predated both and had no way to show them.

**Deliberately not done, and why:**
- Scheduling (`proposeAppointmentSlots`/`confirmAppointmentSlot`) is **not** gated to only be possible after agreement confirmation. Negotiating timing alongside price during `inChat` is a normal, common pattern (e.g. "can you come Tuesday?" discussed before price is finalized) — blocking it until confirmation would remove working flexibility the app already has, for no functional requirement anyone asked for. The *payment* gate is what actually enforces the intended ordering; the underlying scheduling actions stay available whenever they're naturally useful.
- No new `JobStatus` values were added anywhere in this pass — `SchedulingStatus` follows the exact same sub-state pattern as `AgreementStatus`/`JobProgressStage`, per the explicit instruction.
- The "asap jobs skip scheduling entirely" behavior is a judgment call, not something explicitly specified — without it, urgent jobs (which have no reason to schedule a specific future slot) would have been newly blocked from ever reaching payment. Flagged here plainly since it's an interpretation, not a literal instruction.

## Remaining known gaps (unchanged from the prior audit, still real, still not addressed — out of scope for a consistency pass)

- Two payment entry points (Job Detail, Chat) still don't share one code path for the gate check — they now both correctly enforce it, but via separate implementations rather than one shared component.
- "Requested" status still has no explicit customer-side status card, relying on the quote inbox to communicate the waiting state — reasonable today, worth revisiting once visual redesign unifies every stage's presentation.
