# Stage 8.2 notifications and RumptyCloud — review decisions

**Date:** 5 November 2026.

**Source documents:**
- `STAGE8_2_NOTIFICATION_FINAL_CODE_REVIEW.md` (findings F-1 to F-12);
- `RUMPTYCLOUD_STAGING_INTEGRATION_PHASE2_PLAN.md` (revised design, open questions Q1–Q9).

**State of the working tree:**
- HEAD is `7ff140c` (the approved Stage 8.2 UI commit, unchanged).
- The notification backend and client changes are **uncommitted and unchanged by this review**.
- Nothing is deployed. No RumptyCloud code exists.

---

## 1. Notification security findings

| ID | Severity | Finding | Requirement affected |
|---|---|---|---|
| F-1 | **High** | Message pushes now route to `/chat/{jobId}?with=…`; on every installed (pre-8.2) app a tap opens a "Chat is not available" dead end instead of the job page | 9 (compatibility) |
| F-2 | **High** | The read-receipt batch includes `deliveredAt`; when a delivery receipt for the same message lands first, the rules deny the whole read batch, so the message isn't marked Read | Core receipt behaviour |
| F-3 | Medium | Delivery receipts are generated from cache-only snapshots | 1 |
| F-4 | Medium | Delivery-receipt listeners (non-autoDispose providers) survive sign-out and run under the next account | — |
| F-5 | Medium | Sign-out waits on `deleteToken()` with no timeout | 2 |
| F-6 | Medium | An offline sign-out never retries token invalidation, so the device keeps receiving the previous account's pushes | 2 |
| F-7 | Medium | Releasing a token from other accounts uses stale trigger data and deletes without re-checking (late or duplicate events, refresh races) | 3, 5 |
| F-8 | Medium | Unlimited device registrations per account. Above 500, every push to that account fails (`sendEach` limit); each registration write also costs a Function run | 4 |
| F-9 | Medium | Quote amounts and the other party's free text (change requests, cancellation reasons) still appear in push bodies; `visibility: private` depends on device settings | 7 |
| F-10 | Low | Failed delivery receipts retry with no backoff; batches over 500 writes fail permanently | — |
| F-11 | Low | A stolen FCM token lets the thief's own notifications reach the victim's device and stops the victim's pushes | — |
| F-12 | Low | Statements in the Stage 8.2 reports that are inaccurate (S5, S7, S10, "live listener", "older apps keep working throughout") | — |

**Confirmed correct:**
- the server-side preference check (requirement 6);
- recipient-only, once-only, server-time receipts in the rules (requirement 8);
- compare-and-delete cleanup on the delivery path (requirement 5, delivery path);
- legacy tokens and old read-marking writes still accepted (most of requirement 9).

---

## 2. Corrections needed

| Fix | Change | Files |
|---|---|---|
| F-1 | Keep `route: /job/{jobId}`; add `chatWith: senderId` to the notification document and push data; the new client builds the chat route from it | `functions/index.js`, `lib/core/services/push_logic.dart` |
| F-2 | Remove `deliveredAt` from `markAllAsRead` and `markAsRead` | `lib/core/services/chat_service.dart` |
| F-3 | Receipt stream with `includeMetadataChanges: true`; send receipts only when not from cache and no pending writes | `chat_service.dart`, `lib/providers/chat_provider.dart`, `lib/core/services/conversation_logic.dart` |
| F-4 | `autoDispose` on `incomingUnreadProvider` and `deliveryAckProvider` | `lib/providers/chat_provider.dart` |
| F-5 | 6 s timeout on the sign-out hook; timeout and catch around `deleteToken()` | `lib/providers/auth_provider.dart`, `lib/providers/notification_provider.dart` |
| F-6 | Persist a "token invalidation pending" flag and retry at start and on reconnect while signed out | `lib/providers/notification_provider.dart` |
| F-7 | Re-read the triggering document; transactional delete only if same token and older `updatedAt`; legacy cleared only if same token | `functions/index.js` |
| F-8 | Send to the 10 newest devices; prune the rest in the trigger; split sends into groups of 500; UUID-format `deviceId` in the rules; stale-registration cleanup (scheduled, so after Blaze) | `functions/index.js`, `firestore.rules` |
| F-9 | Generic push body by default; stored body only for types on a reviewed safe list | `functions/index.js` |
| F-10 | Per-message backoff; split batches into groups of 450 or fewer | `chat_service.dart`, `chat_provider.dart` |
| F-11 | Covered by F-7 and F-9; App Check per its own plan | — |
| F-12 | Correct both reports | `design/STAGE8_2_BACKEND_NOTIFICATION_IMPLEMENTATION_REPORT.md`, `design/STAGE8_2_BACKEND_SECURITY_REVIEW.md` |

**Recommendation:**
- Fix F-1 and F-2 before the local commit; both are small.
- F-3, F-4 and F-5 are client-only and small, so fix them in the same pass.
- F-6 to F-10 must be fixed before any staging deployment.

---

## 3. RumptyCloud security findings

| # | Finding | Basis | Consequence for the design |
|---|---|---|---|
| R-1 | **No versioning:** an overwrite or delete is permanent | Vendor docs | A key with **write** is destructive even without delete. Deletion only through the audited function; synthetic data only |
| R-2 | Keys are **bucket-wide** (no prefix scope); permissions immutable; rotation manual | Vendor docs | Two keys (K1 read+write for signing, K2 list+read+delete for clean-up); staging bucket never holds production media |
| R-3 | **Size limits on presigned uploads are not documented** | Vendor docs silent | Signed `Content-Length` must be proven by a live test (Q2); otherwise POST policy (Q3) or a Function-proxied upload; video disabled until proven |
| R-4 | Checksum enforcement is not documented | Vendor docs silent | Server-side streamed SHA-256 is authoritative; checksum header only if proven (Q4) |
| R-5 | Whether an unsigned `x-amz-acl` header or a public-read ACL can expose a private object is unknown | Vendor docs: write covers ACLs | Live test T2-08; until proven, treat K1 as able to publish |
| R-6 | 600 writes/min **per key**, shared by all users | Vendor docs | Per-user rate limits and a global limiter at 120 signed write URLs/min |
| R-7 | Prepaid billing with **no spend alerts**; egress price not documented | Vendor docs | $5 balance ceiling, auto top-up off, balance checked before and after each live session |
| R-8 | Encryption at rest, durability and SLA not documented | Vendor docs silent | No production use until answered (Q9) |
| R-9 | `functions/.env` and `.env.<project>` are **not** git-ignored (by design) | `git check-ignore` today | Non-secret settings go in the ignored `.env.local` under a `demo-` emulator project |
| R-10 | **5,752 files under `functions/node_modules` are tracked** in Git | `git ls-files` today | Untrack in a separate approved commit before installing the AWS SDK |
| R-11 | `handytrust-staging` is on Spark: Functions, Secret Manager and Cloud Scheduler aren't available | Firebase pricing page | Local emulator only; the scheduled sweep and any cloud signing service need Blaze |

---

## 4. Remaining technical limitations

**Notifications:**
- Not tested on a real device: real FCM delivery, taps in the foreground, background and terminated states, multi-device behaviour, and account switching.
- Delivered still needs the recipient's app running and signed in. A push shown while the app is closed doesn't count, by design.
- A modified client of the **recipient** can mark its own messages delivered or read without showing them. This is inherent to client-side receipts.
- Deployment order is mandatory:
  1. indexes;
  2. rules;
  3. Functions;
  4. app release.

  A new app running against old rules has its read and delivery writes denied.
- Stale-registration cleanup and App Check need Blaze and their own approvals.

**RumptyCloud:**
- Nine vendor behaviours are unproven (Q1–Q9). Size enforcement during upload is the most important.
- On Spark there's no cloud signing service and no scheduled clean-up. Everything runs in the local emulator.
- Single region (Lagos), no documented durability, no versioning. Not suitable for irreplaceable or sensitive media until the vendor answers Q9.
- Production prerequisites not in Phase 2:
  - image re-encoding and EXIF/GPS stripping;
  - malware scanning;
  - relationship-based access rules beyond "owner";
  - migration of existing media;
  - CDN and caching.

---

## 5. Exact files that would change

### 5a. Notification corrections (F-1 to F-10)

| File | Fixes |
|---|---|
| `functions/index.js` | F-1, F-7, F-8, F-9 |
| `firestore.rules` | F-8 (`deviceId` format) |
| `lib/core/services/chat_service.dart` | F-2, F-3, F-10 |
| `lib/core/services/conversation_logic.dart` | F-3 |
| `lib/core/services/push_logic.dart` | F-1 |
| `lib/providers/chat_provider.dart` | F-3, F-4, F-10 |
| `lib/providers/notification_provider.dart` | F-5, F-6 |
| `lib/providers/auth_provider.dart` | F-5 |
| `functions/test/stage8_2_push_emulator.test.js` | Tests for F-1, F-7, F-8, F-9 |
| `firestore-tests/stage8_2_messaging_rules.test.js` | Test for F-8 |
| `test/stage8_2_backend_client_test.dart` | Tests for F-1 to F-6, F-10 |
| `design/STAGE8_2_BACKEND_NOTIFICATION_IMPLEMENTATION_REPORT.md`, `design/STAGE8_2_BACKEND_SECURITY_REVIEW.md` | F-12 |

No change to Auth, payments, escrow, payouts, Paystack, or other collections' rules.

### 5b. RumptyCloud Phase 2

The full list is in `RUMPTYCLOUD_STAGING_INTEGRATION_PHASE2_PLAN.md` §15. In summary:

| Group | Files |
|---|---|
| Functions code | `functions/media.js` (new), `functions/index.js` (re-export only) |
| Dependencies | `functions/package.json` and lockfile |
| Rules | `firestore.rules` (`media`, `media_quotas`, `media_system`) |
| Tests | `functions/test/media_offline.test.js`, `media_live.test.js`, fixtures, `firestore-tests/media_rules.test.js` |
| Tooling | `tool/check_no_secrets.js` |
| Client | three new client files and one client test |
| Local only, never committed | `.env.local` and `.secret.local` (owner) |

**Preceding change (separate commit):** untrack `functions/node_modules`.

---

## 6. Tests required before each approval

### Gate N1: local commit of the notification changes

1. All tests listed for F-1 to F-6 and F-10 pass.
2. Full suites pass with no regressions:
   - Flutter tests and visual goldens;
   - `flutter analyze` (0 errors, 0 warnings);
   - all Functions tests on the emulator;
   - all Firestore and Storage rules tests;
   - end-to-end with no external calls.
3. An emulator integration test for F-2: chat open, message arrives, and both the delivery receipt and the read are recorded.

### Gate N2: staging deployment of the notification changes

1. Gate N1, plus the F-7, F-8 and F-9 tests.
2. A non-production Firebase project on **Blaze**, since Functions can't be deployed on Spark.
3. Device test matrix on at least 2 physical Android devices:
   - foreground, background and terminated delivery and taps;
   - multi-device delivery;
   - account switch on one device;
   - offline sign-out, then reconnect (F-6);
   - preference off;
   - lock-screen content with "hide sensitive content" both on and off;
   - an older (pre-8.2) build tapping a message push (F-1).
4. Deployment order indexes → rules → Functions, checked in the staging logs.
5. 48 hours of `push_result` logs reviewed for unexpected removals.

### Gate N3: production deployment of the notification changes

1. Gate N2 passed and signed off.
2. Rollback plan:
   - previous rules and Functions versions recorded;
   - the rules change is backward-compatible with older apps (confirmed in the review).
3. App release only **after** rules and Functions are live.

### Gate R1: RumptyCloud tier 1 (offline)

All T1-01 to T1-13 tests pass, with no network and no credentials.

### Gate R2: RumptyCloud tier 2 (live staging)

1. Gate R1 passed.
2. Owner setup done:
   - keys created and permissions confirmed;
   - secrets placed by the owner;
   - $5 ceiling set; auto top-up off.
3. T2-01 to T2-10 pass, and every run ends with 0 objects under the run prefix.

### Gate R3: RumptyCloud staging deployment

1. Gates R1 and R2 passed.
2. Q2 (size enforcement) resolved.
3. `handytrust-staging` on Blaze (cost decision); secrets in Secret Manager; scheduled sweep deployed.

### Gate R4: RumptyCloud production

Out of scope. Needs a separate plan:
- Q8 and Q9 answered;
- production prerequisites from §4;
- a media migration plan;
- relationship-based access rules.

---

## 7. Approvals

Each approval below is separate. One doesn't imply another.

| # | Approval | Covers | Doesn't cover | Prerequisites |
|---|---|---|---|---|
| A1 | **Notification corrections** (implement F-1 to F-10 locally) | Code and test changes in §5a; emulator runs | Commit, deployment | — |
| A2 | **Local commit: notifications** | One commit on `stage-8-ui-replacement` with the backend, client, tests and corrected reports | Push, deployment | Gate N1 |
| A3 | **Staging deployment: notifications** | Deploying indexes, rules and Functions to a non-production Blaze project; installing a staging build on test devices | Production; the Blaze upgrade itself (A4) | A2, Gate N2 items 1–2 |
| A4 | **Blaze on a non-production project** | Billing upgrade of `handytrust-staging` (or a new staging project), with a budget alert | Any production change | Owner cost decision |
| A5 | **Production deployment: notifications** | Rules, index and Functions deployment to `handytrust`, then app release | — | Gates N2 and N3 |
| A6 | **Untrack `functions/node_modules`** | One separate commit removing the tracked files from the index (files stay on disk) | Dependency changes | — |
| A7 | **RumptyCloud tier 1** | Implementing §15 of the Phase 2 plan, offline tests only | Live calls, commit | A6 (recommended) |
| A8 | **RumptyCloud tier 2 live tests** | Outbound calls from the local emulator to the staging bucket, within the §12 limits | Deployment, production buckets | Gate R1; owner key setup and $5 ceiling |
| A9 | **Local commit: RumptyCloud** | One commit of the Phase 2 code and tests (never `.env.local` or `.secret.local`) | Push, deployment | Gate R1 (and R2 if live results are included) |
| A10 | **Staging deployment: RumptyCloud** | Deploying media Functions and secrets to the staging project | Production | Gate R3, A4 |
| A11 | **GitHub push** (any branch) | Pushing approved local commits | — | Owner decision; not requested |

**Standing restrictions, unchanged:**
- no production Firebase changes;
- no Paystack access;
- no production media migration;
- no Blaze upgrade, GitHub push or deployment without the matching approval above;
- the approved Stage 8.2 commit `7ff140c` and the Stage 8.3 scope are unchanged.
