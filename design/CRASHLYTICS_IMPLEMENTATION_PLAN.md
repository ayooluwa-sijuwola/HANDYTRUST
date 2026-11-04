# Crash Reporting — Implementation Plan (not yet built)

Confirmed: no crash-reporting package (`firebase_crashlytics`) exists in `pubspec.yaml` today. Per this phase's instruction, this is a plan only — no dependency added, nothing implemented.

## Compatibility check
Current Firebase client stack: `firebase_core: ^3.15.2`, `firebase_auth: ^5.7.0`, `cloud_firestore: ^5.6.12`, `firebase_storage: ^12.4.10`, `firebase_messaging: ^15.2.10`. `firebase_crashlytics` tracks `firebase_core`'s major version series closely (its `^4.x` line targets `firebase_core ^3.x`) — the current stack is a clearly compatible target. Not added in this pass regardless, since the instruction is plan-only.

## Required setup
1. **Firebase Console**: enable Crashlytics for the project (one-time, console-side — not a code change).
2. **`pubspec.yaml`**: add `firebase_crashlytics: ^4.x` (pin to whatever resolves cleanly against the current `firebase_core` constraint at implementation time — don't guess a version now, resolve it live).
3. **Android**: add the Crashlytics Gradle plugin to `android/build.gradle` (project-level) and apply it in `android/app/build.gradle` — standard FlutterFire-documented steps, no custom logic needed given this project's existing Android setup.
4. **iOS**: modern `firebase_crashlytics` + CocoaPods handles dSYM upload via an automatically-added build phase; no manual Xcode scripting expected, but should be confirmed against whatever Flutter/Xcode version is used at implementation time.
5. **`lib/main.dart`**: initialize Crashlytics right after `Firebase.initializeApp()`, before `runApp()`:
   - `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;` — catches framework-level errors (widget build errors, etc.).
   - `PlatformDispatcher.instance.onError = (error, stack) { FirebaseCrashlytics.instance.recordError(error, stack, fatal: true); return true; };` — catches uncaught async errors outside the Flutter framework.
   - Wrap the existing `runApp(...)` call in `runZonedGuarded` so genuinely uncaught zone errors are also captured, not just the two hooks above.
6. **New file, recommended**: `lib/core/services/crash_reporting_service.dart` — a thin wrapper (`recordError`, `log`, `setUserId`) so call sites across the app go through one place rather than importing `FirebaseCrashlytics` directly everywhere. Matches this codebase's existing "one service per concern" convention (`NotificationService`, `JobService`, etc.).

## Files affected (when implemented)
`pubspec.yaml`, `android/build.gradle`, `android/app/build.gradle`, `lib/main.dart`, new `lib/core/services/crash_reporting_service.dart`. No screen files need changes for basic crash capture — non-fatal error reporting at specific call sites (e.g. the many `debugPrint('[Service] X failed: $e')` catch blocks already scattered through `JobService`, `QuoteService`, `NotificationService`, etc., built up across this whole program) would be a natural *second* wave: replacing/augmenting `debugPrint` with `CrashReportingService.recordError` at those exact existing catch sites, since they already isolate exactly the failure points worth tracking. Not required for MVP crash capture, worth noting as the natural next step.

## Deployment steps (when implemented)
1. Add the dependency, run `flutter pub get`.
2. Wire the three hooks in `main.dart` as above.
3. Add a temporary, manually-triggered test crash (a debug-only button calling `FirebaseCrashlytics.instance.crash()`), confirm it appears in the Firebase Console (can take a few minutes to surface), then remove the test trigger.
4. Build and run a release build at least once before shipping — Crashlytics behavior (especially symbolication) can differ between debug and release.
5. Confirm dSYM/mapping-file upload succeeded for both platforms (Console shows "missing dSYM" warnings if not).

Not implemented in this pass — plan only, per instruction.
