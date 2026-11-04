# HandyTrust — Stage 7: Full Regression, End-to-End Testing & Release Readiness

Date: 2026-11-03 · Scope: verification only (Stages 1–6), per the Stage 7 brief.

**Constraints observed.**
- No production Firebase or Paystack access.
- No real money moved; no deployment, commit or push.
- No security rule weakened; no production code changed.
- Every run used local emulators.
- Test-only changes are listed in §10.3.

**Status labels** used throughout:
- **Verified working**
- **Partially verified**
- **Not tested**
- **Failed**
- **Blocked by external configuration**

---

## 1. Executive summary

- **Automated regression: 504 tests, all passing.** That is 157 Flutter, 196 Functions, 130 Firestore rules, 9 Storage rules, and 12 new end-to-end trigger scenarios.
- **The deployed Cloud Functions now run in the Functions emulator for the first time.** Twelve scenarios drive them through ordinary Firestore writes.
  - This closes the "wiring reviewed, not run" risks carried since Stage 3 (Stage 3 R-9, Stage 5 R-1, Stage 6 R-2).
  - The scenarios cover location privacy, booking normalization, agreement and quote/chat/dispute/review notifications, review timers, rework, paid-cancellation alerts, abandoned checkout, and fail-closed payouts.
- **New defects found (none fixed — reported for approval, §10):**
  - **F-1 Chargebacks are not handled — GO-LIVE BLOCKER.** The webhook acknowledges `charge.dispute.*` with `200 OK` and does nothing (§12).
  - **F-2 High (privacy).** Photo EXIF metadata, including GPS, is stripped only from images larger than 500 KB (600 KB for avatars). Smaller job photos can reveal a customer's exact home location to every artisan on an open job. This undermines D9.
    - Found by code inspection. It needs confirmation on a real device.
  - **F-3 Low.** The address backfill overwrites a *newer* private address with a *stale* main-document address. No current client flow can produce that state. Reproduced in a test and pinned as current behaviour.
  - **F-4 Low (UX).** Opening a job the user isn't allowed to see shows the raw `permission-denied` error text. No data is exposed.
  - **F-5 Medium.** `responseTimeMinutes` (15% of the trust score) is still a constant 30. The data needed to compute it is partly discarded today (§13).
- **Not verifiable in this environment (blocked):**
  - all Paystack test-mode checks, because no test keys were provided (§5);
  - all real-device push and permission tests, because no physical device was available (§6).

  These are owner actions, not passes.
- **Verdict: NOT READY for production go-live.** The verdict would be "ready for a closed pilot with no real payments", after the F-2 fix and the Stage 6 migrations. §16 explains this.

---

## 2. Environment and versions

| Item | Value |
|---|---|
| OS | Windows 11 Home 10.0.26200 |
| Flutter / Dart | 3.41.6 / 3.11.4 |
| Node (local) | **v24.12.0** — `functions/package.json` `engines` is **node 20** (see risk K-7) |
| firebase-tools | 15.22.0 |
| Java (emulators) | 25 |
| firebase-functions / firebase-admin / axios | 5.1.1 / 12.7.0 / 1.18.0 |
| @firebase/rules-unit-testing / firebase (JS) | 3.0.4 / 10.14.1 |

**Emulators used:**
- Firestore `127.0.0.1:8090` for the Functions unit and emulator suites and the rules suites.
- Functions `5701` with Firestore `8790` for the end-to-end harness, in an isolated scratch config (`demo-handytrust-e2e`).
- Storage `9599` with Firestore `8490` for the Storage rules suite.

**Projects:** demo or test project IDs only. No production project was referenced.

**Secrets:**
- A dummy `functions/.secret.local` (`sk_test_DUMMY_STAGE7_EMULATOR_ONLY`) was created so the emulator could load secret-bound functions.
- It was **deleted after the run** (verified absent).
- No Paystack or FCM endpoint was contacted. The log shows no outbound attempts, and no FCM tokens or bank details existed.

---

## 3. The 14 workflows

The workflow IDs come from the audit report, §2.

**Evidence key:**
- **R** = Firestore rules suite
- **F** = Functions unit/emulator suite
- **E** = new end-to-end trigger harness
- **D** = Flutter tests
- **S** = static inspection

| # | Workflow | Result | Evidence and gaps |
|---|---|---|---|
| A | Auth & account | **Partially verified** | R: suspension modes, admin-claim bypass blocked, self-escalation blocked. Email sign-in, verification and reset flows run through Firebase Auth and were **not tested** (no Auth emulator UI run). Account deletion is still a manual admin callable |
| B | Customer onboarding | **Partially verified** | D/R: job creation payload accepted (legitimate-payload suite). No end-to-end UI run |
| C | Artisan onboarding & verification | **Verified working** (server) / UI **Not tested** | R: verification cannot be self-approved; trust inputs are server-only; service area is bounded to `maxServiceRadiusKm`. The admin approval notification is admin-written (allowed) |
| D | Job posting lifecycle | **Verified working** (server) | R + F: 7-day expiry, reopen, withdraw, cancel. E: an old-build job with an exact location is stripped and moved within seconds |
| E | Discovery & matching | **Verified working** (logic) / **Partially verified** (queries) | D: 11 new edge-case tests (§8). Geohash queries need the composite indexes (Stage 6 M-4), which were not exercised against production indexes |
| F | Quotation | **Verified working** | R: 48 h validity, server `updatedAt`. E: a new quote notifies the customer. F: decline, closed and withdrawn quotes notify the right party |
| G | Negotiation & agreement | **Verified working** | R: agreement can't be bypassed; price locked. E: pending and confirmed agreement steps notify the other party (server-generated) |
| H | Booking & scheduling | **Verified working** | R: 24 h artisan confirmation with server time. E: an old-build `matched` job is normalized to `awaitingArtisan` with `bookingRequestedAt`; the artisan is notified with deep link `/job/{id}`; confirmation notifies the customer |
| I | Payment & escrow | **Verified working** (fake Paystack) / **Blocked by external configuration** (real test mode) | F: integer-kobo charge, lock decisions, retry, abandonment. E: cancelling during checkout abandons the pending payment (`abandonReason: job_cancelled`) |
| J | Service execution | **Verified working** | E: submission sets **both** timers from the server `submittedAt` + 14 days, overwriting a client-backdated `autoReleaseAt`; rework clears both and notifies the artisan; completion counts once in stats. E: a payout without bank details fails closed (`no_bank_details`), the job shows `payoutStatus: delayed` and the artisan is told; a release requested by a non-payer is refused |
| K | Dispute resolution | **Verified working** (fake Paystack) / **Blocked** (real) | E: an artisan-raised dispute creates deterministic admin alerts, notifies the customer and increments `openDisputeCount`. F: release, full refund and split settlements; freeze checks |
| L | Reviews & trust score | **Verified working** / **Failed** on one input | E: a review aggregates once (4 → 4.5 over two reviews), triggers the trust-score recompute and notifies the artisan. **F-5:** the response-time component is constant (§13) |
| M | Notifications | **Verified working** (server, in-app) / **Blocked** (push on device) | E: 14 `onNotificationCreated` runs, all with deep-link routes. R: client creates are refused. Push delivery: §6 |
| N | Admin workflows | **Partially verified** | F: callables for refunds, retries, freezes, settlements and the backfill. Admin dashboard UI **not tested** end to end |

---

## 4. Security regression matrix

All rows are **Verified working** unless marked otherwise.

| Area | Threat | Control | Test evidence |
|---|---|---|---|
| Escrow | Client forces `escrowLocked`, self-release, or forged `escrow_releases` | Server-only payments; release needs `submitted` and payer | `escrow_payout.test.js` P0-1 groups (115–412); E: non-payer release refused |
| Escrow | Exploit chain from the audit (§2.4) | Fail-closed chain | `escrow_payout.test.js:305` |
| Amounts | Client-set or overwritten `agreedAmount` | Bounded, ownership-scoped, ≥ ₦3,212 | `escrow_payout.test.js:244`; Stage 4 suites |
| Payouts | Payout to a fraud-frozen artisan (auto or manual) | Freeze check in the funds-claim transaction just before every transfer | `stage4_settlement_emulator`, `stage6_emulator` (on_hold) |
| Payouts | Double payout on retry or webhook redelivery | Funds mutex; create-once references `{jobId}-pN` | `stage3_escrow_emulator`, `stage4_*` |
| Refunds | Refund marked done before Paystack confirms | Only Paystack-reported status advances it | `stage4_pure`, `stage4_settlement_emulator` (real Paystack: **Blocked**) |
| Webhook | Forged webhook | HMAC-SHA512 signature check | `webhook_signature.test.js` |
| Roles | Self-granted admin, privilege escalation | `admin` custom claim; protected fields | `security_regression` Appendix A + Stage 1/2 |
| Trust | Self-written rating, trust score or response time | Protected on create and update (rules 172–200) | `security_regression`; `review_rating_pipeline` |
| Reviews | Duplicate or misattributed reviews | `reviews/{jobId}`; server re-checks parties and status | `review_rating_pipeline`; E |
| Suspension | Suspended user starts new activity | `isNotSuspended`, `isFreezingSuspended` | `security_regression:381`, `:935` |
| Notifications | Spoofed notifications | Client create denied (admin only) | `security_regression` Stage 6; S: the only client writer is the admin verification flow |
| Deep links | Open redirect or admin route via push | `safeNotificationRoute` allow-list | `stage6_test.dart` |
| Location | Artisans read the exact address of open jobs (P-K) | Private subcollection; readable only after booking confirmation | `security_regression:1022`; E; migration suite |
| Location | Address exposed through EXIF in photos | **None for images ≤ 500 KB** | **Failed (static), F-2** |
| Storage | Cross-job photo or evidence access; avatar tampering | Cross-service rules | `storage_rules.test.js` (9) |
| Audit | Forged or edited audit rows | Create validation; no update/delete | `security_regression:1094` |
| Cost/DoS | Rules expression budget on large documents | Diff computed once | `security_regression:452` |
| Chargebacks | Customer chargeback after payout | **None** | **Failed, F-1 (§12)** |

---

## 5. Paystack test-mode results

**Status: Blocked by external configuration.** No Paystack test secret key was provided. The brief forbids production credentials, so none were used. Every money path was exercised against the in-code fake (`_setPaystackFakes`) instead. Those results are shown as **Verified working (fake)**.

| Checklist item (source) | Fake-Paystack result | Real test mode |
|---|---|---|
| S3-1 Pay ₦10,000 → charge ₦10,500; `paystackFeesKobo` recorded | Verified working (fake) | **Blocked** |
| S3-2 Close checkout → resume → single charge | Verified working (fake) | **Blocked** |
| S3-3 Unpaid 24 h → back to `inChat` + notification | Verified working (handler); schedule wiring not run (no Pub/Sub emulator) | **Blocked** |
| S3-4 Cancel during checkout, then pay → `requiresRefund` + alert | Verified working; **E**: abandon on cancel | **Blocked** |
| S3-5 Payout is ₦10,000, not ₦10,500 | Verified working (fake) | **Blocked** |
| S3-6 / S4-5 Webhook redelivery → no change | Verified working (fake) | **Blocked** |
| S4-1 Full refund ₦10,500, kobo unit | Verified working (fake) | **Blocked** — confirms the amount unit |
| S4-2 Split ₦6,000 / ₦4,500 | Verified working (fake) | **Blocked** |
| S4-3 Forced refund failure → retry | Verified working (fake) | **Blocked** |
| S4-4 Fraud freeze → frozen → reactivate → paid once | Verified working (fake) | **Blocked** |
| S4-6 `GET /refund?transaction=` list filter | — | **Blocked** |

**Paystack API assumptions still unconfirmed.** Confirm each in test mode or with Paystack support before go-live:
1. **Refund amount unit.** The code assumes kobo.
2. **List-refunds `transaction` filter.** The code assumes it is supported.
3. **Fetch-refund endpoint and status values.** The code assumes `pending`, `processing`, `processed` and `failed`, with `needs-attention` treated as non-terminal.
4. **Retrying a `needs-attention` refund.** Currently a manual admin action.
5. **Settlement-to-balance configuration.** Transfers fail if settlements go to a bank account instead of the Paystack balance (Stage 3 R-7, Stage 4 R-3). **High operational risk.**
6. **Transfer fees above ₦50,000.** These are absorbed per D1; verify the tier.
7. **International cards disabled** at the account level (D1 refinement). This is a dashboard setting and cannot be checked from code.
8. **Chargeback webhook event names and payloads** (§12).

---

## 6. Real-device results

**Status: Blocked by external configuration.** No physical Android or iOS device was available. As the brief requires, no emulator result is substituted.

| Scenario | Result | Code-level evidence (not a substitute) |
|---|---|---|
| Push — foreground | **Not tested (blocked)** | `onNotificationCreated` ran 14 times in E; it sends only when the user has an FCM token |
| Push — background / terminated | **Not tested (blocked)** | The push data includes `route`; the app routes on tap via `safeNotificationRoute` |
| Push — logged out | **Not tested (blocked)** | Needs a device check that the token is removed on sign-out |
| Push — invalid target route | **Verified working** (unit) / device **Not tested** | `stage6_test.dart`: unknown or external routes fall back to `/notifications` |
| Push — duplicates | **Verified working** (server) | Deduplication by `event.id` + recipient (F, E) |
| Push — deleted job | **Partially verified** | S: a deleted job shows "Job not found". An unauthorized job shows raw error text (F-4) |
| Location permission prompt; denial falls back to manual entry | **Not tested (blocked)** | S: when-in-use only (below) |
| EXIF stripping on uploads | **Not tested (blocked)** | **F-2** found statically |

**Static confirmation of "no background tracking": Verified working.**
- **Android manifest:** `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` only; no `ACCESS_BACKGROUND_LOCATION`.
- **iOS `Info.plist`:** `NSLocationWhenInUseUsageDescription` only; no `Always` key and no `UIBackgroundModes` location.
- **Code:** no `getPositionStream`. `getCurrentPosition` is called only on user action, in `service_request_screen.dart:189` and `service_area_card.dart:60`.

**Device test script for the owner (once Paystack test mode is available):**
1. Sign in on two devices (customer and artisan).
2. Exercise each push case above with the app in the foreground, the background and terminated.
3. Sign out and confirm no push arrives.
4. Delete a job and tap its old notification.
5. Upload a small (< 500 KB) photo that has GPS EXIF, download it from Storage and inspect the metadata.

---

## 7. Address-migration verification (`adminBackfillJobLocationPrivacy`, Stage 6 M-2)

**Suite:** `functions/test/stage7_migration_emulator.test.js`. It runs against the emulator only and was **never run against production**. Result: 10/10 passing.

| Requirement | Result |
|---|---|
| Pagination: 23 jobs, page size 5 → 5 pages, every job examined once, all 23 moved, no exact fields left | **Verified working** |
| Page size divides the total exactly → a final empty page ends cleanly | **Verified working** |
| Rerun safety: a second full run moves 0 and does not rewrite private docs (`movedAt` unchanged) | **Verified working** |
| Interrupted run resumes from `nextCursor`; restarting from the beginning is also safe | **Verified working** |
| Preservation: all non-location fields unchanged; exact values copied unchanged | **Verified working** |
| An existing coarse area (newer app) is not recomputed | **Verified working** |
| Partial or null legacy fields: only real values moved; nulls removed; no coarse point invented without coordinates | **Verified working** |
| No legacy exposure through side channels: no notifications, alerts or audit rows created; no address in any server log statement (S) or notification body (S) | **Verified working** |
| Newer changes not overwritten | **Failed — F-3** (§10) |

**Operational notes:**
- The callable processes 300 jobs per call, with one transaction each. Operators repeat with `nextCursor` until it is `null`.
- The onCreate trigger (E) covers jobs created by old builds after the deploy.

---

## 8. Matching and location results

**Suites:** `test/stage6_test.dart` (existing) and the new `test/stage7_matching_test.dart` (11 tests, all passing).

| Requirement | Result |
|---|---|
| Inside / outside the radius | **Verified working** |
| Boundary: exactly on the radius is included; 1 m short is excluded | **Verified working** |
| Missing coordinates: the job without a location lists everyone as "unknown distance", ranked by quality, none hidden | **Verified working** |
| Invalid coordinates: NaN artisan coordinates are dropped. Out-of-range values give no coarse area. Rules refuse latitude outside ±90, longitude outside ±180 and radius outside [1, `maxServiceRadiusKm`] | **Verified working** |
| Changed location: re-ranked on the next query; the feed follows the artisan's new location | **Verified working** |
| Configured maximum radius: 25 km selects a geohash precision whose 3×3 neighbourhood covers it (checked for 5, 10, 19 and 25 km) | **Verified working** |
| Default radius (10 km) when the artisan has none; zero or negative falls back to the default | **Verified working** |
| Sorting: distance-first in 2 km bands; quality only within a band; ties go nearest first | **Verified working** |
| Fallback: artisans without a service area appear after in-range ones; out-of-range artisans are never added by the fallback | **Verified working** (S: `matching_service.dart:63-79`) |
| No background tracking | **Verified working** (§6) |
| Query limits: 100 artisans per verification status per neighbourhood (Stage 6 R-4) | Accepted risk; the nearest artisans aren't guaranteed in very dense areas |

---

## 9. Compatibility and recovery

| Scenario | Result |
|---|---|
| Old build writes an exact location on create | **Verified working** (E: stripped and moved within seconds; Stage 6 M-6 window) |
| Old build creates `matched` without booking fields | **Verified working** (E: normalized and notified) |
| Old build backdates `autoReleaseAt` | **Verified working** (E: the trigger overwrites it from `submittedAt`) |
| Old build writes notifications after the rules lockdown | **Partially verified.** The writes are refused (R); the UI error noise of Stage 6 M-1 still applies. Rollout order: functions → forced app update → rules |
| Trigger redelivery (at-least-once delivery) | **Verified working** (F: deduplicated notifications, review marker, deterministic alerts, create-once settlements) |
| Interrupted migration | **Verified working** (§7) |
| Payout failure recovery (no bank details) | **Verified working** (E: `failed` / `delayed` / artisan told) and admin retry (F) |
| Paystack outage or timeout during refund (`submit_unknown`) | **Verified working** (fake: reconciled by `reconcileRefunds`) |
| Scheduled sweeps (`expireMarketplaceDeadlines`, `expireAbandonedPayments`, `reconcileRefunds`, `autoReleaseEscrow`) | **Partially verified.** Handlers are tested; the schedule wiring is **not tested** (the emulator ignores schedules without Pub/Sub) |
| Node 20 runtime (production) | **Not tested.** All suites ran on Node 24 (K-7) |

---

## 10. Failed tests and root causes

### 10.1 Test-environment issues (not product defects)

| # | Symptom | Root cause | Resolution |
|---|---|---|---|
| T-1 | First harness run: every trigger crashed with `TypeError: Cannot read properties of undefined (reading 'now')` at `index.js:1934` | The **Functions emulator** wraps `firebase-admin` in a Proxy that returns `admin.firestore` as `fn.bind(target)`. That drops its static members (`Timestamp`, `FieldValue`). This is firebase-tools 15.22.0 `functionsEmulatorRuntime.js:44-54`. Production loads `firebase-admin` unproxied, and the same code passes 196 plain-Node tests | Test-only preload shim (scratchpad, injected through `NODE_OPTIONS`) that re-attaches the statics. Optional hardening, a **production change not made**: import `Timestamp` and `FieldValue` from `firebase-admin/firestore` |
| T-2 | Review aggregation timed out at 25 s in run 3 | Emulator cold start per function (11–31 s observed); the trigger completed just after the limit | Harness wait limit raised to 60 s; passed |
| T-3 | "Port taken" on reruns | Orphaned emulators from earlier stages (PIDs 30304, 30112, 30460, 22532, 10604). Stopping them was not permitted in this session | Moved to fresh ports. **Owner:** `Stop-Process -Id 30304,30112,30460,22532,10604` |

### 10.2 Product defects (documented, not fixed; each fix needs your approval)

**F-1 — Chargebacks not handled. Severity: Critical. GO-LIVE BLOCKER.** See §12.

**F-2 — EXIF/GPS metadata kept on small images. Severity: High (privacy, D9).**
- **Paths affected:**
  - `service_request_screen.dart:86` (job photos)
  - `dispute_screen.dart:263`
  - `job_completion_screen.dart:222`
  - `chat_screen.dart:573`
  - `job_detail_screen.dart:1287`
  - `profile_service.dart:34` (threshold 600 KB)
- **Why it happens:** each path re-encodes (which strips EXIF, since `keepExif` defaults to false) **only above the size threshold**. Below it, the original bytes are uploaded unchanged. On Android, `image_picker` with `imageQuality` copies the original EXIF, GPS included, into its output.
- **Impact:** any artisan account can read open-job photos (Stage 6 Storage rules), so the photo can reveal the exact location that D9 hides.
- **Proposed fix (production, needs approval):** always re-encode through `FlutterImageCompress.compressWithList(..., keepExif: false)`, whatever the size. Optionally add a server-side check.
- **Verification:** needs a real device.

**F-3 — Backfill can overwrite a newer private address. Severity: Low.**
- **Where:** `_protectJobLocation` (`index.js:1925-1940`) merges main-document exact fields into `private/location` unconditionally.
- **When it happens:** only if a job holds legacy main-document fields *and* a later private write. The app writes both documents atomically at creation and has no edit-location flow, so no current client can produce this.
- **Proposed fix:** read the private document inside the transaction. If it exists, only delete the main-document fields and don't merge.
- **Test:** pinned as current behaviour in `stage7_migration_emulator.test.js` ("Known limitation").

**F-4 — Unauthorized job deep link shows raw error text. Severity: Low (UX).**
- **Where:** `job_detail_screen.dart:46` renders `Error: $e`.
- **Proposed fix:** show "You don't have access to this job" and return to the home or notifications screen. This is UI copy only.

**F-5 — Response-time trust input not computed. Severity: Medium (accuracy).** See §13.

### 10.3 Test-only changes made in Stage 7

**Added:**
- `functions/test/e2e_triggers.functions-emulator.test.js` — 12 scenarios. Kept out of `npm test` because it needs the Functions emulator; the header explains how to run it.
- `functions/test/stage7_migration_emulator.test.js` — 10 tests, added to the `npm test` list in `functions/package.json`.
- `test/stage7_matching_test.dart` — 11 tests.

**Outside the repo:**
- Scratchpad emulator configs and the T-1 shim.

**Created and deleted:**
- The dummy `functions/.secret.local`.

**No production source file was changed.**

---

## 11. Risks by severity (open at the end of Stage 7)

| Severity | # | Risk | Owner / plan |
|---|---|---|---|
| **Critical** | K-1 | Chargebacks unhandled (F-1) | Implement before go-live (§12) |
| **High** | K-2 | Paystack test-mode checklist and API assumptions unconfirmed (§5) | Owner, with test keys |
| **High** | K-3 | Settlement-to-balance configuration could make every payout fail | Owner, with Paystack |
| **High** | K-4 | EXIF/GPS leak on small images (F-2) | Fix (approval) and device-verify |
| **High** | K-5 | No real-device push or permission verification (§6) | Owner device test |
| **High** | K-6 | Pre-deploy data migrations not yet run. Stage 3 M-6 (stuck `pending` releases with a transfer code), Stage 4 M-1/M-3/M-6, Stage 5 M-1/M-2, Stage 6 M-2/M-4. Skipping Stage 3 M-6 risks a **double payout** | Release sequence (§15) |
| Medium | K-7 | Tests ran on Node 24; production runs Node 20 | Re-run `npm test` on Node 20 before deploy |
| Medium | K-8 | Scheduled-function wiring not run (no Pub/Sub emulator) | Watch the first scheduled runs in staging logs |
| Medium | K-9 | Trust response-time constant (F-5) | §13 proposal |
| Medium | K-10 | Old-build compatibility windows: notification errors (Stage 6 M-1); exact location exposed for a few seconds (Stage 6 M-6) | Forced minimum app version |
| Medium | K-11 | Rework has no resubmission deadline (Stage 5 R-3, your decision) | Policy |
| Medium | K-12 | Admin UI, auth flows and full UI journeys not tested end to end | Manual QA pass (Stage 8 candidate) |
| Low | K-13 | F-3 backfill overwrite; F-4 raw error text | Optional fixes |
| Low | K-14 | Self-declared artisan location; 100-candidate query cap; sweeps capped at 500 per run | Accepted for MVP |
| Low | K-15 | Orphaned local emulator processes (T-3) | Owner |

---

## 12. Chargeback assessment

**Finding: not implemented (Failed). GO-LIVE BLOCKER.**

- **Evidence:** `paystackWebhook` handles only `charge.success`, `transfer.*` and `refund.*` (`index.js:76-149`). Every other event returns `200 OK` with no record. There is no `chargeback` or `charge.dispute` reference anywhere in `functions/` or `lib/`.
- **Why it matters for an escrow model:**
  - A customer can dispute the card charge with their bank after the platform has paid the artisan.
  - Paystack then deducts the disputed amount from the merchant balance or future settlements. The platform absorbs the loss, the event is invisible to admins, and the artisan's payout cannot be held back.
  - A chargeback raised while funds are still in escrow could also be paid out regardless.

**Recommended remediation.** This is production work. It needs approval and confirmation of Paystack's event names and payloads; the dispute events are believed to be `charge.dispute.create`, `charge.dispute.remind` and `charge.dispute.resolve`.

1. **Record every dispute event** in an append-only `chargebacks/{paystackDisputeId}` document. Link it by transaction reference to the payment and job. Write a `financial_events` row and a deterministic `admin_alerts` entry.
2. **Freeze automatically if funds are still held.** Add a payment-level freeze (`chargebackOpen`) that `_processEscrowRelease`'s final funds-claim check refuses, the same pattern as fraud freezes. This stops auto-release and manual payout.
3. **If already paid out:**
   - mark the job and payment `chargeback`;
   - alert an admin;
   - optionally put the artisan's *future* payouts on hold, following a policy you decide (D-decision needed: recover from the artisan or absorb).
4. **Respond to the dispute:** an admin evidence pack (chat, agreement, completion photos, timestamps) and the Paystack dashboard response, within Paystack's deadline. `remind` events re-alert.
5. **On resolve:** release the freeze if the merchant won; if lost, record the loss and adjust ledgers.
6. **Tests:** signature-verified webhook, idempotent redelivery, escrow freeze before release, a post-payout case, and test-mode confirmation of the payloads.

---

## 13. Trust-score response time (15%) — available data and proposed definition

**Current state (verified):**
- `responseTimeMinutes` defaults to 30. The rules lock it on create and protect it on update (rules 181, 186–200).
- Nothing computes it, so the component is identical for every artisan (`_computeTrustScore`, `index.js:2490-2506`).

**Available data and its reliability:**

| Source | Server-trustworthy? | Notes |
|---|---|---|
| `bookingRequestedAt` → `bookingConfirmedAt` (direct hire / quote acceptance → artisan confirms) | **Yes.** Rules require `request.time` (rules 701, 716); the trigger sets `bookingRequestedAt` for old builds | **But** `_reopenJob` deletes both fields when a booking expires or the artisan withdraws (`index.js:2027`), so declines and no-shows leave no record today |
| Job `createTime` → first quote `updatedAt` | **Yes** (quote `updatedAt` is server-enforced, Stage 5) | Measures speed to quote on open jobs; depends on when the artisan saw the job |
| Chat messages `createdAt` | **No.** The message create rule does not enforce `request.time` (rules 499–508); a client can backdate it | Not usable until it is server-enforced |

**Proposed measurable definition (not implemented):**
- **Event:** a *booking response*. It starts at `bookingRequestedAt` and ends at the first of:
  - confirmed (`bookingConfirmedAt`);
  - artisan withdrew or declined;
  - expired (24 h, `bookingConfirmationHours`).
- **Response minutes:**
  - confirmed or declined: `end − start`;
  - **expired:** counted as the full **1,440 minutes** (24 h);
  - **declined or withdrawn:** counts as a *response* at its time. This is fast, honest declining; it is not penalized as "slow" (track decline rate separately if needed).
- **Quotes (secondary signal, 0% weight initially):**
  - an **unanswered** open job is not counted;
  - a **withdrawn** quote doesn't affect response time;
  - an **expired** quote (48 h) doesn't affect it either, because quote validity concerns price, not responsiveness.
- **Score:** the **median** over the artisan's last 20 booking responses within 90 days, which is robust to one-off outliers. Feed it to the existing `_trustResponseTimePoints`.
  - **Fewer than 3 responses:** keep the neutral 30-minute default.
- **Recorded server-side:** append to `artisans/{id}/booking_responses/{jobId}-{n}` (server-only) in the trigger and the sweep *before* `_reopenJob` clears the fields. Recompute in the same transaction.
- **Prerequisites:**
  - keep or log the booking timestamps on reopen;
  - optionally server-enforce message `createdAt` if chat speed is added later.

---

## 14. Go-live blockers

| # | Blocker | Status |
|---|---|---|
| B-1 | Chargeback handling (F-1, §12) | **Open — implement** |
| B-2 | Paystack test-mode checklists, Stages 3 and 4 (§5), including refund units and the list filter | **Blocked by external configuration** |
| B-3 | Paystack settlement-to-balance configuration and international-cards setting confirmed | **Blocked by external configuration** |
| B-4 | EXIF/GPS stripping on every upload (F-2) and device confirmation | **Open — fix needs approval** |
| B-5 | Real-device push and permission test (§6) | **Blocked by external configuration** |
| B-6 | Pre-deploy migrations executed and verified in staging (§15 steps 3–4); especially Stage 3 M-6 (double-payout guard) | **Not yet run (by design)** |
| B-7 | Legal and account approvals noted in Stage 3 §2 (escrow and holding of funds, terms, fees disclosure) | **Owner** |

---

## 15. Recommended release sequence

Each step needs your approval; none were performed.

1. **Approve and implement** F-1 (chargebacks) and F-2 (EXIF), plus optionally F-3 and F-4. Re-run all suites, including the e2e harness, on **Node 20**.
2. **Staging project** with Paystack **test** keys:
   - deploy functions, rules, indexes and Storage rules;
   - run the full §5 checklist and the §6 device script;
   - watch the first runs of every scheduled function.
3. **Pre-deploy data checks (production, read-only first, then approved fixes):**
   - Stage 3 M-6: count `escrow_releases` with status `pending` and a `paystackTransferCode`, and set them to `processing` by hand;
   - Stage 4 M-1: jobs agreed below ₦3,212;
   - Stage 4 M-6: resolved disputes still holding escrow;
   - Stage 5 M-1: set `bookingStatus: confirmed` on current `matched` jobs.
4. **Production deploy, in order:**
   1. `config/platform` grace values (Stage 5 M-2: 30 days / 720 h);
   2. Firestore indexes (Stage 6 M-4);
   3. **functions**;
   4. run `adminBackfillJobLocationPrivacy` until the cursor is null (Stage 6 M-2);
   5. Storage rules, granting the cross-service permission (Stage 6 M-3);
   6. release the **app** with a forced minimum version;
   7. once adoption is enforced, **Firestore rules** (Stage 5 M-3, Stage 6 M-1);
   8. re-classify existing suspensions (Stage 4 M-3).
5. **After one week:** lower `openJobDays` / `quoteValidityHours` to 7 / 48.
6. **Pilot:** limited users and low transaction caps. Monitor `admin_alerts`, `financial_events`, failed transfers and refunds daily.

---

## 16. Release-readiness verdict

**NOT READY for production go-live with real money.**

**What has improved:**
- The server-side logic is now well covered: 504 automated tests, including the first real execution of the trigger wiring.
- Every original audit exploit remains blocked.
- No regression was found in Stages 1–6.

**What still stands in the way:**
- **One code blocker:** chargebacks (F-1).
- **One high-severity privacy defect:** EXIF/GPS (F-2).
- **Paystack behaviour and device behaviour are unverified.** Those are exactly the areas where emulators cannot stand in for reality.

**What would change the verdict:**
- After F-1 and F-2 are fixed and the staging checklist (§15 step 2) passes: **ready for a limited pilot**.
- After the pilot runs cleanly with the migrations verified: **ready for general release**.

**Stage 7 is complete, pending your review. Stage 8 has not been started.**
