# HandyTrust — application ID migration plan

**Stage:** H1.1 assessment. **Nothing has been renamed.**

## 1. Current identity (verified)

| Where | Value |
|---|---|
| `android/app/build.gradle.kts` `applicationId` | `com.example.handy_trust` |
| `android/app/build.gradle.kts` `namespace` | `com.example.handy_trust` |
| Kotlin package / path | `android/app/src/main/kotlin/com/example/handy_trust/MainActivity.kt` (`package com.example.handy_trust`) |
| `android/app/google-services.json` | One Android client: package `com.example.handy_trust`, app ID `1:300219062368:android:93351eddb2b2634ef44b05`, OAuth client without a certificate hash |
| `lib/firebase_options.dart` | Android app ID as above; iOS/macOS `iosBundleId: com.example.handyTrust` |
| iOS / macOS | `ios/Runner.xcodeproj/project.pbxproj`, `macos/Runner.xcodeproj/project.pbxproj`, `macos/Runner/Configs/AppInfo.xcconfig` (`com.example.handyTrust`) |
| Linux | `linux/CMakeLists.txt` (`APPLICATION_ID`) |

`com.example.*` is a placeholder. Google Play rejects it, and it can't be changed once an app is published under it.

## 2. Proposed final ID (owner to confirm the domain)

`com.handytrust.app` for Android and `com.handytrust.app` for iOS.

- **Prerequisite:** you control the `handytrust.com` domain, or another domain whose reverse form you'll use.
- **If not:** pick a domain you own, e.g. `ng.handytrust.app`. The ID must be unique on Play and should map to a domain you control.

## 3. Implications

- **Firebase:** a new package name needs a **new Android app registration** in project `handytrust`, which produces a new `google-services.json` and app ID. Regenerate `firebase_options.dart` with `flutterfire configure`.
  - **FCM:** tokens are per app instance. Users must install the new app; tokens re-register on first launch (the app already writes `fcm_tokens/{uid}`).
  - **App Check:** register the new app with Play Integrity and its fingerprints.
  - **Auth:** email/password is unaffected. Password-reset and verification links use the Firebase-hosted handler, not the package name.
  - **Storage, Firestore, Functions:** unaffected (project-scoped).
- **Deep links and OAuth:** the manifest has **no** app links or custom schemes today, and no Google/OAuth sign-in. Nothing else to migrate. Future Android App Links must use the new package plus the release SHA-256 in `assetlinks.json`.
- **Distribution:** the new ID is a **different app**. Testers on the current APK must uninstall it and install the new one; data lives in Firebase, so nothing is lost beyond local preferences such as the theme and the onboarding flag.
- **Signing:** change it at the same time (`HANDYTRUST_ANDROID_RELEASE_SIGNING_PLAN.md`).

## 4. Migration procedure (when approved)

1. Confirm the domain and the ID.
2. Register the new Android app (and iOS app if needed) in Firebase. **Keep the old registration** until no tester uses it.
3. Change `applicationId` and `namespace`, and move `MainActivity.kt` to `com/handytrust/app/`. Update the iOS/macOS bundle IDs and Linux `APPLICATION_ID` if those platforms ship.
4. Run `flutterfire configure` to regenerate `firebase_options.dart` and the platform config files.
5. Add the release signing config and register the fingerprints.
6. Build and install on a clean device. Verify:
   - sign-in;
   - Firestore reads;
   - Storage upload;
   - a callable (`getPaymentBreakdown`) on a staging project;
   - FCM token write.
7. Distribute the new build. Tell testers to uninstall the old app.

## 5. Rollback

- Revert the commit. The old Firebase app registration is still there, so the old ID builds and works as before.
- No server data is touched by this change.

## 6. Approvals needed

1. The final ID and domain.
2. Firebase app registration(s).
3. The code and config change, done together with release signing.
