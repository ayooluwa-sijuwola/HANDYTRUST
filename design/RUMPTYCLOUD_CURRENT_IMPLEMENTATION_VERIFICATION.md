# RumptyCloud integration — current implementation verification

**Date:** 6 November 2026
**Scope:** the files on disk now (HEAD `aa9f93c` plus uncommitted changes), inspected directly. Earlier reports were not relied on.
**Not done:** no RumptyCloud call, no upload, no deploy, no commit. The running emulator was only read (two read-only Firestore queries).

## 1. Verdict: IMPLEMENTED, LIVE TEST PENDING

The backend, the Flutter client and the test screen are implemented, and every offline test passes. Credentials are now stored correctly. **No live upload has happened yet**: the running emulator holds 0 media records, and no live-run evidence folder exists.

Before the first live run:

| # | Item | Who | Blocks a live run? |
|---|---|---|---|
| 1 | Confirm in the RumptyCloud dashboard that **automatic top-up is OFF** | Owner | **Yes** |
| 2 | Decide on the **balance cap**: the live runner asks "balance is $5 or less?", but the reported balance is **₦20,000**. That is above US$5 at recent exchange rates; it would equal US$5 only at ₦4,000 per US$. Either lower the balance or restate the cap | Owner | **Yes** |
| 3 | Fix the two clean-up gaps in the live tests (F-2, F-3) | Code | Recommended first |

---

## 2. Backend (`functions/media.js`)

| Check | Result | Evidence |
|---|---|---|
| Firebase authentication enforced | **Yes** | `_requireMediaUser` (`media.js:306`). Refuses unauthenticated (`unauthenticated`), anonymous, unverified-email and suspended accounts. Every media callable calls it first. Offline T1-01 |
| User authorisation | **Yes** | `_loadAccessible` (`media.js:324`). Owner only for upload and confirm; owner or admin for view and delete. A record you may not see returns the same "not found" as a missing one, so ids can't be probed. Ids must be 20 alphanumerics. T1-05, T1-08, T1-09 |
| MIME types and sizes validated | **Yes** | Request (`media.js:497-512`): kind allow-list (3 synthetic kinds); JPEG, PNG or WebP only; extension must match; integer size from 1 byte to the kind limit (5 MB, thumbnails 1 MB); SHA-256 required. Upload (`media.js:577-598`): base64 length bound before decoding; exact size; SHA-256; then the bytes are sniffed (signature, completeness, dimensions ≤ 8000 px and ≤ 40 MP, thumbnails ≤ 512 px). The declared Content-Type is never trusted. T1-02, T1-07 |
| Object keys generated securely | **Yes** | Server only (`media.js:521`): `staging/media/<kind>/<yyyy>/<mm>/<randomUUID>.<ext>`. The prefix must match `^staging(/…)+$` (`media.js:79`). The client never supplies a bucket, key, owner or URL. T1-02 |
| Upload URLs signed correctly | **Yes, but not in use** | **Active mode is `proxy`** (`functions/.env.local`): no upload URL exists; bytes go to the `uploadMediaContent` callable and are checked **before** the server writes them with K1 (`media.js:574-618`). The direct path (presigned PUT, 300 s, Content-Type and Content-Length signed, no checksum parameters; `media.js:201-204`) needs `RUMPTY_UPLOAD_MODE=presigned` **and** `RUMPTY_PRESIGNED_PUT_VERIFIED=true`. It stays disabled until live tests T2-03 and T2-08 prove RumptyCloud enforces the signed length and ignores unsigned ACL headers. Signing checked offline with the real SDK presigner (T1-02) |
| Confirmation checks the actual object | **Yes** | `_verifyStoredObject` (`media.js:449-468`): HEAD (exists, size, content type), then the full object is read back (bounded, 60 s timeout), SHA-256 recomputed and content re-validated. An invalid object is revoked, deleted and the record marked `rejected` (`media.js:656-660`). T1-06 |
| SHA-256 as documented | **Yes** | The client hashes the bytes (`media_service.dart:143`). The server checks the hash on proxy upload before storing (`media.js:594`), then **re-hashes the stored bytes** at confirmation and stores `verifiedSha256` (`media.js:647`). The guide's statement "`verifiedSha256` equals `sha256`" matches the code. T1-06 |
| Download URLs private and temporary | **Yes (code)** | `getMediaUrl` (`media.js:663-675`): verified records only; presigned GET valid **300 s**; returned to the caller, never stored. The app keeps it in memory only (`MediaUrl`). That the bucket itself is private is a dashboard setting; it is **proven only by the live test** (T2-02, anonymous GET and list → 401/403). T1-08 |
| Deletion checks ownership | **Yes** | `deleteMedia` (`media.js:677-688`): owner or admin. Access is revoked first (`deleting`), then the object is deleted with the clean-up key, and a HEAD confirms it's gone before the record says `deleted`. Failures back off; after 8 attempts the record becomes `delete_failed` and an admin alert is raised. T1-09 |
| Firestore metadata lifecycle | **Yes, with one design point** | Created in one transaction with the quota counters (`media.js:524-554`); every later change goes through `_transition`, which keeps the quotas exact (T1-03). Records are **not deleted**: they end as `deleted`, `expired` or `rejected`, a tombstone with timestamps, by design. Rules: clients can only read their own records and never write (`firestore.rules:1202-1214`); media rules tests 6/6 |
| Errors don't expose credentials | **Yes** | Clients get fixed messages. Logs carry only the event, ids, the error class and the HTTP status (`_errFields`, `media.js:144`). Every RumptyCloud network call is wrapped. Configuration problems are reported by **name**. T1-11 injects a store error containing a secret and asserts it appears in no log line or error |

---

## 3. Flutter client

| Step | Works? | Where |
|---|---|---|
| 1. Open the test screen | **Yes**, emulator-mode debug builds only | Profile → gear → "Staging (emulator only)" → **Media storage test** (`settings_screens.dart:209`); route `/staging/media` (`router.dart:236`). Both appear only when `EmulatorConfig.enabled`, which is `HT_EMULATOR` set and not a release build |
| 2. Create a synthetic image | **Yes** | `generateSyntheticImage` (`media_staging_screen.dart:41-68`): gradient + "SYNTHETIC TEST" + timestamp, drawn on the device; JPEG and WebP re-encoded without EXIF. No device photo is ever read |
| 3. Request an upload | **Yes** | `MediaService.upload` → `requestMediaUpload` (`media_service.dart:145`). In proxy mode this returns a media id, **not a URL** |
| 4. Upload the image to RumptyCloud | **Yes, via the server** | Proxy: `uploadMediaContent` (base64), and the Function writes to RumptyCloud. Presigned branch (`media_service.dart:149-158`, Dio PUT with progress) is used only if the server enables it |
| 5. Confirm | **Yes** | `confirmMediaUpload`. Success is reported only when the status is `verified` (`media_service.dart:163-164`) |
| 6. Get a signed image URL | **Yes** | `readUrl` → `getMediaUrl`. Cached until 30 s before expiry (`media_service.dart:182-190`) |
| 7. Display | **Yes** | `_MediaViewer`: `Image.network` with loading and error builders (`media_staging_screen.dart:329-337`) |
| 8. Refresh the URL | **Yes** | "Refresh link" → `readUrl(forceRefresh: true)`; a new image key forces a reload; the counter shows how many loads |
| 9. Delete through the backend | **Yes** | Bin → confirm → `deleteMedia`. On success the app asks for a link again and **expects a refusal** (`media_staging_screen.dart:234-255`) |

**States:**
- **Loading:** the progress bar shows the stage ("Asking the server…", "Uploading…", "Server is verifying…"); the button is disabled and busy; the viewer and list have their own loading views.
- **Errors:** every callable error maps to plain text (`mapFunctionsError`, `media_service.dart:224-253`). A failed upload releases its reservation (`_releaseQuietly`). The list has a retry view.
- **Success:** a green banner with the media id and the upload path.
- **Weaknesses:** F-1 and F-5 below.

---

## 4. Configuration (no values shown)

| Check | Result |
|---|---|
| `functions/.secret.local` exists | **Yes**, written 6 Nov 2026 12:11:27 |
| Variable names present | **Yes**: `RUMPTY_ACCESS_KEY_ID` (24 chars), `RUMPTY_SECRET_ACCESS_KEY` (40), `RUMPTY_CLEANUP_ACCESS_KEY_ID` (24), `RUMPTY_CLEANUP_SECRET_ACCESS_KEY` (40). None empty; no spaces, quotes, CR or BOM |
| Ignored by Git, not tracked | **Yes**: `git check-ignore` → `.gitignore:48`; `git ls-files` → nothing |
| Bucket identifier | `assets-handytrust-01a0f99e-5d6ffa` in `.env.local`, matching the code allow-list (`media.js:78`) |
| Endpoint and region | `https://s3.rumptycloud.com`, `olas-closet`; both match the allow-list (`media.js:76-77`) |
| Key mode | **Single key.** The clean-up key is identical to the app key, and `RUMPTY_SINGLE_KEY_ACCEPTED=true` is in `.env.local`. The key therefore needs **Read + Write + Delete**. Not verifiable offline: live test T2-00 checks it first and stops the run if anything is missing |
| No credentials in the app | **Verified.** The current key values were searched for (matched in memory, nothing printed): 751 working-tree files (lib, android, assets, web, ios, test, tool, design, functions and root files), every entry of both built APKs (debug: 763 entries; release: 571), the Git index and all 9 commits. **0 matches.** The app never receives a key; no `RUMPTY_` name appears in `lib/` |
| Production can't reach the staging bucket | **Verified in code and tests**: (1) the media callables are exported only for a `demo-*` project or `handytrust-staging` (`functions/index.js:4414-4424`), so production `handytrust` never has them; (2) `media.js` refuses any other project (T1-11b); (3) bucket, endpoint, region and prefix are allow-listed; (4) the test screen and route exist only in emulator-mode debug builds; release builds refuse emulator mode (`emulator_config.dart:54`); (5) no deploy-time `functions/.env*` file holds `RUMPTY_` values |
| Local emulator configuration | **Correct**: `firebase.json` ports (auth 9099, firestore 8090, functions 5001, storage 9199) match `EmulatorConfig`; the start script uses `demo-handytrust-media`, the app's project id; the Android `HT_EMULATOR` build leaves out the production `google-services.json` (`build.gradle.kts:17`); the debug-only network config allows plain HTTP only to 10.0.2.2, localhost and 127.0.0.1 |
| Running emulators | Emulators for `demo-handytrust-media` started **12:17:30**, after the credentials were saved, so the Functions emulator should have loaded them. **Not probed**: calling it could contact RumptyCloud |

---

## 5. Offline tests (run today)

| Suite | Passed | Failed | Skipped |
|---|---|---|---|
| Backend media, offline (`functions/test/media_offline.test.js`) | **39** | 0 | 0 |
| Firestore rules, media (`firestore-tests/media_rules.test.js`) | **6** | 0 | 0 |
| Functions runtime configuration (`runtime_config.test.js`) | **4** | 0 | 0 |
| Flutter media client (`test/media_service_test.dart`, `test/media_live_app_test.dart`) | **15** | 0 | **1** (the live app test, skipped without `RUMPTY_LIVE=1`, as intended) |
| Pre-commit secret scan over all uncommitted changes (7 modified, 8 untracked files) | clean | — | — |
| *Regression:* full Functions suite (`npm test`) | **290** | 0 | 0 |
| *Regression:* other Firestore rules suites | **162** | 0 | 0 |
| *Regression:* full Flutter suite (`flutter test`) | **Not completed**: the run stalled when drive C: ran out of space and was stopped at 12:53 without producing a result. To be re-run once disk space is freed | — | — |
| `flutter analyze` on the 8 media files (service, screen, emulator config, initialiser, provider, model, both tests) | **No issues found** | — | — |

The node suites ran against the running Firestore emulator, each under its **own project id** (for example `demo-handytrust-media-offline`). They never touched the app's `demo-handytrust-media` data: it still holds 0 media records.

---

## 6. Live-test readiness (inspected, not run)

| Requirement | Status | Evidence |
|---|---|---|
| ≤ 30 objects per run | **Enforced** | `willCreate` counts every write **before** it happens and stops the run above 30 (`media_live.test.js:75-84`). Planned use: 14 objects in the backend test plus 3 in the app test |
| ≤ 25 MB per run | **Enforced** | Same counter. Planned use is under 20 KB |
| Synthetic images only | **Yes** | Fixtures `synthetic_64x48.jpg/.png`, `synthetic_1x1.webp`, `synthetic_600x400.png` (42 B – 1.7 KB), a text probe and random bytes. The app screen draws its own images |
| Zero objects left | **Mostly** | `after()` checks every recorded key by HEAD, deletes leftovers and fails the run if any remain. The app-side live objects are checked by `verify_keys_absent.js`. **Gaps: F-2, F-3** |
| No broad deletion | **Yes** | Deletes are by exact key, only for keys this run created (`removeOwn` refuses others). The one bucket-wide `list` (T2-00) only counts objects. Reconciliation only reports, never deletes |
| Stop on unexpected balance drop | **Manual only** | No billing API is used. The runner reminds you to compare the balance after the run. Not enforceable in code |
| Top-up setting known before upload | **Not yet**. Gate exists | The runner (`tool/run_rumpty_live_tests.ps1`) asks three yes/no questions (bucket ready and private; balance ≤ $5; top-up OFF) and stops on anything but `yes`. The owner's answer is the control; **top-up is currently unconfirmed** |
| Balance | **Conflict** | The reported ₦20,000 exceeds the runner's ≤ US$5 question at recent rates. Owner decision needed (section 1) |

---

## 7. Android APK compatibility

| Scenario | Works? | What it needs |
|---|---|---|
| **Android emulator + local Firebase emulators** | **Yes**, the intended setup | `tool/run_handytrust_emulator_app.ps1`. The app reaches the PC at 10.0.2.2, which the debug network config allows. The PC needs internet: the Functions emulator uploads to RumptyCloud. The Android emulator needs internet to show images: links point to `https://s3.rumptycloud.com`. A live end-to-end run on the device has **not been done yet** |
| **Physical phone on USB** | **Supported, not yet tried** | The same script with `-UsbPhone`: `adb reverse` for 9099, 8090, 5001, 9199 and host 127.0.0.1 (allowed). The phone must stay connected and needs its own internet to load images. **Wi-Fi only (no USB) does not work**: the emulators listen on localhost only, and the network config blocks plain HTTP to LAN addresses |
| **APK installed separately, away from the PC** | **No** | An emulator-mode APK points at 10.0.2.2 or 127.0.0.1, where nothing runs, so it shows "The media service did not respond…". A normal or release APK uses production `handytrust`, which has no media functions and no test screen. **This needs deployed services:** a real `handytrust-staging` Firebase project (only named in `.firebaserc`; existence unverified); the **Blaze plan** (Cloud Functions and Secret Manager); the four keys in Secret Manager; Functions, rules and indexes deployed. It also needs code: a staging build with that project's Firebase options (none exist; the only `google-services.json` is production) and a gate for the test screen in that build. All of these need approvals not given (billing, deploy) |

---

## 8. Findings

| ID | Severity | Finding | Suggested action |
|---|---|---|---|
| F-1 | Medium | **Nothing retries automatically.** There's no scheduled sweep: Cloud Scheduler needs Blaze; plan §6. Abandoned uploads expire only when the same user makes a new request, and deletion retries happen only on a repeat delete or an admin `runMediaSweep`. The app says "the server will retry it" (`media_staging_screen.dart:242`), and the guide says "retries automatically" | Change the text to "tap Delete again later". Optionally add an admin "run sweep" control in emulator mode |
| F-2 | Medium | **App-side live test can leave an object behind.** If any check fails between upload and delete (`media_live_app_test.dart:82-108`), the object stays. Its key is recorded nowhere: evidence is written only after the loop, and the temporary emulator's records disappear. `verify_keys_absent.js` then fails with "no app-side evidence", so the run does fail visibly | Wrap each iteration in `try/finally`: delete, then record the key; write evidence in `finally` |
| F-3 | Low | **T2-14 (invalid uploads)** doesn't register its keys before uploading. If validation ever failed open, the stored object wouldn't be cleaned up by `after()` | Call `willCreate` (or register the key) before each upload |
| F-4 | Owner | Top-up unconfirmed; ₦20,000 balance vs the ≤ US$5 gate | Section 1 |
| F-5 | Low | The `internal` error text says "Check that the Firebase emulators are running" (`media_service.dart:249`). That's correct today, but wrong if a deployed staging build ever uses it | Revisit with a staging build |
| F-6 | Info | **Single-key mode is active.** One leaked key could read, overwrite and delete everything in the staging bucket. Acceptable for synthetic staging data by owner decision; T2-00 verifies the key's permissions first | A separate Delete-only key restores two-key mode |
| F-7 | Info | Direct (presigned) upload is implemented but **off by design** until T2-03 and T2-08 pass live | None now |
| F-8 | Info | An account with no `users/{uid}` document can still upload; suspension is checked only when the document exists | Acceptable for staging; revisit for real media |

---

## 9. Evidence vs assumptions

**Verified today (direct evidence):**
- the code paths in sections 2 and 3;
- all test counts in section 5;
- the credential file's names, lengths, ignore status and untracked status;
- 0 credential matches across source, APKs and Git;
- allow-listed bucket, endpoint and region;
- the production export gate;
- emulator ports and project id;
- emulator start time after the credentials were saved;
- 0 media records and no live evidence, so no live run has happened.

**Assumed or not verifiable offline:**
- that the endpoint, region and bucket id are right for the real RumptyCloud account (first proven by live T2-00);
- that the single key has Read + Write + Delete (T2-00);
- that the bucket is PRIVATE (dashboard; T2-02);
- that the running Functions emulator loaded the credentials (inferred from timing, not probed);
- prepaid balance and top-up status (owner, dashboard);
- the naira-to-dollar comparison (depends on the exchange rate);
- that the USB-phone path works (supported in code, never run).
