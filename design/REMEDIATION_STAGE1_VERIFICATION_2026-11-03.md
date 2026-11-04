# HandyTrust Remediation — Stage 1: Independent Verification & Plan (2026-11-03)

Companion to `design/HANDYTRUST_WORKFLOW_FUNCTIONAL_AUDIT_2026-11-03.md` (referred to as "the audit"). **No code was modified in this stage.**

Evidence labels: **CONFIRMED (emulator)** = reproduced against the repo's `firestore.rules` in the local emulator; **CONFIRMED (code)** = verified by reading the cited lines again for this stage; **CORRECTED** = the audit's claim or fix was wrong or imprecise and is restated here; **UNVERIFIABLE LOCALLY** = needs evidence from outside the repo.

---

## 1. Finding-by-finding verification

### 1.1 Critical findings

| ID | Verdict | Re-verification notes | Change vs. audit recommendation |
|---|---|---|---|
| HT-001 Transition rule has no field whitelist | **CONFIRMED (emulator + code)** | `firestore.rules:133` `allow update: if isSignedIn() && _isValidJobTransition(jobId)`. The function body (`:384-432`) never references `affectedKeys()`. Firestore ORs the `allow update` statements, so the field-restricted rules at `:142-235` don't constrain this one. Probes P-A to P-D succeed. | None. It remains the root cause. Exact per-transition field lists are in §3. |
| HT-002 Artisan self-release | **CONFIRMED (emulator)**, payout leg **CONFIRMED (code)** | P-A: artisan writes `{status:'inProgress', customerId:A}`, then `{status:'submitted'}`, then creates `escrow_releases/j1`, and all three succeed. `processEscrowRelease` (`functions/index.js:465-661`) never checks *who* requested the release. | **Stronger fix.** Besides rules immutability, add a server-side invariant that doesn't depend on the job doc: pay out only if `release.requestedBy === payment.payerId` (where `payerId` is set server-side at `functions/index.js:1236,1253,1312`) or `requestedBy === 'system'`. This holds even if a future rules regression reopens job-field writes. |
| HT-003 Agreement bypass | **CONFIRMED (emulator)** | P-B succeeds. | **Simpler fix than the audit's.** No new `agreementAmount` snapshot field is needed. The rules can freeze `agreedAmount` once `agreementStatus == 'confirmed'`: no update path may change it (the negotiation rule `:142-156` already excludes confirmed; the transition rule must too), and `agreementStatus:'confirmed'` must only be writable via the artisan-accept rule (`:184-193`). Fewer moving parts and no trigger latency. |
| HT-004 Price overwritten at payment | **CONFIRMED (emulator + code)** | P-D succeeds. `JobService.initPayment` (`lib/core/services/job_service.dart:461-465`) writes the client value. The legitimate UI passes the read-only prefilled `job.agreedAmount` (`payment_screen.dart:63,88-98,289`), so **honest users never trigger this**; only a modified client does. | Fix is unchanged: remove `agreedAmount` from `initPayment` **and** forbid it in the `inChat→paymentPending` rule clause. These must ship together (see §5, B-1). |
| HT-005 Client-controlled auto-release time | **CONFIRMED (emulator + code)** | P-C succeeds. `timestampsForStatus(submitted)` uses device `DateTime.now()` (`job_service.dart:1058`). The cron trusts `autoReleaseAt` (`functions/index.js:229-233`). The UI banner reads `disputeWindowEndsAt` and hides itself when it's null (`job_detail_screen.dart:852-871`). | **Refined.** (a) Rules: on `inProgress→submitted` require `submittedAt == request.time` (i.e. a server timestamp) and forbid client writes to `autoReleaseAt` and `disputeWindowEndsAt`. (b) The job-update trigger sets both to `submittedAt + 14d`. (c) `_releaseEscrow` re-checks `submittedAt + 14d <= now` inside its transaction, which also neutralizes any legacy in-flight jobs with client-set values. The existing `(status, autoReleaseAt)` index stays valid. |
| HT-006 Funded cancel, no refunds | **CONFIRMED (emulator + code)** | P-E succeeds. `grep -n "refund" functions/index.js` finds only stats code. Nothing ever sets `payments.status = 'refunded'`, although the enum has it (`payment_model.dart:3`). | Unchanged, plus an **interim-safety question** (see Decision D2): closing the client cancel path before the refund callable exists removes the customer's only exit from a funded job. |
| HT-007 Dispute resolution moves no money | **CONFIRMED (code)** | `resolveDisputeWithRecord` (`job_service.dart:829-884`) changes status and text only. `_isJobPayable` (`functions/index.js:454-456`) excludes `resolved`. The `onJobCompleted` `resolved` branch only decrements the dispute counter. | Unchanged. Allowed outcomes need product decisions (D3). |

### 1.2 High findings

| ID | Verdict | Notes |
|---|---|---|
| HT-008 Admin deletes funded jobs | CONFIRMED (code) `admin_dashboard_screen.dart:6135-6170` | — |
| HT-009 Abandoned payment dead end | **CORRECTED** | The server side already supports resuming. `EscrowNotifier.initPayment` uses `AsyncValue.guard`, which **swallows** the `paymentPending→paymentPending` error, and `payment_screen.dart:304-306` never checks it, so the flow continues to the idempotent callable, which accepts `paymentPending` (`functions/index.js:1256`). The real dead end is **navigation**: the only routes to `/payment/:id` exist while the job is `inChat` (`job_detail_screen.dart:364`, `chat_screen.dart:207-241`), and `paymentPending` shows no action (`workflow_gate_service.dart:125-132`). **Fix:** add a "Resume payment" action for `paymentPending`, skip `initPayment` when the status is already `paymentPending`, and add the server-side stale-payment sweep. Severity stays HIGH (users strand), but the change is smaller. |
| HT-010 Nothing expires | CONFIRMED (code). Only two `onSchedule` exports exist. | — |
| HT-011 `inProgress` dead end | CONFIRMED (emulator P-F + code: the only `/dispute/` push is `job_detail_screen.dart:450`) | — |
| HT-012 No rework path | CONFIRMED (code) | Rework count and window reset need a decision (D4). |
| HT-013 5% fee shown, not charged | CONFIRMED (code) | See the new HT-041. |
| HT-014 Unlimited reviews | CONFIRMED (emulator P-G) | `review_screen.dart:216` already writes `reviews/{jobId}`, so enforcing `reviewId == jobId` **does not break** the legitimate client. |
| HT-015 Notification spoofing | CONFIRMED (emulator P-H) | Every client sender maps to an underlying document change (see §2.4), so a server-generated model is feasible. |
| HT-016 Lock without amount check | CONFIRMED (code). Exploitability **UNVERIFIABLE LOCALLY** | There's no public key in the repo and no client code reads `config`. Whether a `config/*` doc holds the public key (the comment at `firestore.rules:566` suggests so) needs a check of production data. The fix is cheap regardless: compare against the `payments` doc and the Paystack `amount`/`currency`. |
| HT-017 Double-counted auto-release | CONFIRMED (code) `functions/index.js:282-285` + `:320-322` + `:752-753` | — |
| HT-018 Artisan cancel kills the job | CONFIRMED (code) | Needs a decision on reopen behaviour (D6). |

### 1.3 Medium and low findings
All re-checked against the cited lines and **confirmed as stated**, except:
- **HT-022 (matching) is upgraded: blocked on data.** No client code anywhere writes artisan `latitude` or `longitude`. `grep` for `'latitude'`, `Geolocator.` and `geohash` outside `lib/models/` finds only the customer job-request screen (`service_request_screen.dart:158-209`), and artisan registration stores only free-text `location` (`artisan_registration_screen.dart:48-62`). The current proximity bonus therefore **never applies to any artisan**, and distance-first matching can't be implemented until artisan service location (and radius) is captured. Product decision D8.
- **HT-034:** the demo escrow path is **already non-functional for non-admins today**. Its first write (`demo_escrow_service.dart:44-46`, `escrow.status` with no status change) matches no rule. Gating or removing it breaks nothing that currently works.

### 1.4 New findings from Stage 1

| ID | Severity | Finding | Evidence |
|---|---|---|---|
| **HT-041** | **HIGH (financial)** | **The platform absorbs every Paystack fee.** The charge equals `agreedAmount` (`functions/index.js:1262,1284`), and the payout transfers that same full amount (`:563,624`) from `source:'balance'` (`:628`). Paystack deducts its processing fee from each settled charge and also charges per transfer, so every job leaves the balance short by those fees, and payouts will eventually fail for **insufficient balance**. Transfers also draw on the settled balance, so a payout made before a charge settles may fail. | Charge and payout amounts CONFIRMED (code). Fee schedule and settlement timing are **UNVERIFIABLE LOCALLY** (check the Paystack dashboard). Must be decided together with HT-013 (D1). |
| **HT-042** | MEDIUM | `payment_screen.dart:304` ignores `initPayment` failure (it's swallowed by `AsyncValue.guard`), so a legitimate failure (e.g. agreement not confirmed) surfaces later as a confusing callable error. | CONFIRMED (code) `escrow_provider.dart:113-117` |
| **HT-043** | LOW | There is no CI (`.github/workflows` is absent), so none of the test suites run automatically. `firestore-tests/package.json` runs only `escrow_payout.test.js`. | CONFIRMED |
| **HT-044** | MEDIUM (ordering hazard) | `QuoteService.submitQuote/withdrawQuote/rejectQuote/acceptQuote` call `_notifications.send` **without** try/catch (`quote_service.dart:81,105,126,154`). If the notification rules are tightened before these calls are removed, the quote write succeeds and then the method throws, so the UI reports failure for an action that actually happened. | CONFIRMED (code) |

---

## 2. Dependency map

### 2.1 Job document: the single shared dependency

```
                 firestore.rules /jobs (116-432)
                        ▲         ▲            ▲
      client writes ────┘         │            └──── read rules → open-jobs feed, chat pre-match
 JobService (job_service.dart)    │
   ├─ EscrowNotifier (escrow_provider.dart)
   │    ├─ job_detail_screen.dart (actions, cancel, agreement, slots)
   │    ├─ payment_screen.dart (initPayment)          ← HT-004 / HT-009 / HT-042
   │    ├─ job_completion_screen.dart (submit)        ← HT-005
   │    └─ secure_booking_screen.dart (direct hire)   ← HT-027
   ├─ QuoteService.acceptQuote → JobService.acceptQuote
   ├─ DisputeService → raise/resolveDisputeWithRecord ← HT-007
   ├─ ChatProvider.sendNegotiation → JobService.sendNegotiation
   └─ DemoEscrowService (already broken for non-admins)
 Admin SDK writers (bypass rules): _lockEscrow, _releaseEscrow, [new] timer trigger, refund/dispute callables
 Triggers reading job: onJobCompleted (stats, notifications), processEscrowRelease (payability, amount)
```

### 2.2 Money path

`payment_screen` → `JobService.initPayment` (rules) → callable `initializePaystackTransaction` (writes `payments`, `payment_init_locks`) → Paystack → `verifyPayment`/`paystackWebhook` → `_lockEscrow` (job + payments) → … → `confirmComplete` (client: job + `escrow_releases` + audit) **or** `autoReleaseEscrow` → `_releaseEscrow` → `processEscrowRelease` (reads job, `payments`, `artisan_private`, Paystack transfer) → transfer webhook.
**New components:** a refunds collection, a refund callable, refund webhook handling, a dispute-resolution callable, and a stale-payment sweep.

### 2.3 Trust and reviews
`review_screen` → `reviews/{jobId}` (rules) → `onReviewCreated` (marker under `artisans/{id}/appliedReviews/{reviewId}`) → `onArtisanRatingChanged` → `trustScore`. Job outcomes feed `_recordJobOutcome` via `onJobCompleted` (and the duplicate call in `_releaseEscrow`). Owner-writable inputs: `responseTimeMinutes`, `verificationStatus:id_submitted` (HT-019).

### 2.4 Notifications

| Client sender | Type | Underlying change a trigger can observe |
|---|---|---|
| `quote_service.dart:81` | quote_received | `jobs/{j}/quotes/{a}` created |
| `quote_service.dart:105` | quote_withdrawn | quote status → withdrawn |
| `quote_service.dart:126` | quote_rejected | quote status → rejected |
| `quote_service.dart:154` | quote_accepted | quote status → accepted |
| `dispute_service.dart:59` | dispute_raised | `disputes/{d}` created (already has a trigger) |
| `dispute_service.dart:111` | dispute_resolved | dispute status → resolved/dismissed (admin) |
| `escrow_provider.dart:207,230,253` | agreement_* | job `agreementStatus` change |
| `chat_service.dart:172` | message_received | `jobs/{j}/messages/{m}` created |
| `review_screen.dart:238` | review_received | `reviews/{j}` created (already has a trigger) |
| `verification_service.dart` (in a transaction, admin) | verification_* | admin-written; already allowed via `isAdmin()` |

Push delivery: `onNotificationCreated` → FCM → tap handling in `notification_provider.dart:98-126` (broken `Navigator.pushNamed`, HT-026).

### 2.5 Matching
`service_request_screen` (customer GPS) → `/artisans/:jobId` → `MatchingService.findMatches` (requires an index on artisans `category/isAvailable/approvalStatus/verificationStatus`). The open-jobs feed is `quote_provider.dart:41`. **Missing data:** artisan coordinates (D8).

---

## 3. Rules specification: per-transition field whitelist (core of Stage 2)

Every job update clause must allow only these keys (`affectedKeys().hasOnly([...])`), plus `lastUpdatedAt, lastUpdatedBy, updateVersion`. Also, in **every** clause: `customerId` is never in `affectedKeys`, and `artisanId` is only allowed in requested→matched. Derived from what `JobService` actually writes today, so the legitimate client keeps working unchanged except where marked ★.

| Transition | Actor | Allowed keys | Value checks |
|---|---|---|---|
| requested→matched | customer | status, artisanId, matchedAt | artisan eligible (existing); `matchedAt == request.time` |
| matched→inChat | customer | status | — |
| inChat→paymentPending | customer | status ★ (`agreedAmount` removed from client) | agreement confirmed + scheduling (existing) |
| paymentPending→escrowLocked | server only | — | (Admin SDK) |
| escrowLocked→inProgress | artisan | status, startedAt | `startedAt == request.time` |
| inProgress→submitted | artisan | status, completionImageUrls, beforePhotoUrls, artisanNotes, submittedAt ★ (no `autoReleaseAt`/`disputeWindowEndsAt`) | `submittedAt == request.time`; `completionImageUrls.size() > 0` |
| submitted→completed | customer | status, completedAt | `completedAt == request.time` |
| {escrowLocked, inProgress, submitted}→disputed | customer (later also artisan, D3) | status, disputeReason | — |
| {requested, matched, inChat, paymentPending}→cancelled | customer / artisan (per existing rule) | status, cancelledBy, cancellationReason, cancelledAt | `cancelledBy == request.auth.uid` |
| escrowLocked→cancelled | **removed from clients** (server callable, Stage 4) | — | — |
| disputed→resolved | **server callable** (Stage 4); admin client path retained only until then | — | — |

Sub-state rules already restrict their fields. One addition: the slot-confirmation rule requires `confirmedAppointment in resource.data.appointmentSlots` (HT-031).

`JobService` changes required: ★ `initPayment` stops writing `agreedAmount`; `timestampsForStatus(submitted)` stops writing `autoReleaseAt`/`disputeWindowEndsAt`; `updateJobStatus` already uses server timestamps for milestones (`timestampsForStatus`); `cancelJob` already writes `cancelledBy: _uid` (`escrow_provider.dart:274`). ✓

---

## 4. Prioritized remediation plan (maps to your Stages 2–7)

| Stage | Scope (issue IDs) | Key engineering choice |
|---|---|---|
| **2. Rules & backend authorization** | HT-001/002/003/005 (rules part), HT-014, HT-019, HT-020, HT-021, HT-023 (Firestore part), HT-029, HT-030, HT-031, HT-028 (after its trigger exists), HT-015 (interim) + regression tests | Per-transition whitelists (§3); `customerId`/`artisanId` immutability; `agreedAmount` frozen after confirmation; payout invariant `requestedBy == payment.payerId`. Notifications interim rule: sender and recipient must be the two parties of `jobId`, or a pre-match artisan→customer message on a `requested` job; types are tied to that relationship. The final lockdown comes in Stage 6. |
| **3. Payment init / verification / escrow integrity** | HT-004 (client), HT-005 (trigger + cron recheck), HT-016, HT-009/HT-042 (resume payment), HT-017, HT-041/HT-013 (per D1), HT-035 | Server timers; strict charge matching (`payments` doc + Paystack `amount`/`currency`); fee model implemented server-side, with the UI displaying only server-returned numbers. |
| **4. Cancellation, refunds, disputes** | HT-006, HT-007, HT-008, HT-011, HT-036 | Callables `cancelFundedJob` and `adminResolveDispute` (admin-checked, audited, idempotent). New collection `refunds/{jobId}`, Paystack Refund API (test mode), refund webhook handling. `processEscrowRelease` accepts `resolved` + release outcome (with partial amount). Admin delete becomes a soft-delete guard. |
| **5. Workflow state machines & confirmations** | HT-010 (expiry sweep), HT-012 (rework), HT-018 (reopen), HT-027 (direct-hire acceptance), HT-038, HT-032, HT-033, HT-037 | Additive transitions only, each with rules + `JobService` + `WorkflowGateService` + tests; no transition lets one party bypass the other's confirmation. |
| **6. Reviews, trust, notifications, matching** | HT-015 final (server-generated, `create: if false`), HT-044 ordering, HT-025, HT-026, HT-024, HT-022 (after D8 data capture), HT-028 server audit trail | A single `onJobUpdated` trigger for status/agreement notifications and audit; quote/message/review triggers; client senders removed in the same release as the rule lockdown. |
| **7. Full regression & E2E** | HT-043 CI; emulator E2E for all 14 workflows; device check of push routing | — |
| **8. UI redesign** | Out of scope until 2–7 are accepted | — |

---

## 5. Potentially breaking changes

| # | Change | Who/what breaks if mishandled | Mitigation |
|---|---|---|---|
| B-1 | Rules forbid `agreedAmount` on inChat→paymentPending | **Every payment** from the current app build (it still writes `agreedAmount`) | Ship the `JobService.initPayment` change in the same release. Mobile users on old builds stay blocked until they update. Consider a minimum-version gate, or temporarily allow `agreedAmount` **only if unchanged** (`request.resource.data.agreedAmount == resource.data.agreedAmount`), which accepts old builds safely. **Recommended.** |
| B-2 | Rules forbid client `autoReleaseAt`/`disputeWindowEndsAt` on submit | Every artisan submission from old builds | Same "allow only if equal to the existing value" technique won't work (the value is new). Use a transitional clause that permits but **ignores** these keys (the trigger overwrites them and the cron re-checks `submittedAt`), then remove it after the build is adopted. **Recommended.** |
| B-3 | Remove client cancel from `escrowLocked` | Customers lose their only exit from funded jobs until the refund callable ships | Ship B-3 with Stage 4, **or** ship it in Stage 2 together with an interim "Request cancellation" that creates an admin alert (D2). |
| B-4 | Notification create lockdown | Quote actions throw after succeeding (HT-044); in-app notifications stop | Deploy the triggers first, remove the client senders, then lock the rules, all in one coordinated release. |
| B-5 | `reviewId == jobId` | Nothing legitimate (the client already uses jobId) | — |
| B-6 | `customerId`/`artisanId` immutability | Nothing legitimate (only requested→matched writes `artisanId`) | — |
| B-7 | Suspension enforced in rules | Suspended users' in-flight jobs freeze mid-workflow | Define what suspension does to active jobs (D9): probably block new work and let admins settle existing work. |
| B-8 | Fee model change (D1) | The customer-visible total and the payout amount change | Product sign-off; apply only to jobs entering `paymentPending` after the release. |
| B-9 | `JobStatus.fromString` unknown → `unknown` | Screens that `switch` exhaustively on `JobStatus` | Compile-time: the analyzer flags every switch. |
| B-10 | Legacy production data | Jobs in flight under the old rules (e.g. `submitted` with client-set timers, `paid_escrow` from demo, `resolved` jobs with money stuck) | Requires a production data snapshot (UNVERIFIABLE LOCALLY). Plan a one-off admin reconciliation report before deploying. |

---

## 6. Required regression tests

**Rules (`firestore-tests/`, emulator):**
- Appendix A P-A to P-K converted to `assertFails` (P-F stays `assertFails`, P-L stays as a control). Add them to the `npm test` script.
- Per-transition positive tests using the **exact payloads `JobService` writes**, for every transition in §3. These prove legitimate customer and artisan flows still work.
- Negative tests per transition: an extra field, `customerId` change, `artisanId` change after match, wrong actor (other customer, other artisan, stranger, the job's customer acting as artisan and vice versa), wrong source status, client-time instead of `request.time`.
- `agreedAmount` immutable after confirmation (all clauses); a confirmed agreement is only reachable via the artisan rule.
- `escrow_releases` create by the original customer only; by an artisan → fail.
- Reviews: second review fails; `artisanId` mismatch fails; `reviewId != jobId` fails.
- Notifications: stranger → fail; party → allowed only under the interim relationship rule (Stage 2), then all client creates fail (Stage 6).
- `verifications`: self-approve fails; `artisans.responseTimeMinutes` owner write fails.
- Suspended actor: quote/match/transition fails.

**Functions (`functions/test/`, emulator + mocked `axios`):**
- `processEscrowRelease` refuses when `requestedBy` is neither `payment.payerId` nor `system`.
- `_lockEscrow` refuses on amount mismatch, currency mismatch, unknown reference, or reference belonging to another job; it's idempotent on redelivery.
- The timer trigger sets `autoReleaseAt = submittedAt + 14d`; `_releaseEscrow` refuses when `submittedAt + 14d > now` even if `autoReleaseAt` is in the past.
- Auto-release increments `completedJobs` by exactly 1.
- Duplicate payment init (concurrent, and within the reuse window) → one Paystack transaction (extends the existing test).
- Stage 4: refund happy path, Paystack refund failure → retryable + admin alert, duplicate refund request → single refund, refund webhook redelivery; dispute outcomes release/refund/split each produce exactly one money movement; a disputed job is never paid by auto-release or confirmation.
- Stage 5: expiry sweep (stale requested → expired with quotes closed; stale paymentPending verified-unpaid → inChat).

**Flutter (`test/`):**
- `WorkflowGateService.describeStep` for every status × role, including the new resume-payment / dispute / rework actions.
- Widget tests: job detail renders no action the rules would reject (e.g. no Cancel during `inProgress`).
- Payment screen skips `initPayment` when the job is already `paymentPending`.
- Push routing uses GoRouter (unit test on the route resolver plus a fake router).

---

## 7. Acceptance criteria per stage

| Stage | Accepted when |
|---|---|
| 2 | All converted Appendix A probes fail as required. Every legitimate `JobService` payload passes its positive rules test. Payout invariant test passes. Existing suites still green (Flutter 99, functions 37, rules 26 → plus new). No rule is less restrictive than before for any actor (reviewed by diff). |
| 3 | No client can influence the charged amount, the payout amount or the review window (tests). Escrow locks only on an exact payment match. Abandoned payment is resumable from the UI and auto-reverts server-side. Fee model matches the displayed numbers end to end in Paystack test mode. Auto-release counts once. |
| 4 | Every funded terminal state has exactly one money outcome (payout, refund or split) recorded and confirmed by webhook, or flagged to admin. Funded jobs can't be hard-deleted. Customer can dispute during `escrowLocked`/`inProgress`. All money callables check `admins/{uid}` or job party server-side and write audit logs. |
| 5 | The state diagrams in the audit §3.2 (as amended by product decisions) match the implementation 1:1. Each new transition has rules + service + UI + tests. No unreachable or dead-end non-terminal state remains (verified by a `WorkflowGateService` test that every non-terminal status offers some actor a valid action or a system timeout). |
| 6 | No client can create notifications. Every status transition notifies the correct recipients (trigger tests). Push taps navigate (device check). One review per job. Trust inputs are server-only. Matching ranks by distance within the radius for artisans with captured locations. |
| 7 | CI runs all suites on every push. Emulator E2E passes for all 14 workflows, including malicious-actor variants. Manual Paystack test-mode run of pay → complete → payout and pay → cancel → refund. |

---

## 8. Product-owner decisions required (blocking where noted)

| # | Decision | Blocks |
|---|---|---|
| D1 | **Fee model:** is there a 5% platform fee? Who pays it (added to the customer's charge, or deducted from the artisan payout)? Who absorbs Paystack processing and transfer fees (HT-041)? | Stage 3 |
| D2 | **Refund policy for funded jobs:** who may cancel after payment (customer only? artisan too?), refund amount (full? minus Paystack fees?), and the interim behaviour before refunds ship (admin-mediated request vs. keep the current cancel path open). | Stage 2 (B-3), Stage 4 |
| D3 | **Dispute outcomes:** release / refund / split? Can artisans raise disputes? Is there a deadline for the artisan's response? | Stage 4 |
| D4 | **Rework:** allowed? Maximum count? Does it restart the 14-day window? | Stage 5 |
| D5 | **Expiry durations:** open job (e.g. 14 days?), pending agreement (e.g. 3 days?), abandoned payment (e.g. 24 h?). | Stage 5 (sweep), Stage 3 (payment) |
| D6 | **Artisan backs out before funding:** reopen the job and revive the closed quotes, or cancel? | Stage 5 |
| D7 | **Direct hire:** require explicit artisan acceptance before `matched`? | Stage 5 |
| D8 | **Artisan location:** GPS at registration, a geocoded service address, or both? Service radius (fixed vs. artisan-chosen)? | Stage 6 matching |
| D9 | **Suspension effect on in-flight jobs**, and whether exact customer addresses are hidden until match (HT-023). | Stage 2 |
| D10 | **Production data:** can you provide counts of jobs per status, `resolved` jobs with held funds, and whether a `config/*` doc contains a Paystack public key? | Stage 2 deploy readiness, HT-016 severity |

## 9. Assumptions that couldn't be verified locally
- Deployed rules, functions and indexes match the repo.
- Paystack account: fee schedule, settlement timing, refund webhook event names and payload (verify against Paystack docs in test mode before Stage 4), transfer balance source, whether the public key is exposed.
- `BANK_CODES` correctness (`functions/index.js:355-376`).
- Push behaviour on real devices (HT-026 is concluded from code: under GoRouter's navigator, `Navigator.pushNamed` has no `onGenerateRoute`).
- App Check isn't present (`pubspec.yaml` has no `firebase_app_check`). Callables rely on Auth only, which is acceptable for now but worth noting for Stage 7.
