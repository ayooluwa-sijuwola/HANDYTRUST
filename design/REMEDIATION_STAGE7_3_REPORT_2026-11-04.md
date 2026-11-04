# HandyTrust — Stage 7.3: Final Technical Verification & UI-Rebuild Readiness

Date: 2026-11-04 · Scope: verification and planning only.

**Constraints observed:**
- No production Firebase or Paystack access; no real money moved.
- No deployment, commit or push.
- No Stage 8 implementation and no UI redesign.
- No business policy changed; partial-chargeback accounting not enabled; no migration run.
- A dummy, git-ignored `functions/.secret.local` was created for the Functions-emulator run and **deleted afterwards** (verified).

**Status labels:** **Verified** · **Partially verified** · **Not verified** · **Failed** · **Blocked by external dependency**.

---

## 1. Executive summary

**Backend (Verified, emulators).** The backend is stable enough for a UI replacement.
- **604 automated tests pass:**
  - Flutter 174
  - Cloud Functions 266, on Node 22
  - Firestore rules 139
  - Storage rules 9
  - end-to-end triggers 12 and schedules 4, on Node 22
- **No regressions** against Stage 7.2. The 4 new tests cover the partial-chargeback switch-bypass cases (2 Functions, 1 rules) and the debug demo-escrow path (1 rules).
- **Analyzer:** 37 findings, 0 errors, 0 warnings, 37 info. The one warning and one info finding from Stage 7.2 were fixed (import-only changes). 19 of the 37 come from an **unrelated nested project** (`work_sphere_ai/`, untracked).

**Architecture (Verified, static).** The Flutter code has a usable separation:
- services in `lib/core/services`, Riverpod providers in `lib/providers`, models in `lib/models`, GoRouter in `lib/routes/router.dart`;
- **all money and security decisions run on the server** (Cloud Functions + rules).

A complete UI replacement is feasible **if Stage 8 keeps the provider/service layer and the route contract**.

**Preconditions to resolve before or at the start of Stage 8:**
1. **Nothing since the initial commit is committed** (181 working-tree entries, Stages 1–7.3). A UI rebuild on top of an uncommitted foundation risks losing it. **A baseline commit or branch is strongly recommended before Stage 8** (your action; I did not commit).
2. **`.firebaserc` has a single alias, `default: "handytrust"`** (production), and the app is configured only for that project. A staging Firebase project and app configuration are required before any controlled deployment.
3. **Data contract gaps for the new admin UI:**
   - there is no client code for chargebacks, platform losses, refunds, settlements or financial events;
   - two server callables (`adminCloseChargeback`, `adminSetChargebackInvestigation`) have no client wiring;
   - `JobModel` lacks `chargebackHold` / `chargebackStatus`.
4. **Data migrations other than the address backfill have no scripts** (§9). They must be written and rehearsed in staging.

**Still blocked externally:**
- Paystack test mode (§10) and real devices (§11);
- legal and compliance approvals (§12);
- the Cloud Functions region / Firestore location decision (§8).

**Verdict (§17).** **Ready for Stage 8 UI rebuild — conditionally.** Proceed after the baseline commit, with the Stage 8 constraints in §13. **Not ready for production go-live.**

---

## 2. Repository state and environment

| Item | State |
|---|---|
| Git | Branch `main`, HEAD `c1740f4`. **All remediation work is uncommitted** (181 entries, including deleted legacy files `payment_service.dart`, `customer_registration_screen.dart`, `phone_login_screen.dart`) |
| Untracked, unrelated | `work_sphere_ai/` (a separate face-recognition/workforce project with its own `lib/`). It is analyzed with HandyTrust and could be committed accidentally. **Your decision:** move it out of the repo or ignore it |
| Reports | All 10 required reports present, including **Stage 5** (`REMEDIATION_STAGE5_REPORT_2026-11-03.md`, 223 lines). Its claims were checked against code: booking confirmation rules, `artisanWithdrawFromJob`, `expireMarketplaceDeadlines`, rework, suspension modes; its tests pass |
| Toolchain | Flutter 3.41.6 / Dart 3.11.4; firebase-tools 15.22.0; Java 25; local Node 24.12.0; **Node 22.23.4** (official binary, scratchpad only) for the runtime-matching runs |
| Emulators | One managed Firestore emulator (port 8090) for the unit suites, **stopped after the run**. Separate `emulators:exec` sessions for Storage and Functions; fresh ports per run |

---

## 3. Node.js 22 verification — **Verified** (deployment itself **Blocked by external dependency**)

| Check | Result |
|---|---|
| `firebase.json` | One functions codebase (`default`, source `functions`), `"runtime": "nodejs22"` |
| Functions package | `engines.node: "22"`; lock root `engines.node: "22"`; no other lock change (Stage 7.2 hash check) |
| Dependency compatibility | Every locked package that declares `engines.node` accepts 22.23.4 (enforced by `runtime_config.test.js`) |
| Leftover Node 20 | None in runtime configuration or README. Older design reports mention Node 20 historically (intentionally unchanged) |
| Emulator startup and execution | firebase-tools run **on Node 22**: "Using node@22 from host", no version-mismatch warning, 33 endpoints loaded; 16/16 end-to-end scenarios |
| Consistency across functions | All 33 endpoints are v2 (`gcfv2`), same codebase and runtime; no per-function runtime overrides |
| Actual Node 22 deployment | **Blocked by external dependency** (needs a staging project) |

---

## 4. Stage 7.2 implementation verification

### 4.1 Chargeback integrity

| Requirement | Status | Evidence |
|---|---|---|
| Events authenticated | **Verified** | HMAC-SHA512 over raw body, constant-time compare (`_signaturesMatch`); forged or missing signature → 400, nothing stored; every event re-fetched from `GET /dispute/:id` |
| Duplicates can't duplicate financial actions | **Verified** | Hashed event keys; monotonic Paystack status; idempotent close (concurrent closes → one close, one loss, one financial entry) |
| Open chargeback blocks payouts, refunds, settlements | **Verified** | Final payout transaction (job and payment hold), auto-release, customer-confirmed payout, admin retry, `_settleJob`, `_submitRefund` (`held`), `_retryRefund`. Mutation check: removing the guard fails 7 tests |
| After payout → HandyTrust loss | **Verified** | `platform_losses/{id}` with `absorbedBy: handytrust`, `artisanDeduction: false`, `recoveryStatus: not_pursued`; `platform_loss_recorded` event; transfer untouched |
| No automatic deduction from future earnings | **Verified** | No code path reads `platform_losses` or `chargebackLoss` for payouts; the next job pays the full ₦50,000 (test) |
| Admin investigation auditable | **Verified** | `adminSetChargebackInvestigation` → case `investigation` + `history[]` + `admin_audit_logs`; `fraud_confirmed` alert; no money moves |
| Partial accounting **disabled by default** | **Verified** | Default `false`; only a literal boolean `true` in `config/platform` enables it |
| No bypass of the switch | **Verified (new tests)** | The switch is read in exactly one place (the `_closeChargeback` transaction). `"true"`, `1`, `"yes"`, `{}`, `[]` and others stay off, including end to end through a real close. `config/{doc}` has `allow write: if false` for every client, admins included (new rules test). `chargebackRefundedKobo` is written only by the admin close |

### 4.2 Trust-score integrity

| Requirement | Status | Evidence |
|---|---|---|
| Records server-generated | **Verified** | `booking_responses` written only by Functions; rules deny all client writes and deletes, admins included |
| Clients can't modify response timestamps | **Verified** | Inputs are rules-forced to `request.time` (backdated confirmation refused); artisans can't write `responseTimeMinutes`, `responseTimeSampleSize` or `responseTimeUpdatedAt` |
| Duplicates prevented | **Verified** | Deterministic ID per request; first response immutable; late duplicates are no-ops |
| Expiry and withdrawal preserve history | **Verified** | Written inside `_reopenJob`'s transaction before the fields are deleted; mutation check fails 3 tests |
| Median of last 20 within 90 days | **Verified** | Boundary tests: exactly 90 days included, +1 ms excluded, future excluded, latest 20 only, even-count mean |
| Neutral value below 3 | **Verified** | 0–2 records → 30 min |
| Hourly recalculation | **Verified (emulator)** | The sweep refreshes ≤ 100 artisans whose score is older than 24 h; aged records → neutral (test). The actual hourly cadence is **Blocked by external dependency** (staging) |

---

## 5. Full regression results

Every suite ran green on the first try except Functions and rules, which first had to wait for their emulator (§5 note).

| Suite | Stage 7.2 | **Stage 7.3** | Runtime |
|---|---|---|---|
| Flutter tests | 174 | **174/174** | Dart 3.11.4 |
| Flutter analyzer | 39 (1 warning, 38 info) | **37 (0 errors, 0 warnings, 37 info)** | — |
| Cloud Functions | 264 | **266/266** | **Node 22.23.4** |
| Firestore rules | 137 | **139/139** | Node 22.23.4 |
| Storage rules | 9 | **9/9** | Node 24 (test client only) |
| E2E triggers (Functions emulator) | 12 | **12/12** | Node 22 runtime |
| E2E scheduled functions | 4 | **4/4** | Node 22 runtime |
| **Total** | 600 | **604 passing, 0 failing** | |

**Environment note.** The first Functions run failed every test in about 1 ms with `ECONNREFUSED 127.0.0.1:8090`: the orphaned emulator the unit suites had used was gone. A managed emulator was started, the suites were run, and the emulator was stopped. No test or code change was involved.

---

## 6. Flutter analyzer findings — exact result: **37 issues found (0 errors, 0 warnings, 37 info)**

| Group | Count | Classification |
|---|---|---|
| `work_sphere_ai/**` (separate untracked project): `use_build_context_synchronously` ×10, `deprecated_member_use` ×6 (Radio), `use_super_parameters` ×1, others | **19** | **Not HandyTrust.** Harmless to HandyTrust. Indicates a repository-hygiene problem: move or exclude it (your decision) |
| `lib/screens/settings/settings_screen.dart` — `use_build_context_synchronously` ×8 | 8 | Existing. **Potentially indicative of a deeper problem:** using a `BuildContext` after an `await` can crash if the widget was disposed. The screen is to be replaced in Stage 8, so not fixed; Stage 8 must avoid the pattern |
| `admin_finance_dialogs.dart` ×4, `secure_booking_screen.dart` ×4 — deprecated `Radio.groupValue/onChanged` | 8 | Existing and harmless (deprecated API still works); screens to be replaced |
| `bank_details_screen.dart:181` — deprecated `value` (→ `initialValue`) | 1 | Existing and harmless; screen to be replaced |
| `service_request_screen.dart:190` — deprecated geolocator `desiredAccuracy` | 1 | Existing; harmless today. **Worth fixing in Stage 8** with `LocationSettings` (a future geolocator major version will remove it) |
| **Fixed in Stage 7.3** | 2 | (a) `lib/core/platform_utils.dart` redundant import of the file it re-exports, the **only warning** (the conditional `export` already provides the API). (b) `service_request_screen.dart` unnecessary `dart:typed_data` import. Import-only; no behaviour change; 174/174 tests still pass |

**Newly introduced:** none.

**Correction carried from Stage 7.2:** the Stage 7.1 "no issues" result was wrong (a non-analysing 4-second run).

---

## 7. Security and financial regression — **Verified (emulator)**

| Adversarial case | Status | Where tested |
|---|---|---|
| Unauthorized payment manipulation (client writes to `payments`, `escrowLocked`, `escrow.*`, `payment.*`) | Verified | `escrow_payout` P0-1; **new**: demo-escrow writes refused |
| Self-payment / self-hire (dual role) | Verified | `security_regression` (customer can't hire own artisan profile) |
| Ownership changes (`customerId`/`artisanId`/payer) | Verified | `security_regression`; payout fails closed on payer ≠ customer |
| Price change after agreement | Verified | Agreement and `agreedAmount` rules (Stage 2/5 groups) |
| Early payout (before submission / review window) | Verified | `escrow_payout` §4.1; server `submittedAt` + 14 days (e2e) |
| Duplicate payout / refund / settlement | Verified | Stage 3/4 mutex + create-once; Stage 7.2 concurrency tests |
| Payout with an open chargeback | Verified | Stage 7.1 suite (all paths); e2e scheduled auto-release refuses held job |
| Partial-chargeback switch bypass | Verified | **New** Stage 7.3 tests (Functions + rules) |
| Fake notifications | Verified | Client create denied (rules); only admin verification flow writes |
| Unauthorized address access | Verified | Private location subdocument rules; migration fixes (Stage 7.1) |
| Unauthorized Storage access | Verified | `storage_rules` 9 tests |
| GPS metadata exposure | Verified (unit) / **Blocked** (device) | 17 image-privacy tests incl. upload-path guard; device check pending |
| Fraud-suspension payout attempts | Verified | Stage 4 + Stage 7.2 (fraud suspension → `artisan_suspended_freeze`) |
| Client-controlled timestamps | Verified | `submittedAt`, booking times, milestone times forced to `request.time` |
| Duplicate reviews | Verified | `reviews/{jobId}` + server re-check (`review_rating_pipeline`) |
| Unauthorized admin financial actions | Verified | Every admin callable calls `_requireAdmin` (admins collection); rules deny client writes to all financial collections |

No security rule was weakened. The rules diff this stage is test-only; the one rules change since Stage 7.2 was the additive protections already reported.

---

## 8. Firebase staging readiness

**Inventory (from the code's own deployment manifest):** 33 endpoints, all v2, all in the **default region `us-central1`** (no `region`/`setGlobalOptions`).

| Kind | Endpoints |
|---|---|
| https | `paystackWebhook` |
| callable | 18 functions: 9 admin, `artisanWithdrawFromJob`, payment init/verify/breakdown, `analyzeJob`, and others |
| Firestore triggers | 11 |
| scheduled | 5 |

| Area | Status | Finding / required change before a controlled staging deploy |
|---|---|---|
| Target project | **Failed (config)** | `.firebaserc` only has `default: handytrust` (production). **Add a staging project alias and always deploy with `--project`**. `firebase.json`'s Flutter config and `lib/firebase_options.dart` / `google-services.json` are for production only. A staging app build needs its own Firebase config (FlutterFire flavor or separate config) |
| Region | **Not verified** | All functions default to `us-central1`. v2 Firestore triggers must be compatible with the **Firestore database location**, which can't be read without project access. Decide the region (latency for Nigerian users vs. database location). **Changing the region changes callable URLs:** the app uses `FirebaseFunctions.instance` (default region), so it would need `instanceFor(region:)` |
| Runtime | Verified | `nodejs22`, consistent |
| Firestore rules | Verified (emulator) | 139 tests. Deploy-order constraint (Stage 5 M-3 / Stage 6 M-1): functions → app → rules |
| Storage rules | Verified (emulator) | Cross-service rules: on first deploy Firebase asks to grant the **Storage service agent read access to Firestore** (Stage 6 M-3) |
| Indexes | Partially verified | 28 composite + 2 field overrides; **no exact duplicates**. `favorites` has both COLLECTION and COLLECTION_GROUP versions; both are used (user queries / `adminDeleteUser` collection-group query). **`booking_responses`** (`artisanId`↑, `qualifying`↑, `respondedAt`↓) matches its query exactly. **The emulator doesn't enforce indexes:** every query path, including `collectionGroup('messages')` (chat) and the `artisans.responseTimeUpdatedAt` range (single-field, automatic), must be exercised in staging and checked for `FAILED_PRECONDITION` |
| Scheduled functions | Verified (emulator) / cadence **Blocked** | §8.1 |
| Secrets | Verified (binding) | `PAYSTACK_SECRET_KEY` is bound on exactly the 12 endpoints that call Paystack; `GEMINI_API_KEY` on `analyzeJob`. Staging: `firebase functions:secrets:set` with **test** keys. Secret Manager access is granted on deploy |
| Service accounts / IAM | Not verified | Default compute service account for v2. Needs: Secret Manager accessor (auto), Firestore and FCM access (default), `setCustomUserClaims` for `onAdminGranted/Revoked`, Eventarc service agent for Firestore triggers, Storage service-agent grant above |
| Required APIs / plan | Not verified | Blaze plan; Cloud Functions, Cloud Run, Cloud Build, Artifact Registry, Eventarc, Pub/Sub, **Cloud Scheduler** (manifest `requiredAPIs`), Secret Manager, Firestore, Storage, FCM |
| Environment config | Partially verified | `config/platform` (defaults = approved policy; console/Admin-SDK write only; `partialChargebackAccountingVerified` absent ⇒ off). Paystack webhook URL must be registered **per project** in the Paystack dashboard (test vs live). Hosting serves `build/web` (SPA rewrite) |
| Deploy order | Documented | §9 order; within a release: indexes → functions → (migrations) → Storage rules → app (forced minimum version) → Firestore rules |

### 8.1 Scheduled functions

| Function | Schedule | Time zone | Idempotent / overlap-safe | Recovery |
|---|---|---|---|---|
| `autoReleaseEscrow` | every 1 hours | none (interval, time zone irrelevant) | Yes: transaction on the job + fixed-ID release; payout claimed by the payment mutex; holds re-checked | Next run picks up the remainder |
| `expireMarketplaceDeadlines` | every 1 hours | none | Yes: every reopen re-reads in a transaction; response records create-once | Next run |
| `expireAbandonedPayments` | every 1 hours | none | Yes: verifies with Paystack before reverting; lock decision function shared with the webhook | Next run |
| `reconcileRefunds` | every 3 hours | none | Yes: status only advances from Paystack-reported values; `processed` is terminal | Next run |
| `reconcileStuckEscrowReleases` | every 24 hours | none | Alert-only (no money). Uses `add()`, so a stuck release is re-alerted daily (Low, pre-existing) | Next run |

**Overlap and retries.** All five have no retry policy, so a failed run simply waits for the next tick, and the default timeout (60 s) is far below the interval. Even overlapping invocations can't duplicate a financial operation, because every money step is claimed in a transaction (tested concurrently in Stages 3, 4 and 7.2).

**Needs staging:** the actual cadence, the Cloud Scheduler job creation, timeouts at real data volumes (sweeps are capped at 500 jobs / 100 refreshes per run), and the IAM for scheduler invocation.

---

## 9. Migration inventory and execution order

**No migration has been run.** Only **MIG-7** (`adminBackfillJobLocationPrivacy`) exists as code. **Every other migration is a documented procedure without a script.** Scripts must be written, reviewed and rehearsed on staging data before production (**Not verified**).

| # | Migration (source) | Purpose | Affected data | Preconditions | Idempotent | Paginated | Can overwrite newer data? | Batching / duration | Verification | Recovery / rollback |
|---|---|---|---|---|---|---|---|---|---|---|
| **MIG-0** | Pre-deploy data audit (Stage 2 §3, D10) | Find HT-045 forged trust/verification fields, multiple reviews per job, payer ≠ customer, `resolved`/`cancelled` jobs still `escrowHeld` | Read-only: `artisans`, `reviews`, `jobs`, `payments` | Admin read access | Yes (read-only) | Should be | No | Aggregate counts | Report reviewed by owner | N/A (read-only) |
| **MIG-1** | Stuck pending releases (Stage 3 M-6 / Stage 4 M-5) | Set `escrow_releases` with `status == 'pending'` **and** a `paystackTransferCode` to `processing`, so a re-trigger can't pay twice | `escrow_releases` | **Before** the new functions deploy; reconcile each transfer code with the Paystack dashboard first | Yes (only `pending`+code → `processing`) | Small set | No (status only) | Minutes | Re-query returns 0; each listed transfer confirmed in Paystack | Reversible field change, **but don't revert**: `pending` is the dangerous state. **Critical: skipping it can cause a double payout** |
| **MIG-2** | Jobs agreed below ₦3,212 (Stage 4 M-1) | Count, then either finish (temporarily lower `minJobValueNgn`) or cancel with notice | `jobs`, `config/platform` | Policy decision per job | Yes | Yes | No | Small | Count → 0 open below minimum | Config change reversible; cancellations are not (notify users) |
| **MIG-3** | Classify existing suspensions (Stage 4 M-3, Stage 5 M-4) | Unclassified suspensions **freeze payouts** (fail closed); admins assign `suspensionType` | `users`, `artisans` | After functions deploy (until then they stay frozen: safe) | Yes | Small | No | Manual, via admin UI | No suspended user without a type | Reversible (re-classify) |
| **MIG-4** | Resolved disputes still holding escrow (Stage 4 M-6) | Re-open as admin settlements, case by case | `disputes`, `jobs`, `payments`, `settlements` | MIG-0 list; admin decision per case | Yes (settlement create-once) | N/A | Money moves only via an admin settlement | Manual | Each payment `released`/`refunded`/`settled` | **Not reversible** once money moves; decide carefully |
| **MIG-5** | Confirm legacy bookings (Stage 5 M-1) | Set `bookingStatus: 'confirmed'` on every job currently `matched` | `jobs` | **Before enabling** `expireMarketplaceDeadlines` (otherwise the sweep reopens them) | Yes | Yes | Must not touch jobs already `awaitingArtisan`/`confirmed` (filter: field missing) | Small | Count of `matched` without `bookingStatus` = 0 | Reversible, but note these produce **non-qualifying** response records (no `bookingConfirmedAt`) |
| **MIG-6** | Deadline grace (Stage 5 M-2) | Set `config/platform` `openJobDays` 30 / `quoteValidityHours` 720 at deploy; lower to 7 / 48 after a week | `config/platform` | At functions deploy | Yes | N/A | No | Config only | Sweep summaries over the first week | Reversible config |
| **MIG-7** | Address privacy backfill (Stage 6 M-2; `adminBackfillJobLocationPrivacy`) | Move exact location from job documents to `private/location` | `jobs`, `jobs/{id}/private/location` | After functions deploy; repeat with `nextCursor` until `null` | **Yes** (tested: rerun moves 0; private docs unchanged) | **Yes** (300 per call, cursor) | **No** (Stage 7.1 F-3 fix: an existing private address always wins; 20 concurrent races tested) | One transaction per job; about 1 call per 300 jobs | Query for any job still holding `customerAddress`/`customerLat` = 0 | Not reversible by design (it removes the exposure); **no data is lost** (values preserved; tested). Until it completes, old jobs stay exposed (P-K) |
| **MIG-8** | Notification lockdown order (Stage 6 M-1) | Ship rules that forbid client notifications only after the app minimum version is the Stage 6+ build | Rules, app config | Forced-update mechanism | N/A | N/A | N/A | — | Old-build error rate | Keep the interim rule until adoption |
| **MIG-9** | Indexes (Stage 6 M-4, Stage 7.2) | Create composite indexes **before** the app/functions use them | `firestore.indexes.json` | Before functions/app | Yes | N/A | N/A | Index build can take minutes to hours on large collections | Console shows all `READY` | Additive |
| **MIG-10** | Service areas (Stage 6 M-5) | Ask artisans to set their service area | `artisans` | New app | Yes | N/A | N/A | Communication | Share with an area set | N/A |
| **MIG-11** | Response-time metric (Stage 7.2) | **No backfill possible** (history was deleted on reopen before 7.2); everyone starts neutral | — | — | — | — | — | — | Scores change only after 3+ responses | N/A |

**Safety review (requirement §4):**
- **Duplicate payouts:** prevented only if **MIG-1 runs before** the new functions.
- **Payment history:** no migration erases it.
- **Newer addresses:** MIG-7 can't overwrite them.
- **Address exposure:** MIG-7 creates no notifications, alerts or logs (tested).
- **Dispute states:** MIG-4 is a manual settlement, not a reset.
- **Ownership:** no migration changes `customerId`/`artisanId`/`payerId`.

**Execution order (staging rehearsal first, then production with your approval):**
1. Baseline commit/tag.
2. MIG-0 audit (read-only).
3. Backup/export of Firestore (`gcloud firestore export`) — the recovery point, since several steps aren't reversible.
4. MIG-1.
5. MIG-9 indexes.
6. Deploy functions.
7. MIG-6 config.
8. MIG-5.
9. MIG-7 backfill until the cursor is `null`.
10. MIG-3.
11. MIG-2 and MIG-4 case by case.
12. Storage rules.
13. App release with a forced minimum version.
14. Firestore rules (MIG-8).
15. After a week, finish MIG-6 (lower the deadlines).

---

## 10. Paystack external verification checklist — **Blocked by external dependency**

Nothing below has been performed against Paystack. Use **test keys** in the git-ignored `functions/.secret.local` (emulator) or a **staging** secret, never in chat.

| Area | Documented by Paystack (public docs) | Needs empirical test-mode verification |
|---|---|---|
| Payment initialization | `POST /transaction/initialize`, amounts in subunit | Our `amountKobo` incl. 5% fee; metadata `jobId`; callback/redirect in the webview; international cards disabled (account setting) |
| Payment verification | `GET /transaction/verify/:reference` | Status mapping, `fees`, `authorization.country_code`; retry/resume flow (Stage 3 checklist 1–2) |
| Webhook signature | HMAC-SHA512 of raw body with secret key (`x-paystack-signature`) | End-to-end signature on deployed function; IP allow-list need |
| Duplicate and delayed webhooks | Paystack retries failed webhooks | Redelivery from the dashboard is a no-op; late `charge.success` after cancel → `requiresRefund` (Stage 3 #4–6) |
| Refund creation and reconciliation | `POST /refund`, `GET /refund/:id`, list refunds | Status values and webhook events; `GET /refund?transaction=` filter (Stage 4 #6); `needs-attention` handling |
| Refund amount unit | Subunit stated generally | Confirm a ₦10,500 refund equals 1,050,000 (Stage 4 #1) |
| Dispute webhook payload fields | Event names: `charge.dispute.create` / `remind` (every 4 h) / `resolve`. **The payload is not documented** | Capture real payloads: `id`, `status`, `resolution`, `transaction.reference` vs `transaction_reference`, `refund_amount`, `dueAt` |
| Dispute outcome semantics | Statuses `awaiting-merchant-feedback`, `awaiting-bank-feedback`, `pending`, `resolved` (+`archived`); resolutions `merchant-accepted` / `declined`; auto-accept after 16 h, refunded from balance | What `declined` + `resolved` means (did the merchant win?); what issuer-decided losses report |
| Partial-dispute representation | Accepting may be "full or partial"; `refund_amount` integer in subunit (for the resolve request) | That a fetched resolved partial reports `refund_amount` in kobo equal to the amount returned; refund of the remainder accepted. **Only then** set `partialChargebackAccountingVerified: true` (not activated) |
| Chargeback after payout | — | Where Paystack debits (balance vs settlement); appears as `paid_out` case + `platform_losses` |
| Payout / transfer reconciliation | `POST /transfer`, `transfer.success/failed/reversed` webhooks; `source: balance` | Recipient creation and bank-code table (`BANK_CODES` unverified); fee tier above ₦50,000; retry references `{jobId}-pN` accepted |
| Settlement configuration | — | **Settlements must stay in the Paystack balance** or every payout fails (Stage 3 R-7). Confirm with Paystack |

---

## 11. Real-device testing checklist — **Blocked by external dependency**

**Needs one Android and one iOS physical device** (staging build, test accounts). Emulator and unit tests **do not** replace any of these.

| # | Test | Pass criteria |
|---|---|---|
| D-1 | Push, app **foreground** | Banner or in-app message; tapping opens the right job |
| D-2 | Push, **background** | System notification; tap → correct deep link |
| D-3 | Push, **terminated** | Cold start lands on the deep-linked screen after auth |
| D-4 | Deep links | Job / dispute routes open; invalid or external route → `/notifications`; unauthorized job → friendly message (Stage 7 F-4) |
| D-5 | Logged out | No push after sign-out (token removed) |
| D-6 | Login / session restoration | Kill and reopen → still signed in; unverified email → verify screen; suspended → restricted mode |
| D-7 | Camera upload (job, completion, dispute, chat, avatar, verification) | Upload succeeds; error copy on failure |
| D-8 | Metadata stripping: **< 500 KB and > 500 KB** photos with location on | Downloaded file has **no GPS/EXIF** (EXIF viewer) |
| D-9 | Orientation | Portrait and landscape photos display upright after upload |
| D-10 | Location prompt | "While using the app" only; denial → manual address entry works |
| D-11 | Location only on explicit action | No location request until the user taps "use my location" |
| D-12 | Artisan service-area setup | Save area/radius (≤ 25 km); appears in matching |
| D-13 | Customer and artisan navigation | Full workflow: post → quote → book/confirm → agree → pay (test card) → start → submit → confirm/rework → review |

---

## 12. Legal and operational blockers — **Blocked by external dependency** (not legal advice; qualified review required)

| Item | Status / what's needed |
|---|---|
| Marketplace / escrow legal structure | **Qualified Nigerian legal review.** Whether holding customer funds pending completion is permissible under the chosen structure, or requires a licensed partner (e.g. CBN payment-service licensing considerations) |
| Paystack marketplace / escrow approval | Confirm with Paystack that the delayed-transfer model is permitted on the account and plan |
| VAT on the 5% platform fee | **Tax adviser.** Whether VAT applies to the fee and how it is displayed and collected (the current price shows fee only) |
| Consumer protection / data protection | NDPA 2023 compliance (lawful basis, consent wording for location and photos, data-subject rights); FCCPA consumer terms. **Legal/compliance review** |
| Customer and artisan terms | Drafting and acceptance capture (no versioned acceptance exists in the app today) |
| Refund and cancellation policy publication | Policies D2/D5 must be published and linked in-app |
| Chargeback operating procedure | Owner SOP: respond within Paystack's 16 h window; evidence pack; who may close cases; loss approval |
| Customer support and dispute escalation | Staffing, SLA and escalation path (support tickets exist; no SLA) |
| Admin access control and auditability | Admin = `admins/{uid}` + custom claim; actions audited (`admin_audit_logs`, `financial_events`). **Needed:** named admin list, least privilege (no role tiers exist: every admin can settle money), MFA on admin accounts, periodic review |
| Privacy policy and consent wording | Location (precise, on tap), photos (metadata stripped), notifications, AI analysis of job text/photos (`analyzeJob` → Gemini) **must be disclosed** |
| Data retention and deletion | Account deletion is an admin callable; financial and audit records are intentionally retained. **Needs** a documented retention schedule (legal retention for financial records vs NDPA minimisation) |

---

## 13. Stage 8 architecture assessment — **Verified (static)**

**Layers (keep):**
- **Routing:** `lib/routes/router.dart`, GoRouter, 38 paths. Includes `/admin` as a `ShellRoute` with 12 sections, all rendered by one `AdminDashboardScreen(section:)`.
- **Central `redirect` guard** (keep its rules exactly):
  - signed-out → `/login`;
  - unverified email → `/verify-email`;
  - **suspended restricted mode** (view prefixes `/jobs`, `/job/`, `/dispute/`, `/notifications`, `/support`; plus `/chat/`, `/payment/` for non-freezing suspensions);
  - admin guard (`isAdminProvider`);
  - dual-role → `/role-select`.
- **Auth and session:** `authStateChangesProvider`, `authNotifierProvider` (`auth_service.dart`), `currentUserProvider` / `currentUserProfileProvider` (`users/{uid}`), `isAdminProvider` (`admins/{uid}`).
- **Riverpod providers:** 21 files, about 60 providers (jobs, quotes, chat, escrow/payment, disputes, reviews, notifications, matching, verification, portfolio, favorites, support, platform config).
- **Services:** 24 in `lib/core/services`. Key ones: `job_service`, `quote_service`, `chat_service`, `escrow_service`, `paystack_service`, `admin_finance_service`, `dispute_service`, `matching_service` + `distance_matching`, `storage_service` + `image_privacy`, `notification_service`, `profile_service`, `verification_service`, `workflow_gate_service`.
- **Models:** 15, with `fromJson`/`toJson`.
- **Role separation:** customer vs artisan is a **mode** of one account (`activeRole`); admin is a separate guard. Home switches tab sets (customer: Home · Jobs · Wallet · Profile; artisan: Dashboard · Jobs · Chats · Profile).
- **Payment and escrow integration points** (must be preserved):
  - `initializePaystackTransaction`, the payment webview, `verifyPayment`, `getPaymentBreakdown`;
  - job status transitions via `escrowNotifierProvider`;
  - payout status mirrored on the job (`payoutStatus`).
- **Notification navigation:** `notification_provider.dart` → `safeNotificationRoute` allow-list → GoRouter `push`. **Keep the allow-list** when renaming routes.

**Coupling that matters for a full UI replacement:**
- **Data access inside screens (16 files).** `admin_dashboard_screen.dart` alone has **54** direct Firestore/Functions/Storage references and is **7,881 lines**. Others: `bank_details` (4), `open_jobs_feed`, `business_profile`, `artisan_dashboard`, `verification_upload` (3 each), and a few single uses. **Stage 8 must move these into services/providers first** (or re-create them faithfully); otherwise replacing the screen deletes working logic.
- **Workflow and business logic inside large screens.** `job_detail_screen.dart` (2,518 lines) holds the per-status action logic: agreement, confirm/decline booking, cancel requests, rework, dispute window, evidence upload. Its actions call providers, but the **which-action-when** logic lives in the widget; extract it into a view-model before redesigning.
- **Admin UI gaps (new screens needed; no reusable UI):**
  - chargeback cases (`chargebacks`, close and investigation callables are not wired);
  - platform losses;
  - refunds / settlements / financial events / orphan charges (no client code reads these);
  - `JobModel` lacks `chargebackHold`/`chargebackStatus`.
- **Debug-only demo escrow:** `/demo-payment/:jobId` is registered in **release** builds; the payment screen only links to it under `kDebugMode`. Rules refuse its writes (new test), but Stage 8 should drop it or gate the route itself.
- **Shared widgets** (26 in `lib/widgets`): replace visually, but **preserve behaviour** of `service_area_card` (GPS on tap only), `workflow_timeline` / `workflow_status_card` (status mapping), `cancellation_reason_dialog`, `notification_bell`, `job_status_badge`. Theme files (`app_colors`, `app_design_system`, `app_theme`, `breakpoints`) are to be replaced by the Stitch design tokens.
- **States:** loading, error and empty states are implemented ad hoc per screen (`AsyncValue.when`, `shimmer_loaders`, `error_snackbar`). The rebuild should standardise them.

**Stage 8 constraints (recommended):**
1. Don't change services, providers, models, rules or Functions except the identified contract additions.
2. Keep route paths, or update `safeNotificationRoute` and the server `route` values together.
3. Keep the redirect guard semantics.
4. Every upload through `StorageService` / `ProfileService` (the guard test enforces this).
5. No new direct Firestore writes from widgets.
6. Run the full suite after each screen group.

---

## 14. Complete screen inventory

**Legend:**
- **Replace** = UI to be rebuilt from the Stitch design.
- **Reuse** = existing providers/services carry the logic.
- **Extract** = logic currently in the widget must move to a provider or view-model first.
- **New** = no existing implementation.

Every screen needs loading, error and empty states unless noted.

### 14.1 Customer

| Screen | Existing implementation | Required workflow | Backend dependencies | Extra states | Replace? | Logic reuse |
|---|---|---|---|---|---|---|
| Authentication | `login_screen`, `register_screen`, `verify_email_screen`, `forgot_password_screen`, `splash_screen`, `role_selection_screen`, `suspended_screen` | Sign up/in, verify email, reset, choose role, suspended view | Firebase Auth, `users/{uid}`, `authNotifierProvider` | Unverified, suspended (restricted), dual-role | Replace | Reuse |
| Home / discovery | `home_screen` (`_CustomerHomeTab`) | Recent jobs, featured artisans, post a job | `customerJobsProvider`, `featuredArtisansProvider` | No jobs yet | Replace | Reuse |
| Artisan search & filtering | `browse_artisans_screen` (`/browse-artisans`, **2 direct Firestore calls**), `artisan_list_screen` (`/artisans/:jobId`, distance-first matching), `favorites_screen` | Browse by category; job-specific ranked matches (in-range, then unknown distance); favorites | `matchingProvider` (geohash + `distance_matching`), `favoriteArtisansProvider` | No artisans in range; no location | Replace | Reuse matching; **Extract** browse queries |
| Artisan profile | `artisan_profile_screen` (`/artisan/:uid`) | Profile, trust score, reviews, portfolio, favorite, hire | `artisanProfileProvider`, review providers, `portfolioProjectsProvider`, `escrowNotifierProvider` (direct hire) | Unverified artisan; suspended artisan not hireable | Replace | Reuse |
| Job creation | `service_request_screen` (`/request`) | Category, description, photos (sanitized), budget, urgency, location (GPS on tap or manual), AI suggestion | `jobRequestNotifierProvider` → `createJob` (coarse area + private location), `aiServiceProvider` (`analyzeJob`), `platformConfigProvider` (minimum value) | Photo processing errors; location denied | Replace | Reuse |
| Quotes | Inside `job_detail_screen` (`jobQuotesProvider`) | View, accept or reject quotes; 48 h validity | `quote_service`, rules quote validity | Expired quote; none yet | Replace | **Extract** action logic |
| Booking & agreement | `secure_booking_screen` (`/secure-booking/:artisanId`, direct hire), `chat_screen` (`/chat/:jobId`: agreement, scheduling, images), `job_detail_screen` | Direct hire → artisan confirms within 24 h; chat; propose/confirm agreement (locks price); slots | `escrowNotifierProvider`, `chatNotifierProvider`, `messagesStreamProvider`, private location after confirmation | Awaiting artisan; booking expired / declined → reopened | Replace | Reuse; **Extract** from job detail |
| Payment & escrow | `payment_screen` (`/payment/:jobId`), `payment_webview_screen`, `demo_escrow_screen` (debug) | Breakdown (price + 5% fee), Paystack checkout, verify, resume, escrow locked | `getPaymentBreakdown`, `initializePaystackTransaction`, `verifyPayment`, `paystack_service` | Abandoned (24 h), already paid, `requiresRefund`, failure | Replace | Reuse; **drop demo route** |
| Work progress | `job_detail_screen` (`/job/:jobId`), `workflow_timeline`, `all_jobs_screen` (`/jobs`) | Status timeline, start/submit notifications, payout/refund/settlement status | `jobStreamProvider`, `escrowNotifierProvider`, `payoutStatus`/`refundStatus`/`settlementStatus` | Disputed, cancellation pending, chargeback hold (**contract gap**) | Replace | **Extract** |
| Completion & reviews | `job_detail_screen` (confirm / rework), `review_screen` (`/review/:jobId`) | Confirm completion (release), one rework with reason, 14-day window, review once | `escrowNotifierProvider`, `jobReviewProvider`, `onReviewCreated` | Window elapsed (auto-release), already reviewed | Replace | Reuse / **Extract** |
| Disputes & cancellation | `dispute_screen` (`/dispute/:jobId`), cancellation dialog in job detail | Raise dispute + evidence (sanitized); paid-cancellation request; see decision | `disputeServiceProvider`, `disputeForJobProvider`, admin settlement outcome fields | Dispute open/resolved; cancellation approved/declined | Replace | Reuse |
| Notifications | `notifications_screen` (`/notifications`), `notification_bell` | List, mark read, deep-link | `userNotificationsProvider`, `notificationServiceProvider`, `safeNotificationRoute` | Empty | Replace | Reuse |
| Profile & settings | `profile_screen`, `settings_screen` (`/settings`, **8 context-after-await lints**), `wallet_screen` (`/wallet`), `contact_support_screen`, `about_screen` | Avatar (sanitized), account, theme, deletion request, payments history, support tickets | `profileServiceProvider`, `customerPaymentsProvider`, `supportTicketServiceProvider` | Deletion pending | Replace | Reuse |
| Chats list | `my_chats_screen` (`/my-chats`) | Conversations | `customerJobsProvider`, `lastMessageProvider` | Empty | Replace | Reuse |

### 14.2 Artisan

| Screen | Existing implementation | Required workflow | Backend dependencies | Extra states | Replace? | Logic reuse |
|---|---|---|---|---|---|---|
| Authentication / onboarding | `artisan_registration_screen` (`/register/artisan`, 2 direct calls) + shared auth | Artisan profile creation (trust fields default; pending approval) | `artisans/{uid}` create rules | Pending approval | Replace | **Extract** |
| Dashboard | `artisan_dashboard_screen` (`ArtisanHomeTabContent`; 3 direct calls) | Overview, verification status, active jobs, earnings summary | `artisanJobsProvider`, `artisanProfileProvider`, `verificationStatusProvider` | Unverified / pending; suspended | Replace | **Extract** |
| Job discovery | `open_jobs_feed_screen` (`/open-jobs`, 1,379 lines, 3 direct calls) | Nearby open jobs by distance (coarse area only), pre-match chat, quote | `openJobsFeedProvider`, `distance_matching`, `quoteServiceProvider`, `chatServiceProvider` | No service area set; none nearby | Replace | **Extract** |
| Service-area setup | `service_area_card` inside `business_profile_screen` (`/business-profile`, 3 direct calls) | Location on tap, radius ≤ `maxServiceRadiusKm` | `artisans` service-area rules, `platformConfigProvider` | Permission denied | Replace | Reuse card logic |
| Quotes | `open_jobs_feed_screen` | Submit, edit, withdraw; 48 h validity | `quote_service`, `onQuoteWritten` | Expired, chosen elsewhere | Replace | Reuse |
| Booking requests | `job_detail_screen` | Confirm within 24 h, or decline (reason) | Rules (server time), `artisanWithdrawFromJob`, response-time records | Expired | Replace | **Extract** |
| Active jobs | `all_jobs_screen`, `job_detail_screen` | Agreement, schedule, start work, cancellation request | `escrowNotifierProvider`, chat | Restricted (suspended) mode | Replace | **Extract** |
| Work submission | `job_completion_screen` (`/job/:jobId/submit`) | Before/after photos (sanitized), submit → server timers | `storage_service`, `escrowNotifierProvider`, `onJobCompleted` timers | Upload failure | Replace | Reuse |
| Rework | `job_detail_screen` | See reason, resubmit (fresh 14 days) | Rework rules, timer clearing | — | Replace | **Extract** |
| Earnings & payouts | `wallet_screen` (artisan tab), `bank_details_screen` (`/bank-details`, 4 direct calls) | Payouts by status (processing/paid/on hold/delayed), bank details | `artisanPaymentsProvider`, `artisanPayoutReadyProvider`, `artisan_private`, `payoutStatus` | No bank details; on hold (freeze/chargeback) | Replace | **Extract** bank details |
| Disputes | `dispute_screen` | Raise / respond with evidence | `disputeServiceProvider` | — | Replace | Reuse |
| Reviews | `artisan_profile_screen` (own), `review_tile` | Read reviews, rating | Review providers | None yet | Replace | Reuse |
| Notifications | `notifications_screen` | As customer | As customer | — | Replace | Reuse |
| Profile & settings | `profile_screen`, `settings_screen`, `business_profile_screen`, `portfolio_manager_screen` (`/portfolio`), `portfolio_project_screen` (`/portfolio-project`), `verification_upload_screen` (`/verification`, 3 direct calls) | Business info, portfolio (sanitized), ID/selfie verification | `portfolioServiceProvider`, `verificationServiceProvider`, `storage_service` | Verification pending/rejected | Replace | Reuse / **Extract** |

### 14.3 Admin (currently one `AdminDashboardScreen` with 12 sections + `admin_finance_dialogs`)

| Screen | Existing implementation | Required workflow | Backend dependencies | Replace? | Logic reuse |
|---|---|---|---|---|---|
| Admin dashboard | Section `dashboard`, `admin_charts`, `analytics` | KPIs, alerts feed (`admin_alerts`, resolve) | Direct queries in screen | Replace | **Extract** (54 direct calls in this file) |
| User management | Section `users`; suspend dialog **with suspension type**; `adminDeleteUser`; `deletions` section | Suspend (type), reactivate, delete on request | `users`, `account_deletion_requests`, `adminDeleteUser` | Replace | **Extract** |
| Artisan verification | Sections `artisans`, `verifications` | Approve/reject IDs (admin notification) | `verification_service` (admin-written notification) | Replace | Reuse service |
| Job oversight | Section `jobs` (+ private location for admins) | Inspect jobs, audit trail | `jobs`, `jobPrivateLocationProvider`, `auditLogs` | Replace | **Extract** |
| Dispute management | Section `disputes` + finance dialogs (release / full refund / split; paid-cancellation decide) | Settle with reason; amounts validated server-side | `adminResolveDispute`, `adminResolveCancellation` | Replace | Reuse `admin_finance_service` |
| Chargeback management | **None** | List cases, Paystack status, due time, payout state, accounting; close (merchant won / customer refunded); investigation | `chargebacks` (+`events`), `adminCloseChargeback`, `adminSetChargebackInvestigation` | **New** | Callables exist; client service and model **New** |
| Financial loss records | **None** | List `platform_losses` (amount, basis, case, artisan) | `platform_losses` (admin read) | **New** | **New** |
| Escrow & payout monitoring | Partial (reads `payments`, `escrow_releases`; retry payout/refund dialogs) | Frozen/failed payouts, held/failed refunds, settlements, orphan charges, financial event log | `refunds`, `settlements`, `financial_events`, `orphan_charges` (**no client code**), `adminRetryPayout/Refund`, `adminRefundCharge` | Replace + **New** views | Partial |
| Fraud & suspension management | Suspension-type dialog; `adminSetPayoutFreeze` in finance service | Freeze/unfreeze artisan or job payouts with reason; fraud suspension | `adminSetPayoutFreeze`, user suspension fields | Replace | Reuse |
| Audit history | Section `auditLogs` | Admin actions and job audit logs | `admin_audit_logs`, `jobs/*/auditLogs` | Replace | **Extract** |
| Platform configuration | Section `settings` (reads `config`) | **View only**: rules forbid client writes; changes via console/Admin SDK (by design, incl. the partial switch) | `config/platform` | Replace (read-only display) | Reuse |
| Reviews / support | Sections `reviews`, `support` | Moderate reviews, answer tickets | `reviews`, `support_tickets` | Replace | **Extract** |

---

## 15. Outstanding technical risks

| Severity | Risk | Status |
|---|---|---|
| **High** | All remediation is uncommitted; a UI rebuild could overwrite or lose it | Not verified (owner action: baseline commit/branch) |
| **High** | No staging project; `.firebaserc` defaults to production | Failed (config) |
| **High** | Migrations other than MIG-7 are unscripted (MIG-1 prevents double payouts) | Not verified |
| **High** | Paystack test mode, real devices, legal approvals | Blocked by external dependency |
| Medium | Region vs Firestore location undecided; callables use the default region | Not verified |
| Medium | Business logic embedded in large screens (admin 7,881 lines / 54 direct calls; job detail 2,518 lines) | Verified (static), mitigation in §13 |
| Medium | Admin UI missing for chargebacks, losses and financial records; `JobModel` contract gap | Verified (static) |
| Medium | Emulator doesn't enforce indexes; collection-group queries unverified | Partially verified |
| Medium | `BuildContext` used after `await` (settings screen) | Existing; avoid in Stage 8 |
| Low | Debug demo-escrow route registered in release (writes refused by rules) | Verified (rules) |
| Low | `work_sphere_ai/` nested in the repo | Owner decision |
| Low | Scheduled sweeps capped per run; default 60 s timeout | Staging check |
| Low | Daily duplicate stuck-release alerts (`add()`) | Existing |
| Low | Orphaned local emulator processes from earlier stages | Local only |

---

## 16. Recommended next steps (each needs your approval)

1. **Commit or branch the current state** (baseline before Stage 8), and decide on `work_sphere_ai/`.
2. **Create a staging Firebase project:** alias in `.firebaserc`, staging app config, test Paystack keys as staging secrets, webhook URL in the Paystack test dashboard, region decision.
3. **Write and test migration scripts** (MIG-0 audit, MIG-1, MIG-5) against emulator fixtures, then rehearse the §9 order on staging.
4. **Stage 8 kick-off tasks** (before visual work):
   - extract data access from the admin dashboard, job detail, open-jobs feed, bank details, business profile, artisan dashboard, verification upload and registration into services/providers;
   - add the data contracts for chargebacks, losses, refunds, settlements, financial events and job chargeback fields;
   - remove or gate the demo route.
5. Run the Paystack test-mode checklist (§10) and the device checklist (§11) on staging.
6. Start the legal/compliance reviews (§12) in parallel.

---

## 17. Final UI-rebuild readiness verdict

**READY FOR STAGE 8 (complete UI replacement) — CONDITIONALLY.**

**What supports this:**
- The backend, rules and money workflows are verified on emulators with 604 passing tests and no regressions.
- The Node 22 runtime is verified locally.
- The app has a reusable service/provider/model layer and a central, well-defined routing guard.

**The conditions:**
1. Make a baseline commit before Stage 8 starts.
2. Stage 8 follows the §13 constraints: the logic layer is reused, embedded screen logic is extracted before replacement, route and deep-link contracts are kept, and the identified admin contracts are added.

**NOT READY for production go-live:** staging, Paystack test-mode verification, real-device testing, migration scripting and rehearsal, and legal approvals remain outstanding.

**Stage 7.3 is complete, pending your review. Stage 8 has not been started; nothing was deployed, committed or pushed.**
