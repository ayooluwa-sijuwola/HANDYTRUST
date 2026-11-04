# Stitch Payment Audit — Group 7

Per the now-settled product decision, HandyTrust stays job-first — no direct-booking wizard. The Stitch "Cost Breakdown" / "Lock Funds in Escrow" step and "Escrow Protection Active" banner are still valid *visual* references for the existing lump-sum Payment screen; the 3-step Details→Schedule→Payment wizard those mockups were embedded in is not built, per the earlier decision.

---

## Screen / state inventory

### Escrow payment (initiation)
**Current file**: `lib/screens/payment/payment_screen.dart`
**Current implementation**: amount field (pre-filled from `job.agreedAmount`), 5% platform-fee breakdown, "Lock Funds in Escrow" button → `escrowNotifierProvider.initPayment` → Paystack `initializeTransaction`. Already had a compact "Escrow Protected" banner.
**Stitch equivalent**: the Cost Breakdown / Lock Funds step, visually.
**Gap (Task 2)**: the old banner was one sentence — didn't answer what escrow is, why it's held, when it releases, who can release it, or what happens in a dispute. **Fixed**: replaced with a 5-fact educational card covering exactly those points, always visible (not collapsed), sourced from real existing behavior (`_DisputeCountdownBanner`, `JobService`'s completion-confirmation transition, the dispute flow) — except one fact was deliberately written *without* a specific number, see the bug below.

### Payment processing / Payment success / Payment failure
**Current file**: `lib/screens/payment/payment_webview_screen.dart`
**Current implementation (before this pass)**: real, correct outcome handling — `verifyTransaction`'s result was never assumed on error (a prior fix already removed a "treat any exception as success" fallback). But the UI response was a `SnackBar` + immediate navigation for both outcomes — functionally correct, not "polished."
**Fixed**: added `_PaymentResultView`, a full-screen result state (icon, headline, explanation, single action) for both success and failure, shown before navigating away. `verifyTransaction`'s call and both outcome branches are untouched — this only changes how the same two outcomes are presented.
**Processing state**: already existed (a "Verifying payment…" overlay) — untouched, already adequate.

### Escrow locked / Awaiting completion / Awaiting customer confirmation
**Current file**: `job_detail_screen.dart`, via `WorkflowGateService.describeStep`
**Current implementation**: already correct and complete — `escrowLocked` ("Payment Complete" phase, role-aware description, real "Start Job" action for the artisan), `inProgress` ("Job In Progress"), `submitted` ("Work Submitted" / waiting-on text, real confirm/dispute actions for the customer). No changes needed; confirmed by re-reading, not assumed.

### Auto-release countdown
**Current file**: `_DisputeCountdownBanner` in `job_detail_screen.dart`
**Current implementation**: counts down `job.disputeWindowEndsAt`, shown while `submitted`. Already exists, already real.
**A real bug found while writing the escrow-education copy** (see below) — the countdown this banner shows does not match what actually releases the funds.

### Payment released
**Current file**: `job_detail_screen.dart`, `JobStatus.completed` branch
**Gap (Task 3)**: this branch previously showed a "Leave a Review" button for the customer and **nothing at all** for the artisan — no confirmation that payment had actually reached them. **Fixed**: added an inline `WorkflowStatusCard` (same pattern the `submitted` case already used, not a `WorkflowGateService` change — `describeStep` collapses completed/disputed/resolved/cancelled into a generic 'Closed' phase, which was never meant to be the last thing either party sees) confirming "Payment Released" for both roles.

### Transaction history
**Current file**: `lib/screens/wallet/wallet_screen.dart` (`_LedgerRow`)
**Gap (Task 5)**: showed status, date, and amount, but not the related job or the job's current workflow stage. **Fixed**: rows now also show the job's category (via `jobStreamProvider`, already-existing data) and workflow phase (via `WorkflowGateService.describeStep`, same source every other redesigned screen uses) — no new wallet functionality, no milestone data invented, still built entirely against the real single-payment `PaymentModel`.

---

## Backend gap discovered — auto-release timing doesn't match what the UI promises

While writing the "when is it released" fact for the escrow-education card, I checked what actually drives the automatic release, since I didn't want to put a specific number in front of a paying customer without confirming it. Found a real discrepancy between two different pieces of the system:

- **What the UI shows**: `_DisputeCountdownBanner` counts down `job.disputeWindowEndsAt`, which `JobService._timestampsForStatus` sets to **14 days from the moment the job is marked `submitted`** (`job_service.dart` line ~1019).
- **What actually releases the funds**: the scheduled Cloud Function `autoReleaseEscrow` (`functions/index.js`, runs hourly) releases any job where `status == 'submitted' AND autoReleaseAt <= now`. `autoReleaseAt` is set to **48 hours from the moment escrow is locked** (`job_service.dart` line ~1013, mirrored in `functions/index.js`'s `_lockEscrow`) — a different field, set at a different (earlier) pipeline stage, and never recomputed when the job later reaches `submitted`.

The practical effect: if an artisan takes longer than 48 hours between escrow being locked and marking the job `submitted` — which is normal for any job that isn't finished same-day — `autoReleaseAt` has already passed by the time `submitted` is reached. The very next hourly run of `autoReleaseEscrow` will release the funds, while the customer-facing banner is telling them they have up to 14 days left to review and dispute. The 14-day figure is not enforced anywhere server-side; only the 48-hour-from-lock figure is.

**Not fixed in this pass** — `JobService` and Cloud Functions are both explicitly off-limits for Group 7. Flagging it here because it's a real correctness problem in a money-handling flow, not a cosmetic one, and it directly blocked writing the escrow-education card honestly: the "When is it released?" fact was written *without* a specific number rather than repeating either the wrong-in-practice 14-day claim or introducing a new, unreviewed claim of my own. This needs a product/engineering decision (most likely: recompute `autoReleaseAt` from `disputeWindowEndsAt` when the job transitions to `submitted`, so one real deadline drives both the Cloud Function and the UI) before either number can be safely stated to a customer.

No other missing backend support was found — every other state in this audit is backed by real, working data.
