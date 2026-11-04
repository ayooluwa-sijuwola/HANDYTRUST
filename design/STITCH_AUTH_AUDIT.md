# Stitch Auth Audit — Group 2

Same standing note as `STITCH_IMPLEMENTATION_AUDIT.md`: no Stitch mockups have been supplied for any auth screen. All 22 screenshots so far were post-login (customer/artisan) screens. This audit is therefore built entirely from the current codebase — what exists, what's already good, and what's real duplication worth fixing with Group 1's tokens. Nothing here follows a Stitch layout, per the standing "no layout invention without a reference" rule.

One thing worth surfacing up front: **the auth screens already have their own reusable component layer** — `lib/widgets/auth_scaffold.dart` (`AuthBrandHeader`, `AuthLogoBadge`, `AuthCard`, `AuthFieldLabel`, `SocialSignInRow`, `AuthDivider`, `AuthFooter`). This predates this task and already satisfies most of "don't duplicate styling across screens." The real remaining duplication is the primary-submit-button-with-loading-spinner block, copy-pasted identically across three screens.

---

## Screen-by-screen

### Login
**Current file**: `lib/screens/auth/login_screen.dart`
**Purpose**: email/password sign-in
**Existing functionality**: form validation (email format, required password), `authNotifierProvider.signIn`, loading state disables the button, error surfaced via `SnackBar` with `context.colors.error`, "Forgot Password?" link, "Sign Up" link, coming-soon Google/Apple row
**Stitch equivalent**: none supplied
**Required components**: already uses `AuthBrandHeader`/`AuthCard`/`AuthFieldLabel`/`AuthDivider`/`SocialSignInRow`/`AuthFooter`. Missing: a shared submit-button component (currently 17 lines of loading-ternary markup, identical to Register's and Forgot Password's)
**Missing states**: none functionally — loading and error are both handled. Error text is generic ("Sign-in failed.") only as a *fallback* when `authNotifierProvider`'s error is null; the real Firebase error message is shown when present, so this isn't the "generic message hides real errors" problem Task 3 warns about.

### Signup (Register)
**Current file**: `lib/screens/auth/register_screen.dart`
**Purpose**: account creation with inline role selection (customer/artisan)
**Existing functionality**: name/email/city/password/confirm-password validation (password: 8+ chars, 1 uppercase, 1 number — confirm must match), `_RoleTile` picker, `authNotifierProvider.signUp`, loading state, error `SnackBar`
**Stitch equivalent**: none supplied
**Required components**: same gap as Login — duplicated submit-button block. `_RoleTile` here is private to this file and visually/structurally near-identical to `RoleSelectionScreen`'s own private `_RoleTile` (different file, different class, same concept) — a second, smaller duplication worth closing
**Missing states**: none functionally. Comment at line 63 confirms verification-redirect is router-owned, not this screen's job — correct, not touched.

### Email Verification
**Current file**: `lib/screens/auth/verify_email_screen.dart`
**Purpose**: blocking gate shown while `firebaseUser.emailVerified == false`
**Existing functionality**: polls `currentUser.reload()` every 4s (comment explains why navigation isn't done here — router's `redirect` reacts to the resulting auth-state change), "Resend verification email," "I've verified — continue" (manual re-check), "Use a different account" (sign out)
**Stitch equivalent**: none supplied
**Required components**: already uses the shared auth widgets; no submit-button duplication here (both buttons are single-shot, not loading-gated)
**Missing states**: **resend has no loading/disabled state** — nothing stops a user from tapping "Resend verification email" repeatedly (Firebase itself may rate-limit, but the button gives no feedback while the call is in flight, and no error is shown if `resendVerificationEmail()` throws — the `SnackBar` at line 53-55 always says "sent" unconditionally, even on failure). This is a real, in-scope Task 3 gap: an error can be silently swallowed here.

### Forgot Password
**Current file**: `lib/screens/auth/forgot_password_screen.dart`
**Purpose**: password reset request
**Existing functionality**: email validation, loading state, real error surfaced inline (`_error` text, not swallowed), success state swaps the whole card body (`_sent` flag) rather than a toast
**Stitch equivalent**: none supplied
**Required components**: same submit-button duplication as Login/Register
**Missing states**: none — this screen already does inline error display exactly right, and is the best-handled of the three form screens.

### Role Selection ("onboarding: which mode")
**Current file**: `lib/screens/auth/role_selection_screen.dart`
**Purpose**: interstitial shown only when a dual-role user has no `activeRole` set yet (router guard, line ~154-161 of `router.dart`)
**Existing functionality**: two `_RoleTile` cards, writes `activeRole` via `profileServiceProvider.setActiveRole`, loading state, error `SnackBar`
**Stitch equivalent**: none supplied
**Required components**: does **not** use `auth_scaffold.dart` at all — it hand-rolls its own logo row and heading instead of reusing `AuthBrandHeader`/`AppTextStyles`. Real, in-scope inconsistency: this screen looks and is built differently from Login/Register/Forgot-Password for no functional reason.
**Missing states**: none functionally.

### Artisan Registration ("onboarding: artisan profile step 2")
**Current file**: `lib/screens/auth/artisan_registration_screen.dart`
**Purpose**: collects category/skills/bio/service-area after a user picks the artisan role; reached post-verification
**Existing functionality**: form validation per field, writes to both `users` and `artisans` collections (merge, not overwrite — comment explains why), loading state, error `SnackBar` with the real exception message (not swallowed)
**Stitch equivalent**: none supplied
**Required components**: uses a normal `AppBar` scaffold, not the `AuthCard` pattern — correct, since this is post-login (not a "before you're in the app" screen); same submit-button duplication as Login/Register/Forgot-Password.
**Missing states**: none.

### Splash
**Current file**: `lib/screens/auth/splash_screen.dart`
**Purpose**: shown while `authStateChangesProvider` is resolving, before the router knows where to send the user
**Existing functionality**: loading spinner + error fallback
**Stitch equivalent**: none supplied
**Required components**: none new — but this screen uses **hardcoded raw colors** (`Color(0xFFF9FAFB)` background, `Color(0xFF1A56DB)` — an old blue that isn't Trust Green) instead of `context.colors`. This predates the design-system work entirely and is a real, visible brand inconsistency (briefly shows the wrong primary color on every cold start) — flagged as in-scope for Group 2 even though it's not one of the six screens the task named, since it's the first screen every session sees.
**Missing states**: handled (loading/data/error via `authState.when`).

### Suspended
**Current file**: `lib/screens/auth/suspended_screen.dart`
**Purpose**: blocking screen for `accountStatus == 'suspended'`
**Existing functionality**: sign-out action, already uses `context.colors` correctly
**Stitch equivalent**: none supplied
**Required components**: none needed — already consistent, low-traffic screen, left as-is.
**Missing states**: none.

### Dead screens (confirmed, not touched)
`phone_login_screen.dart` and `customer_registration_screen.dart` are redirect-only stubs kept for legacy deep-link safety (per their own doc comments) — they render a spinner for one frame and immediately `context.go()` elsewhere. No visual surface to redesign. Unchanged.

---

## Summary of real, in-scope work

1. **New `AuthButton` component** — closes the 4x-duplicated (Login, Register, Forgot Password, Artisan Registration) loading-spinner-submit-button block. Uses the existing Trust Green `ElevatedButton` theme, not `CommitButton` — no Stitch evidence supports a black button on auth screens, and inventing one isn't a "UI replacement," it's a guess. Documented here as a deliberate choice, not an oversight.
2. **New `AuthTextField` component** — bundles `AuthFieldLabel` + `TextFormField`, removing the repeated label/field pairing boilerplate across Login/Register/Forgot Password (and optionally Artisan Registration, which uses floating `labelText` instead — left as-is there since that's a different, also-valid pattern already used consistently within that screen).
3. **Verify Email — fix the swallowed-error gap**: give "Resend" a loading state and show the real error on failure instead of an unconditional "sent" toast.
4. **Role Selection — bring it onto the shared auth-widget system**: replace its hand-rolled logo/heading with `AuthBrandHeader`/`AppTextStyles`; its private `_RoleTile` stays screen-local since `RegisterScreen`'s `_RoleTile` and this one differ in enough real ways (icon+label+sublabel vs icon+title+subtitle+checkmark+selection-elevation) that merging them risks forcing one design to fit two different contexts — flagged, not merged, per "don't invent."
5. **Splash — swap hardcoded colors for `context.colors`**, fixing the wrong-brand-color flash on cold start.

Nothing above touches `authNotifierProvider`, `AuthService`, Firestore profile-creation writes, role logic, or `router.dart`'s redirect chain (login → email-verification → suspended → admin → role-select, confirmed read, not modified).
