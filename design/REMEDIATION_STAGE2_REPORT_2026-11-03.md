# HandyTrust Remediation — Stage 2 Report: Security Rules & Backend Authorization (2026-11-03)

Scope: Stage 2 only, per `design/REMEDIATION_STAGE1_VERIFICATION_2026-11-03.md` §4, with policies D1–D10 as approved. **Nothing was deployed, committed or pushed. No production Firebase or Paystack system was accessed.** All rules testing ran against the local Firestore emulator.

---

## 0. Policy check (D1–D10) against the Stage 1 report — constraints needing clarification

No approved policy was changed. Items marked **❓** need your answer before the stage that implements them.

| Policy | Constraint / finding | Needs decision? |
|---|---|---|
| **D1** 5% fee on top, artisan gets full price, HandyTrust absorbs Paystack fees | **Pricing verified as far as possible.** Paystack's own support pages state: local payments **1.5% + ₦100, with the ₦100 waived under ₦2,500**, and **processing fees are not returned on refunds**. From third-party sources only (confirm on your Paystack dashboard): ₦2,000 cap on local fees, 3.9% + ₦100 for international cards, transfer fees ₦10 (≤₦5k) / ₦25 (≤₦50k) / ₦50. **Model (see §0.1):** HandyTrust **loses money** on local jobs under ~₦292 and between **₦2,381–₦3,211** agreed price (that's where the customer's charge crosses ₦2,500 and the ₦100 flat fee kicks in), on **every international-card job under ~₦13,820**, and on **every refund** (the whole processing fee is lost). VAT on Paystack fees isn't modelled. | **❓** Accept the loss bands, or add a minimum job value / a fee floor (e.g. `max(5%, ₦X)`)? Who absorbs the non-refundable Paystack fee when a job is refunded (D2)? |
| D1 (legal) | Holding customer funds for up to 14+ days and paying them out to third parties is an **escrow / marketplace model**. Whether this needs licensing or a specific Paystack product/agreement (Paystack offers split payments/subaccounts for marketplaces) is a **legal and Paystack-account question I can't answer**. VAT may apply to the 5% platform fee. | **❓** Confirm with counsel and Paystack before real money flows |
| **D2** Paid cancellations need admin review | **Implemented in Stage 2** as an interim (§1). **Gap:** there's no admin tooling yet to *act* on a request. The alert can be dismissed, but approving means a manual Paystack-dashboard refund plus a Firebase-console status change until Stage 4. The refund **amount** isn't specified (full 105%? 100%? minus the non-refundable Paystack fee?). | **❓** Refund amount rule. Confirm the manual interim procedure is acceptable |
| **D3** Both parties can dispute; release/refund/split | Fits Stage 4. A split is two money movements (transfer + partial refund), each with its own Paystack fee. | No |
| **D4** One rework; new 14-day window on resubmission | Compatible with Stage 2: the server now recomputes the window on **every** entry into `submitted`. | No |
| **D5** Configurable deadlines | ❓ Two values are ambiguous in the current flow. **"Artisan quotations: 48 h"**: does a quote *expire* 48 h after it's sent, or must artisans quote within 48 h of posting? **"Customer agreement confirmation: 48 h"**: today the *customer* confirms first and the *artisan* accepts second, so whose 48 h? "Abandoned payments: 24 h" interacts with Paystack's authorization-URL lifetime and the existing 30-minute init-reuse window (Stage 3). | **❓** Clarify both meanings |
| **D6, D7** | Stage 5. D7 changes the existing direct-booking behaviour (`secure_booking_screen.dart` currently assigns immediately). Noted, not changed. | No |
| **D8** GPS + service address + radius | No artisan coordinates exist today (Stage 1 finding), so **existing artisans need a backfill prompt**. Collecting precise location is personal data under Nigeria's Data Protection Act 2023, so it needs a stated purpose, consent and a retention period (legal confirmation). | **❓** Legal sign-off on location consent wording |
| **D9** Suspension blocks new activity, protects existing jobs | **Rules implemented (§1)** exactly as stated. **Conflict:** the *router* (`lib/routes/router.dart:131`) locks a suspended user out of the **whole app**, so a suspended artisan can't actually complete an existing funded job even though the rules now allow it. **Address reveal after assignment:** Firestore can't hide individual fields of a readable document, so this needs the exact address moved to a separately-protected sub-document plus a migration of existing jobs. That's a data-model change; I deferred it to Stage 6 (with matching), not done silently. | **❓** Should suspended users get a restricted "finish existing jobs only" app mode? Approve the Stage 6 placement of the address split |
| **D10** | Agreed. I can provide an Admin-SDK script that outputs only aggregate counts for you to run; I won't access production. | No |

### 0.1 Fee model (D1), using the pricing above
| Agreed price | Customer pays | HandyTrust 5% | Paystack fee | Transfer | **Net (local card)** | Net (intl card) | Lost if refunded |
|---|---|---|---|---|---|---|---|
| ₦1,000 | ₦1,050 | ₦50 | ₦15.75 | ₦10 | **+₦24.25** | −₦100.95 | ₦15.75 |
| ₦2,400 | ₦2,520 | ₦120 | ₦137.80 | ₦10 | **−₦27.80** | −₦88.28 | ₦137.80 |
| ₦3,000 | ₦3,150 | ₦150 | ₦147.25 | ₦10 | **−₦7.25** | −₦82.85 | ₦147.25 |
| ₦5,000 | ₦5,250 | ₦250 | ₦178.75 | ₦10 | **+₦61.25** | −₦64.75 | ₦178.75 |
| ₦10,000 | ₦10,500 | ₦500 | ₦257.50 | ₦25 | **+₦217.50** | −₦34.50 | ₦257.50 |
| ₦50,000 | ₦52,500 | ₦2,500 | ₦887.50 | ₦25 | **+₦1,587.50** | +₦327.50 | ₦887.50 |
| ₦200,000 | ₦210,000 | ₦10,000 | ₦2,000 (cap) | ₦50 | **+₦7,950** | +₦1,660 | ₦2,000 |

The fee model itself is implemented in Stage 3, after your D1 answers.

---

## 1. What changed and why

### 1.1 `firestore.rules`
| Change | Issue | Effect |
|---|---|---|
| `_isValidJobTransition` rewritten: per-transition `affectedKeys().hasOnly([...])` whitelists; `customerId` in no list (immutable); `artisanId` only on requested→matched; no payment/escrow/agreement/payout field in any list | HT-001 → closes HT-002, HT-003, HT-004, HT-005 | A legal status change can no longer carry a rewrite of protected fields |
| `submittedAt == request.time` required on submission, plus at least one completion photo | HT-005 | The review-window anchor is server time. Photos were already required by the UI |
| Old-build compatibility: client `autoReleaseAt`/`disputeWindowEndsAt` tolerated **only within 13–15 days of server time** (marked TRANSITIONAL) | HT-005, B-2 | Old app builds keep submitting; backdated values are rejected outright; the server overwrites them anyway |
| `agreedAmount` not writable on inChat→paymentPending (an unchanged re-send by old builds still passes, since an unchanged value isn't an affected key) | HT-004, B-1 | The artisan-accepted price is frozen. Old builds keep paying |
| `escrowLocked → cancelled` removed for all clients. New **paid-cancellation request** rule (party only, escrowLocked/inProgress, one pending at a time, no status or money fields) | HT-006, D2 | Neither party can unilaterally cancel a funded job; they can ask |
| The customer can't hire their own artisan profile (`artisanId != uid`) | new (self-dealing) | Prevents one person controlling both sides of escrow. **❓ confirm** this is acceptable (it's a new restriction) |
| Job **create** must be unassigned and un-agreed, with keys limited to `JobModel.toJson` | **HT-046 (new, confirmed)** | A customer could previously create a job pre-agreed at any price, bypassing the artisan |
| Artisan **create** must use default trust and stat values | **HT-045 (new, confirmed)** | An artisan could previously self-create as "trusted" with 5★ from 900 ratings |
| Artisan owner can't change `responseTimeMinutes`/`uid`. `id_submitted`/`pending_later` only when the matching `verifications/{uid}` record exists in that state after the write (`getAfter`) | HT-019 | Trust inputs aren't self-writable |
| `verifications`: the owner may only write `pending`/`pending_later`, never reviewer fields | HT-020 | No self-approval |
| Suspension (`isNotSuspended`, `isArtisanEligible` + `accountStatus`) on job create, quote create/edit, being hired, pre-match chat. **Not** on existing-job transitions | HT-021, D9 | Blocks new activity; protects existing jobs and escrow |
| Slot confirmation must be one of the artisan's proposed slots | HT-031 | The customer can't bypass the artisan's scheduling |
| `escrow_releases` create: `requestedBy == auth.uid`, fixed key list | HT-002 | Releases are attributable to the real payer |
| `reviews` create: `reviewId == jobId`, `artisanId == job.artisanId` | HT-014 | One review per job, for the real artisan |
| `notifications` (interim): types limited to those clients actually send (server-only types removed); sender→recipient must be a real relationship on a real job; fixed keys and length caps | HT-015 | Strangers can't notify anyone; no fake "verification approved" or "payment released" from clients |

### 1.2 `functions/index.js`
| Change | Issue |
|---|---|
| `processEscrowRelease`: pays out only if `release.requestedBy` is `system` or equals `payment.payerId` (set server-side at charge), **and** `job.customerId === payment.payerId`. Otherwise it fails closed with an `admin_alerts` entry `payout_authorization_failed` | HT-002 (a server invariant independent of the job doc) |
| `onJobCompleted`: on every entry into `submitted`, sets `autoReleaseAt` and `disputeWindowEndsAt` = server `submittedAt` + 14 days | HT-005, D4-ready |
| `_releaseEscrow`: re-checks `submittedAt + 14 days <= now` inside its transaction; missing `submittedAt` fails closed | HT-005 (also neutralizes in-flight jobs with client-set timers) |
| `onJobCompleted`: on a new paid-cancellation request, writes an `admin_alerts` `paid_cancellation_request` and notifies the other party | D2 |
| `_computeReviewApplication`: rejects reviews whose ID ≠ jobId (optional 3rd arg; existing callers unchanged) | HT-014 defense |
| New pure, exported helpers `_isReleaseRequesterAuthorized`, `_reviewWindowEndMs`, `_isReviewWindowElapsed`, `REVIEW_WINDOW_MS` | testability |

### 1.3 Flutter (only what the rules changes require)
| File | Change |
|---|---|
| `lib/core/services/job_service.dart` | `initPayment` no longer takes or writes an amount (HT-004). `timestampsForStatus(submitted)` writes only the `submittedAt` server timestamp (HT-005). New `canRequestPaidCancellation` + `requestPaidCancellation` (D2). Client transition table no longer lists escrowLocked→cancelled (mirrors rules; the admin path bypasses it) |
| `lib/providers/escrow_provider.dart` | `initPayment(jobId)`; new `requestPaidCancellation` |
| `lib/screens/payment/payment_screen.dart` | Call site updated (the amount shown is display/validation only) |
| `lib/screens/job/job_detail_screen.dart` | Cancel button: on funded jobs it reads "Request Cancellation", explains that escrow stays protected, and shows "Cancellation requested — under review" once filed. **No other UI changed.** Previously this button produced a permission error in `inProgress`, and in `escrowLocked` it cancelled with no refund |
| `lib/models/job_model.dart` | Four cancellation-request fields + `hasPendingCancellationRequest` |
| `lib/models/audit_log_model.dart` | `JobActionType.paidCancellationRequested` (only a `firstWhere` lookup exists, no exhaustive switch) |
| `lib/screens/admin/admin_dashboard_screen.dart` | Two readable alert labels (`paid_cancellation_request`, `payout_authorization_failed`) in the existing alerts card |

### 1.4 Tests
| File | Change |
|---|---|
| `firestore-tests/security_regression.test.js` (**new**, 58 tests) | Appendix A probes inverted into must-fail regressions + HT-045/HT-046, self-hire, slot, cancellation-request abuse, suspension (4), **legitimate exact-payload tests for every client write path** (customer, artisan, transactions, old-build compat), and **rule-cost tests on full-size (~50-field) job documents** |
| `firestore-tests/escrow_payout.test.js` | **One existing step changed (test 13):** its bare `{status:'submitted'}` (no photo, no `submittedAt`), a payload the real app never sends, is now asserted to **fail**, and the real `JobService.submitCompletion` payload is asserted to succeed. Justification: rejecting that payload *is* the HT-005 fix |
| `functions/test/stage2_authorization.test.js` (**new**, 13 tests) | Payout requester authorization, review window maths (incl. a backdated-timer scenario), one-review-per-job |
| `test/job_service_agreement_test.dart` | **Three existing tests replaced by two:** two asserted that the *client* computes `autoReleaseAt` from `DateTime.now()` (the vulnerability itself), and a third ("submitted also stamps submittedAt") is folded into the stricter replacement. Replacements: "client doesn't write the timers" and "submittedAt is exactly one server timestamp". 5 new tests for `canRequestPaidCancellation` + JSON round-trip (99 − 3 + 2 + 5 = 103) |
| `firestore-tests/package.json`, `functions/package.json` | `npm test` scripts include the new files |

---

## 2. Test results (all executed 2026-11-03)

| Suite | Before Stage 2 | After Stage 2 |
|---|---|---|
| Flutter `flutter test` | 99 / 99 | **103 / 103 passed** |
| Functions `npm test` (emulator) | 37 / 37 | **50 / 50 passed** |
| Rules `npm test` (`escrow_payout` + `security_regression`, emulator) | 26 / 26 (no security regression suite) | **84 / 84 passed** |
| New security regression suite **run against the pre-Stage-2 rules** (baseline) | — | **24 security tests failed** (exploits present); all legitimate payloads passed (except the not-yet-existing cancellation request) |
| Original audit probes (Appendix A) on the new rules | exploits succeeded | **all exploit probes now fail** except **P-K** (address exposure; deferred to Stage 6, see D9) |
| `flutter analyze` | — | **No issues** in changed files. The whole project shows only pre-existing infos plus one pre-existing warning (`lib/core/platform_utils.dart` unused import) in untouched files |

---

## 3. Deployment order (when you authorize it; not done)

1. **Cloud Functions first.** This gives the payout invariant, the server timers and the window re-check. Safe on its own: it only adds checks.
2. **Firestore rules second.** Old app builds keep working (compat B-1/B-2), except that **old builds lose the ability to cancel funded jobs** (they'll show a permission error; the money is protected). That's intended under D2.
3. **App release third.** New builds stop writing `agreedAmount` and the timers, and gain "Request Cancellation". (Shipping the app before the rules would make "Request Cancellation" fail against the old rules.)
4. After old builds age out: remove the TRANSITIONAL `_timerWithinBand` allowance from the submission clause.

**Before deploying, run a production data audit** (aggregate-only script, D10): artisans with non-default trust/verification fields but no admin approval record (HT-045 forgeries made under the old rules **persist**, since re-writing identical values is a no-op), multiple reviews per job (HT-014 history), jobs whose `customerId` differs from their payment's `payerId` (HT-002 history; payout now fails closed for these), `submitted` jobs with client-set timers (handled by the re-check), and `resolved`/`cancelled` jobs with `escrowHeld` payments.

---

## 4. Remaining risks (honest list)

| Risk | Severity | Plan |
|---|---|---|
| A real counterparty can still choose the title/body of a notification they send (relationship-checked, but free text) | Medium | Stage 6: server-generated notifications, client create → `if false` (ordering hazard HT-044 respected) |
| Exact customer address/coordinates still readable by any artisan account on open jobs (P-K) | Medium (privacy) | Stage 6 data-model split (D9) |
| Storage rules unchanged: dispute evidence and job photos readable by any signed-in user; avatar path has no rule (HT-029) | Medium | Stage 6 (needs Storage emulator tests; cross-service rules need IAM setup) |
| No admin UI to act on cancellation requests. Dismissing the alert doesn't clear the job's `pending` request, so users keep seeing "under review" until an admin edits the job | Medium (operational) | Stage 4 callable. Interim: manual procedure (Paystack refund + console update) |
| Payout-invariant and timer **trigger wiring** is covered by code review + pure-function tests, not by an emulator trigger harness | Medium | Stage 7 (adds functions emulator harness) |
| `paymentPending` cancel vs late Paystack success: a charge can complete after the job was cancelled (the webhook then errors) | High (money) | Stage 3 (cancel in `paymentPending` must verify there's no successful charge) |
| Router lock-out of suspended users contradicts D9 | Medium | Your decision (§0) |
| Denied requests reach the 1000-expression budget. They're still denied (correct), but the budget is shared across `allow` statements | Low | Legitimate writes verified on full-size docs (cost tests). Any future rule must keep those tests green |
| Old builds' job-create payload may contain keys outside the new allow-list (I can't see older builds) | Low–Medium | The allow-list matches the current `JobModel.toJson`. Check the minimum installed version before deploying |
| Self-hire block is a new business restriction | Low | Your confirmation (§1.1) |
| The local emulator from these runs is still running (PID 30304, port 8090) | — | Stop with `Stop-Process -Id 30304` |

---

## 5. Stage 2 acceptance criteria (from the Stage 1 report §7)

| Criterion | Status |
|---|---|
| All converted Appendix A probes fail as required | **Met**, except P-K, which is deferred by design to Stage 6 (D9 data-model change) |
| Every legitimate `JobService` payload passes a positive rules test | **Met.** Covers every transition and sub-state, plus old-build compatibility and full-size documents |
| Payout invariant test passes | **Met** (pure function). Trigger wiring is reviewed, not emulator-tested (Stage 7) |
| Existing suites still green | **Met:** 103/103, 50/50, 84/84, with one existing rules test step changed and three Flutter tests replaced by two, each justified above |
| No rule is less restrictive for any actor | **Met** by review. The only new permission is the narrowly scoped paid-cancellation request (D2). The milestone-timestamp checks I added are optional-if-absent for compatibility, never looser than before |

**Stage 2 is complete, pending your review.** Stage 3 (payment init/verification/escrow integrity, fee model per D1) needs the D1 and D5 answers in §0.
