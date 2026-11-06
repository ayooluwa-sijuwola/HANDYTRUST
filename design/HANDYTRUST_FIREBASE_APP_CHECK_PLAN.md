# HandyTrust — Firebase App Check plan

**Stage:** H1.1 assessment. App Check is **not** enabled, and no enforcement or console change was made.
**Source:** Firebase docs, *App Check, Flutter default providers* (read 5 November 2026).

## 1. Current state (verified)

- No `firebase_app_check` dependency in `pubspec.yaml`, and no `FirebaseAppCheck` call in `lib/`.
- Firestore, Storage and Cloud Functions accept any request that passes Auth and the security rules. The rules and server checks still protect data (they are the real boundary), but nothing proves a request comes from the genuine app. Scripts using the public web/Android API keys can call callables and query Firestore within the rules.
- The Firebase Android app has no SHA-256 fingerprint registered (needed by Play Integrity).

## 2. Providers (documented)

| Platform | Provider | Notes |
|---|---|---|
| Android | **Play Integrity** (default) | Needs the app distributed via, or registered with, Google Play and its SHA-256 in Firebase. Some devices need "Meets basic device integrity" enabled in the Play Console |
| Android dev/CI/emulator | **Debug provider** | Debug token registered in the console; never shipped in release builds |
| iOS (if shipped) | App Attest (iOS 14+), DeviceCheck, or App Attest with DeviceCheck fallback | — |
| Web (if shipped) | reCAPTCHA v3 / Enterprise | — |

Activation is `FirebaseAppCheck.instance.activate(androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug)` after `Firebase.initializeApp()`. Token TTL is configurable from 30 minutes to 7 days; the SDK refreshes at about half the TTL. Shorter TTLs use more attestation quota.

## 3. Compatibility

- **Firestore and Storage:** enforcement is per product in the console. Clients without valid tokens are rejected once it's enforced.
- **Cloud Functions callables:** the server enforces per function with `enforceAppCheck: true` in the `onCall` options (a Functions change). It's also visible in `request.app` for logging-only mode.
- **`paystackWebhook` (onRequest) must NOT require App Check.** It's called by Paystack's servers and is authenticated by its HMAC signature.
- **Scheduled and trigger functions:** not affected.
- **Emulator tests:** the debug provider or emulator; existing test suites don't use App Check.
- **Old app versions:** installed builds without App Check send no token. Enforcing would immediately break them. There's no store audience today, so the cost is low, but testers must update first.

## 4. Rollout (staged; monitor before enforcing)

1. **Code (needs approval):**
   - add `firebase_app_check`;
   - activate with Play Integrity in release and Debug in debug builds;
   - on callables, log `request.app` presence without rejecting.
2. **Console:**
   - register the app with Play Integrity, add the SHA-256 (requires the release signing plan) and debug tokens for developers and CI;
   - TTL 1 hour to start.
3. **Monitor for at least 2 weeks.** App Check request metrics for Firestore, Storage, Auth and Functions; target ≥ 99% verified requests from current builds.
4. **Enforce gradually:**
   - Storage first (smallest surface);
   - then Firestore;
   - then callables via `enforceAppCheck: true`, except `paystackWebhook`.
5. **Rollback:** turn enforcement off in the console (immediate) or redeploy Functions without `enforceAppCheck`. The SDK keeps sending tokens harmlessly.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Legitimate users blocked (rooted devices, sideloaded builds, devices without Play services) | Monitoring phase; "basic integrity" setting; staged enforcement; clear error copy in the app |
| Quota exhaustion with short TTLs | Start at 1 h TTL; review quota |
| Webhook broken by mistake | Explicit exclusion and a test that `paystackWebhook` options have no App Check |
| Debug token leaks | Tokens per developer, revocable; never in release builds |

## 6. Dependencies and approvals

- Release signing and fingerprints (`HANDYTRUST_ANDROID_RELEASE_SIGNING_PLAN.md`) and, ideally, the final application ID first.
- Approvals: the Flutter dependency and activation code; the console registration; the Functions logging change; the enforcement schedule.
- Cost: App Check itself is listed as no-cost; Play Integrity has usage tiers set by Google Play.
