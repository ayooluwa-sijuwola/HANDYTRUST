# RumptyCloud staging integration — implementation report

**Date:** 6 November 2026. **Branch:** `stage-8-ui-replacement`; HEAD `7ff140c`, unchanged.

**Scope:** local implementation of the Phase 2 plan, for **synthetic staging media only**.

**Not done:**
- nothing committed, staged, pushed or deployed;
- no billing change, no production project touched, no Paystack access;
- no real media moved.

## Status at a glance

| Area | Status |
|---|---|
| Backend (`functions/media.js`), rules, indexes | **Implemented; tested offline** |
| Offline tests T1-01 … T1-13 | **All pass** |
| Emulator wiring (real callables over HTTP, Auth-emulator tokens) | **Tested: 7 of 7 pass** |
| Flutter client (service, providers, emulator-only test screen) | **Implemented; unit-tested** |
| Full regression (Flutter, goldens, Functions, rules, Storage, end-to-end) | **All pass** |
| Live staging tests T2-01 … T2-12 | **Implemented, NOT RUN. Blocked:** no credential file, key permissions unconfirmed, balance not confirmed (§12–13) |
| Android APK build | **Builds.** Normal debug APK and emulator-mode debug APK both exit 0 (§11). First attempts failed because drive C: had **0 bytes free** (§19) |
| Production | **Not approved; not ready** (§18) |

---

## 1. Executive summary

**How it works:**
- Firebase stays the authority. Six callables check Firebase Auth and Firestore, keep a `media/{id}` record, and alone hold the RumptyCloud keys.
- RumptyCloud stores the objects in the existing **private staging bucket** `assets-handytrust-01a0f99e-5d6ffa`, under `staging/media/…`.

**Upload path:**
- The vendor doesn't document size enforcement on presigned uploads, so uploads default to a **Function-proxied** path.
- Size, file signature, dimensions and SHA-256 are checked **before anything is written to the bucket**. Confirmation then re-reads the stored object and checks it again.
- A presigned-PUT path is implemented but **disabled** until live tests T2-03 and T2-08 prove the store enforces length and ignores unsigned ACL headers.

**What's verified offline:** everything verifiable without credentials. That includes the real AWS SDK presigner, and the emulator stack driven over the callable protocol.

**What's not verified yet:** vendor behaviour (Q1–Q9).

**Android builds:** both build. They first failed because the disk was full, and succeeded once space was free.

---

## 2. Architecture implemented

```
Flutter (emulator mode only)          Firebase emulators (demo-handytrust-media)          RumptyCloud (staging bucket)
──────────────────────────────        ─────────────────────────────────────────────      ────────────────────────────
MediaService.upload(bytes)
  sha256(bytes) ───────────────────▶  requestMediaUpload  auth · kind · type · size · rate ·
                                        quotas · pending · global limit · random key ·
                                        media/{id}=pending                  (no URL in proxy mode)
  base64(bytes) ───────────────────▶  uploadMediaContent  owner · size == declared ·
                                        SHA-256 == declared · signature · dimensions ·
                                        completeness ──── only then ────────▶  PutObject (K1)
                 ──────────────────▶  confirmMediaUpload  HEAD · bounded re-read ·
                                        SHA-256 · signature again ──────────▶  HEAD/GET (K1)
                                        → verified (or delete via K2 → rejected)
  view ────────────────────────────▶  getMediaUrl  owner/admin · verified ─▶ presigned GET 300 s (K1)
       ◀── temporary URL (memory only, never stored) ─────────────────────────────────────────▶ GET
  delete ──────────────────────────▶  deleteMedia  revoke first → DeleteObject (K2) → HEAD 404 → deleted
                                        (failure: back-off retries → delete_failed + admin alert)
admin ─────────────────────────────▶  runMediaSweep  expire abandoned · interrupted · retry deletes ·
                                        report (never delete) untracked objects
```

**Keys:**

| Key | Permissions | Used for |
|---|---|---|
| **K1** (signer) | read + write | Proxied PUTs, verification reads, signing URLs |
| **K2** (cleanup) | list + read + delete | Deletion, post-delete HEAD, reconciliation listing |

Neither key leaves the Functions process.

**When the callables exist:** only when the project ID that function discovery receives is `demo-*` (emulator) or `handytrust-staging`. Verified:
- `handytrust` (production) → not exported;
- `demo-handytrust-media` → exported;
- other test project IDs → not exported.

**Why not an `.env` switch:** the original design used `HT_MEDIA_STAGING` in `.env.local`. firebase-tools 15.22 discovers functions **before** it reads `.env` files (`functionsEmulator.js`, around lines 357–372), so that switch could never work.

---

## 3. Files created

| File | Purpose |
|---|---|
| `functions/media.js` | Backend: config allow-list, S3 client (K1/K2), content validation, quotas/limits, state machine, the six callables, sweeps, test seams |
| `functions/test/media_offline.test.js` | T1-01 … T1-12 (36 tests) |
| `functions/test/media_live.test.js` | T2-01 … T2-12, gated and budgeted (§12) |
| `functions/test/fixtures/media/synthetic_64x48.png`, `.jpg`, `synthetic_600x400.png`, `synthetic_1x1.webp` | Synthetic, decodable fixtures (42 B – 1.7 KB) |
| `firestore-tests/media_rules.test.js` | T1-13 (6 tests) |
| `tool/generate_media_fixtures.dart` | Reproducible fixture generator (checks every fixture decodes) |
| `tool/check_no_secrets.js` | Pre-commit secret scan (staged diff, or `--stdin`) |
| `lib/core/firebase/emulator_config.dart` | Opt-in emulator mode (demo project; fails closed; never in release builds) |
| `lib/core/services/media_service.dart` | Client: request → upload → confirm → URL → delete; error mapping; URL cache in memory |
| `lib/models/media_ref.dart` | `MediaRef` (no URL field), `MediaUrl` (memory only) |
| `lib/providers/media_provider.dart` | Service, my-media stream, temporary-URL provider |
| `lib/ui/staging/media_staging_screen.dart` | Emulator-only test screen. Synthetic PNGs drawn on the device; no photo picker |
| `test/media_service_test.dart` | 15 client tests |
| `android/app/src/debug/res/xml/network_security_config.xml` | Debug only: HTTP to `10.0.2.2` / `localhost` / `127.0.0.1` (emulators) |
| `design/patches/RUMPTYCLOUD_STAGING_TRACKED_FILES.patch` | The RumptyCloud-only diff of the tracked files (separable from A1) |
| `design/RUMPTYCLOUD_STAGING_INTEGRATION_IMPLEMENTATION_REPORT.md` | This report |

**Local-only, not in Git:**

| File | Why it's excluded |
|---|---|
| `functions/.env.local` | Endpoint, region, bucket, upload mode; **no credentials**. Git-ignored |
| `.vscode/launch.json` | Launch configurations. Excluded by `.git/info/exclude` |

## 4. Files modified (RumptyCloud portion only)

| File | Change | Also changed by A1? |
|---|---|---|
| `functions/index.js` | +19: project-ID-gated `require('./media').callables` | yes |
| `functions/package.json` | +2 dependencies; `test:media`, `test:media:live` scripts placed **before** A1's `test` line, which is byte-identical | yes |
| `firestore.rules` | +20: `media`, `media_quotas`, `media_system` | yes |
| `firestore.indexes.json` | +33: four `media` composite indexes | yes |
| `functions/package-lock.json` | AWS SDK resolution (+414) | no |
| `firebase.json` | Emulator ports for `auth` 9099, `functions` 5001, `storage` 9199. Without the `auth` entry the CLI refused to start the Auth emulator | no |
| `.gitignore` | `tool/.secret-prefix.local` | no |
| `pubspec.yaml` / `pubspec.lock` | `crypto: ^3.0.6`. Already in the lockfile as transitive; **no version change**, only the dependency kind | no |
| `android/app/build.gradle.kts` | `google-services` applied unless `HT_EMULATOR=true` is in the build environment | no |
| `android/app/src/debug/AndroidManifest.xml` | Debug-only `networkSecurityConfig` | no |
| `lib/core/firebase/firebase_initializer.dart` | +9: emulator-mode branch | no |
| `lib/routes/router.dart` | `/staging/media` registered only when `EmulatorConfig.enabled` | no |
| `lib/ui/settings/settings_screens.dart` | "Staging (emulator only)" group, only when `EmulatorConfig.enabled` | no |

**Separation evidence:**
- The patch for these 14 files was generated against a snapshot taken **before** any RumptyCloud edit.
- Every A1-added line in the four shared files is still present (52/52, 17/17, 278/278, 1/1).
- All 219 other A1-state files are byte-identical.

## 5. Dependencies added

| Package | Version | Notes |
|---|---|---|
| `@aws-sdk/client-s3` (Functions) | `^3.1163.0` | Installed with `npm install --ignore-scripts` (26 packages) |
| `@aws-sdk/s3-request-presigner` (Functions) | `^3.1163.0` | Same install |
| `crypto` (Flutter) | `^3.0.6` | Promoted from transitive to direct; same resolved version |

**Not added, deliberately:** `@aws-sdk/s3-presigned-post` (T2-04; see §13), and any image-processing library (§16).

**SDK finding, verified offline:** the SDK's default "flexible checksums" put `x-amz-checksum-crc32` (calculated on an **empty** body) and `x-amz-sdk-checksum-algorithm` into presigned PUT URLs. `media.js` sets `requestChecksumCalculation`/`responseChecksumValidation` to `WHEN_REQUIRED`.

Without `signableHeaders`, **Content-Type is not signed**. Both points are covered by test T1-02 using the real presigner.

## 6. Firestore schema

All three collections are written only by `functions/media.js`.

**`media/{mediaId}`** (random 20-character ID):

| Group | Fields |
|---|---|
| Identity and location | `provider`, `env`, `bucket`, `objectKey`, `kind` |
| Declared content | `mimeType`, `sizeBytes`, `sha256` |
| Ownership and access | `ownerUid`, `visibility: 'private'` |
| Lifecycle | `status`, `uploadMode`, `quota` (`reserved` \| `used` \| `released`), `createdAt`, `updatedAt`, `expiresAt` |
| Verification | `uploadedAt`, `verifyingSince`, `verifiedAt`, `verifiedSha256`, `width`, `height` |
| Rejection and deletion | `rejectedReason`, `deleteFinalStatus`, `deleteRequestedAt`, `deleteRequestedBy` (audit), `deleteAttempts`, `nextDeleteAt`, `lastDeleteError {errorName, httpStatus}`, `deletedAt` |

**Status values:**
- `pending` → `uploading` → `uploaded` → `verifying` → `verified`;
- any of these → `deleting` → `deleted` | `expired` | `rejected` | `delete_failed`.

**`media_quotas/{uid}`:** `reservedBytes`, `usedBytes`, `pendingCount`, `windowStart`, `windowCount`, `dayStart`, `dayCount`, `updatedAt`.

**`media_system/limits`:** `reservedBytes`, `usedBytes`, `pendingCount`, `minute`, `minuteCount`, `updatedAt`.

**Other:**
- `admin_alerts/media_delete_failed_{id}` is raised after 8 failed deletions.
- **No URL is ever stored.** Test T1-08 scans every document.

**Indexes added** (composite, collection `media`):
- `status` + `expiresAt`;
- `ownerUid` + `status` + `expiresAt`;
- `status` + `verifyingSince`;
- `status` + `nextDeleteAt`.

The emulator doesn't enforce indexes. JSON validity and query/index correspondence were checked by hand; real index builds need a deployment.

## 7. Security rules changes

| Collection | Read | Write |
|---|---|---|
| `media/{id}` | Owner (`ownerUid == auth.uid`) or admin | **None** from any client, including admins |
| `media_quotas/{uid}` | Owner or admin | None |
| `media_system/{doc}` | None | None |

**T1-13 proves:**
- a forged "verified" record is refused;
- the owner can't change status, owner, key, bucket, visibility, checksum, size or quota fields;
- no client can delete a record;
- list queries must be scoped to the caller.

No existing rule was changed: all 162 earlier rules tests still pass.

## 8. Functions implemented

| Callable | Who | Enforces |
|---|---|---|
| `requestMediaUpload` | Signed in, not anonymous, verified email, not suspended | Allowed kinds `test-avatar`/`test-portfolio`/`test-thumb` (no video, no real categories, no identity); JPEG/PNG/WebP; extension matches; size limits; SHA-256 format; configuration allow-list (endpoint, region, bucket, `staging/` prefix); per-user 10 per 10 min and 50 per day; 100 MB per user; 1 GB total; 3 pending per user and 30 overall; **120 upload operations/min overall** (vendor: 600 writes/min per key); clears the caller's own expired uploads first |
| `uploadMediaContent` | Owner | Size bound before decoding; exact size; SHA-256; signature; dimensions (≤ 8000 px a side, ≤ 40 MP; thumbnails ≤ 512 px); completeness (JPEG EOI, PNG IEND, RIFF length). **Nothing is stored unless all pass** |
| `confirmMediaUpload` | Owner | HEAD size/type, then a re-read bounded to the declared size with a 60 s timeout, then SHA-256 and signature again. Invalid → removed with K2 → `rejected` |
| `getMediaUrl` | Owner or admin | `verified` only; 300 s presigned GET; returned once, never stored |
| `deleteMedia` | Owner or admin | Revoke first; DeleteObject (missing = success); HEAD must be 404; failures back off (1 min → 24 h); after 8 attempts `delete_failed` plus an admin alert; idempotent |
| `runMediaSweep` | Admin | Expired and interrupted uploads; deletion retries; reconciliation **reports** untracked objects and never deletes them |

**Scheduled sweep:** none deployed, because Cloud Scheduler isn't available on Spark. The admin callable and the per-request clean-up of the caller's own uploads are the testable substitutes. A scheduled version needs a later Blaze decision.

**Logs:** event, ID, status, reason and error class/HTTP status only. Test T1-11 injects store errors whose text contains a fake secret and proves no log line or error contains it.

## 9. Flutter client integration

**`MediaService`:**
- computes the real SHA-256, then request → upload (proxy callable, or a presigned PUT through `dio` with progress) → confirm;
- reports success **only** when the server returns `verified`;
- on any failure after the request it releases the record, so a retry starts clean;
- maps errors to user-safe messages: offline, timeout, expired, limit, rejected (with reason), not configured, not found;
- caches temporary URLs **in memory** until 30 s before expiry, cleared when the signed-in account changes;
- delete succeeds only on a server-confirmed `deleted`.

**Emulator mode** (`EmulatorConfig`, opt-in, never in release builds) needs both switches:
- the Dart define `HT_EMULATOR=true` switches the app to the demo project and the emulators;
- the build environment `HT_EMULATOR=true` leaves the production `google-services.json` out of the Android build.

If only the Dart define is set, Firebase start-up fails (`duplicate-app`) and the app **refuses to start**, rather than silently using production.

**Test screen:** Settings → "Staging (emulator only)" → Media storage test. The group and the `/staging/media` route exist only in emulator mode; the visual goldens are unchanged, 654/654.

**Not wired into real screens:** existing profile, portfolio and job uploads still use Firebase Storage, as required. No real category is migrated.

## 10. Credentials and Git-ignore verification

**Checked on 6 November 2026:**

| Path | Status |
|---|---|
| `functions/.secret.local` | Ignored (`.gitignore:48`), never in Git history, **not present** |
| `functions/.env.local` | Ignored (`:49`) |
| `tool/.secret-prefix.local` | Ignored (`:51`, added) |
| `.vscode/launch.json` | Excluded (`.git/info/exclude`) |
| Tracked secret/env files | 0 |

The secret scan over all RumptyCloud changes is clean (exit 0). No key-shaped literals were found.

**Secret names:**

| Key | Variables | Note |
|---|---|---|
| K1 | `RUMPTY_ACCESS_KEY_ID`, `RUMPTY_SECRET_ACCESS_KEY` | The approved names |
| K2 | `RUMPTY_CLEANUP_ACCESS_KEY_ID`, `RUMPTY_CLEANUP_SECRET_ACCESS_KEY` | **New.** The plan listed only K1's names, but required a second key |

The code refuses to run without both pairs and never substitutes one key for the other.

**Emulator behaviour found during testing:** when a declared secret is missing from `.secret.local`, the Functions emulator **calls Google Secret Manager** for the emulator project. For `demo-handytrust-media` that returned 403 and nothing was retrieved.

**Consequence:**
- Always run the emulators under a `demo-` project.
- Put all four RumptyCloud variables in `.secret.local`.
- The end-to-end run, which doesn't call media functions, made **0** Secret Manager attempts.

## 11. Offline test results (6 November 2026)

**Common settings:** Node 22.23.4; Firestore emulator on 127.0.0.1:8090; `firebase emulators:start --only firestore --project demo-handytrust`.

| Suite | Command | Exit | Result |
|---|---|---|---|
| T1-01 … T1-12 | `node --test test/media_offline.test.js` | 0 | **36 / 36** |
| T1-13 rules | `node --test media_rules.test.js` | 0 | **6 / 6** |
| Client | `flutter test test/media_service_test.dart` | 0 | **15 / 15** |
| Emulator wiring (Auth + Firestore + Functions + Storage, `demo-handytrust-media`, real callable HTTP) | scratch script | 0 | **7 / 7**: unauthenticated → UNAUTHENTICATED; unverified email → PERMISSION_DENIED; `test-video` and `identity-document` → INVALID_ARGUMENT; valid request without credentials → FAILED_PRECONDITION "Media storage is not configured."; non-admin sweep → PERMISSION_DENIED |
| SDK presigner (offline, dummy keys) | probe + T1-02 | 0 | PUT signs `content-length;content-type;host`; no checksum parameters; path-style; GET signs `host` |
| Gradle configuration | `gradlew :app:tasks --all` (JBR 21) | 0 / 0 | Normal: `processDebugGoogleServices` **present**. `HT_EMULATOR=true`: **absent** |
| Android build, normal | `flutter build apk --debug` | **0** | 163 MB APK; production app ID **present** (unchanged behaviour) |
| Android build, emulator mode | `HT_EMULATOR=true flutter build apk --debug --dart-define=HT_EMULATOR=true` | **0** | 188 MB APK; production app ID and storage-bucket string **absent** |

**Coverage of the offline suites:**

| Topic | Tests |
|---|---|
| Authentication and authorisation | T1-01, T1-05, T1-13 |
| Kind, type and size limits | T1-02 |
| Quotas and rate limits | T1-03 |
| Pending uploads and expiry | T1-04, T1-05 |
| SHA-256 on the real bytes | T1-06 |
| Content validation | T1-07 |
| Temporary URLs, none stored | T1-08 |
| Deletion: revoke-first, retries, `delete_failed`, idempotency, audit | T1-09 |
| Sweeps; reconciliation never deletes | T1-10 |
| Fail-closed configuration and log hygiene | T1-11 |
| Git-ignore and secret scan | T1-12 |

## 12. Live test results

**Not run.** The following stop conditions apply:

1. **Credential permissions are unknown.** The K1 and K2 permission names haven't been confirmed.
2. **There is no credential file:** `functions/.secret.local` doesn't exist.
3. **Balance not confirmed:** prepaid balance ≤ $5, auto top-up off, and balance checked.

Without these the suite **skips itself** and names only the missing conditions. That skip was verified: 0 network calls.

**When run, the suite enforces:**
- at most 30 objects and 25 MB per run;
- synthetic fixtures only;
- a run-unique prefix `staging/livetest/<runId>/`;
- deletion only inside that prefix;
- a final listing that must show **0 objects**, or the run fails and prints the keys;
- a JSON evidence file per run (keys and outcomes, no credentials).

| ID | Objective | Status |
|---|---|---|
| T2-01 | Proxy upload → confirm → verified | Implemented, not run |
| T2-02 | Owner GET works and SHA matches; non-owner refused; anonymous GET and **listing** refused; expired URL refused | Implemented, not run |
| T2-03 | Larger, smaller and chunked bodies vs signed Content-Length refused **by the store**, with no object left | Implemented, not run. Gates the presigned mode |
| T2-04 | POST `content-length-range` | **Not implemented** (§13) |
| T2-05 | Wrong `x-amz-checksum-sha256` rejected or ignored | Implemented, not run (informational) |
| T2-06 | Response-header overrides | Implemented, not run (informational) |
| T2-07 | DeleteObject on a missing key | Implemented, not run (informational) |
| T2-08 | Unsigned `x-amz-acl` on presigned PUT; `PutObjectAcl public-read` with K1; anonymous GET must stay 401/403. Any exposure **fails and stops** | Implemented, not run |
| T2-09 | Wrong Content-Type and expired PUT URL refused, no object | Implemented, not run |
| T2-10 | Run ends with 0 objects under its prefix | Implemented, not run |
| T2-11 (added) | Backend deletion, repeat deletion, object really gone | Implemented, not run |
| T2-12 (added) | Object altered after upload → `checksum_mismatch`, removed, `rejected` | Implemented, not run |

## 13. Skipped and not-implemented items

| Item | Reason |
|---|---|
| All live tests | Stop conditions in §12 |
| T2-04 (POST policy) | Needed only if T2-03 fails. The proxy path already enforces size independently of the vendor. POST support is undocumented and would need another dependency |
| Presigned PUT in normal use | Disabled until T2-03 and T2-08 pass. Needs `RUMPTY_UPLOAD_MODE=presigned` **and** `RUMPTY_PRESIGNED_PUT_VERIFIED=true` |
| Video (`test-video`) | Disabled: size enforcement unproven; plan §3 and roadmap M5 |
| Orphan auto-deletion | Report-only. Emulator data is ephemeral and broad bucket clean-up is forbidden |
| Scheduled sweep | Needs Cloud Scheduler (Blaze) |
| Real-device run | No Android emulator image or device on this machine |

## 14. Object clean-up evidence

No object has been created in the bucket by this work: no credentials exist, and the live suite didn't run. Offline tests use an in-memory store.

## 15. Storage cost and balance observations

None supplied by you yet. No live operation was performed, so expected spend is $0.

## 16. Known limitations

- **Content validation is structural, not a full decode.** It checks the signature, header dimensions and completeness markers.
  - **Not implemented:** image decode/re-encode, EXIF/GPS stripping, malware scanning. These are production prerequisites.
  - The test screen uploads only PNGs drawn on the device, which carry no camera metadata.
  - The app has an existing Stage 7.1 image-privacy path for Firebase uploads; it isn't wired to this staging path.
- **Access rule:** `getMediaUrl` allows **owner or admin** only. Real categories need relationship rules (job, conversation, dispute) and their own reviews.
- **Proxy size:** a 5 MB image travels as about 6.7 MB of base64 in the callable request. That's within Cloud Functions request limits, but more bandwidth than a presigned PUT.
- **Emulator persistence:** emulator Firestore data is lost on restart unless you use `--import/--export-on-exit` (§19). Objects whose records are lost show up only as "untracked" in reconciliation reports.
- **Push in emulator mode:** registration fails harmlessly, since there's no real sender ID, so push can't be tested in this mode.
- **Secret Manager fallback:** the Functions emulator falls back to Secret Manager when secrets are missing (§10).

## 17. Unresolved vendor questions

Q1–Q9 from the Phase 2 plan §13 are all **still open**:

| Q | Question |
|---|---|
| Q1 | Presigned GET |
| Q2 | Content-Length enforcement |
| Q3 | POST policy |
| Q4 | Checksum verification |
| Q5 | Response-header overrides |
| Q6 | DeleteObject on a missing key |
| Q7 | ACL exposure |
| Q8 | What counts as a write against the 600/min limit |
| Q9 | Egress price, encryption at rest, durability and SLA |

Q1, Q2 and Q4–Q7 are answered by the live suite once it may run. Q8 and Q9 need the vendor.

## 18. Production blockers (none addressed by this work)

- **Vendor questions:** Q1–Q9 answered, including encryption at rest, durability and SLA.
- **Data protection:** a versioning or independent backup strategy, since the bucket has no versioning.
- **Image handling:** re-encoding and EXIF/GPS stripping.
- **Attachments:** malware scanning before any document type is allowed.
- **Access control:** relationship-based rules per category.
- **Infrastructure:** production buckets and keys (separate K1/K2 per bucket); Secret Manager; Blaze; a scheduled sweep.
- **Reviews and planning:** category-specific security reviews and migration/rollback plans (roadmap M1–M9).
- **Verification:** real-device testing.
- **Operations:** monitoring and recovery.

The roadmap (`RUMPTYCLOUD_MEDIA_MIGRATION_ROADMAP.md`) remains authoritative.

## 19. Build and test instructions

**Which operations use what:**
- **Local emulators:** sign-in, Firestore records, the six callables.
- **Live staging bucket:** only the object operations (store, read back, sign URLs, delete), done by the emulated Functions with your credentials.

**0. Disk space (blocker found, then cleared).**
- Drive C: had **0 bytes** free during the first builds. Gradle crashed with a native-memory failure, then "There is not enough space on the disk".
- I removed only the 545 debug intermediates (239 MB) my failed build had written. Your release APK in `build/app/outputs` is untouched.
- Space later rose to about 4.4 GB, and both builds then succeeded; about 1.5 GB was free afterwards.
- **Keep at least 5 GB free** for Android builds.
- The last APK built (`build/app/outputs/flutter-apk/app-debug.apk`) is the **emulator-mode** one; your next normal build replaces it.

**1. Credentials (you only; never in chat).**
- In an editor, create `functions/.secret.local` with four lines:
  - `RUMPTY_ACCESS_KEY_ID=…` and `RUMPTY_SECRET_ACCESS_KEY=…` for **K1** (read + write);
  - `RUMPTY_CLEANUP_ACCESS_KEY_ID=…` and `RUMPTY_CLEANUP_SECRET_ACCESS_KEY=…` for **K2** (list + read + delete).
- The file is git-ignored.
- `functions/.env.local` (no secrets) already contains the endpoint, region, bucket and `RUMPTY_UPLOAD_MODE=proxy`.

**2. Start the emulators** (repository root; Node 22 recommended):

```
firebase emulators:start --only auth,firestore,functions,storage --project demo-handytrust-media --export-on-exit "%USERPROFILE%\handytrust-emulator-data"
```

On later runs add `--import "%USERPROFILE%\handytrust-emulator-data"` to keep the media records between sessions.

**Never use `--project handytrust` or `--project staging` with the emulators:** missing secrets would be fetched from that real project's Secret Manager.

**3. Run the app in emulator mode.**

| Device | How |
|---|---|
| VS Code | Run and Debug → **"HandyTrust — local emulators (Android emulator)"**. For a USB phone, the "(USB phone, adb reverse)" configuration |
| Android emulator (CLI) | PowerShell: `$env:HT_EMULATOR='true'; flutter run --dart-define=HT_EMULATOR=true` |
| USB phone | First `adb reverse tcp:9099 tcp:9099`, then the same for 8090, 5001 and 9199. Then `$env:HT_EMULATOR='true'; flutter run --dart-define=HT_EMULATOR=true --dart-define=HT_EMULATOR_HOST=127.0.0.1` |

If the app stops at start-up with "Emulator mode needs an Android build made with HT_EMULATOR=true…", the build still contained the production config. Run it again with the environment variable set. This is the intended safety check.

**4. Synthetic account.**
- Register in the app; this account exists only in the Auth emulator.
- The email-verification link is printed in the emulators' terminal. Open it in a browser, then return to the app.

**5. Upload.**
- Settings → "Staging (emulator only)" → **Media storage test**.
- Choose a kind → **Generate image** → **Upload**.
- The states show Requesting → Uploading → Server is verifying → "Verified by the server: <id>".

**6. Check the Firestore record:**

```
curl -H "Authorization: Bearer owner" "http://127.0.0.1:8090/v1/projects/demo-handytrust-media/databases/(default)/documents/media"
```

It should show `status: verified`, `verifiedSha256` equal to `sha256`, and no URL.

**7. View.** Tap **View**. A temporary URL (300 s) is requested and shown; it's held in memory only.

**8. Delete.** Tap **Delete** → "Deleted from the bucket". The server confirmed HEAD → 404 before reporting it.

**9. Check the object is gone.**
- Take the `objectKey` from step 6.
- Check it in the RumptyCloud dashboard, or with your own S3 tool using **K2**, for example `aws s3api head-object --endpoint-url https://s3.rumptycloud.com --bucket assets-handytrust-01a0f99e-5d6ffa --key <objectKey>`. Expect 404.

**Live tests (I run these after your confirmations):**

```
RUMPTY_LIVE=1 RUMPTY_LIVE_OWNER_CONFIRMED=balance-checked-auto-topup-off firebase emulators:exec --only firestore --project demo-handytrust-media "cd functions && node --test test/media_live.test.js"
```

## 20. Git status and HEAD

**HEAD:** `7ff140c`, unchanged.

**Pre-existing staged changes (A6):** 5,752 deletions under `functions/node_modules`. Byte-identical to the baseline manifest; nothing new is staged.

**Pre-existing unstaged changes (A1):**
- 23 tracked files, including `.claude/` and `android/build/` noise;
- 3 untracked tests;
- all unchanged, **except** the four shared files, whose A1 lines are all intact (§4).

**New RumptyCloud changes:**

| Kind | Files |
|---|---|
| Tracked, modified | 14 (§4); patch in `design/patches/RUMPTYCLOUD_STAGING_TRACKED_FILES.patch` |
| Untracked, new | 16 (§3), plus this report and the patch |
| Local-only | `functions/.env.local` (ignored), `.vscode/launch.json` (excluded) |

**Generated or temporary files:**
- All temporary probes, harness logs and snapshots are in the session scratchpad, outside the repository.
- Removed: `android/.kotlin/`, which every Gradle build recreates (consider ignoring it), and the 545 debug intermediates from the failed build.
- Left alone: three pre-existing JVM crash logs from June/July 2026 in `android/`.

## 21. Confirmation

- **No:** commit, stage, push, deployment, billing upgrade, production Firebase change, Paystack access, bucket or key creation, real media migration.
- **No secret was seen, stored or printed.**
- **Remaining work needs your approval:** the live staging tests (§12).
