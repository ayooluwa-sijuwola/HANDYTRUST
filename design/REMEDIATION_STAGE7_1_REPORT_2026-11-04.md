# HandyTrust — Stage 7.1: Critical Defect Remediation

Date: 2026-11-04 · Scope: Stage 7 findings F-1 (chargebacks), F-2 (photo metadata) and F-3 (address migration). F-5 (trust-score response time) is presented for decision only. Nothing else.

**Constraints observed:**
- No production Firebase or Paystack access; no real money moved.
- No deployment, commit or push; no Stage 8 UI work.
- No approved financial policy changed and no security rule weakened.
- Emulators and fakes only.
- A dummy, test-only `functions/.secret.local` was created for each Functions-emulator run and **deleted after every run** (verified absent).

---

## 1. Findings and root causes

**F-1 — Chargebacks (Critical, Stage 7 blocker B-1).**
- **Root cause:** `paystackWebhook` handled only `charge.success`, `transfer.*` and `refund.*`. Every other event fell through to `200 OK`. No code anywhere knew a card dispute existed.
- **Consequences:**
  - Escrowed funds could be auto-released, confirmed by the customer or settled by an admin while the issuer was reversing the charge.
  - A refund could be submitted on top of a bank chargeback, refunding the customer twice.
- **Fixed** (§3–4).

**F-2 — Photo metadata (High, privacy D9).**
- **Root cause:** each upload screen re-encoded only images over 500 KB (600 KB for avatars); smaller files were uploaded with their original bytes. On Android, `image_picker` with `imageQuality` copies the original EXIF, GPS included, into its output.
- **Impact:** open-job photos are readable by every artisan account, so a small photo could reveal the customer's home location.
- **Fixed** (§5).

**F-3 — Address migration (Low).**
- **Root cause:** `_protectJobLocation` merged the job document's exact fields into `private/location` without reading it first. A newer private address could be overwritten by a stale copy, and the coarse area was computed from the stale copy too.
- **Fixed** (§6).

**Also found and fixed while in this code:**
- The webhook HMAC was compared with `!==`. It now uses a constant-time comparison (`crypto.timingSafeEqual`).
- The Dart `PaymentStatus` enum had no value for a charged-back payment and would have shown it as "Pending". The value `chargedBack` was added, with a "Charged Back" label. These are label-only changes, not a redesign.

**Found, not fixed (reported):**
- **Node 20 has been decommissioned on Google Cloud.** See §8 — this is a new go-live blocker.
- A Functions-emulator limitation with v2 scheduled functions (§9).
- `reconcileStuckEscrowReleases` still uses `add()`, which can repeat an alert every 24 h for the same stuck release. This is pre-existing and Low severity.

---

## 2. Files changed and why

**Production code:**

| File | Change | Why |
|---|---|---|
| `functions/index.js` | New chargeback module: `_onDisputeWebhook`, `_closeChargeback`, the `adminCloseChargeback` callable, and pure helpers `_nextDisputeStatus`, `_disputeReference`, `_payoutStateAtChargeback`. Webhook routing for `charge.dispute.*`. `fetchDispute` added to the Paystack client | F-1 |
| `functions/index.js` | Chargeback guard added to `_payoutBlockReason` (now also given the payment), `_settleJob`, `_submitRefund` (new `held` refund status) and `_retryRefund` (may resubmit `held`). Admin alert when a pre-chargeback transfer completes (`_onTransferSucceeded`) | F-1: no money path can bypass a hold |
| `functions/index.js` | `_signaturesMatch` (constant-time) | Webhook authenticity |
| `functions/index.js` | `_protectJobLocation` reads `private/location` in the same transaction; an existing private location wins and the coarse area is derived from it | F-3 |
| `firestore.rules` | `chargebacks/{id}` and `chargebacks/{id}/events/{e}`: admin read only; no client writes (admins included) | F-1. This only adds a rule block and nothing is weakened |
| `lib/core/utils/jpeg_metadata.dart` (new) | Lossless pure-Dart JPEG metadata stripper and inspector | F-2 |
| `lib/core/utils/image_privacy.dart` (new) | `ImagePrivacy.sanitize`: the single gate every photo passes through | F-2 |
| `lib/core/services/storage_service.dart` | All 5 upload methods call `ImagePrivacy.sanitize` first: job photos (including chat images and before/after photos), profile photo, verification ID/selfie, portfolio, dispute evidence | F-2 |
| `lib/core/services/profile_service.dart` | Avatar upload calls `ImagePrivacy.sanitize` | F-2 |
| `lib/models/payment_model.dart`, `lib/screens/wallet/wallet_screen.dart` | `PaymentStatus.chargedBack` and the "Charged Back" label | F-1 display correctness |

**Test-only changes:**

| File | Change |
|---|---|
| `pubspec.yaml`, `pubspec.lock` | `image: ^4.8.0` declared in **dev_dependencies** to build GPS-tagged test JPEGs. It was already locked transitively at 4.8.0 with the same hash; only its role changed to "direct dev". The lock file's other differences predate this stage |
| `functions/package.json` | `npm test` list includes the new chargeback suite |
| `.gitignore` | `functions/.secret.local` and `functions/.env.local` added. The local secrets file was **not** ignored, so a test key placed there could have been committed. The dummy files used in Stages 7 and 7.1 were never committed and are deleted |
| `functions/test/stage7_1_chargeback_emulator.test.js` (new) | 30 tests |
| `functions/test/e2e_schedules.functions-emulator.test.js` (new) | 4 end-to-end schedule tests (§9) |
| `functions/test/stage7_migration_emulator.test.js` | The pinned "known limitation" test was replaced by F-3 regression tests (4) |
| `firestore-tests/security_regression.test.js` | 3 chargeback rules tests |
| `test/stage7_1_image_privacy_test.dart` (new) | 17 tests |

---

## 3. Chargeback state machine and transition rules

**What Paystack documents** (Manage Disputes guide and Disputes API reference):
- **Events:**
  - `charge.dispute.create` — sent when a dispute is logged;
  - `charge.dispute.remind` — sent every 4 h while unresolved;
  - `charge.dispute.resolve` — sent once resolved.
- **Dispute statuses:** `awaiting-merchant-feedback`, `awaiting-bank-feedback`, `pending`, `resolved`; samples also show `archived`.
- **Resolutions:** `merchant-accepted` and `declined`.
- **Auto-acceptance:** a dispute left unanswered for 16 h is accepted automatically and refunded from the Paystack balance.
- **Fetch endpoint:** `GET /dispute/:id`.
- **Not documented:** **the webhook payload is not documented.** The handler therefore never trusts it alone (see "Rules" below).

**Our case status:**

```
              any dispute event for an unknown dispute
                         │  (places HOLD on payment + job)
                         ▼
   ┌──────────────► open ──────── Paystack reports resolved/archived ───► paystack_resolved
   │                  │  ▲ remind: remindCount++, alert re-surfaced              │
   │                  │  └ status only moves forward                              │
   │                  └──────────── adminCloseChargeback (refused: not resolved) ─┤
   │                                                                              ▼
   │                                              adminCloseChargeback(outcome, reason ≥ 10)
   │                                              — Paystack re-fetched NOW, must be resolved
   │                                                                              ▼
   └── late/duplicate events after close: logged + alerted, never applied ──── closed
                                                    (merchant_won | customer_refunded)
```

**Rules:**
1. **Authenticity.**
   - The HMAC-SHA512 of the raw body is compared in constant time; a missing or forged signature gets `400` and nothing is recorded (tested).
   - Then `GET /dispute/:id` is fetched, and the fetched dispute is authoritative.
   - If the fetch fails, the hold is still placed from the signed payload, the case is marked `verified: false`, and a `chargeback_unverified` alert is raised. Placing a hold moves no money, so it fails safe.
2. **Supported events.** Only the three documented events are processed. Any other `charge.dispute.*` event gets `200`, a `chargeback_event_unsupported` alert, and no state change.
3. **Identification.**
   - The transaction reference is read from `transaction.reference` or `transaction_reference`; the two shapes appear in Paystack's objects.
   - The fetched reference wins. A conflicting webhook reference raises `chargeback_reference_mismatch`.
   - Payment lookup is by document ID (equal to the Paystack reference), falling back to the `paystackReference` field. The job and customer come from the payment; the artisan from the job.
   - No match means `chargeback_unmatched`: the case is recorded, nothing else is touched.
4. **Persistence.** `chargebacks/{disputeId}` holds:
   - dispute ID, reference, payment, job, customer, artisan;
   - Paystack status and resolution;
   - the raw `refund_amount` (its unit is undocumented, so it is **never used to move money**);
   - currency, `dueAt`, remind count, verification flag;
   - **where the funds were when it arrived** (`payoutStateAtOpen`: `in_escrow`, `payout_initiated`, `paid_out`, `settlement_in_progress`, `already_*`).

   Every distinct event is also stored in `chargebacks/{id}/events/{sha256 key}` and in `financial_events`.
5. **Idempotency, delays and ordering.**
   - The event key is a hash of event, status, resolution and dispute timestamps. A redelivery is a no-op: one event, one financial record, one alert.
   - Paystack status ranks only move forward (open types → resolved/archived), so a delayed `create` after `resolve` cannot reopen a case.
   - Unknown status strings never replace known ones.
6. **Holds.**
   - A new case sets `payments.chargebackHold = true`, `openChargebackIds += [id]`, and job `chargebackHold = true`, `chargebackStatus = 'open'`. All of this happens in the same transaction as the case record.
   - Several disputes on one payment are supported; the hold stays until every one is closed.
7. **Closing.** `adminCloseChargeback` is admin-only, needs a reason, and requires Paystack to report the dispute resolved, re-fetched at that moment. If Paystack is unreachable, the close is refused.
   - `merchant_won` is refused if Paystack says `merchant-accepted`.
   - `customer_refunded`: still-held funds (`escrowHeld`, `settling`, `requiresRefund`) become **`chargedBack`**, a terminal status that nothing can pay out or refund. Unexecuted settlement legs and pending/held/failed refunds become `cancelled_chargeback`. If the money had already gone (`releasing`, `released`, `settled`), the payment keeps its status and gets `chargebackLoss: true`.
   - **Both outcomes:** the hold is lifted only if no other open chargeback remains. The decision is written to `admin_audit_logs` and `financial_events`, and a `chargeback_closed` alert names the next manual step.
   - **Idempotency:** repeating the same decision is a no-op; a conflicting decision is refused.
8. **Nothing automatic.**
   - No webhook ever releases, refunds or confiscates funds.
   - Closing a case doesn't resume anything: a frozen payout or held refund needs an explicit admin retry, which re-checks every guard.
9. **Admin notification.** Through the established mechanism, `admin_alerts` with deterministic IDs. Alert types:
   - `chargeback_opened`
   - `chargeback_after_payout` (high priority)
   - `chargeback_paystack_resolved`
   - `chargeback_unverified`
   - `chargeback_unmatched`
   - `chargeback_reference_mismatch`
   - `chargeback_event_after_close`
   - `chargeback_event_unsupported`
   - `refund_held_chargeback`
   - `chargeback_payout_completed`
   - `chargeback_closed`

   The artisan's job shows `payoutStatus: on_hold` while funds are still in escrow.

---

## 4. Escrow and payout protection verification

The suite is `stage7_1_chargeback_emulator.test.js`: 30/30 tests, against the emulator with a fake Paystack. **Every money path:**

| Path | Guard | Test result |
|---|---|---|
| Auto-release (14-day sweep) | `_payoutBlockReason` on the job → skipped + `autorelease_blocked` alert | Blocked; no release doc. **Also verified end to end** through the real scheduled function (§9) |
| Customer-confirmed payout | Final funds-claim transaction, immediately before the transfer (job + payment) | Frozen; 0 transfers |
| Chargeback arriving *during* payout processing, just before the final check | Same transaction re-reads the hold | Frozen; 0 transfers |
| Admin retry of a frozen payout | Re-runs the final check | Frozen again |
| Admin dispute settlement (release, refund, split) | `_settleJob` refuses `chargeback_open` | Refused; nothing created |
| Settlement created *before* the chargeback (legs unexecuted) | Payout leg: final check. Refund leg: `_submitRefund` | Neither leg moves money; closed as `customer_refunded`, both legs become `cancelled_chargeback` |
| Refund of a non-funding charge | `_submitRefund` holds it (prevents a double refund) | `held`, 0 refund calls; resubmitted only after close |
| Transfer already in flight | Cannot be recalled (no documented Paystack API). If it fails, funds return to escrow and stay held; if it succeeds, `chargeback_payout_completed` | Both cases tested |
| Already paid out | Recorded as `paid_out`, `chargeback_after_payout` alert, payment untouched | Tested |
| Duplicate and conflicting money movements | Existing funds mutex, create-once settlements and refunds (Stages 3–4), plus idempotent case handling | Duplicate webhook, duplicate close and conflicting close all tested |
| Hold flags changed by a client | Rules: transition whitelists; payments server-only | 3 new rules tests |

**Mutation check:**
- **Method:** the chargeback line was temporarily deleted from `_payoutBlockReason`.
- **Result:** 7 tests failed.
- **Restore:** the file was restored byte-identical (SHA-256 checked).

The suite genuinely detects a missing guard. All Stage 3/4 protections still pass (§7).

---

## 5. Photo metadata stripping: implementation and tests

**Pipeline.** `ImagePrivacy.sanitize` runs for every photo, whatever its size:
1. Refuse empty input or input over 25 MB before decoding.
2. **Always** re-encode natively: `FlutterImageCompress.compressWithList` with `format: jpeg`, `keepExif: false`, `autoCorrectionAngle: true` (rotation applied), size capped at 2560 px and quality 88.
3. **Always** run the pure-Dart `JpegMetadata.strip` as a final, platform-independent pass.
   - **Kept** (needed for decoding and correct colour): JFIF, the ICC profile, the Adobe colour transform, all image data.
   - **Removed:** EXIF (including GPS), XMP, IPTC/Photoshop, comments and every other application segment.
   - **Orientation:** if a tag survives (for example, no native encoder on web), a new EXIF block containing **only** Orientation is written so the photo stays upright.
4. Verify with `JpegMetadata.inspect(...).isClean`. Anything unexpected fails closed with a plain message and **no upload**.
   - Malformed, truncated or unsupported images are refused.
   - Without a native encoder, a non-JPEG is refused rather than uploaded raw.
   - Error messages contain no device paths or exception detail (tested).

**Coverage:**
- Every Storage upload in `lib/` goes through this gate: 6 `putData` call sites in `StorageService` and `ProfileService`.
- Only the processed bytes are uploaded. No code path uploads the original file, and file names are fixed (`image_N.jpg`), never the device file name.
- `image_picker` may leave temporary copies in the app's private cache on the device; they are never uploaded and other apps can't read them.

**Tests** (`test/stage7_1_image_privacy_test.dart`, 17/17):
- **Fixtures:** real JPEGs with GPS EXIF (Lagos coordinates), XMP, IPTC and a comment. One is **below 500 KB** and one **above**; both sizes and the GPS data are confirmed by an independent decoder (`package:image`).
- **Result:** after stripping, neither our inspector nor `package:image` finds GPS or EXIF, and the text "Home Street" / "GPSLatitude" is absent from the bytes.
- **Correctness:**
  - pixels are identical (lossless);
  - dimensions are preserved;
  - Orientation 6 is kept as the only tag (decodes rotated);
  - ICC and Adobe segments are kept;
  - multi-scan (progressive) files are handled.
- **Sanitizer behaviour:**
  - small photos now go through the encoder (the old bug);
  - a worst-case encoder that keeps metadata is still cleaned;
  - web fallback, non-JPEG refusal, corrupt input, empty input and oversize input are all covered.
- **Regression guard:** a source-scan test fails if any `putData`, `putFile` or `putString` in `lib/` lacks `ImagePrivacy.sanitize` in its method. A mutation check removed the avatar call, the guard caught it, and the file was restored byte-identical.

**Not verifiable here (needs a real device):** that the native re-encode on Android and iOS outputs no EXIF and correct rotation for camera photos. The final Dart pass guarantees no GPS either way; only rotation quality depends on the device (§10).

---

## 6. Address-migration concurrency fix and tests

**The fix.** The private document is read **inside** the migration transaction.
- **Existing private address:** if one exists, it is kept as is; the stale job-document copy is deleted, and the coarse area is derived from the kept address.
- **Why the private copy always wins:** the rules accept exact fields on the job document **only at creation**, while the private document can be written at or after creation, so an existing private location is never older.
- **Concurrent writes:** the transaction's read set is the conditional-update mechanism. A private write that lands mid-transaction forces a retry, which then sees it.
- **Rules compatibility:** no marker field is added to the private document (its rules use `hasOnly`).

**Tests** (`stage7_migration_emulator.test.js`, 13/13):
- **Unchanged from Stage 7 (9):** pagination, empty final page, rerun safety, interrupted resume, preservation, coarse area kept, partial/null fields, no-location jobs, no side channels.
- **New (4):**
  - a newer private address is kept byte-for-byte, with the area taken from it;
  - repeated runs keep it;
  - **20 concurrent races** between the migration and a customer write: the newer address wins every time;
  - **two operators running the migration at once:** each job moved once and consistent.

**Not run against production.**

---

## 7. Full regression results

| Suite | Node 24 (local) | Notes |
|---|---|---|
| Flutter (`flutter test`) | **174/174** | +17 image privacy; `flutter analyze`: no issues |
| Cloud Functions (`npm test`) | **229/229** | +30 chargeback, +3 migration (net) |
| Firestore rules (security + escrow) | **133/133** | Includes every original audit exploit (Appendix A, P0-1 chain) + 3 chargeback rules tests |
| Storage rules | **9/9** | |
| End-to-end triggers (Functions emulator) | **12/12** | No outbound calls (log checked) |
| End-to-end schedules (Functions emulator) | **4/4** | §9 |
| **Total** | **561 passing, 0 failing** | |

---

## 8. Node 20 test results — and a new blocker

**Configured production runtime:**
- `firebase.json` → `"runtime": "nodejs20"`;
- `functions/package.json` → `"engines": {"node": "20"}`.

Official Node binaries were installed through npm **into the scratchpad only**; system Node was unchanged.

| Suite | Node 20.20.2 | Node 22.23.4 |
|---|---|---|
| Cloud Functions | **229/229** | **229/229** |
| Firestore rules | **133/133** | **133/133** |
| End-to-end triggers | **12/12** — firebase-tools itself run under Node 20, so the emulator confirmed "Using node@20" (setting `PATH` alone is ignored) | not run |

**New finding — GO-LIVE BLOCKER (K-16).**
- **Schedule:** Google's runtime-support schedule lists **Node.js 20 as deprecated on 2026-04-30 and decommissioned on 2026-10-30**. After decommission, functions on that runtime can no longer be created or updated.
- **Effect:** the configured `nodejs20` would very likely **block deployment**.
- **Recommendation:** move to `nodejs22` in both `firebase.json` and `engines`. The full suites already pass on Node 22.
- **Status:** **not changed**, because it is production configuration and needs your approval.
- **Still to confirm:** the date against Firebase's own documentation.

---

## 9. Scheduled-function verification

**Configuration (verified from the deployed endpoint manifest):**

| Function | Schedule | Paystack secret | Calls Paystack? |
|---|---|---|---|
| `autoReleaseEscrow` | every 1 hours | — | No (creates `escrow_releases`; payout runs in the triggered function, which has the secret) |
| `expireMarketplaceDeadlines` | every 1 hours | — | No |
| `expireAbandonedPayments` | every 1 hours | bound | Yes (verify) |
| `reconcileRefunds` | every 3 hours | bound | Yes |
| `reconcileStuckEscrowReleases` | every 24 hours | — | No |

The configuration has no time zone (irrelevant for interval schedules), no retry policy (acceptable: every sweep is idempotent and re-runs on the next tick) and the default timeout.

**End-to-end execution** (`e2e_schedules.functions-emulator.test.js`, **4/4**). All 5 scheduled functions were executed by the Functions emulator through the same request Cloud Scheduler sends a v2 scheduled function: an HTTP POST with `X-CloudScheduler-*` headers.
- An unconfirmed booking older than 24 h is reopened; one at 2 h is untouched.
- A due job is auto-released (fails closed without bank details), while **a chargeback-held job is not**: the alert names `chargeback_open` and the funds stay in escrow.
- A stuck release is flagged.
- Both Paystack-bound schedules load with their secret and run, making no Paystack call when there is no eligible data.

**Emulator limitations (test-environment):**
- Without the Pub/Sub emulator, scheduled functions are skipped.
- With it, the emulator binds topics `firebase-schedule-<name>` but its delivery path rejects v2 schedules: `Unsupported trigger signature: http` (firebase-tools 15.22.0). Hence the direct scheduler-style request.
- **The emulator never fires on a timer, so the cadence itself can't be tested locally.**

**Safe verification of the real cadence (owner, staging):**
1. Deploy to a **staging** project with Paystack **test** keys.
2. In Cloud Scheduler, confirm five jobs exist with the schedules above.
3. Use "Force run" once per job and check the function logs.
4. Then watch two natural ticks of each hourly job and one of each daily job.
5. Confirm no Paystack call is made by the three unsecreted schedules.

---

## 10. Remaining Paystack and real-device checks

**Blocked by external configuration (none performed; none claimed):**

*Paystack test mode:*
- Stage 3 checklist (6 items) and Stage 4 checklist (6 items), unchanged.
- Unconfirmed API assumptions from Stage 7 §5 (refund unit, list filter, statuses, settlement-to-balance, transfer tiers, international cards).
- **New for chargebacks:**
  1. Use Paystack's test-mode tooling to raise a dispute on a test charge (or ask Paystack support how). Confirm the three webhook events arrive at the webhook URL with a valid signature.
  2. Capture one real payload of each and confirm the field names: `id`, `status`, `resolution`, `transaction.reference` / `transaction_reference`, `refund_amount`, `dueAt`.
  3. Confirm the **unit of `refund_amount`**.
  4. Confirm what `resolution: declined` + `status: resolved` means: did the merchant win, or only contest?
  5. Confirm how a **partial** acceptance is represented.
  6. Confirm `GET /dispute/:id` returns the same object.
  7. Confirm the 16-hour auto-accept behaviour and where the refund is debited from.

*Real device:*
- Every push case from Stage 7 §6 (foreground, background, terminated, logged-out, invalid route, duplicates, deleted job).
- **New for F-2:** on one Android and one iOS device, upload a **small (< 500 KB) and a large** camera photo with location services on. Download each from the Storage emulator or staging and confirm with an EXIF viewer that there is no GPS or EXIF. Also check that portrait photos display upright.

**Keeping credentials out of the conversation:**
- Never paste keys into chat.
- Put Paystack **test** keys in `functions/.secret.local`, which the Functions emulator reads.
- **It was not git-ignored before this stage.** Stage 7.1 added `functions/.secret.local` and `functions/.env.local` to `.gitignore`. Confirm with `git check-ignore functions/.secret.local` before creating the file.
- Alternatively, use `firebase functions:secrets:set` on a **staging** project only.

---

## 11. Outstanding risks and go-live blockers

**Go-live blockers:**

| # | Item | Status |
|---|---|---|
| B-1 | Chargebacks | **Implemented and tested (emulator).** Payload and resolution semantics are unconfirmed in Paystack test mode. **The blocker remains until §10 Paystack items 1–5 are confirmed** |
| B-2/B-3 | Paystack test-mode checklists; settlement-to-balance and international-card settings | **Blocked by external configuration** |
| B-4 | EXIF/GPS | **Fixed and unit-tested.** Device confirmation outstanding (§10) |
| B-5 | Real-device push | **Blocked by external configuration** |
| B-6 | Pre-deploy migrations (Stage 3 M-6 double-payout guard, Stage 4 M-1/M-3/M-6, Stage 5 M-1/M-2, Stage 6 M-2/M-4) | Not run (by design) |
| B-7 | Legal and account approvals | Owner |
| **B-8 (new)** | **Functions runtime `nodejs20` decommissioned 2026-10-30** | **Needs approval to change to `nodejs22`** |

**Risks:**

| Severity | Risk |
|---|---|
| High | Chargeback resolution semantics (`declined` vs merchant won; partial acceptance) are undocumented. The design fails safe: a hold stays until an admin closes it after a Paystack-confirmed resolution |
| Medium | Chargeback admin actions exist only as callables plus alerts. There is no dashboard screen to list cases or close them (Stage 8 UI) |
| Medium | **Partial chargeback acceptance:** closing as `customer_refunded` marks all still-held funds `chargedBack`. Any remainder owed to the artisan must be settled manually (no automated split for this case) |
| Medium | After `customer_refunded` the job isn't cancelled automatically. The admin follows the alert's `nextStep` (job lifecycle stays an admin decision) |
| Medium | Policy decision needed: recovery from the artisan after a lost chargeback that was already paid out (`chargebackLoss`) — absorb, or hold future payouts? |
| Medium | F-5: response-time component still constant (§12) |
| Low | Old app builds show `chargedBack` payments as "Pending" (enum fallback); fixed in the new build |
| Low | Native re-encode orientation on unusual devices; the Dart pass keeps the Orientation tag, so the photo stays upright |
| Low | `reconcileStuckEscrowReleases` duplicate alerts (pre-existing) |
| Low | Orphaned local emulator processes from these runs (ports 8090, 8190, 8290, 8390, 8490, 8590, 8790 and later); stopping processes is not permitted in this session |

---

## 12. Recommended next steps (each needs your approval)

1. **Approve the runtime change** to `nodejs22` (B-8), then re-run all suites on Node 22, including both e2e harnesses.
2. **Decide F-5** (below).
3. **Decide the chargeback policies:** recovery after a paid-out loss, and handling of partial acceptance.
4. **Staging with Paystack test keys** (local ignored secret or staging secret): run §10 Paystack items and the Stage 3/4 checklists, then the §9 scheduler checks.
5. **Device pass:** push cases and the F-2 photo checks.
6. Admin UI for chargeback cases, as part of the Stage 8 scope.
7. Then the Stage 7 §15 release sequence (migrations → deploy order → pilot).

### F-5 — trust-score response time: proposal for your decision (NOT implemented)

**Definition — booking response time:**
- **Starts** at `bookingRequestedAt`, which is server-enforced.
- **Ends** at the first of: confirmed (`bookingConfirmedAt`, server-enforced), declined or withdrawn, or expired (24 h).
- **The score** is the **median** of the artisan's last 20 responses within 90 days, fed into the existing `_trustResponseTimePoints`. With fewer than 3 responses the neutral 30-minute default is kept.

**How each outcome counts:**

| Outcome | Effect |
|---|---|
| Confirmed | Minutes from request to confirmation |
| **Declined / withdrawn** by the artisan | Counts as a response at its actual time. A prompt honest "no" isn't penalized; decline rate can be tracked separately if you want |
| **Expired** (no answer in 24 h) | Counts as the full **1,440 minutes**, the worst value |
| **Unanswered open-job quote requests** | **Not counted.** An open job isn't addressed to a specific artisan |
| **Withdrawn quotes** | Not counted |
| **Expired quotes** (48 h validity) | Not counted. Validity concerns price, not responsiveness |
| Quote speed (job posted → first quote) | Optional secondary signal at 0% weight initially |
| Chat reply speed | Excluded until message `createdAt` is server-enforced (currently client-set) |

**Prerequisite:** `_reopenJob` currently deletes the booking timestamps on expiry or withdrawal. They would be appended to a server-only `booking_responses` log before being cleared.

**Awaiting your explicit decision; nothing implemented.**

---

**Stage 7.1 is complete, pending your review. Stage 8 has not been started; nothing was deployed, committed or pushed.**
