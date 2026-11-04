# Part 2 — Authentication

All flows implemented via `AuthService` (`lib/core/services/auth_service.dart`) + `AuthNotifier` (`lib/providers/auth_provider.dart`) + `router.dart`'s centralized redirect. Firebase Authentication's email/password provider is the only sign-in method reachable in the UI.

## Login ✅
- **Start screen**: `/login` (`login_screen.dart`).
- **Validation**: email regex match, password non-empty (client-side only — Firebase enforces its own minimums server-side).
- **Firestore writes**: none directly — `AuthService.signIn` only calls `FirebaseAuth.signInWithEmailAndPassword`.
- **Navigation**: on success, the router's redirect logic (not the screen itself) sends the user to `/verify-email` (if unverified) or `/home` — the screen never navigates manually.
- **Possible failures**: mapped to friendly copy by `AuthService.friendlyError` (wrong password, user not found, invalid email, too many attempts, disabled account, network failure) — shown as a `SnackBar`.
- **Missing pieces**: no "remember me," no biometric/social sign-in despite the UI in a prior redesign pass showing placeholder Google/Apple buttons (those are visual-only, confirmed non-functional — tapping shows a "coming soon" message, no real OAuth integration exists).

## Signup ✅
- **Start screen**: `/register` (`register_screen.dart`).
- **Validation**: name ≥2 chars, email regex, city optional, password ≥8 chars with at least one uppercase and one digit, confirm-password match.
- **Firestore writes**: `AuthService.createAccount` creates the Firebase Auth account, calls `sendEmailVerification()`, then writes `users/{uid}` with the submitted profile (`roles: [selectedRole]`, `activeRole: selectedRole`) — two separate operations, not one atomic write (see "Missing pieces").
- **Navigation**: router redirect sends the newly-created, unverified account to `/verify-email` automatically.
- **Possible failures**: same `friendlyError` mapping as login (most relevantly `email-already-in-use`, `weak-password`).
- **Missing pieces**: **Auth-account creation and the Firestore profile write are not atomic** — if the app is killed or the network drops between the two `await`s in `createAccount`, an Auth account exists with no `/users/{uid}` document. `AuthService.userProfileStream` has an explicit self-healing fallback for exactly this case (documented in its own code comment), so the app recovers gracefully rather than crashing, but the underlying non-atomicity is real, not hypothetical. Role selection at signup does not branch the form — customer and artisan get an identical field set; artisan-specific onboarding is a separate second step (see "Profile completion").

## Forgot password ✅
- **Start screen**: `/forgot-password` (`forgot_password_screen.dart`).
- **Validation**: email regex only.
- **Firestore writes**: none — `AuthService.sendPasswordReset` calls `FirebaseAuth.sendPasswordResetEmail`.
- **Navigation**: stays on the same screen, swapping to a success state (no redirect); a "Back to Login" button returns to `/login`.
- **Possible failures**: raw exception text is shown (`e.toString()`), not passed through `friendlyError` — the one auth flow whose error messaging doesn't match the others' friendliness level.
- **Missing pieces**: none functionally — this flow is complete and self-contained.

## Email verification ✅
- **Start screen**: `/verify-email` (`verify_email_screen.dart`) — a hard router-level gate; every authenticated-but-unverified path lands here regardless of the requested URL.
- **Validation**: n/a (no form).
- **Firestore writes**: none.
- **Navigation**: the screen polls `FirebaseAuth.currentUser.reload()` every 4 seconds; because `AuthService.authStateChanges()` uses `userChanges()` (not `authStateChanges()`), a `reload()` that flips `emailVerified` to true propagates automatically to the router's `refreshListenable`, which re-runs the redirect and sends the user to `/home` on its own — no manual navigation call in the screen. A manual "I've verified — continue" button exists as a fallback trigger for the same check.
- **Possible failures**: none surfaced distinctly — a failed resend silently retries on next attempt (no error state shown for `resendVerificationEmail` failures, confirmed by reading the screen: the resend button always shows the same success snackbar regardless of outcome).
- **Missing pieces**: no visible countdown/rate-limit feedback if "Resend" is tapped repeatedly (Firebase itself rate-limits this server-side, but the UI gives no indication).

## Role selection ✅ (dual-role accounts only)
- **Start screen**: `/role-select` (`role_selection_screen.dart`) — only reached via router redirect, only for accounts with both `customer` and `artisan` in `roles` and no `activeRole` set yet.
- **Validation**: a role tile must be selected before "Continue" enables.
- **Firestore writes**: `ProfileService.setActiveRole(uid, role)` writes `activeRole` to `users/{uid}`.
- **Navigation**: `context.go('/home')` on success (manual, not router-redirect-driven, unlike most other auth transitions in this app).
- **Possible failures**: any write error shown via `SnackBar` with the raw error message.
- **Missing pieces**: none — a small, complete, self-contained flow. Once `activeRole` is set, this screen is never shown again for that account (switching roles later happens via Settings, not this screen).

## Guest mode ❌ — does not exist as a reachable feature
Grepped every reference to `signInAnonymously`/`signInForDemo` across `lib/` — neither exists anywhere. `isAnonymous` appears only as a *check*, not a trigger: the router's redirect explicitly treats any anonymous Firebase session as equivalent to signed-out ("Strip any anonymous/demo sessions — treat them as signed-out," per the redirect's own code comment). Older documentation files at the repository root (`AUTH_AUDIT_REPORT.md`, `AUDIT_SUMMARY.txt`) describe a "Register without OTP for demo" anonymous-auth feature and a specific Firebase Console configuration bug blocking it — that feature is **not present in the current codebase**, whether because it was removed after those documents were written or because those documents described work that was never actually merged. Either way: guest/demo mode is not something a user can reach today.

## Admin login 🔒 — no dedicated login flow; reachability was itself a documented problem
There is no `/admin-login` route or distinct admin sign-in screen. An account with an `/admins/{uid}` Firestore document and the corresponding Auth custom claim signs in exactly like any other user via `/login`, and the router's redirect independently gates any `/admin/*` route on the resolved admin-claim state. **Historically** (prior to the most recent design-system rework in this codebase), the only way to *discover* the admin section as a user was a hidden long-press gesture on the customer home screen's greeting text, prompting a PIN dialog — this was identified as a real, if low-severity, security-and-discoverability issue and was removed in the most recent pass in favor of a conditional "Admin Dashboard" row in the Profile menu, visible only when the signed-in account resolves as an admin. Confirm this replacement is present in the version of `profile_screen.dart` being archived — it was the stated intent of the most recent relevant change.

## Profile completion ✅ (artisan only)
- **Start screen**: `/register/artisan` (`artisan_registration_screen.dart`) — category, skills, bio, business info.
- **Trigger**: not part of the linear signup flow. `ArtisanHomeTabContent` checks for an existing `artisans/{uid}` document on load; if none exists, it auto-redirects to `/register/artisan` via `WidgetsBinding.instance.addPostFrameCallback`. This means a new artisan only reaches this step by first landing on their home tab — there is no direct hand-off from the signup screen itself.
- **Firestore writes**: creates `artisans/{uid}` with `approvalStatus: 'pending'`, `responseTimeMinutes: 30.0` (a hardcoded default — see Part 6/Part 20 for why this value never actually updates), `trustScore: 0.0`.
- **Navigation**: back to the artisan home tab, which now renders the pending-approval banner instead of redirecting again.
- **Possible failures**: standard form-validation failures; no distinct network-failure handling beyond whatever the underlying write throws.
- **Missing pieces**: no equivalent "profile completion" step exists for customers — their profile is considered complete immediately after the single-step signup form.

## Session restore ✅
Handled implicitly by `AuthService.authStateChanges()` (backed by `userChanges()`) feeding `AuthChangeNotifier`, which is GoRouter's `refreshListenable`. On app relaunch, `WidgetsFlutterBinding.ensureInitialized()` → `initializeFirebase()` → `runApp` — Firebase Auth's own SDK-level session persistence restores the signed-in user before the router's first redirect evaluation runs, so a previously-authenticated user lands on `/home` (or whichever gate applies) without re-entering credentials. No custom token-refresh or session-management code was found beyond what the Firebase Auth SDK provides natively.

## Logout ✅
`AuthNotifier.signOut()` → `AuthService.signOut()` → `FirebaseAuth.signOut()`. Reachable from three places, confirmed by direct inspection: Profile screen's menu (with a confirmation dialog), Settings screen (also with confirmation), and `SuspendedScreen` (no confirmation — it's the only action available there). After sign-out, the router's redirect sends the user to `/login` automatically; no screen navigates manually.

---

## Cross-cutting notes for this Part

- **Testing**: as of the most recent work in this repository, exactly one automated test file exists in the entire project (`test/job_service_agreement_test.dart`, covering the Agreement Confirmation feature's validation logic — see Part 6). No test exists for any authentication flow.
- **The two-write signup non-atomicity** (Auth account + Firestore profile) is the most concrete "possible failure" gap across all of Part 2 — it's mitigated by a self-healing read path, not eliminated at the write layer.
