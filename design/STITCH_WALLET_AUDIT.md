# Stitch Wallet Audit — Group 8

Per the settled product decision: MVP simple wallet, no milestone payments. Money model is a single `PaymentModel` per job, `PaymentStatus` (`pending → processing → escrowHeld → released`, plus `refunded`/`failed`) — no separate escrow model exists, and none is being introduced.

---

## Current wallet features
`lib/screens/wallet/wallet_screen.dart` (already touched once in Group 7): role-aware (customer/artisan via `activeRole`), a dark summary card (In Escrow total + Total Spent/Paid Out), and a flat, unsegmented ledger list (`_LedgerRow`) showing status, date, amount, related job category, and — since Group 7 — the job's current `WorkflowGateService` phase. Real empty/loading/error states already exist.

## Missing features (this group's actual scope)
- **No grouping** — Task 2 asks for Active escrow / Completed / full history shown distinctly; today it's one undifferentiated list ordered by `createdAt`.
- **No artisan-specific earnings dashboard** — Task 3 wants Total earnings / Available balance / Pending escrow / Released earnings as distinct figures; today the artisan view only gets a relabeled version of the same two-stat customer summary card ("Paid Out" instead of "Total Spent").
- **No withdrawal-readiness signal at all** — nothing on this screen today tells an artisan whether their payout setup is complete.

## Available backend data
Everything Task 2/3 ask for is already real and queryable: `customerPaymentsProvider`/`artisanPaymentsProvider` (full `PaymentModel` history, already live-streamed), `jobStreamProvider` (job title/category, already used by `_LedgerRow`), `WorkflowGateService.describeStep` (phase text, already wired in). Bank-details completeness (`artisan_private/{uid}`: `bankName`/`accountName`/`accountNumber`) is stored and readable by the artisan (owner-only per rules) but has no client provider yet — added one, read-only, no new writes.

## Missing backend requirements
None for Tasks 2/3 — everything needed already exists. For Task 4 specifically: **nothing is missing** in the sense of "not built" — payout is fully automatic (see below) — but see the withdrawal-readiness findings for the one real gap (no client-readable signal of *why* a payout might fail).

---

## Task 4 — Withdrawal readiness audit

Traced the full payout path (`functions/index.js`):

1. Escrow releases (manual `confirmComplete` or the `autoReleaseEscrow` cron) → both write an `escrow_releases/{id}` document.
2. `processEscrowRelease` — a **Firestore-trigger** Cloud Function (fires on document creation, not client-callable) — consumes it, resolves/creates a Paystack Transfer Recipient from the artisan's stored bank details (`artisan_private`), and initiates a real Paystack Transfer.
3. The `transfer.success`/`transfer.failed`/`transfer.reversed` Paystack webhook updates the `escrow_releases` doc's final status and notifies the artisan.

**Answers**:
- **Is withdrawal implemented?** There is no separate "withdraw" action — payout is **automatic and push-based**. The moment a job's escrow releases, money is transferred to the artisan's bank account with no further step from them. A "Withdraw Funds" button (as shown in the Stitch mockups) would not correspond to anything real in this system — there's no balance sitting ready to be pulled.
- **Are bank details stored?** Yes — `artisan_private/{uid}`, collected via `bank_details_screen.dart`.
- **Automatic or manual?** Automatic (Cloud Function trigger), not manual.
- **What backend exists?** A complete, real transfer pipeline: bank-code mapping, account-name verification against Paystack's own resolve endpoint (aborts the transfer rather than sending to an unverified account), recipient caching, and webhook-driven status reconciliation. The code's own comments flag one honest caveat: the `BANK_CODES` table hasn't been verified against Paystack's live bank list from this environment — a real but narrow gap, already documented in the source, not something this pass needs to re-flag as new.

**Conclusion**: nothing to build labeled "Withdrawals coming soon" — that would misdescribe a system that already pays out automatically. The real gap is different: an artisan has no way to tell, before completing a job, whether their payout is even *set up* to succeed. **Implemented this pass**: a payout-readiness indicator on the Earnings screen — reads `artisan_private` (read-only, new provider, no new writes) and shows "Complete payout setup" linking to `bank_details_screen.dart` if bank details are missing, or a reassuring "Payouts are automatic" note if they're already on file. This is real data being surfaced, not new functionality.
