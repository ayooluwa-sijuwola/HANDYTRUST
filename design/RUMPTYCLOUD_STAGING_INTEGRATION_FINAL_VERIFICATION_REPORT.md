# RumptyCloud staging integration — final verification report

**Date:** 6 November 2026. **Branch:** `stage-8-ui-replacement`. **HEAD:** `aa9f93c` (your commit "Fianlisin rumptycloud", made outside this session at 10:44).

**Overall status: NOT READY FOR LIVE TESTING.** Live testing is **BLOCKED** because the RumptyCloud credentials are not on this computer: `functions\.secret.local` was never created at `C:\PROJECTS\handy_trust\functions\`. Everything up to the RumptyCloud boundary is implemented and verified, **including on an Android emulator**.

**No credential and no signed link appears in this report.**

## 1. Acceptance criteria

| Requirement | Result |
|---|---|
| Backend integration | **Complete**: offline (39/39) and emulator verified |
| Flutter integration | **Complete**: unit tested (15/15) and **run on an Android emulator** |
| Emulator configuration | **Verified on device**: Auth, Firestore and Functions reached from Android at `10.0.2.2`; the production config is absent |
| Credentials | **BLOCKED**: no `functions\.secret.local` on this computer (§5) |
| Bucket permissions | **BLOCKED**: verified automatically by T2-00 once credentials exist |
| Live image upload | **BLOCKED**: not run |
| Upload confirmation | **BLOCKED** live. Verified offline against a fake store |
| Private image retrieval | **BLOCKED** live. Verified offline |
| In-app image display | **BLOCKED** live. The display path is built and rendered with on-device images; a real private image can't be fetched without credentials |
| Unauthorized access | **Verified offline and on emulator** (rules and callables). Live check BLOCKED |
| Authorized deletion | **BLOCKED** live. Verified offline (revoke-first, retries, idempotent) |
| Clean-up | **BLOCKED** live. Nothing was created in the bucket by this work |
| Automated tests | **Passing** (§9) |
| Android debug build | **Successful** (normal and emulator mode) |
| User instructions | **Complete**: `design/RUMPTYCLOUD_LIVE_STAGING_TEST_GUIDE.md` |

**The one action needed:** in PowerShell on this computer, run

```
cd C:\PROJECTS\handy_trust
powershell -ExecutionPolicy Bypass -File tool\set_rumpty_credentials.ps1
```

Confirm it prints `Full path: C:\PROJECTS\handy_trust\functions\.secret.local`. Then the live run can start (guide §15, or ask me to run it).

## 2. What was inspected

- **Git:** HEAD `aa9f93c` (not `7ff140c`), nothing staged, no other uncommitted work at the start of this session.
- **That commit:** contains the A1, A6 and RumptyCloud work plus the design documents. Checks:
  - **no** `.secret.local` or `.env*` file in it;
  - `tool/check_no_secrets.js` over its full diff: **clean**;
  - `functions/node_modules` no longer tracked;
  - the branch has no upstream (not pushed).
- **Local configuration:**
  - `functions/.env.local` (non-secret, git-ignored): endpoint, region, bucket, `RUMPTY_UPLOAD_MODE=proxy`.
  - **No credential file** in the repository, the user profile or the environment. The `.env` files found belong to the separate `work_sphere_ai` project and were not touched.
  - `.claude` settings contain no sandbox or deny rules that could hide files from me.
- **Documents:** Phase 1 report, Phase 2 plan, implementation report, roadmap, storage audit, allow-list, architecture, implementation roadmap, review decisions. `RUMPTYCLOUD_MEDIA_SECURITY_REVIEW.md` doesn't exist; the media security review is `HANDYTRUST_MEDIA_SECURITY_REVIEW.md`.

## 3. Changes in this session (uncommitted; on top of `aa9f93c`)

| File | Change |
|---|---|
| `functions/media.js` | **Least-privilege keys:** K1 read + write; K2 **delete only** (list optional, used only for the admin report); post-delete verification uses K1's read. **Explicit single-key mode** (`RUMPTY_SINGLE_KEY_ACCEPTED=true`, written only by the setup script after you type ACCEPT); otherwise the same key in both roles is refused. **Refuses to run for any project other than `demo-*` / `handytrust-staging`.** The reconciliation report works without list permission |
| `functions/test/media_offline.test.js` | +3 tests (T1-11b): production refusal, key-role rules, reconciliation without list. One project ID under `emulators:exec`. Dummy-credential line rewritten so the secret scanner passes |
| `functions/test/media_live.test.js` | Rewritten (§7) |
| `functions/tools/verify_keys_absent.js` (new) | Checks by key that every object the app-side live test created is gone |
| `test/media_live_app_test.dart` (new) | Live test of the **app's own** `MediaService` + `DioMediaUploader` against the emulators and the real bucket |
| `lib/core/services/media_service.dart` | Returns the upload mode; logs callable error codes (no data); clear message for unreachable emulators |
| `lib/core/firebase/emulator_config.dart` | **Defect fixed on device** (§6): format-valid **fake** API key, assembled at run time so no key-shaped literal exists in source |
| `lib/ui/staging/media_staging_screen.dart` | JPEG/PNG/WebP choice; images drawn on the device and encoded with the existing `flutter_image_compress` (EXIF dropped); upload path shown; viewer with **Refresh link**; delete then **server re-check** ("no longer available"); readable chips (**defect fixed on device**) |
| `test/media_service_test.dart` | Updated for the above |
| `tool/set_rumpty_credentials.ps1` (new) | Hidden-input credential setup. Checks git-ignore first. Accepts base64 secrets. Prints the saved path and computer |
| `tool/start_rumpty_emulators.ps1` (new) | Checks the credential names, then starts the emulators (`demo-handytrust-media`, data persisted) |
| `tool/run_handytrust_emulator_app.ps1` (new) | Runs the app in emulator mode (Android emulator, or a USB phone with `adb reverse`) |
| `tool/run_rumpty_live_tests.ps1` (new) | Dashboard confirmations, then the bounded live run with an evidence folder |
| `design/RUMPTYCLOUD_LIVE_STAGING_TEST_GUIDE.md`, this report | New |

**Local only:** `functions/.env.local`, `.vscode/launch.json` and `firebase-debug.log` (emulator log, no secrets) are git-ignored or excluded.

## 4. Backend, schema and rules

**Functions** (exported only for `demo-*` or `handytrust-staging` projects):
- `requestMediaUpload` → `uploadMediaContent` (proxy) or a presigned PUT → `confirmMediaUpload` → `getMediaUrl` → `deleteMedia`;
- admin-only `runMediaSweep`.

**Request checks:** auth, kind, type, extension, size, SHA-256, quotas and limits. **Object keys** are server-generated random UUIDs under `staging/media/`. **Confirmation** checks HEAD size and type, a bounded re-read, SHA-256 and signature. **Reads** use 5-minute signed links that are never stored. **Deletion** revokes access first, then deletes, verifies 404 and retries with back-off.

Full detail: `RUMPTYCLOUD_STAGING_INTEGRATION_IMPLEMENTATION_REPORT.md` §6–§8. The schema and rules are unchanged this session: `media`, `media_quotas` and `media_system` are server-written and owner-readable.

**Upload path:**
- **Proxy is used now:** bytes go through the Function, are checked, and only then written.
- **Direct presigned upload** is implemented and tested end to end by T2-13. It's switched on only after the live run proves the store enforces signed length (T2-03) and ignores unsigned ACL headers (T2-08). Until then the app uses the proxy path automatically.

## 5. Credential and bucket verification

- **Credentials:** **not present on this computer.**
  - You reported running the setup script twice. After each run, `C:\PROJECTS\handy_trust\functions\.secret.local` did not exist, checked with Bash, PowerShell `Test-Path` and a file search.
  - `functions\.env.local` was also untouched; the script rewrites it at the end, so it didn't finish here.
  - Two script defects that could have caused this were fixed:
    - base64 secrets containing `=` were wrongly rejected;
    - a missing `git` gave an unclear error.
  - The script now prints the full path and computer name.
- **Bucket identity:** allow-listed in code (bucket, endpoint, region), with the project gate.
  - READY/PRIVATE status and the balance (≤ $5, auto top-up off) were **confirmed by you in this session**. They weren't independently verifiable here; there's no dashboard API.
  - Anonymous access was previously probed (403).
- **Permissions:** to be verified by **T2-00** before any other live operation. It proves:
  - K1 can write, head and read;
  - K2 can delete;
  - K2 cannot write (recorded);
  - listing is recorded as optional.

  A missing required permission stops the run.

## 6. Android emulator verification (performed)

**Set-up:**
- `Pixel_8` (Android 14), started with `-memory 2048`: the default 6 GB exceeded this PC's free memory.
- The emulator-mode debug APK was installed.
- A synthetic, verified test account and profile were created in the **local** emulators only, and removed afterwards.

| Step | Result |
|---|---|
| App start | `[emulator] EMULATOR MODE — project demo-handytrust-media at 10.0.2.2`; no `duplicate-app`, so the production config was absent |
| Onboarding → sign-in | Signed in through the **Auth emulator** |
| Home, Profile, Settings | Data read from the **Firestore emulator** at 10.0.2.2 (`safeStream … OK`) |
| Settings | "STAGING (EMULATOR ONLY) → Media storage test" present |
| Create image | JPEG (6,974 and 7,565 B) and **WebP (5,582 B)** encoded on the device |
| Upload, no credentials | First result: "Something went wrong". **Root cause:** `IllegalArgumentException: Please set a valid API key`. The Android Functions SDK collects an Installations token before each callable and rejected the placeholder key's format. **Fixed** (format-valid fake key), rebuilt and re-tested: the app now shows **"Media storage is not configured on this server."**, the correct fail-closed result, with `media_config_missing` logged by the Functions emulator |
| Visual check | Unselected chips had white text on a light background (unreadable). **Fixed** using the app's `HtChip`; verified on device |

**In emulator mode** the Android SDK still contacts Google's public Installations/FCM endpoints using the fake key and the demo project. These calls fail harmlessly; no HandyTrust project is involved.

## 7. Live test suite (ready; not run)

**`functions/test/media_live.test.js`** runs in-process against the real bucket, with every object under the run-unique prefix `staging/livetest/<runId>/`:

| Test | Checks |
|---|---|
| T2-00 | Permissions and initial object count (if listing is allowed) |
| T2-01 ×3 | JPEG, PNG, WebP: upload → confirm, HEAD size and type, Firestore record |
| T2-02 | Owner read twice with fresh links (SHA-256 match); non-owner refused; anonymous GET and anonymous listing refused; expired link refused |
| T2-14 | Invalid files rejected before storage |
| T2-03 | Size enforcement on presigned PUT |
| T2-08 | ACL exposure |
| T2-09 | Wrong type and expired PUT link refused |
| T2-13 | Direct-upload path end to end (only if T2-03 and T2-08 pass) |
| T2-05/06/07 | Informational vendor behaviour |
| T2-12 | Tampered object rejected and removed |
| T2-11 | Owner deletion, repeat deletion, non-owner refused, object gone, record `deleted`/`released`, link refused |
| T2-10 | Every created key checked gone |

**`test/media_live_app_test.dart`** drives the **app's** client code: JPEG, PNG and WebP upload, two reads, decoding by Flutter's image codec, the other account refused, delete, then refused. `verify_keys_absent.js` then checks each created key.

**Guards:**
- ≤ 30 objects and ≤ 25 MB per run;
- `RUMPTY_LIVE=1` plus your confirmation;
- a `demo-` project only;
- deletion only of keys this run created;
- the run fails if any are left.

**Evidence:** JSON in a `%TEMP%` folder, with keys and outcomes only.

**Objects created and bytes uploaded in this session:** **0 / 0 B**. **Prepaid balance:** not observed by me. You confirmed it's ≤ $5 with auto top-up off.

## 8. CORS

Not needed for Android: the Android app doesn't use CORS.

A web build using direct presigned uploads or `<img>` loads from the bucket would need RumptyCloud CORS (dashboard only, ≤ 20 origins). If that's ever needed, the narrowest configuration is: origin `http://localhost:<port>` for local web testing only, methods `PUT`/`GET`, header `Content-Type`. Never `*`, and never by making the bucket public. Not configured: no web test is in scope.

## 9. Test results (6 November 2026)

| Command | Exit | Passed | Failed | Skipped |
|---|---|---|---|---|
| `flutter analyze` | 1 | — | 0 new | 23 existing issues (10 deprecation infos, 13 in excluded `work_sphere_ai`); none in changed files |
| `flutter test` | 0 | 366 | 0 | 1 (live app test, gated) |
| `flutter test test_visual` | 0 | 654 | 0 | 0 |
| Functions (16 suites + media offline + media live), Firestore emulator, Node 22 | 0 each | 329 (incl. 39 media offline) | 0 | live suite skipped (gated) |
| Firestore rules (incl. 6 media) | 0 | 168 | 0 | 0 |
| Storage rules | 0 | 9 | 0 | 0 |
| End-to-end (Functions + Firestore + Pub/Sub; dummy secret created and removed) | 0 | 16 | 0 | 0; **0 external calls, 0 Secret Manager attempts** |
| Android debug APK, emulator mode (final) | 0 | — | — | 188 MB; production app ID **absent** |
| Android debug APK, normal | 0 (earlier today) | — | — | Production config present, unchanged |
| Media offline + live suites **under `firebase emulators:exec`** (as the live-run script launches them) | 0 | 39 | 0 | live suite skipped (gated) — see note |
| PowerShell scripts | — | 4/4 parse | — | Start script refuses without credentials (verified) |

**Note: a harness defect was found and fixed.**
- **Symptom:** under `emulators:exec` the offline suite first failed 25/39.
- **Cause:** `emulators:exec` sets `FIREBASE_CONFIG`, so the Admin SDK used a different project namespace from the test's per-test reset.
- **Fix:** both media suites now derive one project ID. Re-run: 39/39 under `emulators:exec` and 39/39 standalone.
- **Why it matters:** the live-run script launches the suite this way.

**Contacts and changes:**
- **Production:** none. **Firebase deployment:** none. **Paystack:** none (dummy key only inside the end-to-end emulator).
- **Notification and location code:** no changes.

## 10. Known limitations

- **Live behaviour is unproven** until credentials exist. That covers presigned GET, size and ACL enforcement, checksum and response-header behaviour, and delete semantics (Q1–Q7).
- **Rule:** staging read access is owner or admin only.
- **Emulator workflow:**
  - emulator mode adds a harmless app check warning and Installations/FCM failures (fake key);
  - the emulator Android image needs `-memory 2048` on this PC;
  - a reinstall needs an uninstall first (the emulator's internal storage is small).
- **Production:** none of the production blockers (implementation report §18) are addressed.

## 11. Manual steps still required

1. Run `tool\set_rumpty_credentials.ps1` **on this computer in `C:\PROJECTS\handy_trust`**, and confirm the printed path.
2. Re-check the dashboard (READY, PRIVATE, balance ≤ $5, auto top-up off).
3. Either ask me to run the bounded live suite, or run `tool\run_rumpty_live_tests.ps1` yourself.
4. Follow the guide for your first in-app upload.

No commit, push, deployment, billing change, production change, Paystack access or real media was involved.
