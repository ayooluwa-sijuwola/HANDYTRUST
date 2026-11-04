# Payment Safety Hardening Report — Phase 12.5

No UI redesigned, no unrelated workflow modified. Companion document: `design/PAYOUT_RACE_CONDITION_AUDIT.md` (full trace).

---

## 1. Root cause

Two independent, compounding gaps in `functions/index.js`'s `_releaseEscrow` (the 14-day auto-release path):

1. **No transaction, no status precondition** — unlike `_lockEscrow` (the escrow-lock path, already correct) and `JobService.confirmComplete` (the customer-manual release path, already transactional), `_releaseEscrow` read the job with a plain `.get()` and wrote with a plain `.update()`, never re-checking that the job was still `submitted` at write time.
2. **Auto-generated `escrow_releases` document IDs** in *both* creation paths — nothing about the document ID prevented two separate documents from existing for the same `jobId`. `processEscrowRelease` (the Firestore trigger that initiates a real Paystack Transfer) fires unconditionally on every new document in that collection, with no check for "has this job already been paid."

If a customer manually confirmed a job in the same narrow window the hourly auto-release cron was processing that same job, both paths could each create their own release document, and both would trigger a separate real Paystack Transfer for the same job — a genuine duplicate payout of real money.

## 2. Fix implemented

**Single mechanism, applied at both creation sites, per the task's "do not duplicate payout logic" requirement**: the `escrow_releases` document ID is now the `jobId` itself (not an auto-generated ID), and both creation paths check-then-create inside a Firestore transaction.

- `JobService.confirmComplete` (Dart): `_db.collection('escrow_releases').doc(jobId)` instead of `.doc()`; the transaction now also `tx.get(releaseRef)`s and throws `JobStateConflictException` if it already exists, before ever writing.
- `_releaseEscrow` (Node.js, auto-release): rewritten to wrap the job read, release-doc read, job-status write, and release-doc write in one `db.runTransaction`, mirroring `_lockEscrow`'s existing correct pattern. Reads both the job and the release doc, bails out cleanly (no error, just a log line) if the job isn't `submitted` or the release doc already exists.

Two transactions racing to create the *same document ID* is exactly the scenario Firestore's optimistic-concurrency transaction retry is designed to make safe — this is a structural guarantee enforced by the database, not a timing assumption. Whichever transaction commits first wins; the other's transaction detects the conflict, retries, re-reads, and correctly sees the release now exists.

**Defense in depth, Task 3**:
- `processEscrowRelease` now atomically claims the release document (`pending` → `processing`) as its very first action, inside its own transaction, before any Paystack API call. A second invocation of the same function for the same document — a platform-level retry, or any other reason it might fire twice — finds the document no longer `pending` and exits immediately, before any money moves.
- `paystackWebhook`'s `transfer.success` handler now checks the release isn't already `completed` before sending the artisan's "payment sent" notification, so a redelivered webhook (Paystack webhooks are also at-least-once delivery) doesn't send a duplicate notification. Not a money-safety fix — Paystack itself only transfers once — but closes the "webhook retries are safe" gap Task 3 named.

**Security backstop, Task 5**: `firestore.rules` previously had no `escrow_releases` match block at all (default-deny by omission). Added an explicit rule: the customer's own `confirmComplete` client write is scoped to `releaseId == jobId`, the job's own `customerId`, and `status == 'pending'` only; every other operation (read, update, delete, and any create that doesn't match those three conditions) is `false`. Cloud Functions (Admin SDK) bypass this regardless, and remain the only path that can ever move a release past `pending`.

## 3. Files changed
`lib/core/services/job_service.dart` (`confirmComplete`), `functions/index.js` (`_releaseEscrow`, `processEscrowRelease`, `paystackWebhook`'s transfer-success handler), `firestore.rules` (new `escrow_releases` match block), `test/job_service_agreement_test.dart` (new test group). Plus `design/PAYOUT_RACE_CONDITION_AUDIT.md` and this report (both new).

## 4. Tests added
5 new tests in a `Payout idempotency — state machine guards (Phase 12.5)` group, all passing. Scope stated plainly, same as the existing agreement-checkpoint tests' own disclosed limitation: this repo has no Firestore emulator, so the actual transaction/concurrency behavior (two transactions racing for the same document, the atomic claim in `processEscrowRelease`) **cannot** be exercised by a pure Dart unit test — that would require emulator-based integration tests, which don't exist in this repo today (a standing gap, not new to this phase). What *is* genuinely unit-testable and is tested: the state machine's independent first layer of defense — `completed` has zero valid outbound transitions (so a second release attempt can't move an already-paid job anywhere), `completed → completed` is invalid, `submitted → completed` remains the one legitimate path, and releasing from any other status (`escrowLocked`, `inProgress`) is rejected — matching `_releaseEscrow`'s new transactional precondition exactly. `flutter test`: **49/49 passing** (44 prior + 5 new). Full-project `flutter analyze`: 13 pre-existing issues, zero introduced.

**Recommended follow-up, not done here**: set up Firebase emulator-based integration tests (Firestore + Functions) specifically for the concurrent-release and automatic-vs-manual-release-racing scenarios named in Task 4 — the only way to genuinely exercise the transaction-retry guarantee this fix relies on, rather than trusting Firestore's documented behavior on paper.

## 5. Remaining payment risks
- The emulator-testing gap above — this fix is architecturally sound and matches Firestore's documented transaction semantics exactly, but has not been exercised under real concurrent load.
- `BANK_CODES` table (unrelated to this phase's fix) — still unverified against Paystack's live bank list, per Phase 12's audit; unchanged here.
- No real Paystack sandbox transaction has been run against any of this program's changes, including this fix — still the top item on the manual test list in `design/PRODUCTION_PAYSTACK_CHECKLIST.md`.

---

Stopping here per your instruction.
