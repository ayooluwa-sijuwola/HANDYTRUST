# HandyTrust — Android release signing plan

**Stage:** H1.1 assessment. No keystore was created, and no signing setting was changed.

## 1. Current state (verified)

`android/app/build.gradle.kts`:

```kotlin
buildTypes {
    release {
        // TODO: Add your own signing config for the release build.
        // Signing with the debug keys for now, so `flutter run --release` works.
        signingConfig = signingConfigs.getByName("debug")
    }
}
```

- **Release APKs are signed with the machine-local debug key.** Each developer machine has a different debug key, so updates built on different machines can't install over each other. A debug-signed build can't be published on Google Play.
- No `key.properties`, keystore file or CI exists. `.gitignore` does **not** list `*.jks`, `*.keystore` or `key.properties` (only `functions/.secret.local`).
- No code shrinking or obfuscation settings are present (the Flutter defaults apply).
- The Firebase Android app has **no SHA-1/SHA-256 fingerprint registered** (`google-services.json` OAuth client has no certificate hash). That's fine today: there's no Google Sign-In and no App Check. Both App Check (Play Integrity) and any future Google sign-in will need the release fingerprints.

## 2. Recommended strategy

1. **Play App Signing** (if distributing through Google Play):
   - Google holds the **app signing key**; you keep an **upload key**.
   - A lost upload key can be reset through Play support; a lost app signing key can't be recovered outside Play App Signing.
   - Required for Android App Bundles.
2. **Generate the upload keystore on an owner-controlled machine** (`keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 4096 -validity 10000 -alias upload`):
   - use a strong, unique store password and key password;
   - **never in the repository and never shared in chat.**
3. **Local configuration:**
   - `android/key.properties` (git-ignored) with `storePassword`, `keyPassword`, `keyAlias`, `storeFile`;
   - `build.gradle.kts` reads it when present and fails release builds when it's absent (no silent fallback to debug);
   - add `*.jks`, `*.keystore` and `android/key.properties` to `.gitignore` first.
4. **CI (when introduced):**
   - store the keystore as a base64 secret plus the passwords as separate secrets (GitHub Actions encrypted secrets);
   - decode to a temp file during the job, delete it after;
   - restrict the secrets to protected branches and environments with required reviewers.
5. **Backup and recovery of the upload key:**
   - two encrypted copies (e.g. a password manager vault, plus an offline encrypted USB in a safe);
   - the passwords live in the password manager, never alongside the file;
   - record the SHA-256 fingerprint in the runbook.
6. **Fingerprints:**
   - register the upload-key and Play app-signing-key SHA-256 (and SHA-1) in the Firebase Android app;
   - needed for App Check (Play Integrity) and any future Google-based auth.
7. **Release verification:**
   - `apksigner verify --print-certs app-release.apk` (or `bundletool` for AAB);
   - compare the certificate SHA-256 with the recorded fingerprint;
   - install over the previous release on a test device to confirm upgrade continuity.

## 3. Interaction with the application-ID change

Signing and the application ID should change **together, before the first store release**. Changing the ID later creates a different app. See `HANDYTRUST_APPLICATION_ID_MIGRATION_PLAN.md`.

## 4. Risks

| Risk | Mitigation |
|---|---|
| Keystore committed or leaked | `.gitignore` first; secret scanning; CI secrets |
| Keystore lost (outside Play App Signing) | Play App Signing; two encrypted backups |
| Silent debug-signed release | Build fails when `key.properties` is missing in release mode |
| Users on today's debug-signed APK can't upgrade to the release-signed APK (signature mismatch) | One-time reinstall for current testers; there are no store users yet |

## 5. Approvals needed

1. Generate the upload keystore (by the owner) and enrol in Play App Signing.
2. `.gitignore` additions and the `build.gradle.kts` signing change (a code change).
3. Register the fingerprints in Firebase.
4. Set up CI secrets when CI exists.
