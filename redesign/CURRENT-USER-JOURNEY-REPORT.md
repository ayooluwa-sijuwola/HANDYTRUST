# HandyTrust — Current Customer & Artisan Workflow Report

Traced directly from the running code — `router.dart`, `job_service.dart`'s state machine, `firestore.rules`, and every screen in the flow. This describes **what the app actually does today**, not a future spec.

**Updated to reflect the Negotiation Agreement Confirmation feature** (see `AGREEMENT-CONFIRMATION-IMPLEMENTATION-REPORT.md` for the full implementation record). The previous version of this document described the post-quote-acceptance stage as "negotiate + schedule" — that framing is gone; §2 below documents the real checkpoint that now sits between negotiation and scheduling.

---

## 1. The shared backbone: one job, one state machine

Every customer and every artisan interaction ultimately routes through a single, server-enforced state machine (`JobService.allowedTransitions`, mirrored in `firestore.rules`). This is the logic everything else hangs off of:

```
requested → matched → inChat → paymentPending → escrowLocked → inProgress → submitted → completed
                                                        ↓                        ↓
                                                    disputed ──────────────→ resolved
                                              (from escrowLocked, inProgress, or submitted)

Any of requested/matched/inChat/paymentPending/escrowLocked can also go → cancelled
```

**Why it's built this way**: each arrow is a one-directional gate — a job can never skip a step or go backward. `requested→matched` can only be triggered by a customer accepting a quote. `escrowLocked→inProgress` can only happen after real money has actually moved (Paystack webhook, not a client claim). `submitted→completed` requires either the customer's explicit confirmation or the 48-hour auto-release timer. This is what makes the "trust" in HandyTrust structural rather than just a marketing word: neither party can unilaterally force the job past a checkpoint the other party controls.

### `JobStatus` is unchanged — `agreementStatus` is a sub-state, not a new top-level status

The Agreement Confirmation feature added **zero** new values to `JobStatus`. `matched`, `inChat`, and `paymentPending` are exactly what they were before. What's new is a second, independent field — `agreementStatus` — that only has meaning *while* `status == inChat`:

```
JobStatus.inChat
  contains → agreementStatus: negotiating | pendingArtisanConfirmation | confirmed | changesRequested
```

This mirrors a pattern the codebase already had: `JobProgressStage` (accepted → onTheWay → workStarted → ... → completed) is a fine-grained sub-state that only has meaning while `status == inProgress`, and it doesn't touch `JobStatus` either. `agreementStatus` does for `inChat` exactly what `progressStage` already does for `inProgress`.

**Why this was chosen over adding new top-level statuses** (e.g. `AGREEMENT_PENDING`, `AGREEMENT_CONFIRMED` as their own `JobStatus` values): every screen, every Firestore rule, every composite index, and every job document already in the database is keyed on the current 11-value `JobStatus` enum. Renaming or expanding it would be a breaking change across the entire app for a distinction that's genuinely local to one status (`inChat`) — the sub-state pattern extends the existing architecture the same way `progressStage` already proved out, rather than duplicating it with a second, parallel state-machine concept living at the top level.

**One naming note worth flagging plainly**: the stored/serialized value is `pendingArtisanConfirmation` (camelCase), matching this codebase's existing enum-serialization convention (`JobStatus`, `JobProgressStage`, and `QuoteStatus` all serialize via bare `.name`, which is camelCase — e.g. `escrowLocked`, `onTheWay`). Some references to this feature use `pending_artisan_confirmation` (snake_case) — that spelling does not exist anywhere in the actual database or code; see §12 (Report) for why this wasn't silently "corrected" to match without a note.

---

## 2. The Agreement Confirmation Checkpoint

### Purpose
Turn "we're done negotiating" into an explicit, two-party, state-controlled action — not an inference drawn from reading a chat thread.

### Why it exists
Before this feature, a job could move from `inChat` straight to payment at any time, with no record of what was actually agreed beyond whatever the two parties happened to type in chat. Chat history is unsafe as the basis for a trust marketplace: it's not structured, not auditable in a targeted way, and easy to misremember or dispute later ("I never agreed to that price"). The checkpoint replaces "trust the conversation" with "trust an explicit, timestamped, field-locked confirmation from both parties" — consistent with how every other consequential step in this app already works (quote acceptance, escrow lock, completion confirmation are all explicit actions, never inferred).

**Negotiation happens in chat. Chat alone does not advance the job.** A customer and artisan can go back and forth on price and scope indefinitely via the existing chat/`agreedAmount` negotiation mechanism — none of that, by itself, changes `agreementStatus` or moves the job forward. Only the explicit actions below do.

### Customer actions
- **Confirm Agreement**: available once the job is `inChat` and a quote has been accepted (there is always an assigned artisan by this point — see §4's business rules). Submits a locked scope-of-work summary and (optionally) an updated price, moves `agreementStatus → pendingArtisanConfirmation`, and notifies the artisan.
- While `pendingArtisanConfirmation`, the customer sees a **waiting state** — there is nothing further for them to do until the artisan responds.
- If the artisan requests changes, the customer can revise the summary and confirm again.

### Artisan actions
- **Review**: once the customer confirms, the artisan sees a read-only summary — service, description/scope, agreed price, schedule (if one exists yet), and location.
- **Accept Agreement**: moves `agreementStatus → confirmed`. The job may now proceed toward payment.
- **Request Changes**: requires a reason (free text). Moves `agreementStatus → changesRequested` and notifies the customer. This does not touch any field the customer owns — only the artisan's own confirmation flag resets.

### Allowed transitions
```
negotiating         → pendingArtisanConfirmation   (customer confirms)
changesRequested    → pendingArtisanConfirmation   (customer re-confirms after revising)
pendingArtisanConfirmation → confirmed             (artisan accepts)
pendingArtisanConfirmation → changesRequested      (artisan requests changes)
```

### Blocked transitions (enforced in both `JobService` and `firestore.rules` — not just the UI)
- Customer cannot confirm while `agreementStatus` is already `pendingArtisanConfirmation` or `confirmed` — no double-submission, no silently overwriting a confirmed agreement.
- Artisan cannot act at all while `agreementStatus` is `negotiating` or `changesRequested` — there's nothing for them to accept or reject until the customer has actually confirmed something.
- Neither party can write the *other* party's confirmation fields — a customer's Firestore write can never touch `agreementConfirmedByArtisan`, and an artisan's write can never touch `agreementConfirmedByCustomer`. This is a field-level Firestore rule, not an app-layer convention.

---

## 3. Entry & identity — both roles start here

1. **Register** (`/register`) — pick a role (customer or artisan) via two tappable tiles; same field set (name, email, city, password) regardless of choice. This only sets `roles: [selectedRole]` on the profile — it doesn't branch the form.
2. **Verify email** (`/verify-email`) — blocking gate. The app polls Firebase every 4 seconds; the moment verification lands, the router's redirect logic notices on its own and sends the user to `/home`.
3. **Artisan-only extra step**: a new artisan profile doesn't exist until they've completed `/register/artisan` (category, skills, bio, business info). If they reach the artisan home tab without one, `ArtisanHomeTabContent` auto-redirects them there.
4. **Dual-role users**: on their first `/home` visit, they're interstitially sent to `/role-select` to explicitly choose which mode they're in for this session.

**Why**: email verification and artisan-profile-completion are both hard gates in the router's `redirect:` callback, not screen-level checks.

---

## 4. The navigation shell

Once past the gates above, both roles land in the same 4-tab shell (`MainShellScreen`), just with different content per tab:

| Tab | Customer | Artisan |
|---|---|---|
| **Explore** | Home feed — hero "post a job" CTA, category grid, nearby artisans, active-jobs preview | Their own dashboard — pending-approval/verification banners, availability toggle, stats, quick actions |
| **My Tasks** | `AllJobsScreen`, filtered to jobs where they're the customer | Same screen, filtered to jobs where they're the matched artisan |
| **Wallet** | Payment history — amounts currently in escrow, total spent | Payment history — amounts currently in escrow, total paid out |
| **Profile** | Account menu, role switch, settings, sign out | Same, plus artisan-specific settings |

Chat is reached via a header icon next to the notification bell, or contextually from within a specific job.

---

## 5. Customer journey, start to finish

**A. Post a job** (`/request`) — category, description, photos, budget, urgency, optional scheduled date. Job is created at `status: requested`.

**B. Receive quotes** — the job becomes visible to any approved+verified artisan in that category. Multiple artisans can independently submit quotes (`jobs/{jobId}/quotes`, one per artisan).

**C. Compare and chat with artisans** — the customer can open a chat thread with each quoting artisan *before* committing to any of them. Rules specifically isolate these pre-match conversations so competing artisans can't see each other's messages.

**D. Accept a quote** — `status: requested → matched`. Only the customer can trigger it, only from `requested`, and it locks in one artisan.

**E. Negotiate terms** — `status: matched → inChat`. Price can be discussed and revised via chat (`agreedAmount` is editable during this state). **This step, by itself, does not move the job forward** — see §2.

**F. Confirm Agreement** (the gate, §2) — once satisfied, the customer submits the agreed scope and price and taps Confirm Agreement. `agreementStatus → pendingArtisanConfirmation`.

**G. Wait for artisan confirmation** — no customer action available; the artisan must Accept or Request Changes.

**H. Schedule work** — the artisan proposes appointment slots and the customer confirms one (`appointmentSlots`/`confirmedAppointment`). **Factual note**: in the current implementation, scheduling is available at any point while `status == inChat` — it is *not* hard-gated to only become available after `agreementStatus == confirmed`. The step is placed here to match the intended flow, but a customer and artisan can propose/confirm a slot before, during, or after the agreement checkpoint; whatever schedule exists at confirmation time is simply what gets referenced in the locked summary. See §12 for why this is flagged rather than silently presented as strictly sequenced.

**I. Fund escrow** — `status: inChat → paymentPending → escrowLocked`, and only reachable once `agreementStatus == confirmed` (§4's business rules). The customer pays via Paystack; the webhook (not the client) is what actually flips the job to `escrowLocked`.

**J. Track progress** — once the artisan taps "On My Way," the customer sees a live position + ETA. Progress also advances through discrete stages that the artisan sets manually.

**K. Confirm completion** — `status: submitted → completed`, triggered by the customer confirming the work is done, *or* automatically after 48 hours if they never respond.

**L. Review artisan** — after completion, the customer can leave a star rating + written review.

**Escape hatch at any point from `escrowLocked` onward**: either party can raise a dispute, which freezes the job at `disputed` until an admin resolves it.

---

## 6. Artisan journey, start to finish

**A. Browse jobs** — the Open Jobs Feed shows every job still at `status: requested` in their category, visible to *any* registered artisan regardless of approval state. Submitting an actual quote requires the full approved+verified gate.

**B. Submit quote** — one active quote per artisan per job (`jobs/{jobId}/quotes/{artisanId}`).

**C. Get selected** — if their quote is accepted, `status: requested → matched`, and the job's `artisanId` is now permanently theirs (this is what makes "artisan cannot accept an agreement they were not selected for" enforceable — see §4).

**D. Negotiate terms** — `status: matched → inChat`. Same chat/`agreedAmount` mechanism as the customer's step E. **Chat alone does not advance the job.**

**E. Review customer agreement** — once the customer confirms (§2), the artisan sees a read-only summary: service, description, agreed price, schedule, location.

**F. Accept Agreement** — `agreementStatus → confirmed`. The job may now proceed to scheduling/payment. (Or **Request Changes** — reason required, returns to negotiating, customer is notified.)

**G. Schedule work** — proposes appointment slots for the customer to confirm. Same factual note as §5H: not strictly gated to happen only after Accept Agreement in the current implementation.

**H. Start work** — once escrow is locked, the artisan taps "I'm On My Way," which starts a live-location share and begins the fine-grained progress-stage tracker.

**I. Submit completion proof** — uploads photos and moves the job to `status: submitted`. This hands the completion decision to the customer (or the 48-hour timer) — the artisan alone can never mark their own job complete.

**J. Receive payment** — once the customer confirms (or the timer fires), the job hits `completed` and an `escrow_releases` record is created. **This is where the journey currently stops short of its own promise — see §11.**

**K. Build Trust Score** — completed/cancelled job counts, ratings, and dispute history all feed the server-computed Trust Score. **See §11 — this does not yet influence search ranking.**

---

## 7. Where the two journeys structurally depend on each other

- Neither party can skip the other's action — every forward transition requires a specific party's explicit trigger. The Agreement Checkpoint is the clearest example added by this feature: the artisan cannot move the job forward without the customer confirming first, and the customer cannot start payment without the artisan accepting.
- Money only moves in the direction the state machine allows: it can only lock and only release forward — never sideways.
- Chat, quotes, agreement confirmation, and appointment negotiation are all scoped to *this specific job* — there's no persistent "conversation" independent of a job.

---

## 8. Business rules (Agreement Confirmation)

Enforced in both `JobService` (the pure `canConfirmAgreement`/`canRespondToAgreement`/`canInitPayment` predicates) and `firestore.rules` (the server-side mirror) — not UI-only conventions:

- **Customer cannot confirm agreement without an accepted quote.** Structurally, `inChat` is unreachable without one (quote acceptance sets `artisanId` and moves the job to `matched` first) — this is also explicitly re-checked as a defensive guard.
- **Customer cannot confirm while a confirmation is already pending or already confirmed** — no double-submission, no overwriting a confirmed agreement by re-running the same action.
- **Artisan cannot accept (or request changes on) an agreement unless they are the job's selected artisan** — enforced by matching the caller's UID against the job's own `artisanId`, the same field quote acceptance set and nothing in this feature can reassign.
- **Artisan cannot act until the customer has confirmed** — no accept/reject is possible while `agreementStatus` is `negotiating` or `changesRequested`.
- **Payment cannot begin until `agreementStatus == confirmed`** — enforced twice: `JobService.initPayment` checks it inside its own transaction, and `firestore.rules`' `_isValidJobTransition` checks it independently for the `inChat → paymentPending` transition. Either layer alone would block an unconfirmed payment attempt.
- **Confirmed agreement terms cannot be modified.** Once `agreementStatus == confirmed`, the negotiated-price rule (`agreedAmount`) no longer permits edits from either party, and `agreementScope` has no write path at all outside the (now-blocked) confirm action.
- **Customer cannot write the artisan's confirmation fields, and the artisan cannot write the customer's** — a field-level Firestore rule, not just something the UI happens not to expose.
- **Every agreement state change is captured in the job's immutable audit log** — the same transactional audit-log mechanism every other job mutation already uses; no separate auditing system was built.

---

## 9. Migration note

- **Existing `inChat` jobs are safe.** All 8 new fields are optional; a job document with no `agreementStatus` at all is read as `negotiating` everywhere — both in the Dart model (`?? AgreementStatus.negotiating`) and in Firestore rules (`.get('agreementStatus', 'negotiating')`, never a bare field access that would error on a missing field). No backfill was required or performed.
- **However: jobs entering payment after this feature's rules are deployed require agreement confirmation, with no exception for jobs already mid-negotiation.** A job that was sitting at `inChat` before this shipped, with an entirely informal chat-based understanding already reached under the old system, is now blocked from `paymentPending` until it goes through the real Confirm Agreement / Accept Agreement flow.
- **Existing informal chat agreements do not automatically count as confirmed.** There is no migration step that infers `agreementStatus: confirmed` from prior chat content — deliberately: the entire point of this feature is that chat history is not an acceptable substitute for an explicit confirmation, so retroactively treating chat as confirmation would undermine the feature on day one.
- **The Firestore rules changes require deployment** (`firebase deploy --only firestore:rules`) to take effect in the live project. As of this writing that deployment has not been run from this environment — the same operational gap already flagged for the Wallet feature's composite indexes.

---

## 10. Future considerations

- **Agreement expiry.** There is currently no timeout on `pendingArtisanConfirmation` — an artisan can leave a confirmed-by-customer agreement unanswered indefinitely, with the customer stuck waiting and no automatic path forward. The app already has a precedent for exactly this kind of window (escrow's 48-hour auto-release) — a similar expiry (e.g., 24–48h) that either nudges the artisan, reverts the agreement to `negotiating`, or prompts the customer to consider other options would close a real gap this feature currently leaves open.
- **Reopening quotes if the artisan does not respond.** Related to expiry: today, once a quote is accepted, every competing quote is closed (`QuoteService.acceptQuote`), and there is no path back to that pool if the selected artisan goes silent — the customer's only options are to keep waiting or cancel the job outright. Letting a customer "reopen" quoting after a non-responsive artisan is a real product improvement, but a nontrivial one: it would mean either resurrecting closed quotes or restarting quote collection, neither of which the current quote lifecycle supports, and is a genuine architectural decision, not a small addition.
- **Dispute handling around agreed terms.** A dispute today (`disputed` status) has no structural connection to the locked agreement summary this feature now produces — an admin resolving a dispute still has to reconstruct what was agreed from chat history and the job's raw fields, which is exactly the problem this feature solved for the two original parties but not yet for admin dispute resolution. Surfacing the confirmed `agreementScope`/`agreedAmount`/schedule directly in the dispute and admin-resolution views would extend this same trust-checkpoint value to the one place in the app that most needs authoritative terms: adjudicating a disagreement.

---

## 11. Notable gaps still open in this flow (kept factual — none of these are complete)

- **Escrow payout automation is still missing.** `escrow_releases` records are created on completion, but nothing currently consumes them to trigger an actual Paystack transfer. This remains the single largest gap between what the journey *implies* ("receive payment") and what the code *does* — unchanged by this feature and not claimed otherwise anywhere in this document.
- **The Wallet tab reads real payment records but is not milestone-aware.** It shows a job's payment as one line, not a phased breakdown — that model doesn't exist in the data yet. Not redesigned or completed by this feature.
- **Trust Score does not yet drive artisan ranking in discovery/search.** It is computed and stored correctly server-side, but the matching/ranking query does not yet read it. Not changed by this feature.

These three gaps predate the Agreement Confirmation feature and are unaffected by it — flagged here explicitly so this document never reads as claiming any of the three is done.

---

## 12. Report — documentation update

### Summary of documentation changes
Replaced the single vague "Negotiate & schedule" step (customer §5E / artisan journey's old §C) with the real sequence now enforced in code: **Negotiation (chat) → Agreement Confirmation Gate → Scheduling**, and made explicit that chat alone never advances the job — only the Confirm Agreement / Accept Agreement / Request Changes actions do. Added a new dedicated section (§2) documenting the checkpoint's purpose, rationale, per-role actions, and allowed/blocked transitions. Updated the state-machine section (§1) to state plainly that `JobStatus` did not change and to explain the sub-state design choice, including a note on the actual (camelCase) stored value versus the snake_case spelling used in the source task description. Added §8 (business rules), §9 (migration note), and §10 (future considerations) as new sections. Renumbered every subsequent section to keep the document in a single coherent read order. Preserved and reinforced the existing "don't overclaim" caveats — retitled as §11 to make clear none of the three flagged gaps (escrow payout, Wallet, Trust Score ranking) are described as complete anywhere in the document.

### Sections modified
- §1 — extended (state machine + new sub-state explanation)
- §2 — new (Agreement Confirmation Checkpoint)
- §5 (was §4) — customer journey steps E–I rewritten
- §6 (was §5) — artisan journey steps C–G rewritten
- §7 (was §6) — one sentence added referencing the checkpoint as a concrete example
- §8 — new (business rules)
- §9 — new (migration note)
- §10 — new (future considerations)
- §11 (was §7) — retained, reworded slightly to explicitly state "none of these are complete" per the requirement not to overclaim
- All other sections (§3–4, entry/nav) — unchanged, renumbered only

### Inconsistencies found between documentation and current code
1. **Naming**: the task description that drove this feature's implementation used `pending_artisan_confirmation` (snake_case). The actual stored/serialized value, consistent with every other enum in this codebase, is `pendingArtisanConfirmation` (camelCase). Documented as-is in §1 rather than silently changed to match the snake_case spelling, since the camelCase value is what's actually in the database and code.
2. **Scheduling is not actually gated behind the Agreement Checkpoint.** The customer/artisan journey diagrams (both the one driving this update and the original feature request) present `Confirm Agreement → Wait for confirmation → Schedule work` as a strict sequence. In the real implementation, `proposeAppointmentSlots`/`confirmAppointmentSlot` have no dependency on `agreementStatus` at all — scheduling has been and remains available at any point during `inChat`, independent of the agreement checkpoint's state. Documented honestly in §5H/§6G rather than presented as strictly sequenced, since the instruction was to document the architecture that exists, not the one implied by the diagram.
3. **Everything else checked out.** The business rules, blocked transitions, and migration behavior described in §8/§9 all match the implementation verified by `flutter analyze` and the 24 passing unit tests in the prior turn — no other drift found.

### Recommended next implementation priority
Of the three gaps restated in §11, **escrow payout automation** is the one this feature's own migration note (§9) makes more urgent, not less: this feature just added a real, enforced checkpoint that makes the *path to payment* trustworthy — but the payment itself still doesn't reach the artisan's bank account at the end of that path. Shipping a more trustworthy on-ramp to a promise the backend still doesn't keep widens the gap between what the app *asks the artisan to trust* and what it *actually delivers*, rather than narrowing it. That was the top priority before this feature and remains the top priority after it.
