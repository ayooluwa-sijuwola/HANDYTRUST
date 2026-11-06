# Job posting failure: root cause

**Date:** 6 November 2026
**Reported error:** "Couldn't post your job. Submit request failed. Check your network and try again."
**Scope:** the code on disk; the built APKs and web build; local Firestore emulator reproductions in isolated namespaces.
**Not done:** no production access, nothing deployed, nothing committed.

## 1. Summary

| | |
|---|---|
| **Failing call** | `JobRequestNotifier.submitRequest` (`lib/providers/job_provider.dart`) → `FirestoreRepository.createJob` (`lib/firebase/firestore/firestore_repository.dart:20-45`) → one atomic `WriteBatch.commit()` that writes `jobs/{jobId}` **and** `jobs/{jobId}/private/location`. It goes to the **production** Firebase project `handytrust` |
| **Actual error** | Firestore **`permission-denied`**. Reproduced locally (section 3); the device log will show `[JobRequest] submission failed: cloud_firestore/permission-denied`. The app hid it behind a generic "check your connection" message |
| **Root cause** | **The app is newer than the Firestore rules deployed in production.** Since Stage 6 (commit `7e16eb1`), the app stores the customer's exact address and coordinates in a new private sub-document, `jobs/{id}/private/location`, written in the same batch as the job. The rule allowing that write exists only in the local `firestore.rules`. The program's own reports record that the rules were **never deployed** (`design/PHASE12_PRODUCTION_READINESS_REPORT.md:31`; `design/REMEDIATION_STAGE6_REPORT_2026-11-03.md` §5). Older rules have no rule for that path, so the private write is denied and, because the batch is atomic, the whole job is rejected |
| **When it happens** | Whenever the customer gives a location (GPS or a typed address). A job with no location at all still posts under the old rules |
| **Misleading message** | The catch-all in `job_provider.dart` turned every failure, including a server refusal, into "Check your connection and try again". **Fixed locally** (section 5) |
| **Fix for the cause** | Deploy the current rules to production. **Not authorised**, and it has knock-on effects (section 6). Owner decision |

---

## 2. Trace and checks

| # | Check | Finding |
|---|---|---|
| 1 | Flutter submission path | "Find Artisans" button → `_submit` (`lib/ui/screens/post_job_screen.dart:141`), which needs ≥ 1 photo and a signed-in profile → `jobRequestNotifierProvider.submitRequest`. Photos are uploaded to Firebase Storage one by one; each failure is caught and counted, never fatal. Then `createJob`. The snackbar shows `Couldn't post your job: ${state.error}` (`post_job_screen.dart:169`) |
| 2 | Exact operation | A Firestore batch with two writes: (a) `jobs/{id}`: the job without exact location, plus coarse `areaLat`, `areaLng`, `areaGeohash3`, `areaGeohash4`, `areaLabel`, `updateVersion: 0`, server `lastUpdatedAt`, `lastUpdatedBy`; (b) `jobs/{id}/private/location`: `customerLat`, `customerLng`, `customerAddress`, whichever exist. No Cloud Function and no HTTP API is involved |
| 3 | Base URL and environment | No API base URL; direct Firestore. Normal and release builds use project `handytrust` (`lib/firebase_options.dart`, `android/app/google-services.json`). Local-emulator mode needs `HT_EMULATOR=true` and isn't used by these builds |
| 4 | Auth token | Present: the screen refuses to submit without a signed-in profile, and the rules evaluated `request.auth.uid` (the denial wasn't `unauthenticated`) |
| 5 | Firestore connectivity and rules | Connectivity isn't the cause: an offline batch waits rather than failing. **Rules are**: section 3 |
| 6 | Cloud Functions and region | Not involved in job creation. (Production has no Functions deployed: `design/BILLING_DEPENDENCY_AUDIT.md`) |
| 7 | Error handling and codes | The real error was printed only to the device log; the UI always said "Check your connection". Now fixed (section 5) |
| 8 | Effect of the independent media backend work | **None.** No file of that workstream had been created when this was investigated. The RumptyCloud media changes don't touch job posting, which uses Firebase Storage |
| 9 | Localhost or unreachable endpoint | No. All three current builds contain the same job-posting code; the release APK was built today at 12:49. Your local emulators hold **0 Auth accounts, 0 users and 0 jobs**, so the error wasn't produced against them; it came from a production-configured build |

The exact reported wording ("Submit request failed. Check your network") doesn't exist in the source, the Git history or any build. All builds contain "Couldn't post your job" + "Could not submit your job request. Check your connection and try again", so the report is a paraphrase of that message.

---

## 3. Reproduction (local emulator, isolated namespaces, no production)

The app's exact batch (the same keys, values and types as `createJob`) was replayed as a signed-in customer against three versions of `firestore.rules`:

| Rules version | GPS + address | Typed address only | No location |
|---|---|---|---|
| **Current local** (HEAD + working tree) | allowed | allowed | allowed |
| `c1740f4` (the last commit before the Stage 6 rules) | **permission-denied** | **permission-denied** | allowed |
| `efe5398` (initial commit) | **permission-denied** | **permission-denied** | allowed |

Each case was run with 0 photos and with 1 photo; photos make no difference. The denial follows the `private/location` write: a typed address alone, with no coarse area fields, is still denied. The old job-create rule checked only `customerId` and `status`.

Script: run locally from the session scratchpad, not added to the repo. The permanent regression for the current rules already exists: `firestore-tests/security_regression.test.js:1050`, *"NEW client: job (coarse area) + private location created together"*.

**Remaining confirmation (owner, read-only):**
- Firebase Console → Firestore → Rules: the published rules have no `match /private/{docId}` under `jobs`, and the publish date is before 3 November 2026; or
- reproduce on the phone with `adb logcat | findstr JobRequest` and see `cloud_firestore/permission-denied`. With the fix below, the app now also shows `(permission-denied)` on screen.

---

## 4. Related production issue (separate, not the cause)

The production Storage bucket `handytrust.firebasestorage.app` was never provisioned (`design/STORAGE_UPLOAD_ROOT_CAUSE.md`). Every job photo upload therefore fails. The current app still saves the job and says "*N* photos failed to upload". Provisioning the bucket is a Console step; on the Spark plan, Firebase's current Storage terms may require Blaze. Not part of this fix.

---

## 5. Local fix applied: truthful error messages

`lib/providers/job_provider.dart`:
- Firebase errors are now caught by code and logged as `plugin/code: message`.
- `jobSubmitErrorMessage(code)` chooses the text:

| Code | Message |
|---|---|
| `unavailable`, `deadline-exceeded`, `network-request-failed` (and timeouts) | "No connection to HandyTrust. Check your network and try again." |
| `permission-denied` | "The server refused to save this job. This is not a network problem; please contact support. (permission-denied)" |
| `unauthenticated` | "Your session has expired. Please sign in again." |
| `resource-exhausted` | "Too many requests right now…" |
| anything else | a generic message with the code; never blames the network |

Nothing is reported as success unless the batch committed. Rules, privacy and the batch itself are unchanged.

**This does not make job posting work in production.** It makes the failure visible and accurate until the rules are deployed.

---

## 6. Fixing the cause: owner decision, needs approval

Deploying the current rules (`firebase deploy --only firestore:rules,firestore:indexes --project handytrust`) would make job posting with a location work. But the current rules also contain every other remediation change (Stages 1–8), with consequences for a Spark project with no Functions deployed:

- **Notifications:** client-created notifications are removed (Stage 6, M-1). Without deployed Functions, nobody creates notifications, and older app builds would show errors after successful actions.
- **Data migration:** existing jobs still carry exact locations until `adminBackfillJobLocationPrivacy` runs (M-2). That is a Function, not deployed.
- **Indexes:** the new indexes (M-4) must build before the radius queries work.

Options:
1. Deploy the full current rules with a planned rollout (M-1 to M-6).
2. Deploy a minimal production rules change: add only the `jobs/{id}/private/location` rule and the `area*` keys to whatever is published now. This needs the published rules first.
3. Leave production as is. Job posting with a location keeps failing, now with an honest message.

---

## 7. Files changed

| File | Change |
|---|---|
| `lib/providers/job_provider.dart` | Code-aware error handling; new `jobSubmitErrorMessage` |
| `test/job_request_submit_error_test.dart` | **New**: 6 tests (permission-denied isn't blamed on the network; connectivity codes are; expired session; unexpected errors; photo failure doesn't fail the job; success path) |
| `design/JOB_POSTING_FAILURE_ROOT_CAUSE.md` | **New**: this report |

## 8. Test results

| Check | Result |
|---|---|
| Rules regression `firestore-tests/security_regression.test.js` (includes the new-client job + private-location batch) | **113 passed, 0 failed, 0 skipped** |
| Reproduction matrix (3 rule versions × 3 location cases × 2 photo counts) | 18 cases as tabled in section 3 |
| `flutter analyze` on the two changed Dart files | **No issues** |
| New Flutter test `test/job_request_submit_error_test.dart` | **Not yet run.** Drive C: has ~150 MB free (100% full), and a Flutter test compile needs roughly that much temporary space. Run after freeing space: `flutter test test/job_request_submit_error_test.dart` |
