# Escrow Payout Automation — Implementation Report

Closes Critical Finding 1.1, tracked since the very first audit in this program: `escrow_releases` documents were created on job completion, but nothing ever consumed them to actually pay the artisan. This was the single most important unresolved item in the entire program.

## Read this before deploying anything

This is real-money infrastructure. I cannot run it, cannot call Paystack's live API from this environment, and cannot deploy Cloud Functions from here. Everything below was built by careful reading of the existing code and Paystack's documented API shapes, verified for **syntax** (`node -c functions/index.js` passes) and **internal consistency** with this codebase's own patterns — not verified end-to-end against a real transaction. Treat this as a careful first draft ready for staged testing (Paystack test mode, small real amounts) before any production payout, not as proven-correct.

---

## A bug found before writing any new code

Reading `_releaseEscrow` (the 48-hour auto-release scheduled function) directly: it marks the job `completed` and the payment `released` — but it **never created an `escrow_releases` document**. Only the customer-manual-confirmation path (`JobService.confirmComplete`, Dart client) did that. A payout consumer watching only `escrow_releases` creation would have silently never fired for any auto-released job — the job and payment records would say "released" while no transfer was ever attempted, and nothing would look broken until an artisan asked where their money was. Fixed by making `_releaseEscrow` create the same record the manual path already does, so both paths now funnel through one consumer.

## What was built

1. **`processEscrowRelease`** (new, Firestore-triggered on `escrow_releases` creation) — the actual payout: reads the job and payment record for the true paid amount, reads the artisan's bank details, resolves/verifies the account with Paystack before trusting it, creates or reuses a Transfer Recipient, and initiates the transfer. Marks the release `failed` with a specific reason at every failure point (no bank details, unverified account, recipient creation failure, transfer initiation failure) rather than leaving it silently stuck — and notifies the artisan in-app when they need to act (missing/bad bank details).
2. **`paystackWebhook` extended** to handle `transfer.success`/`transfer.failed`/`transfer.reversed` — the webhook, not the synchronous transfer-initiation response, is what marks a release `completed`. Same "webhook is authoritative" pattern this file already uses for `charge.success`.
3. **`_releaseEscrow` fixed** — see the bug above.
4. **Daily reconciliation sweep** — flags any release stuck in `pending`/`processing` past 2 hours into `admin_alerts` (the same collection disputes already alert into), so a silent failure gets a human's attention instead of vanishing.
5. **One new Firestore index** (`escrow_releases: status + requestedAt`) for the reconciliation sweep's query — added to `firestore.indexes.json`, not yet deployed (see below).

## What I could not verify — and why that matters

**Bank codes.** `bank_details_screen.dart` stores a free-text bank display name (`bankName`), not a Paystack bank code — Paystack's Transfer Recipient API requires the numeric code, not the name. I added a static lookup table for the app's exact 20 bank options, using my best knowledge of Nigeria's standard NIBSS bank codes. Confidence is genuinely uneven across that table: the traditional banks (GTBank, Zenith, UBA, Access, First Bank, etc.) use codes that have been stable and widely published for years — I'm fairly confident in those. The newer fintech entries (Kuda, Moniepoint, Opay, PalmPay) use different-format codes I'm less certain of. **I did not call Paystack's `GET /bank` list to confirm any of these** — that wasn't possible from this environment. The table is clearly commented as needing verification.

**The real safety net for this, not just a disclaimer**: before ever creating a Transfer Recipient, `_resolveAndVerifyAccount` calls Paystack's account-resolution endpoint and compares the bank's own record of the account holder's name against what the artisan typed. If a bank code is wrong, resolution will either fail outright or return a name that doesn't match — either way, the function aborts and marks the release `failed` rather than proceeding on an unverified guess. This doesn't make the bank-code table correct, but it does mean a wrong code fails safely instead of silently succeeding against the wrong account.

**Paystack Transfer API shapes** (recipient creation, transfer initiation, account resolution) — I have solid confidence in these; they're Paystack's stable, well-documented REST endpoints, structurally simpler and less prone to drift than a 20-entry bank-code table.

## Deployment steps I cannot do from here

- `firebase deploy --only functions` — to ship any of this code.
- `firebase deploy --only firestore:indexes` — for the new `escrow_releases` index (same outstanding gap as the Wallet feature's indexes from earlier — now three deployment items queued: Wallet's two payment indexes, plus this one).
- Paystack account setup: your Paystack account needs Transfers enabled (a separate capability from accepting payments, typically requiring business verification), and `PAYSTACK_SECRET_KEY` needs live-mode Transfer permission if this is meant to pay real artisans rather than run in test mode first.
- **Strongly recommended before any real payout**: run this against Paystack's test/sandbox mode first, with a test bank account, and manually confirm the resolved account name logic behaves as expected — the account-verification check is new code that has never executed once.

## Files changed
`functions/index.js` (the payout consumer, webhook extension, `_releaseEscrow` fix, reconciliation sweep, bank-code table, in-app notification helper), `firestore.indexes.json` (one new index).

## What this does not do
It does not touch milestone payments (`06-escrow-wallet.md`'s multi-milestone model still doesn't exist) — this pays out the single, whole-job amount, consistent with the "ship the simple case first" sequencing that document already laid out. It does not build the admin-facing Escrow Monitoring UI `10-admin-redesign.md` speced — the reconciliation sweep writes to `admin_alerts`, which exists as a collection but has no dedicated admin screen surfacing it yet.
