# HandyTrust V2 — Firebase/FlutterFire WebKit Compatibility Upgrade

**Date:** 2026-08-21
**Scope:** Focused dependency-compatibility upgrade only, per `design/V2_IOS_SAFARI_RELIABILITY_REPORT.md` §16's recommendation. No unrelated refactoring, redesign, or feature work performed.

---

## Before / After Baseline

**Established before any change was made**, per this task's instruction:

| Package | Before | After |
|---|---|---|
| `firebase_core` | 3.15.2 | 4.13.0 |
| `firebase_core_web` (transitive) | 2.24.1 | **3.10.0** |
| `firebase_core_platform_interface` | 6.0.3 | 8.1.0 |
| `firebase_auth` | 5.7.0 | 6.5.7 |
| `firebase_auth_web` | 5.15.3 | 6.2.6 |
| `firebase_auth_platform_interface` | 7.7.3 | 9.0.6 |
| `cloud_firestore` | 5.6.12 | 6.8.0 |
| `cloud_firestore_web` | 4.4.12 | 5.7.2 |
| `cloud_firestore_platform_interface` | 6.6.12 | 8.0.6 |
| `firebase_storage` | 12.4.10 | 13.4.6 |
| `firebase_storage_web` | 3.10.17 | 3.11.12 |
| `firebase_storage_platform_interface` | 5.2.10 | 6.0.6 |
| `firebase_messaging` | 15.2.10 | 16.5.0 |
| `firebase_messaging_web` | 3.10.10 | 4.2.4 |
| `firebase_messaging_platform_interface` | 4.6.10 | 4.9.3 |
| `cloud_functions` (client-side Dart callable, **not** the Node.js Cloud Functions runtime in `functions/`, which is entirely unaffected by this change) | 5.6.2 | 6.3.6 |
| `cloud_functions_web` | 4.11.5 | 5.1.12 |
| `cloud_functions_platform_interface` | 5.8.2 | 6.0.6 |
| `_flutterfire_internals` | 1.3.59 | 1.3.76 |

Confirmed test baseline before touching anything:
- `flutter test`: 99/99 passing
- Cloud Functions tests: 37/37 passing
- Firestore Rules emulator suite: 26/26 passing
- Fresh `flutter build web --release` produced, served, and **the exact WebKit failure re-reproduced live in this session** (see §1) before any dependency was touched — the original failure was not assumed from the prior report, it was re-confirmed fresh.

---

## 1. Root Cause

**Confirmed cause:** `firebase_core_web` versions prior to **3.10.0** contain a WebKit-specific module-loading race — per that package's own changelog, version 3.10.0 explicitly "load[s] firebase-app.js before component bundles to avoid WebKit import race." Under Chromium's script-loading/scheduling behavior this race does not manifest; under WebKit it does, and one of the dependent component bundles (Auth, Firestore, Functions, Messaging, or Storage — all initialize as "components" registered against the core Firebase app instance) ends up executing JS-interop code that expects the core app object to already be fully registered, hits a value that is still null/undefined at that point, and Dart's compiled interop layer throws `Null check operator used on a null value`.

**Is this app's own code responsible?** No — re-confirmed in the prior investigation (exhaustive search of `lib/` for `dart:html`/`dart:js`/`dart:js_util`/`IndexedDB`/`localStorage`/`setPersistence`: zero matches) and not contradicted by anything found in this task. The failure was entirely inside third-party plugin interop code this repository does not own or control.

**Did the dependency upgrade resolve it?** **Yes — confirmed, reproduced, not assumed.** The identical WebKit reproduction steps that failed before the upgrade (same build method, same server, same viewport, same test script) now succeed: `Firebase.initializeApp()` completes, Firebase Auth resolves, the app reaches the real login screen, and two real Auth/Firestore-touching interactions (wrong-password login, duplicate-email signup) both complete correctly with clean, expected error messages and zero page errors. Full before/after evidence is in §3.

---

## 2. Changes Made

**Dependency changes (`pubspec.yaml`):** all six Firebase-family packages bumped together, as a single interconnected group (not individually), to the versions in the baseline table above. `flutter pub get` resolved this set with **zero conflicts** — confirming these six packages' new major versions are mutually compatible as a group, not just individually installable.

**Source changes required: none.** `flutter analyze` after the upgrade produced the **exact same 16 pre-existing baseline issues** (1 warning, 15 info-level, all predating this task) and **zero new issues** — meaning this app's actual usage of the Firebase APIs happened to already be forward-compatible with the new major versions' public surface. No breaking API change was hit, so no source-level migration was necessary.

**Configuration changes required: none.** `firebase_options.dart` (the generated Firebase config) did not need regeneration — the underlying project config (API keys, app IDs, project ID) is unrelated to the SDK version and was untouched. No change to `firestore.rules`, `storage.rules`, or any Cloud Functions source was needed or made — the task's own instruction not to alter security rules unless the upgrade explicitly required it was followed; it did not.

**What was explicitly NOT done:** no workaround, browser-sniffing hack, or delayed-initialization patch was added to paper over the failure — the actual fix is the dependency upgrade itself, confirmed by direct before/after reproduction, not inferred from a changelog alone.

---

## 3. Verification

| Area | Result | Evidence |
|---|---|---|
| Firebase initialization | **PASS** | Before: `[HandyTrustApp] Firebase initialization failed: Null check operator used on a null value` (WebKit only). After: `[firebase_initializer] Firebase.initializeApp completed` logged successfully on both engines, zero init failures. |
| Chromium | **PASS** (unaffected throughout) | Cold launch + refresh both reach the real login screen in both before/after runs, 0 page errors, 0 console errors. |
| WebKit | **PASS (fixed)** | Before: never reaches the app, shows the recovery screen after the auth-resolution timeout. After: reaches the real login screen (`"Welcome Back"`/`"Login to Account"`) on both cold launch and refresh, 0 page errors, 0 console errors — identical outcome to Chromium. |
| Auth | **PASS** | Live WebKit test: wrong-password login against the real production Firebase Auth project returns the correct, clean `"Email or password is incorrect."` message — confirms the Auth SDK's request/response cycle works end-to-end post-upgrade, not just app boot. |
| Session restoration | **PASS** | `[init_provider] waiting for initial auth-state resolution` → `[init_provider] initial auth-state resolution completed` logged in sequence, quickly, on WebKit post-upgrade — the 20-second bounded gate from the prior task is intact and unmodified, and now resolves via genuine success rather than via its own timeout/recovery path. |
| Firestore | **PASS** | Live WebKit test: duplicate-email signup (`createAccount`, which reads/writes the `users` collection) returns the correct `"An account with this email already exists."` message — a real Firestore read/write round-trip against production, working correctly post-upgrade. Firestore Rules emulator suite also re-run clean (see below). |
| Storage | **CODE-LEVEL ONLY** | `firebase_storage` upgraded within the same compatible group and compiles/analyzes clean; no live Storage upload was exercised (would require an authenticated session, still blocked by the pre-existing, unrelated account-verification gap — see Remaining Risks). |
| Cloud Functions | **CODE-LEVEL ONLY (client) / re-confirmed unaffected (server)** | The client-side `cloud_functions` Dart package upgraded cleanly (analyze: 0 new issues). The Node.js Cloud Functions themselves (`functions/`) are a completely separate package tree, untouched by this Flutter-side upgrade — re-confirmed by re-running their test suite (below), unaffected. Live end-to-end calling of a deployed function remains blocked by the pre-existing, unrelated Spark-plan/zero-deployed-functions gap. |
| Review aggregation (`onReviewCreated`) | **PASS (unaffected, re-confirmed)** | `functions/test/review_rating_pipeline.test.js` (8 cases, including the fabricated-review-rejection and idempotency-marker-relevant validation logic) re-run after this upgrade: all 8 still pass, part of 37/37 overall. Untouched by this task, confirmed still intact. |
| iOS location | **PASS (unaffected, re-confirmed)** | `ios/Runner/Info.plist`'s `NSLocationWhenInUseUsageDescription` re-read directly after the upgrade: present, unchanged. This upgrade touches no iOS native project files. |
| Flutter tests | **PASS — 99/99** | Re-run in full after the upgrade; identical pass count to the pre-upgrade baseline. |
| Functions tests | **PASS — 37/37** | Re-run in full (against the Firestore emulator where needed) after the upgrade; identical pass count. |
| Rules tests | **PASS — 26/26** | Re-run in full after the upgrade; identical pass count, confirming no security-rule regression from this purely client-dependency change. |
| V2 regression tests | **PASS — all 13** | The 5 `test/init_provider_test.dart` cases and 8 `functions/test/review_rating_pipeline.test.js` cases from the prior task are both counted within the 99 and 37 totals above respectively — explicitly re-verified, not merely assumed included. |
| Real iPhone Safari | **NOT PERFORMED** | No physical iPhone is available in this environment. See Remaining Risks — this is the one verification this report cannot provide, stated plainly rather than implied. |

---

## 4. Remaining Risks

- **No physical iPhone / real Mobile Safari confirmation exists.** Playwright's WebKit engine is the same underlying browser-engine family Safari uses and is a strong, direct signal — this task's fix was verified by reproducing the *exact* reported failure mode and confirming it is now absent under that same engine — but WebKit-on-Windows-via-Playwright is not byte-identical to Apple's actual iOS Safari build (different OS integration, memory/sandbox constraints, and iOS-specific WebKit patches could theoretically still differ). This is the single most important remaining gap between "very strong evidence" and "proven on the actual target device," and it cannot be closed without a physical iPhone.
- **Storage and native Cloud Functions calling were not live-exercised**, for reasons unrelated to this upgrade (the pre-existing account-verification and Spark-plan/zero-deployed-functions gaps, both unchanged and out of this task's scope) — both are CODE-LEVEL ONLY per the table above, not CONFIRMED LIVE.
- **The `LocalNotificationService.init` WebKit-specific `TypeError`** noted in the prior report's investigation (`type 'minified:Op' is not a subtype of type 'minified:r'`) was not specifically re-tested in isolation this task — it is caught/non-fatal either way (the app's own `main.dart` already wraps it in a try/catch), and was out of this task's stated scope (Firebase initialization specifically), but is flagged here for completeness rather than silently dropped. A follow-up check of whether the same dependency group upgrade also resolved this specific secondary error would be a cheap, valuable next step.
- **82 other, non-Firebase packages in this project are also behind their latest available versions** (per `flutter pub outdated`'s output during this task) — none of these were touched, per the explicit instruction to prefer the smallest compatible upgrade set and not upgrade the tree merely because newer versions exist.

---

## 5. Recommendation

**HandyTrust is now ready to proceed to the next production-readiness stage for the specific issue this task targeted** — the confirmed WebKit Firebase-initialization failure is fixed, verified via direct before/after reproduction (not assumed from a changelog), with zero regressions across all 162 combined automated test cases (99 + 37 + 26) and zero new `flutter analyze` issues.

**This is not a signal that HandyTrust overall is production-ready** — every other gap already documented in `design/HANDYTRUST_V1_V2_MASTER_GAP_ANALYSIS.md` and `design/V2_IOS_SAFARI_RELIABILITY_REPORT.md` remains exactly as previously described (undeployed Cloud Functions, unverified test accounts, the refund/cancellation gap, web-push infrastructure gaps, etc.) — none of those were in this task's scope and none were touched.

**One more focused remediation is still recommended before this specific area is fully closed out:** a real Mobile Safari test on a physical iPhone, to convert this task's strong WebKit-engine evidence into device-confirmed proof. Everything that could be verified without a physical device has been verified, cleanly, with evidence — this report does not overstate that as more than it is.
