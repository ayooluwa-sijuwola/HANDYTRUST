# HandyTrust — Stage 7.2: Node.js 22, Chargeback Policy and Trust Score

Date: 2026-11-04 · Scope: the four approved decisions only. A: Node 22 runtime. B: chargeback policies (loss after payout, partial chargebacks). C: trust-score response time. D: testing.

**Constraints observed:**
- No production Firebase changes or Paystack calls, and no real money moved.
- No deployment, commit or push; no Stage 8 UI.
- No financial policy changed beyond the approved decisions.
- No undocumented Paystack behaviour assumed.
- A dummy `functions/.secret.local` was created for each Functions-emulator run and **deleted afterwards** (verified). It is git-ignored since Stage 7.1.

---

## 1. Changed files

**Production code and configuration:**

| File | Change |
|---|---|
| `firebase.json` | `"runtime": "nodejs20"` → `"nodejs22"` |
| `functions/package.json` | `engines.node` `"20"` → `"22"`. The `npm test` list gains the two new suites |
| `functions/package-lock.json` | Root `engines.node` → `"22"` **only**. A hash of the lock file with that field excluded is identical before and after, so no dependency moved |
| `README.md` | Three "Node.js 20" references → 22 (developer setup). Historical design reports are left as written |
| `functions/index.js` | **B:** <br>• `partialChargebackAccountingVerified` config switch, default `false` <br>• `_availableKobo` <br>• `_validateSettlement` / `_settlementAmounts` work on the undisputed balance <br>• settlement records `availableKobo`, `chargebackRefundedKobo` and `platformRetainedKobo` from the undisputed balance <br>• payout final check freezes `chargeback_partial_shortfall` <br>• `_refundCharge` subtracts amounts the issuer already returned <br>• pure `_chargebackAccounting` <br>• `_closeChargeback` rewritten for the approved policies <br>• `_setChargebackInvestigation` + `adminSetChargebackInvestigation` callable <br><br>**C:** <br>• booking-response module (records, median, recompute) <br>• `_reopenJob` writes the response in its own transaction <br>• `onJobCompleted` records requests, confirmations and customer cancellations <br>• hourly sweep refreshes ageing 90-day windows |
| `firestore.rules` | **New, server-only:** `platform_losses` (admin read) and `booking_responses` (admin read). <br>**Tightened artisans rules:** `responseTimeSampleSize` and `responseTimeUpdatedAt` added to the owner-protected fields and forbidden on create. Nothing is weakened |
| `firestore.indexes.json` | One composite index: `booking_responses` (`artisanId` ↑, `qualifying` ↑, `respondedAt` ↓). The file stays in its compact repository style; compared with HEAD it is pure additions, earlier stages' plus this one |

**Test-only:**

| File | Change |
|---|---|
| `functions/test/runtime_config.test.js` (new, 4) | Node 22 declared everywhere; no Node 20 left; every locked dependency's `engines.node` accepts 22.23.4; the entry point loads and exports only v2 endpoints. Uses `semver`, already present as a transitive dependency |
| `functions/test/stage7_2_policy_trust_emulator.test.js` (new, 31) | §3–§5 |
| `functions/test/stage7_1_chargeback_emulator.test.js` | Two assertions updated to the new close result and next-step wording (intended, policy-driven) |
| `firestore-tests/security_regression.test.js` (+4) | §6 |

---

## 2. Runtime compatibility evidence (A)

| Check | Result |
|---|---|
| Configured runtime | `firebase.json` `nodejs22`; `engines.node` `22`; lock root `22`; README updated. `runtime_config.test.js` fails if `nodejs20` or `"node": "20"` reappears |
| Dependency compatibility | All packages in `package-lock.json` that declare `engines.node` accept Node 22.23.4 (0 incompatible) |
| Node 22-specific APIs | No removed or changed Node API in use. Only `crypto`, `fetch` (tests) and `Buffer` are used directly; the code relies on firebase-functions v5 (v2 SDK), firebase-admin 12 and axios |
| Functions suite on **Node 22.23.4** | **264/264** |
| Firestore rules suite on **Node 22.23.4** | **137/137** |
| End-to-end triggers + schedules, CLI and runtime on Node 22 | **16/16**. The emulator logged "Using node@22 from host" with **no version-mismatch warning** |
| Build | The Functions package has no build step (plain JS; `scripts` is only `test`). The emulator loaded all 34 function definitions on Node 22 |
| Leftover Node 20 configuration | None in runtime config. The first Node 22 e2e run warned "requested node version 20"; the cause was **my scratch emulator config** from Stage 7, which was corrected and the run repeated cleanly. The repository was never at fault |

---

## 3. Accounting rules (B)

**What Paystack documents** (Disputes API; Manage Disputes):
- Accepting a dispute may refund **"either full or partial"**.
- `refund_amount` is an integer **"in the subunit of the supported currency"**, i.e. kobo for NGN. This is stated for the resolve and update request parameters.
- **Not documented:**
  - what the *fetched* dispute's `refund_amount` holds for issuer-decided outcomes (the open/archived sample shows `null`; resolved samples show `merchant-accepted` with `1002`);
  - whether `declined` means the merchant ultimately won.

**Accounting basis.** The pure function `_chargebackAccounting` decides it at close.

| Basis | When | Amount reversed to the customer |
|---|---|---|
| `paystack_verified` | `config/platform.partialChargebackAccountingVerified === true` **and** Paystack (fetched at close) reports `resolved` + `merchant-accepted` **and** `refund_amount` is an integer, > 0, ≤ the amount still held, currency NGN or absent | `refund_amount` |
| `assumed_full` | Anything else: the switch is off (**the default**), the resolution or status is not established, or the amount is missing, non-integer, zero, too large or in another currency | Everything still held (the conservative full hold of decision 3) |
| `amount_unknown` | The payment record has no charge amount | Not computed |
| `merchant_won` | Admin closes as merchant won (refused if Paystack says `merchant-accepted`) | 0 |

**While a chargeback is open, the hold is always the full payment.** The final amount isn't known until Paystack resolves it.

**Chargeback after payout (decision 2).** The payment status is one of `releasing`, `released`, `settled`, `refundPending` or `refunded`.
- `platform_losses/{chargebackId}` is written, create-once, inside the close transaction:
  - `absorbedBy: 'handytrust'`
  - `artisanDeduction: false`
  - `recoveryStatus: 'not_pursued'`
  - `amountKobo` and `amountBasis` (the estimate is flagged when `assumed_full`)
  - the payment state at close and the payout state when the chargeback opened
- A `platform_loss_recorded` financial event is written.
- The payment keeps its status, with `chargebackLoss: true`.
- **No transfer is reopened or reversed**, and no code path reduces a later payout. Tested: the same artisan's next job is paid the full ₦50,000.
- **Evidence and history:** the case, its event log, `history[]` (close and investigation entries), `admin_audit_logs` and `financial_events` are all server-only and never deleted. Admin user deletion doesn't touch them.
- **Fraud investigation:** `adminSetChargebackInvestigation` (`investigating` | `cleared` | `fraud_confirmed`, notes required) records the outcome on the case, writes an audit log and, for `fraud_confirmed`, raises an alert. **No money moves and nothing is suspended automatically.** The admin applies the existing fraud suspension, which already freezes that artisan's payouts (tested).

**Partial chargeback while funds are in escrow** (switch on and verified only):
- **Accounting:** the payment stays `escrowHeld` with `chargebackRefundedKobo = R`; the undisputed balance is `charge − R` (`_availableKobo`).
- **Entitlement and fee are unchanged:** the artisan's entitlement is still the agreed service price, and the 5% fee is still computed on it.
  - If **R ≤ the fee**, the undisputed balance still covers the artisan in full. The payout proceeds **after an explicit admin retry**, and the platform's retained fee is reduced by R.
  - If **R > the fee** (a shortfall), any automatic or retried payout is frozen as `chargeback_partial_shortfall`. The admin decides through a settlement validated against the undisputed balance:
    - `release` is refused (`release_exceeds_undisputed_balance`);
    - `split` must fit inside it;
    - `full_refund` refunds what is still held.

    The settlement records `availableKobo`, `chargebackRefundedKobo` and `platformRetainedKobo`.
- **A refund still owed** (a non-funding charge) is reduced by R, or cancelled if R covers it, so the customer is never refunded twice.
- **A partial during an executing settlement** is refused (`partial_chargeback_during_settlement`): the case stays open and the hold stays in place for manual reconciliation.

**No duplicates:**
- the close is idempotent (concurrent closes produce one close, one loss record and one financial entry);
- settlements are create-once (concurrent attempts produce one settlement, at most one payout and at most one refund);
- the payment funds mutex is unchanged;
- dispute events after close are logged, not applied.

---

## 4. Trust-score response time (C)

**Definition (approved):**
- **Metric:** the median of the artisan's last **20** qualifying booking responses within **90 days**.
- **Neutral value:** **30** minutes with fewer than **3** qualifying responses.
- **Use:** feeds the existing 15% `_trustResponseTimePoints` component; the score is recomputed in the same transaction.

| Event | Response time | Where recorded |
|---|---|---|
| Booking request | start = `bookingRequestedAt` (or `matchedAt`) | `onJobCompleted` (requested → matched), create-once |
| Confirmed | `bookingConfirmedAt − start` | `onJobCompleted` (matched → inChat) |
| Declined, or withdrawn **before** confirming | actual decline time (server clock) − start | Inside `_reopenJob`'s transaction (`artisan_declined_booking`) |
| Withdrawn **after** confirming | the **original confirmation** time | `_reopenJob` (`artisan_withdrew`): written from `bookingConfirmedAt` if the trigger hadn't yet recorded it, otherwise untouched |
| Expired (24 h) | **1,440** minutes | `_reopenJob` from the hourly sweep (`booking_expired`) |
| Customer cancels before any answer | recorded, **not qualifying** | `onJobCompleted` (matched → cancelled) |
| Unanswered / withdrawn / expired quotes | not counted | — |

**Integrity:**
- **Immutable, server-side records:** `booking_responses/{jobId}_{artisanId}_{requestedAtMs}`. Rules deny every client write, admins included. Admins can read them.
- **First response wins:** a set response is never changed, and redeliveries or late duplicates are no-ops.
- **No history loss:** the response is written **in the same transaction** that reopens the job, before the booking fields are deleted. Expiry and withdrawal can no longer destroy it.
- **No client-time manipulation:** times come only from fields the rules force to `request.time` (`bookingRequestedAt`, `matchedAt`, `bookingConfirmedAt`; a rules test refuses a backdated confirmation) or from the server clock. Minutes are clamped to [0, 1440].
- **Protected inputs:** artisans cannot write `responseTimeMinutes`, `responseTimeSampleSize` or `responseTimeUpdatedAt`, on update or on create (rules tests).
- **Window ageing:** the hourly `expireMarketplaceDeadlines` refreshes up to 100 artisans per run whose score is more than 24 h old, so old records leave the 90-day window even without new bookings.
- **History before Stage 7.2:** it was deleted on reopen and cannot be reconstructed. Every artisan starts at the neutral 30 minutes until three qualifying responses exist.

---

## 5. Test results

| Suite | Result |
|---|---|
| Flutter (`flutter test`) | **174/174** |
| Cloud Functions (`npm test`, Node 24) | **264/264** (+31 Stage 7.2, +4 runtime) |
| Cloud Functions on **Node 22** | **264/264** |
| Firestore rules (incl. all original audit exploits) | **137/137** on Node 24 and **137/137** on Node 22 (+4) |
| Storage rules | **9/9** |
| End-to-end triggers (Functions emulator, Node 22) | **12/12** |
| Scheduled functions end to end (Node 22) | **4/4** |
| **Total** | **600 passing, 0 failing** |

**New Stage 7.2 tests (31) cover every requested area:**
- **Node 22 compatibility:** the 4 runtime tests.
- **Chargeback after payout:** the loss is recorded and attributed to HandyTrust, the completed transfer is untouched, and the next payout is paid in full. With verified data, the recorded loss equals the verified amount.
- **Fraud investigation and suspension:** recorded without moving money, then the existing fraud suspension freezes the artisan's other payouts.
- **Partial accounting:**
  - the switch-off fallback;
  - the eight unestablished-data fallbacks;
  - a reversal within the fee, with the artisan paid in full after retry;
  - a shortfall, with the payout frozen and settlement validated against the undisputed balance (split produces a ₦40,000 transfer and a ₦2,500 refund);
  - a refund owed being reduced;
  - a partial during settlement being refused.
- **Full and partial holds:** both are tested.
- **Concurrent settlement attempts** and **concurrent closes:** both tested.
- **Duplicate dispute events** after a partial close: tested.
- **Trust-score events:**
  - request and confirmation records, with the first response immutable;
  - decline;
  - expiry via the real sweep;
  - withdrawal after confirmation, both with and without the trigger record;
  - customer cancellation (non-qualifying).
- **Score boundaries:** neutral below 3, median, even count, the exact 90-day boundary, future records, only the latest 20, and minute clamping.
- **Recalculation:** updates the stored score and `trustScore`; historical records age out through the sweep; an artisan with no history stays at the neutral value.

**Mutation checks** (each one backed up, mutated and restored byte-identical; SHA-256 verified):
- Disabling the response write in `_reopenJob` fails 3 tests.
- Removing the shortfall freeze **initially passed**, which exposed a coverage gap. I added an automatic-payout shortfall test; the mutation now fails it.

**Test-environment issues found (not product defects):**
1. **The shared Firestore emulator on port 8090 had exited.** It was an orphan from earlier stages, and the unit suites depend on it.
2. **Running the unit suites inside `emulators:exec` made 88 tests fail.** The command exports `FIREBASE_CONFIG`, and `admin.initializeApp()` prefers it over each file's `GCLOUD_PROJECT`. All suites collapsed onto one project and cleared each other's data in parallel. The fix was to run them against a plain local emulator, as in Stages 2–7.1.
3. **Correction to the Stage 7.1 report:** it said `flutter analyze` found no issues. That 4-second run evidently analyzed nothing. A full run reports **39 pre-existing issues**: 38 info-level lints (BuildContext across async gaps, deprecated Radio/Form APIs) and 1 unused-import warning. All are in files not modified in Stages 7.1–7.2. No Dart file changed in this stage.

---

## 6. Security protections (none weakened)

The four new rules tests cover:
- `platform_losses` and `booking_responses` are readable only by admins and writable by no client (admins included), including delete;
- an artisan can't update `responseTimeMinutes`, `responseTimeSampleSize` or `responseTimeUpdatedAt`, nor create a profile carrying the latter two;
- a backdated `bookingConfirmedAt` is refused while the server-time one succeeds.

All 133 earlier rules tests and the Stage 7.1 chargeback holds still pass.

---

## 7. Remaining external verification

**Paystack test mode — blocked by external configuration.** No test keys were available, and none were requested in chat; use the git-ignored `functions/.secret.local` or a staging secret.
1. Raise a test dispute and capture real `charge.dispute.create`, `charge.dispute.remind` and `charge.dispute.resolve` payloads plus `GET /dispute/:id`.
2. **Before enabling partial accounting** (`config/platform.partialChargebackAccountingVerified = true`), confirm:
   - that a partially accepted dispute reports `status: resolved`, `resolution: merchant-accepted` and `refund_amount` in **kobo**, equal to the amount returned to the customer;
   - what an **issuer-decided** loss reports;
   - what `declined` + `resolved` means for the outcome;
   - that a later refund of the remaining balance on a partially charged-back transaction is accepted, and for what maximum amount.
3. The Stage 3/4 checklists, the Stage 7 §5 API assumptions, and the Stage 7.1 §10 chargeback items remain outstanding.

**Staging (owner):**
- Deploy with `nodejs22` to a **staging** project.
- Confirm the deploy succeeds on the Node 22 runtime and that the five Cloud Scheduler jobs exist and run (Stage 7.1 §9).
- Create the new `booking_responses` composite index before the response-time query runs; until it exists the query fails and the score stays unchanged.

**Real device — blocked:** push cases and the photo-metadata checks (Stage 7.1 §10).

---

## 8. Outstanding risks and next steps

| Severity | Item |
|---|---|
| Blocker | Paystack test-mode verification (above); until then partial chargeback accounting stays **off**. Real-device checks. Pre-deploy migrations (Stages 3–6). Legal and account approvals |
| Medium | No admin UI yet for chargeback cases, investigations, platform losses or shortfall settlements (callables and alerts only) — Stage 8 |
| Medium | A partial chargeback during an executing settlement needs manual reconciliation (refused by design) |
| Medium | The response-time metric starts at the neutral value for everyone; it becomes meaningful once artisans have 3+ responses after deployment |
| Low | Sweeps process at most 500 jobs and 100 response-time refreshes per hourly run |
| Low | 39 pre-existing Flutter analyzer lints (no errors) |
| Low | Orphaned local emulator processes from these runs (permission to stop them was not available) |

**Recommended next steps (each needs your approval):**
1. Run the staging Node 22 deploy and the Paystack test-mode verification.
2. Enable partial accounting only after item 2 of §7 is confirmed.
3. Do the device pass.
4. Then follow the Stage 7 §15 release sequence.

**Stage 7.2 is complete, pending your review. Nothing was deployed, committed or pushed; Stage 8 has not been started.**
