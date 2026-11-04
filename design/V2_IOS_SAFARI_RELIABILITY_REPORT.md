# HandyTrust V2 — iOS Safari / Web Reliability Investigation & Fixes

**Date:** 2026-08-21
**Scope:** Confirmed iOS location P0, focused investigation of iPhone Safari loading reliability, review→rating pipeline fix.
**Primary technical context used:** `design/HANDYTRUST_V1_V2_MASTER_GAP_ANALYSIS.md` (verified, not blindly trusted — every relevant claim re-checked against current source before acting on it).

---

## 1. Executive Summary

**The user's reported problem is real, reproducible, and now has a concrete, evidenced root cause — not a guess.** Using Playwright's WebKit engine (the actual browser engine Safari uses, installed and run in this session as the closest available substitute for a physical iPhone — see §11's honest caveat on what this does and doesn't prove), HandyTrust's web build was confirmed to **fail to initialize Firebase at all** under WebKit, while the identical build works correctly under Chromium. The exact, reproduced error is:

```
Null check operator used on a null value
```

thrown from inside `Firebase.initializeApp()` itself (the failure happens before this app's own `firebase_initializer.dart` even logs "Firebase.initializeApp completed" — i.e., before any of this app's own code runs at all). A second, related WebKit-only failure was also captured in the same run: `LocalNotificationService.init` throws a `TypeError` (`type 'minified:Op' is not a subtype of type 'minified:r'`) — caught and logged, non-fatal, but a second confirmed WebKit-specific divergence in the same startup path.

**This is not application code.** An exhaustive search of this repository's own `lib/` code found zero `dart:html`/`dart:js`/`dart:js_util` usage, zero explicit Firebase persistence configuration, and zero unsafe null-assertion (`!`) operators anywhere in the startup/auth/router chain. The failure originates inside the third-party `firebase_core_web`/`firebase_auth_web`/`firebase_messaging_web` plugin packages' own JS-interop code, which this repository does not control. Firebase's Flutter web plugins are currently pinned to `firebase_core: ^3.15.2` / `firebase_auth: ^5.7.0` / etc. — a full major version behind what's available on pub.dev (`firebase_core: 4.13.0`, `firebase_auth: 6.5.7`, and five other packages similarly a major version behind). This class of "Null check operator" WebKit/JS-interop failure is a known, previously-documented category of bug across FlutterFire's transition to `dart:js_interop`; the major-version line is the most likely place this is already fixed.

**I did not perform this dependency upgrade.** A simultaneous major-version bump across six interlinked Firebase packages is real, app-wide, breaking-change-risk surgery — touching every screen that reads a `User`, a `DocumentSnapshot`, or calls a Cloud Function. Per this task's own instruction to document a deeper architectural issue before a large rewrite, and not to rewrite working architecture unnecessarily, this is flagged here as **the clear, specific, next V2 task** (§16), not something to attempt inside an already-large multi-part session. What I *did* do: fixed the two confirmed, scoped, low-risk-blast-radius items (iOS location permission, review→rating pipeline), and — independent of whether the Firebase-plugin root cause gets fixed next — closed the **architectural gap that turned this failure into an infinite spinner with no recovery path**, so that this exact failure (and any other future startup failure, for any reason) now shows a clean, actionable recovery screen instead.

**Direct answers to the final success-criteria questions are in §17.**

---

## 2. Safari Loading Issue — Root Cause

**Confirmed root cause (reproduced live, this session, not inferred):** `Firebase.initializeApp()` throws `Null check operator used on a null value` under the WebKit browser engine, and does not throw under Chromium, for the identical release web build served the identical way. This was reproduced twice independently in the same run (once from `main()`'s pre-`runApp()` call, once from `firebaseInitializationProvider`'s call inside the widget tree — both call the same `initializeFirebase()` function, both fail identically), confirming this is deterministic, not a flaky race.

**Evidence trail, in order:**
1. `flutter build web --release` succeeds cleanly (0 analyzer issues beyond the pre-existing baseline) — confirming this is not a compile-time or type error, only a WebKit-runtime one.
2. Live test against the release build, served locally (`serve -s`, mirroring Firebase Hosting's SPA rewrite behavior — the same method used for all live testing across this engagement):
   - **Chromium, 390×844 (iPhone-sized) viewport:** cold launch reaches the real login screen in ~7.8s, refresh works identically, zero page errors, zero console errors.
   - **WebKit, identical viewport, identical build, identical server:** cold launch never reaches the login screen. Instead, my new `StartupErrorScreen` (§5) renders — proving the fix's own failure-handling works, but also proving the underlying Firebase initialization genuinely fails on this engine.
3. Full console capture on WebKit shows the exact failure sequence (see §1) — the error is thrown from inside `Firebase.initializeApp()` itself, confirmed by the absence of this app's own `debugPrint('[firebase_initializer] Firebase.initializeApp completed')` log line anywhere in the captured output.
4. This repository's own code was searched exhaustively (`dart:html`, `dart:js`, `dart:js_util`, `dart:js_interop`, `IndexedDB`, `localStorage`, `sessionStorage`, `document.cookie`, `setPersistence`) — **zero matches anywhere in `lib/`.** The failure is not reachable from, or explainable by, any code this repository controls.
5. `flutter pub outdated` shows `firebase_core`/`firebase_auth`/`cloud_firestore`/`firebase_storage`/`firebase_messaging`/`cloud_functions` are all pinned a full major version behind pub.dev's latest (3.15.2→4.13.0, 5.7.0→6.5.7, 5.6.12→6.8.0, 12.4.10→13.4.6, 15.2.10→16.5.0, 5.6.2→6.3.6 respectively — all interlinked, must move together).
6. This app's own `firebase_options.dart` web config was checked for a plausible narrower cause (e.g. a missing optional field known to trip specific init code paths in older `firebase_core_web` releases) — the config is complete and standard for an app not using Analytics; no local misconfiguration was found. This further points at the plugin version itself, not this app's usage of it.

**What this is NOT:** not a code bug in this repository, not something fixable by editing our own Dart source, not a symptom of anything flagged elsewhere in this document (auth persistence, router redirects, IndexedDB config) — those are all confirmed clean (§4, §6). It is squarely a third-party plugin/WebKit-engine interop incompatibility, most plausibly resolved by the major-version upgrade line, per FlutterFire's own history of WebKit-compatibility fixes during its `dart:js_interop` migration.

**Honest limit of this evidence (§11 expands on this):** Playwright's `webkit` channel is desktop/generic WebKit, closely related to but not byte-identical to Apple's actual iOS Safari build. This is strong, reproducible, engine-level evidence and the most direct explanation available for the user's reported experience — but it is not a substitute for confirmation on a real iPhone.

---

## 3. iOS Location Issue

**Confirmed and fixed.** `ios/Runner/Info.plist` was missing `NSLocationWhenInUseUsageDescription` entirely, while `lib/screens/home/service_request_screen.dart` actively calls `Geolocator.checkPermission()`/`requestPermission()`/`getCurrentPosition()` from the Post Job flow. Per Apple's platform requirement, calling a location API without the matching usage-description key terminates the app the first time that code path runs on a real device — this was previously undetected because no live iOS testing had occurred anywhere in this engagement.

**Fix applied:**
- Added `NSLocationWhenInUseUsageDescription` to `ios/Runner/Info.plist`, with a clear, honest description of why the permission is requested.
- No other permission was added — camera and photo-library descriptions were already present and correct; no additional location-tier permission (e.g. `Always`) is requested anywhere, matching the app's actual one-shot, foreground-only usage.
- **Only one screen in the entire app calls the location API** (`service_request_screen.dart` — confirmed by exhaustive `Geolocator.` grep across `lib/`), so this fix has no other call sites to verify.

**Verified failure-mode handling, improved this session (`_fetchLocation`):**
| Condition | Before | After |
|---|---|---|
| Location Services off system-wide | Fell through to `getCurrentPosition()`, which would throw `LocationServiceDisabledException`, caught by the broad `catch (_)` → generic "Could not get location" message | Now checked explicitly first (`Geolocator.isLocationServiceEnabled()`), with a specific, actionable message pointing at Settings |
| Permission denied (one-time) | Clean message, correct | Unchanged — still correct |
| Permission permanently denied | Was lumped into the same generic "denied" message as a one-time denial | Now has its own message, explicitly telling the user to enable it in Settings (since re-requesting is a no-op once permanently denied) |
| Any other failure (geocoding, platform channel error, a services-disabled race between the two checks) | Broad `catch(_)` → generic fallback message | Unchanged — still correctly catches everything, never crashes |

**Behavior when granted:** unchanged, already correct — captures position, reverse-geocodes, pre-fills the address field.
**Behavior when denied/permanently denied/services disabled:** in every case, the app degrades to manual address entry with a clear, specific message — confirmed by reading the full function, not merely asserted. No crash path exists in this flow on any platform.

---

## 4. Firebase Auth Findings

- **No explicit persistence configuration exists anywhere** (`setPersistence`/`Persistence.*` — zero matches). The app relies entirely on the Firebase Auth JS SDK's own default (`indexedDBLocalPersistence` in modern SDK versions) via the `firebase_auth_web` plugin — this app has no control over, and does not override, that default.
- **`authStateChangesProvider` uses `userChanges()`, not `authStateChanges()`**, by deliberate, documented choice (`auth_service.dart`'s own comment: `authStateChanges()` doesn't reflect profile-relevant changes the way `userChanges()` does). This is unrelated to the WebKit failure (the failure occurs before either stream is even reached) and is not touched by this pass.
- **CONFIRMED, previously undocumented architectural gap, now fixed:** `authStateChangesProvider`'s first emission had **no timeout anywhere**. If Firebase Auth's persisted-session restoration never resolves (for any reason — a blocked/slow IndexedDB, a stalled network token-refresh, or literally anything else), the provider stays `AsyncLoading` forever, the router's `redirect` callback's `if (authAsync.isLoading) return null;` never lets the user leave `/`, and `SplashScreen` spun forever with **zero failure state and zero retry option.** This is the second, independent "infinite spinner" risk in this app (distinct from and in addition to the Firebase-init failure in §2) — it protects against a *different* class of hang (auth-state resolution specifically, which succeeds once Firebase itself initializes, but could still independently stall). Fixed in §5.
- **No unsafe `!` operators exist anywhere in the startup/auth/router chain** — confirmed by direct grep of `auth_provider.dart`, `router.dart`, `main.dart`, `init_provider.dart`, `splash_screen.dart`, `auth_service.dart`. The only three `!` operators found anywhere in `auth_service.dart` (`credential.user!` ×3, inside `createAccount()`, immediately after a successful `createUserWithEmailAndPassword()` call) are pre-existing, already classified (P3, original QA audit) as low-risk since Firebase guarantees a non-null user on that specific success path — **not part of the startup chain** (this only runs during an active signup action, not app boot), reconfirmed but deliberately not touched, matching Part 7's explicit instruction not to "fix" something already correct.
- **Part 7's specific question — does anything dereference null during Auth → profile → router redirect:** No. `auth_service.dart`'s `userProfileStream`/`fetchUserProfile` both correctly gate on `snap.exists` before ever touching `snap.data()`, and additionally re-check `data == null` even after that (defense-in-depth beyond what's required) before constructing a `UserModel`. `currentUserProfileProvider` explicitly emits `Stream.value(null)` for the signed-out case specifically so it can never get stuck in `AsyncLoading` forever (a deliberate, already-correct fix, per its own code comment). `router.dart`'s redirect callback uses `.asData?.value` throughout, never a bare `!`. **This entire chain was already correct — confirmed, not re-"fixed."**

---

## 5. The Fix — Deterministic Startup State Machine

Implemented exactly the state machine requested: `Initializing → (Authenticated OR Unauthenticated) OR Recoverable initialization error`, never an unbounded spinner.

- **New: `lib/widgets/startup_error_screen.dart`** — a shared recovery screen ("Something went wrong while starting HandyTrust." / "Check your internet connection and try again." / **Retry** button). Never renders a raw error object or stack trace.
- **New: `waitForInitialAuthState()` in `lib/providers/init_provider.dart`** — a pure, unit-tested function that races the auth-state stream's first emission against a 20-second timeout. **Deliberately not a blanket `Stream.timeout()`** on the long-lived stream (that would incorrectly fire on any later >20s gap between genuine, infrequent auth events — normal, not a bug) — it subscribes once via `.first`, independently of the app's long-lived `authStateChangesProvider` subscription (Firebase's `authStateChanges()`/`userChanges()` is a broadcast stream, so a second listener is safe and doesn't consume or disrupt events for the first — verified by a dedicated regression test, §7). 20 seconds is deliberately generous, chosen specifically so a normal, working-but-slow network never trips it, per the explicit instruction against an arbitrarily tiny timeout that would hide real backend problems.
- **New: `authResolutionProvider`** wraps the above as a second app-level startup gate in `main.dart`, watched immediately after `firebaseInitializationProvider` succeeds.
- **`main.dart`'s `HandyTrustApp`/new `_AuthResolutionGate`:** both of the app's two startup gates (Firebase init, then auth-state resolution) now render `StartupErrorScreen` on failure, each with its own `Retry` (via `ref.invalidate(...)` on the specific failed provider) — not the previous raw-`Text('Failed to initialize the app. $error')` with no recovery action at all.
- **`SplashScreen`'s error branch** (reached only in the rare case of a *later* auth-stream error, after a successful initial resolution — the router's redirect logic means this is very unlikely to be hit in normal operation) was also fixed to use the same shared recovery screen, for consistency and to close the last remaining raw-error-text path in this specific chain.

**This fix does not, on its own, resolve the WebKit/Firebase-init failure in §2** — that requires the plugin-version work flagged in §16. What it does is guarantee that failure (and any other future one) degrades to a clean, actionable screen instead of a blank/spinning dead end — **directly and immediately verified working**, live, on the actual WebKit engine, in this session (§2's evidence: the recovery screen is exactly what rendered).

---

## 6. Firestore Findings

No Firestore-specific startup risk was found. `currentUserProfileProvider`'s signed-out path resolves instantly and does not depend on Firestore at all; the signed-in path subscribes to a live snapshot listener whose resolution timing does not block the router (the redirect logic reads it via `.asData?.value`, defaulting to `null`/loading-tolerant everywhere it's consulted — confirmed by re-reading the redirect callback in full, no blocking `await` or unguarded access exists). No offline-persistence configuration override exists in this app's own code (relies on `cloud_firestore_web`'s defaults, same reasoning as Auth's persistence in §4). No uncaught Firestore query/listener exception was found anywhere in the startup path.

---

## 7. Router Findings

Full redirect callback re-read this session (`lib/routes/router.dart`). Confirmed:
- The `if (authAsync.isLoading) return null;` guard is the ONE place a stuck upstream provider could previously deadlock the whole app — now bounded by §5's fix, since the router never even mounts until `authResolutionProvider` has resolved one way or the other.
- Suspended-account check, admin-route guard, and dual-role interstitial all correctly treat their respective providers' still-loading state as "let navigation through" rather than blocking — none of these can deadlock the router even independent of §5's fix (confirmed via direct code reading, not assumed).
- No scenario was found where the router waits forever for a provider **other than** the one now fixed in §5.

---

## 8. Web Bootstrap Findings

- `web/index.html` is a stock, unmodified Flutter Web bootstrap (`flutter_bootstrap.js`, standard iOS meta tags already present — `apple-mobile-web-app-capable`, `apple-mobile-web-app-status-bar-style`, `apple-touch-icon`). Nothing unusual found here.
- **No service worker file of any kind exists in `web/`** (`grep`/`find` for `*service*worker*`/`sw.js` returned nothing) — this is directly relevant to §9 (web push cannot function without one, regardless of any other fix).
- `web/manifest.json` still carries generic Flutter-template placeholder content (`"name": "handy_trust"`, `"description": "A new Flutter project."`, default Flutter-blue `theme_color`) rather than HandyTrust branding — a real but purely cosmetic gap, unrelated to reliability, not fixed in this pass (out of this task's scope, noted for completeness).
- **`flutter build web --release`'s own WASM-compatibility dry-run output flags `flutter_secure_storage_web` as using `dart:html`/`dart:js_util`/`package:js` internally** — this is a THIRD-PARTY dependency (not this app's own code), but it is a concrete, confirmed example of exactly the kind of low-level browser-API surface Part 4 asked to identify, and it's used for this app's one stored value (`auth_access_token`, `secure_token_manager.dart`) on every platform including web. Not proven to be the cause of the §2 failure (the failure occurs before any auth/token code runs at all), but flagged as a second, independent piece of transitive browser-API surface worth being aware of.

---

## 9. Notification Findings — In-app vs. Push, Clearly Separated

Per the explicit instruction not to conflate these, stated as four distinct, separately-verified layers:

1. **In-app notification (Firestore document under `notifications/{id}`):** works correctly, confirmed in an earlier phase of this engagement — every notification source in the app now reliably writes to this collection (§10 of the gap analysis).
2. **Firestore notification document → actual push send (`onNotificationCreated` Cloud Function):** code exists and is correct, but **is one of the 15 Cloud Functions confirmed, live, this session and repeatedly across this engagement, to be undeployed** (Spark plan, zero functions on the linked project). This is INFRASTRUCTURE BLOCKED, not a code defect, and — per the explicit instruction — **not silently deployed or billing-upgraded in this pass**, only reported.
3. **Web push specifically (Flutter Web target):** **confirmed additionally, independently blocked, even setting aside the Cloud Functions gap** — no `firebase-messaging-sw.js` service worker exists anywhere in `web/` (required by the Firebase JS SDK for web push delivery), and no VAPID key is configured anywhere in this app's Dart code (`grep` for `vapidKey`/`VAPID` returns nothing) — required for `FirebaseMessaging.instance.getToken()` to even request a web push subscription. **Web push cannot function today for any reason, deployment or not.**
4. **iOS Safari Web Push specifically — a hard platform limitation, not a bug:** confirmed via current (2026) documentation research — Web Push on iOS requires iOS 16.4+ **and** the site must be installed to the Home Screen as a standalone PWA; a page open in an ordinary Safari tab cannot receive push notifications on iOS at all, regardless of version. Even for an installed PWA, EU users on iOS 17.4+ do not receive push at all (a regional/regulatory restriction, not something any app can work around). Sources: [PWA iOS Limitations and Safari Support](https://www.magicbell.com/blog/pwa-ios-limitations-safari-support-complete-guide), [Web Push Support for Mobile Safari](https://academy.insiderone.com/docs/web-push-support-for-mobile-safari).
5. **Native iOS push (a real installed iOS app, not the Web build):** unrelated to any of the above — governed by APNs configuration inside the iOS project, which was not part of this investigation's location/Safari-web scope and was not audited in this pass.

**Bottom line:** even once Cloud Functions are deployed, web push will remain non-functional until a service worker + VAPID key are added — and even then, iOS Safari users will only ever receive it if they've installed the app to their Home Screen, a real, unavoidable platform ceiling worth setting expectations around now rather than after deployment.

---

## 10. Review / Trust-Score Pipeline — Fixed and Tested

Verified against current code first, exactly as instructed — the gap analysis's claim held up under re-verification: `review_screen.dart`'s only attempt to update an artisan's `rating`/`totalRatings` was a **direct client-side transaction**, run as the reviewing customer, who can never be the artisan document's own owner — `firestore.rules`' `isOwner(uid) || isAdmin()` gate on `artisans/{uid}` update rejected this on every single attempt, silently (caught, logged as a comment claiming a Cloud Function handled it in production — no such function existed).

**Fix implemented — a new Cloud Function, not a client-side workaround (aggregation must not live on an untrusted client, per the explicit instruction):**
- **`exports.onReviewCreated`** (`functions/index.js`), Firestore-triggered on `reviews/{reviewId}` creation (review documents use `jobId` as their own doc ID by existing convention, giving this function a cheap, direct job lookup).
- **`exports._computeReviewApplication`** — a pure, exported validation function (unit-tested in isolation, 8 cases, `functions/test/review_rating_pipeline.test.js`) that independently re-verifies, server-side, under the Admin SDK: the rating is a real number in 1-5; the review has an `artisanId`; the referenced job exists; **the review's `artisanId` and `customerId` actually match the job's real parties** (this is the server-side defense-in-depth that closes the fabricated-review vector documented in the gap analysis §16.3 — `firestore.rules`' reviews create rule does not itself check this, so a customer could otherwise attribute a review to an uninvolved artisan; this function now refuses to let such a review affect any real rating, even though the document itself can still be created per the existing rule); and the job is actually `completed`.
- **Idempotent by construction** — a `artisans/{artisanId}/appliedReviews/{reviewId}` marker, checked and written in the same Firestore transaction as the rating update, using the exact same fixed-ID transactional-guard pattern already proven correct elsewhere in this codebase (`escrow_releases`, `payment_init_locks`). A redelivered trigger (Cloud Functions are at-least-once) cannot double-count a review into the average.
- **Server-authoritative, matching the V2 design exactly** — this new function only ever updates `rating`/`totalRatings`; it does not touch `trustScore` directly. The existing, unmodified `onArtisanRatingChanged` trigger (already correct, already tested, not touched in this pass) picks up the resulting change and recomputes `trustScore` exactly as it already does for every other rating-affecting event — completing the pipeline the original code assumed existed, using components already proven correct rather than duplicating logic.
- **Client cleanup:** the doomed client-side `_updateArtisanRating` transaction was removed from `review_screen.dart` (not weakened, not left as a "try anyway" — it could never succeed and was pure dead weight once the real fix landed). The review-document creation itself and the artisan notification send are both unchanged, both already correct.
- **Duplicate-submission protection:** unchanged, already correct — the review document's ID is deterministically `jobId`, so a second submission attempt hits `allow update: if false` rather than a second `create`, and is rejected — confirmed still true, not modified.
- **Server-side rating validation:** unchanged, already correct at the rules layer (`rating is int`, `1 <= rating <= 5` on the `reviews` create rule) — the new function adds a second, redundant type check as defense-in-depth, consistent with this codebase's established pattern of not relying solely on one layer.

**Tests added:** `functions/test/review_rating_pipeline.test.js` (8 cases, pure, no emulator needed) — all passing. See §12 for full results.

---

## 11. Testing Executed — What Was and Wasn't Possible

**Executed, this session, with real results (not fabricated):**
- `flutter analyze` — 16 issues, identical to every prior baseline this engagement, 0 new.
- `flutter test` — **99/99 passing** (94 pre-existing + 5 new, `test/init_provider_test.dart`).
- `flutter build web --release` — succeeded.
- Cloud Functions unit tests (`node --test`, against the local Firestore emulator where needed) — **37/37 passing** (29 pre-existing + 8 new, `functions/test/review_rating_pipeline.test.js`).
- Firestore Rules emulator suite — **26/26 passing**, unchanged (no rules were touched this pass), re-run to confirm no regression.
- **Live browser testing, Chromium, iPhone-sized viewport (390×844):** cold launch, refresh, both clean — real login screen reached, zero page errors, zero console errors.
- **Live browser testing, WebKit engine, identical viewport, identical build:** installed and run this session specifically as the Safari-adjacent option this task explicitly permits when a physical device is unavailable. **This is the test that surfaced the §2 root cause** — cold launch and refresh both fail to reach the app; the new recovery screen renders instead, confirmed via full console-log capture down to the exact thrown error.

**Not executed, explicitly, honestly, per this task's own instruction not to fake it:**
- **No physical iPhone or real mobile Safari was available in this environment.** Playwright's `webkit` channel is desktop/generic WebKit (the same underlying engine family, closely related to Safari's rendering/JS engine), **not** literally Apple's iOS-specific mobile Safari build. The failure reproduced here is strong, direct, engine-level evidence and the most plausible explanation for what the user is experiencing — but it is not a substitute for confirmation on a real device, and this report does not claim it is.
- Native iOS build/run (Xcode, simulator, or device) was not attempted — this session has no macOS/Xcode toolchain available.
- Push notification delivery (web or native) was not, and could not be, tested end-to-end — blocked by the infrastructure gaps in §9, independent of anything fixable in a coding session.
- Login/logout/chat/Post Job/profile-loading live-workflow testing (items 11-15 of this task's requested test list) remain blocked by the same account-verification gap documented throughout this entire engagement (`design/HANDYTRUST_V1_V2_MASTER_GAP_ANALYSIS.md` §22) — re-confirmed still true, not re-tested from scratch in this pass since nothing in this phase's fixes touches that blocker.

---

## 12. Tests Passed (consolidated)

| Suite | Result |
|---|---|
| `flutter analyze` | 16 issues (pre-existing baseline), 0 new |
| `flutter test` | 99/99 |
| `flutter build web --release` | Success |
| Cloud Functions unit tests | 37/37 |
| Firestore Rules emulator suite | 26/26 |
| Live: Chromium cold launch + refresh | Pass, 0 errors |
| Live: WebKit cold launch + refresh | **Reproduces the confirmed root cause** — recovery screen shown correctly, per design |

## 13. Tests Unavailable

- Physical iPhone / real mobile Safari (no device in this environment).
- Xcode/native iOS build (no macOS toolchain in this environment).
- End-to-end push notification delivery, web or native (infrastructure-blocked, independent of this session).
- Authenticated live workflows — login, chat, Post Job, profile — beyond what pre-auth/startup testing can reach (account-verification blocker, unchanged, pre-existing across this whole engagement).

---

## 14. Remaining Infrastructure Blockers (unchanged, reconfirmed, not re-litigated in depth here — see the gap analysis for full detail)

- Zero Cloud Functions deployed (Spark plan) — blocks `onNotificationCreated` (and now `onReviewCreated`) from ever actually running in production until deployed.
- No staging/test Firebase project.
- Neither disposable test account is email-verified.
- Web push additionally blocked by a missing service worker + VAPID config (§9), independent of the deployment gap.

## 15. Remaining Product Blockers (unchanged from the gap analysis, not re-litigated here)

Refund/cancellation-after-payment architecture, artisan-location capture, artisan-initiated disputes, the 14-day-vs-3-day dispute-window conflict, the Manager-role premise — all as previously documented, none touched by this pass's scope.

---

## 16. Exact Next Recommended V2 Task

**Upgrade the Firebase Flutter plugin family (`firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `firebase_messaging`, `cloud_functions`) from the current 3.x/5.x/12.x line to the current 4.x/6.x/13.x line, as a dedicated, focused task with its own regression pass — not bundled into another multi-part session.**

This is the single most consequential unresolved finding in this report: it is the confirmed, reproduced root cause of real Firebase-initialization failure under the WebKit engine, and the most plausible fix given (a) this app's own code contains none of the failure surface, (b) the failure is inside third-party plugin interop code, and (c) this is a well-documented category of bug in FlutterFire's history around exactly this kind of engine-specific interop failure. **Why this wasn't attempted in this session:** it is a simultaneous major-version bump across six interlinked packages with real breaking-API-change risk touching nearly every screen in the app (any code reading a `User`, `DocumentSnapshot`, `Reference`, or calling a Cloud Function) — exactly the kind of "large rewrite" this task's own rules ask to be documented first, not silently attempted, especially inside a session already covering thirteen other parts. It deserves its own session: upgrade, run the complete test suite (all of it, not a subset), re-run the exact WebKit reproduction in this report to confirm the fix, then do a full authenticated live-QA pass (which will also, finally, unblock the account-verification-gated testing that has been pending across this entire engagement) before considering it done.

---

## 17. Final Success Criteria — Direct Answers

- **Does HandyTrust load reliably on iPhone Safari?** No — not confirmed reliable, and there is now direct, reproduced evidence of why: `Firebase.initializeApp()` fails under the WebKit engine. This has not been fixed in this pass (see §16); what has been fixed is that this failure (and any other future startup failure) no longer produces a blank/infinite-spinner dead end — it shows a clear recovery screen with a Retry action instead.
- **If not, exactly why not?** `Firebase.initializeApp()` throws `Null check operator used on a null value` inside the third-party `firebase_core_web`/related plugin code, reproduced live under WebKit, not present under Chromium, with this app's own code confirmed to be uninvolved (§2).
- **Does Firebase Auth restore correctly on Safari?** Not reachable to test independently — Firebase itself never successfully initializes under WebKit in this session's reproduction, so Auth's persistence-restoration behavior specifically could not be isolated and evaluated on its own. The auth-state-resolution timeout gap that WAS found and fixed (§4/§5) is a separate, independently real architectural risk, not dependent on §2's root cause being fixed first.
- **Can the router resolve without deadlocking?** Yes, now — confirmed by design and by the new regression test suite (§5/§12): both startup gates (Firebase init, auth-state resolution) are bounded, and the router itself never mounts until both have resolved one way or the other.
- **Does Post Job work on iOS?** Not live-device-tested (no physical iPhone available), but the one confirmed iOS-specific defect in that flow — the missing location permission string — is fixed, verified by full-file re-read, and the location-failure-handling logic was independently improved and confirmed via code reading to degrade gracefully in every case (granted / denied / permanently denied / services disabled / any other error).
- **Does location permission work correctly?** Yes, on Android (already correct, unchanged). On iOS, the crash-causing gap (missing `Info.plist` key) is fixed; not confirmed on a real device.
- **Does review → rating → trust score actually work?** Yes, now, code-level confirmed and unit-tested (§10, §12) — the previously completely non-functional pipeline (every review created a record but never moved the artisan's rating) is fixed with a proper server-side Cloud Function, correctly idempotent, correctly re-verifying party consistency, and correctly deferring to the existing, unmodified `trustScore` recompute trigger. **Not yet live-verified** — like every other Cloud Function in this project, `onReviewCreated` is undeployed (Spark plan) and has never run against real production traffic.
- **Are push notifications technically supported on the target platforms?** Web push: currently non-functional for any user, on any browser, regardless of deployment status (missing service worker + VAPID config, §9) — and even once that's fixed, iOS Safari users can only ever receive it if they've installed the app to their Home Screen (a hard Apple platform limitation, not a bug). Native iOS push was out of this investigation's scope.
- **What remains blocked by infrastructure?** All Cloud Function-dependent behavior — notifications, the new review→rating pipeline (`onReviewCreated`) and its downstream trust-score recompute (`onArtisanRatingChanged`, itself also undeployed), all live Paystack/payment validation, all authenticated live-workflow QA — none of this changed in this pass, all pre-existing and unchanged.
- **What should we build next for V2?** The Firebase plugin major-version upgrade (§16) — everything else in this report is either already fixed, or blocked on infrastructure/product decisions outside a coding session's authority.
