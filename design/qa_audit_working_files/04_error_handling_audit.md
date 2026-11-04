# HandyTrust Error-Handling & Defensive-Coding Audit

Read-only sweep of lib/. Overall unusually well-defended for a project this size (safeStream/safeDocStream, WorkflowGateService, transactional JobService). Findings below are the real gaps that remain.

## Highest-value finding: false "success" on password reset (P0)

**File:** lib/screens/auth/forgot_password_screen.dart:36-46 + lib/providers/auth_provider.dart:94-102

```dart
// forgot_password_screen.dart
try {
  await ref.read(authNotifierProvider.notifier).sendPasswordReset(_emailCtrl.text.trim());
  if (mounted) setState(() => _sent = true);   // always runs
} catch (e) { ... }

// auth_provider.dart
Future<void> sendPasswordReset(String email) async {
  state = state.copyWith(isLoading: true, error: null);
  try {
    await _authService.sendPasswordReset(email);
    state = state.copyWith(isLoading: false);
  } on FirebaseAuthException catch (e) {
    state = state.copyWith(isLoading: false, error: AuthService.friendlyError(e));
    // no rethrow
  }
}
```
AuthNotifier.sendPasswordReset swallows FirebaseAuthException into its own riverpod state and never rethrows. ForgotPasswordScreen never watches authNotifierProvider — only calls the method and assumes normal return means success. Any FirebaseAuthException (rate-limited, malformed email that slips validation, disabled project config) is silently absorbed, and screen still shows "Check your inbox" even though nothing was sent. Concrete scenario: user rate-limited (too-many-requests), told email was sent, waits forever. Exactly the "false success state" class this audit targets. Fix: rethrow in notifier, or have screen watch authNotifierProvider and check .error after await.

## 1. print/debugPrint
No bare print( calls anywhere. debugPrint used consistently (25 files) as diagnostic channel, not substitute for user feedback. No sensitive-value leakage (uids/paths logged, not tokens/passwords). P3 informational.

## 2/3. throw / try-catch tracing / empty catch blocks
No truly empty catch(e){} blocks — every catch does something. Intentional swallows well-commented:
- storage_service.dart / portfolio_service.dart::removeImage — Storage-delete failures swallowed, "Storage object may already be gone — Firestore is source of truth" (reasonable).
- **[P2]** review_screen.dart:247-265 `_updateArtisanRating` — wrapped in catch(_){} with comment "handled by Cloud Function in production," but functions/index.js's onArtisanRatingChanged only fires when rating/totalRatings actually change. If client-side transaction throws (offline/transient conflict), review doc still saves and user sees success, but artisan's rating/totalRatings/trust-score are silently never updated for that review — no retry, no visibility. Real if narrow silent data-consistency bug.

Genuine well-engineered infra: lib/core/utils/safe_firestore.dart deliberately converts stream-level failures (including permission-denied) into empty lists/null rather than propagating AsyncError — documented intentional tradeoff. **P3/informational**: a genuine ongoing permission problem (e.g. admin whose custom claim was revoked mid-session) is indistinguishable in UI from "no data," could mask a real access bug from support/QA.

JobService is exemplary: every transition throws typed exception (JobNotFoundException, JobStateConflictException) on failure, every caller (EscrowNotifier via AsyncValue.guard) captures into provider state.

## 4. Null-assertion `!` usage
No currentUser! force-unwraps anywhere. `!` usages found are "provably safe" given preceding .exists check in same Firestore transaction. Two minor exceptions:
- **[P3]** auth_service.dart:28 — `await credential.user!.sendEmailVerification();` right after createUserWithEmailAndPassword succeeds — realistically never null but would throw uncaught if it were.
- **[P3]** profile_service.dart:116,132 — `email: user.email!` in updateEmail/updatePassword — safe for email/password-only auth, would NPE if phone/anonymous auth added.

## 5. `late` fields
Every late final assigned unconditionally in initState() before first read. No read-before-assignment risk found.

## 6. `.first`/`.last`/`.single` on possibly-empty collections
All checked call sites guarded (isNotEmpty checks, ?? null fallbacks). No real risk found.

## 7. Unsafe casts
Consistently defensive — nullable casts with ?? {} / ?? [] fallback almost everywhere. One partial exception:
**[P2]** paystack_service.dart::initializeTransaction — `Map<String, dynamic>.from(result.data as Map)` then unqualified casts like `data['paymentId'] as String` (lines 34,40,42). If Cloud Function ever returns a shape missing these keys (deploy mismatch, function error swallowed server-side), throws raw TypeError. Caught by payment_screen.dart:314's catch, but user-facing text ($e) includes raw Dart TypeError text (see category 10). ai_provider.dart:69-79 has the same pattern but IS mitigated by outer try/catch converting to friendly AiServiceException.

## 8. Mutating Firestore-derived lists
Not found. All models parse list fields via List<String>.from(json[...] ?? []), growable mutable copy. No unmodifiable-list risk.

## 9. Unawaited async writes
Mostly clean. One intentional fire-and-forget: notification_provider.dart:83 register() for FCM token registration — self-contained, internal try/catch, comment confirms intentional. No P0/P1 "UI shows success while write silently fails" beyond review-rating case above.

## 10. Raw exception text shown to users — systemic, inconsistent (P1/P2, widespread)

Largest and most actionable category. App clearly knows the rule — does it right in several places:
- auth_service.dart::friendlyError maps FirebaseAuthException codes to friendly copy.
- ai_provider.dart::AiServiceException documents "safe to show e.toString() directly."
- open_jobs_feed_screen.dart:929-940 _friendlySubmitError() translates permission-denied/network to plain English.
- admin_dashboard_screen.dart:4482-4493 _deleteUser logs full detail to debugPrint, shows only fixed friendly string.

But same file and majority of rest of app do the opposite dozens of times — raw '$e'/e.toString() interpolated directly into showErrorSnackbar/Text/SnackBar. Recurs ~70+ times across the app. Representative sites:
- job_detail_screen.dart:44,702,715,735,981,993,1894,1907
- wallet_screen.dart:60,149; payment_screen.dart:50,330; payment_webview_screen.dart:81
- my_chats_screen.dart:142,184,480; review_screen.dart:46,72,241; dispute_screen.dart:52,336
- verification_upload_screen.dart:140,163; open_jobs_feed_screen.dart:90,951; portfolio_manager_screen.dart:63,76,97,106; portfolio_project_screen.dart:84,117
- settings_screen.dart:375,405,438,470,841,938,1058; bank_details_screen.dart:119; business_profile_screen.dart:99; artisan_registration_screen.dart:96; role_selection_screen.dart:38
- notifications_screen.dart:91,160; contact_support_screen.dart:62; artisan_dashboard_screen.dart:133; artisan_list_screen.dart:47

Concrete scenario: customer on spotty connection taps "Accept Quote," Firestore rules reject write mid-transaction; job_detail_screen.dart:702 shows "Could not accept quote: [cloud_firestore/permission-denied] Missing or insufficient permissions." verbatim in a snackbar. Directly violates "users never see Firebase internal codes." lib/widgets/error_snackbar.dart::showErrorSnackbar does no sanitization itself — fix has to happen per call site or via shared friendlyMessage(Object e) helper used everywhere. P1 on payment/escrow/dispute flows (real money/trust involved), P2 elsewhere.

## 11. TODO/FIXME/HACK/XXX
None found in lib/ (zero grep matches). Long inline design-rationale comments referencing design/*.md docs instead.

## 12. Hardcoded/demo/simulated paths that could reach production

- **[P2]** lib/core/services/payment_service.dart::simulatePayment and lib/providers/payment_provider.dart::simulatePaymentProvider — full fake-Paystack payment path writing PaymentStatus.escrowHeld and calling JobService.lockEscrow directly, with NO kDebugMode gate at all (unlike the carefully-gated DemoEscrowScreen/payment_screen.dart:323 path). Currently dead code (simulatePaymentProvider not referenced from any screen) but a live landmine if ever wired to a button in a release build — escrow would appear locked with zero real money movement. Recommend deleting or adding kDebugMode guard.
- **[P3]** lib/core/services/escrow_service.dart — entire second, older write-layer for job transitions, completely unreferenced. Duplicates JobService's state machine but WITHOUT audit-log write, updateVersion/optimistic-concurrency fields, and with a different (previously-buggy per job_service.dart's own comments) auto-release timing: 7-day autoReleaseAt at escrow-lock time vs current fixed 14-day window at submission time in JobService. Dead code today but risk of accidental reintroduction of a fixed timing bug if anyone re-wires a screen to it. Recommend deletion.
- **[P3]** lib/core/services/admin_audit_log_service.dart — unused duplicate of admin_audit_service.dart. Also serializes action.name directly rather than action.toJsonValue() — if used, AdminAction.betaTesterChanged would log as "betaTesterChanged" instead of expected "beta_tester_changed".
- demo_escrow_screen.dart:114 and payment_screen.dart:323 — the actually-wired demo path is exemplary defense-in-depth (double-gated: caller checks kDebugMode before navigating, destination re-checks kDebugMode against direct/deep-link access). No issue — positive contrast to ungated PaymentService.simulatePayment above.

## Other notable pattern: ImagePicker calls outside try/catch (P2, recurring)

Several screens call ImagePicker().pickImage(...) (or .readAsBytes()) BEFORE entering their try block, so a PlatformException from the picker itself (camera unavailable, permission denied) is unhandled, propagates as uncaught exception from a gesture callback — no user feedback, silently no-op button. Exact bug class verification_upload_screen.dart was explicitly hardened against (comments at lines 84-100/118-123), but fix not applied consistently elsewhere:
- job_completion_screen.dart:215-217 — _pickImage: ImagePicker().pickImage(...) called before try.
- portfolio_manager_screen.dart:52-56 — _addPhoto: same pattern.
- settings_screen.dart:424-428 — _pickAndUploadPhoto: same pattern.

Concrete scenario: artisan taps "Add Photo" with photo-library permission revoked; pickImage throws instead of returning null; nothing happens, no error shown, artisan assumes tap didn't register, retries repeatedly.

---

### Summary by severity
- **P0:** 1 (forgot-password false success state)
- **P1:** raw-error-to-user pattern on payment/escrow/dispute flows (category 10 subset)
- **P2:** raw-error-to-user pattern elsewhere (category 10 bulk); silent review-rating swallow; ImagePicker-outside-try/catch (3 screens); ungated simulatePayment dead code; paystack_service unguarded response cast
- **P3:** dead-code duplicates (EscrowService, AdminAuditLogService); minor `!` unwraps in auth/profile services; safe_firestore's permission-denied-looks-like-empty tradeoff (documented, intentional)

Files most relevant to follow-up: lib/screens/auth/forgot_password_screen.dart, lib/providers/auth_provider.dart, lib/widgets/error_snackbar.dart (needs shared sanitizer), lib/screens/review/review_screen.dart, lib/core/services/payment_service.dart, lib/core/services/escrow_service.dart, lib/core/services/admin_audit_log_service.dart, lib/screens/job/job_completion_screen.dart, lib/screens/artisan/portfolio_manager_screen.dart, lib/screens/settings/settings_screen.dart.
