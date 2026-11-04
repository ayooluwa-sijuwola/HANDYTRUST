# HandyTrust — Full Production QA Audit

**Audit date:** 2026-08-17
**Scope:** Entire Flutter app (mobile + web) + Cloud Functions + Firestore/Storage rules, against the live production Firebase project `handytrust` (no emulator/staging environment exists for this project).
**Method:** (1) Static code audit across 6 parallel deep-dives (feature/route inventory, Cloud Functions, navigation/routing, error-handling sweep, payment/escrow pipeline trace, Firestore/Storage security rules). (2) `flutter analyze` / `flutter test` / `flutter build web`. (3) Live browser testing (Playwright driving the release `flutter build web` output via Flutter's accessibility-semantics DOM tree) against real production Firebase Auth/Firestore, using disposable test accounts.

**Labeling convention used throughout, per audit instructions:**
- **CONFIRMED LIVE** — reproduced against the running app + real production Firebase in this session, with a screenshot/log captured.
- **CODE-LEVEL ONLY** — verified by reading the source (rules, Dart, Cloud Functions) but not executed/reproduced live in this session.
- **INFRASTRUCTURE BLOCKED** — code is correct/deployable but currently inert because of Spark-plan Cloud Functions, undeployed functions, or unprovisioned/unconfirmed external config. Not counted as a code defect.
- **UNABLE TO VERIFY** — could not be confirmed either way in this session (e.g., requires production Paystack account settings, or requires spending down a real rate limiter).

No application code, Firestore/Storage rules, Cloud Functions, or business logic were modified during this audit. Two disposable test accounts were created against the real `handytrust` Firebase Auth (customer: `dannyrotimi11+htaudit1@gmail.com`, artisan: `dannyrotimi11+htaudit2@gmail.com`) with the user's explicit approval; no real payment/escrow transaction was executed.

---

## REMEDIATION ADDENDUM (2026-08-17) — read this before acting on the P0 findings below

**The three P0-1 findings in §2 (Firestore rules gaps enabling a fabricated/duplicated escrow payout) and the P0-4/P0-5 findings (`/portfolio-project` crash, forgot-password false success) have since been analyzed in detail and remediated.** See:
- `design/P0_REMEDIATION_PLAN.md` §1-12 — the full pre-implementation root-cause analysis (including two refinements to the original P0-1 finding discovered during that deeper investigation, which made the actual exploit surface *larger* than described below — no real payment or `escrowLocked` step was even required).
- `design/P0_REMEDIATION_PLAN.md` §13 — the implementation record: exact files changed, a new 26-case Firestore Rules emulator test suite (new test infrastructure — none existed at the time of this audit), a new 19-case Cloud Functions unit test suite, and full `flutter analyze`/`test`/`build web` results, all passing.

**The findings in §2, §3, and §5 of this document below are left exactly as originally written** (per instruction, historical findings are not rewritten) — they remain an accurate record of what this audit found and how, at the time it was performed. They should now be read as **describing a vulnerability that has since been fixed**, not the current state of the code. Do not re-derive a fix from this document without also reading `design/P0_REMEDIATION_PLAN.md` §13, since the actual root cause (per that deeper investigation) was more subtle than this document's original P0-1 write-up alone conveys.

**Still true and unchanged by the remediation:** the live-testing gaps in §8 (customer/artisan/admin authenticated workflows, real payment/escrow pipeline) remain outstanding — remediating the P0 rules/code issues did not itself constitute the live authenticated testing pass this audit was unable to complete. Cloud Functions remain undeployed (Spark plan); no live or test-mode Paystack transaction has occurred at any point across either this audit or the remediation work. The refund/cancellation-after-payment architecture gap discovered during remediation planning also remains unaddressed by design, pending a separate design phase.

---

## 0. Executive summary

The application is unusually well-engineered for its stage — the job/quote/escrow state machine, Cloud Functions idempotency patterns, and most error handling show real prior hardening work (multiple `design/*.md` audit docs in the repo corroborate this history). However, this audit found **three P0 Firestore-rules gaps that would allow a customer to fabricate a fully-paid escrow and receive a real Paystack payout without ever paying**, found independently by two separate investigation paths (rules-first and payment-pipeline-first), which gives high confidence this is real. These are **not yet live-exploitable for real money** only because all 15 Cloud Functions are currently undeployed (Spark plan) — confirmed directly via `firebase functions:list` against the live project. They **must** be fixed before Cloud Functions or live Paystack keys go live.

---

**Note on finding format:** Per the audit brief, P0 and P1 findings below use the full required template (Finding/Severity/Category/Screen-Feature/Repro/Expected/Actual/Root Cause/Evidence/Affected Users/Production Risk/Recommended Fix/Dependencies/Verification Required). P2/P3 findings (higher volume, lower individual stakes) use a condensed one-block form that still carries every one of those fields, just without repeating the field labels, to keep the document navigable — noted here explicitly rather than silently doing it.

---

## 1. Feature inventory

See Appendix A for the full route table, screen inventory, services, and providers. Summary: HandyTrust is a Flutter app (mobile + Flutter Web, go_router, Riverpod, Firebase) connecting Customers and Artisans through a job→quote→agreement→payment→escrow→work→completion→review lifecycle, with a separate Admin back-office (11 sections in one shell route) and a Beta Tester mechanism (a Firestore boolean + admin toggle/filter inside the Users/Artisans admin tab — **not** a standalone admin section, correcting an initial inventory note that missed it; confirmed via `admin_dashboard_screen.dart` lines 2745-4260 and corroborated by the passing `artisan_eligibility_test.dart` / `admin_audit_log_test.dart` test suites).

---

## 2. P0 — Critical

### P0-1: Duplicate/conflicting `escrow_releases` Firestore rule blocks allow a fabricated or duplicated real payout

**[REMEDIATED 2026-08-17 — see design/P0_REMEDIATION_PLAN.md §13 for the exact fix and test results. Finding text below is preserved unchanged as the original historical record.]**

**Severity:** P0
**Category:** Security / Payment-Escrow / Fund Safety
**Screen/Feature:** Escrow release & payout pipeline (backend rules + `processEscrowRelease` Cloud Function)
**Exact Reproduction Steps:**
1. As an authenticated customer, create a job and move it to `paymentPending` (or beyond) through normal negotiation.
2. Via the Firestore client SDK directly (not through the app UI), write a new document to `escrow_releases/{anyRandomId}` (an ID that is **not** equal to the job's ID) with `{ jobId, status: 'pending', requestedAt: now, requestedBy: self }`.
3. This write is accepted because `firestore.rules` defines **two separate `match /escrow_releases/{...}` blocks** for the same collection: the intended one at lines 443-450 (`allow create: if ... releaseId == jobId && status=='pending'`) and a second, looser leftover block at lines 514-521 (`allow create: if isSignedIn() && jobExists(jobId) && customerId==auth.uid` — no `releaseId==jobId` constraint, no `status` constraint). Firestore ORs all matching `match` blocks for a path, so the union of permissions applies — the looser block wins for any write the stricter block would have rejected.
4. `processEscrowRelease` (a Firestore `onDocumentCreated` trigger on `escrow_releases/{releaseId}`, `functions/index.js:395-524`) fires on **any** new document in the collection regardless of ID, checks only that `job.artisanId` exists, and derives the payout amount by looking up a `payments` doc for that `jobId` — falling back to `job.agreedAmount` if none exists (`:435-440`) — with **no check that any real payment was ever captured**.
5. A second exploit variant: because block 2 doesn't enforce `releaseId==jobId`, a customer can create a **second** `escrow_releases` document for a job that already has a legitimate one, producing two independent real Paystack transfers for a single job.

**Expected Behavior:** Only a server-side, Admin-SDK-executed process (after a real, verified Paystack charge) should ever be able to create a valid `escrow_releases` document, and exactly one per job, ever.
**Actual Behavior:** Any authenticated customer can create an escrow-release document for their own job with no real payment behind it, or a duplicate one for an already-paid job, directly via the Firestore SDK — bypassing the app UI entirely.
**Root Cause:** Two non-exclusive `match /escrow_releases/{...}` blocks exist in `firestore.rules` (443-450 and 514-521); the second appears to be an un-cleaned-up leftover — the first block's own comment ("Previously had no match block at all... Made explicit here", per `design/PAYMENT_SAFETY_HARDENING_REPORT.md` Task 5) strongly suggests its author was unaware the second block already existed elsewhere in the file. Confirmed live-app-native, not purely theoretical: `lib/core/services/escrow_service.dart:105` (`EscrowService.confirmComplete`, dead UI code but not blocked by rules) uses the exact auto-generated-ID write shape that only the loose block permits.
**Evidence:** `firestore.rules:443-450` vs `firestore.rules:514-521`; `functions/index.js:395-524` (`processEscrowRelease`); `lib/core/services/escrow_service.dart:102-110`. Independently found by two separate audit passes (rules-first and payment-pipeline-first) — see `05_payment_escrow_audit.md` Finding 1/2 and `06_security_audit.md` Finding 1/2 in the audit working files.
**Affected Users:** All customers (as the attacker), the platform itself (as the financial victim — real Paystack balance drained), and indirectly artisans (whose accounts could be used, wittingly or not, as the receiving end).
**Production Risk:** Direct, real financial loss once Cloud Functions are deployed and live Paystack keys are configured. This is the single most severe finding in the audit.
**Recommended Fix:** Delete the second `match /escrow_releases/{id}` block (`firestore.rules:514-521`) entirely, folding its `read: isAdmin()` into the first block if that read access is still wanted. Do not apply this fix during the audit — documented here for the follow-up remediation phase.
**Dependencies:** None — this is a rules-only fix, deployable independent of Cloud Functions/Blaze status.
**Verification Required:** CODE-LEVEL ONLY. The Firestore rules-OR-semantics behavior is standard, documented platform behavior, not something executed against production in this audit (exploiting it live was explicitly out of scope). Recommend confirming with the Firebase Rules Playground or Firestore emulator before remediation, and adding a rules-unit-test regression guard afterward (the repo already has a `test/` convention for this kind of contract test, e.g. `artisan_eligibility_test.dart`).

---

### P0-2: `payments` collection create rule has no ownership, amount, or job-linkage validation

**[REMEDIATED 2026-08-17 — see design/P0_REMEDIATION_PLAN.md §13 for the exact fix and test results. Finding text below is preserved unchanged as the original historical record.]**

**Severity:** P0
**Category:** Security / Payment-Escrow / Fund Safety
**Screen/Feature:** Payment initiation (backend rules)
**Exact Reproduction Steps:** Any signed-in, non-anonymous user calls `payments.add({ payerId: self, jobId: <any job's ID>, artisanId: <any artisan>, amount: <any number>, status: 'escrowHeld' })` directly via the Firestore SDK. `firestore.rules:409-420` accepts this as long as `payerId == request.auth.uid` and `status` is `'pending'` or `'escrowHeld'` — it does not check that the caller is that job's actual customer, nor validate `amount` against anything, nor require `artisanId` to match the job.
**Expected Behavior:** A `payments` document with `status: 'escrowHeld'` should only ever be creatable by server-side code after a real, Paystack-verified charge for that specific job and customer.
**Actual Behavior:** Any authenticated user can plant a `payments` document for any job with an arbitrary amount, immediately in `escrowHeld` status, with zero payment having occurred.
**Root Cause:** `firestore.rules:409-420`'s `payments` create rule omits the `getJob(jobId).customerId == request.auth.uid` ownership check that the parallel `escrow_releases` block 1 (correctly) has, and allows `status: 'escrowHeld'` — a value that should be unreachable client-side — on create.
**Evidence:** `firestore.rules:409-420`. Corroborated live-app-native by `lib/core/services/payment_service.dart:15-42` (`PaymentService.simulatePayment`), which performs exactly this write shape (only reachable in-app behind `kDebugMode`, but the rules impose no such restriction on a raw SDK call).
**Affected Users:** Same as P0-1 — this finding compounds it, since `processEscrowRelease`'s amount lookup (`functions/index.js:435-440`) queries `payments` by `jobId` alone with no `status`/`payerId` filter, meaning a planted `payments` doc directly controls the payout amount P0-1 fires.
**Production Risk:** Same as P0-1 — real financial loss once Functions are deployed.
**Recommended Fix:** Add `getJob(request.resource.data.jobId).customerId == request.auth.uid` to the `payments` create rule, and restrict `status: 'escrowHeld'` on create to `isAdmin()` (or forbid it entirely on create, requiring a subsequent server-side `update`, since only Cloud Functions should ever set that value).
**Dependencies:** None — rules-only fix.
**Verification Required:** CODE-LEVEL ONLY, not executed against production.

---

### P0-3: Customer can self-transition their own job from `paymentPending` to `escrowLocked` directly via Firestore, bypassing Paystack entirely

**[REMEDIATED 2026-08-17 — see design/P0_REMEDIATION_PLAN.md §13 for the exact fix and test results. Finding text below is preserved unchanged as the original historical record.]**

**Severity:** P0
**Category:** Security / Payment-Escrow / Job State Machine
**Screen/Feature:** Job lifecycle (backend rules)
**Exact Reproduction Steps:** Customer's job reaches `paymentPending`. Via the Firestore SDK directly, the customer writes `jobs/{id}.update({ status: 'escrowLocked', paymentReference: '<anything>' })`. `firestore.rules:395`'s `_isValidJobTransition` allows this transition for `isAdmin() || isCust` with no further field constraint — the same transition that `_lockEscrow` (`functions/index.js:127-170`) is supposed to gate behind a real, verified Paystack charge.
**Expected Behavior:** Only the Paystack webhook / `verifyPayment` Cloud Function (both server-side, Admin SDK, which bypasses rules) should ever be able to move a job into `escrowLocked`.
**Actual Behavior:** The job's own customer can perform this transition directly, with a fabricated `paymentReference` and zero real payment. Downstream `startWork`/`submitCompletion`/`confirmComplete` transitions then proceed exactly as if payment had happened, eventually triggering a real payout via `processEscrowRelease` (once deployed) through the legitimate `confirmComplete` path — no need to even combine this with P0-1/P0-2.
**Root Cause:** `firestore.rules:395` grants the `paymentPending → escrowLocked` transition to `isCust` in addition to `isAdmin()`, when it should be admin(Cloud-Function-via-Admin-SDK)-only. `JobService.lockEscrow` (`lib/core/services/job_service.dart:479-486`) and `EscrowNotifier.lockEscrow` (`lib/providers/escrow_provider.dart:119-123`) are live Dart methods that perform exactly this write; the shipped app only calls them from the `kDebugMode`-gated demo path today, but **the security boundary is the Firestore rule, not which app screens currently call it** — a modified client or a direct SDK/REST call using a legitimate customer's ID token bypasses the app entirely.
**Evidence:** `firestore.rules:395` (`_isValidJobTransition`); `functions/index.js:127-170` (`_lockEscrow`, the transition this rule was supposed to reserve for); `lib/core/services/job_service.dart:479-486`; `lib/providers/escrow_provider.dart:119-123`.
**Affected Users:** All customers (as attacker); the platform (financial loss); also creates a secondary failure mode — if the real customer *does* pay for real after a fake client-side lock already changed the status, `_lockEscrow`'s transaction throws (`functions/index.js:140-143`, "Cannot lock escrow: job is in state escrowLocked"), the webhook returns HTTP 500, and the real successful charge is **never reconciled to the job** — money captured for real, escrow never reflects it, with only a `console.error` line and no `admin_alerts` entry.
**Production Risk:** Real financial loss once Functions/live Paystack keys are active; independently a data-integrity bug (silently un-reconciled real charges) even without malicious intent.
**Recommended Fix:** Remove `isCust` from the `paymentPending → escrowLocked` branch in `firestore.rules:395`; restrict to `isAdmin()` only (Cloud Functions use the Admin SDK, which bypasses rules regardless, so this doesn't block the legitimate webhook path).
**Dependencies:** None — rules-only fix. Should be fixed together with P0-1/P0-2 since they share the same root pattern (rules trusting client-asserted payment/escrow state).
**Verification Required:** CODE-LEVEL ONLY, not executed against production.

---

### P0-4: `/portfolio-project` route crashes outright on any direct/deep navigation (browser refresh, bookmark, back/forward restore)

**[REMEDIATED 2026-08-17 — see design/P0_REMEDIATION_PLAN.md §13 for the exact fix and test results. Finding text below is preserved unchanged as the original historical record.]**

**Severity:** P0
**Category:** Runtime Crash / Navigation / Flutter Web
**Screen/Feature:** Artisan → Portfolio → Add/Edit Project (`/portfolio-project`)
**Exact Reproduction Steps:** As an artisan, navigate to Portfolio Manager, tap "Add Project" (pushes `/portfolio-project` with a Dart-object payload via `extra:`). Then hit browser refresh (Flutter Web), or open the URL directly/from a bookmark, or trigger a browser back/forward history restore to that entry.
**Expected Behavior:** Screen loads normally, or at minimum shows a graceful "can't open this directly" state.
**Actual Behavior:** Hard crash. `router.dart:383-392` does `artisanId: extra['artisanId'] as String` where `extra` becomes `{}` when `state.extra` is null (true on any direct/refreshed navigation) — `null as String` throws `type 'Null' is not a subtype of type 'String'` synchronously during `build()`, uncaught.
**Root Cause:** The route carries its entire payload via `extra:` with zero path parameters, and does a non-nullable cast with no fallback, unlike every sibling route in the same file which defaults to `''`/`null`.
**Evidence:** `router.dart:383-392`; `lib/screens/artisan/portfolio_project_screen.dart:19` (`required this.artisanId`, non-nullable); reachable in-app via `portfolio_manager_screen.dart:238,325`.
**Affected Users:** Any artisan who refreshes the browser while on this screen (Flutter Web only — this specific crash mode doesn't apply to mobile, which has no browser refresh, but the underlying `extra`-only pattern is a Web-specific landmine).
**Production Risk:** Crash/red-screen for a legitimate, common browser action on the web build. Not a security or financial issue, but a real reliability defect matching exactly the class of bug this audit was scoped to catch ("Android must NEVER... Flutter Web must correctly...").
**Recommended Fix:** Encode `artisanId` as a path/query parameter instead of `extra`, or add a null-safe fallback with a "can't open this link directly" empty state, consistent with how `/artisans/:jobId`, `/artisan/:uid`, etc. already degrade gracefully in the same file.
**Dependencies:** None.
**Verification Required:** CODE-LEVEL ONLY in this pass — not yet reproduced live (requires an authenticated, verified artisan session, which was pending user email verification at time of writing; recommend a follow-up live pass once an artisan test account is available).

---

### P0-5: Forgot-password flow shows a false "email sent" success state on any `FirebaseAuthException`

**[REMEDIATED 2026-08-17 — see design/P0_REMEDIATION_PLAN.md §13 for the exact fix and test results. Finding text below is preserved unchanged as the original historical record.]**

**Severity:** P0
**Category:** Error Handling / False Success State
**Screen/Feature:** Forgot Password (`/forgot-password`)
**Exact Reproduction Steps:** Trigger any `FirebaseAuthException` during password reset — e.g. rate-limiting (`auth/too-many-requests`) from repeated requests, or any other Firebase-side rejection.
**Expected Behavior:** If the reset email could not actually be sent, the user should see an error, not a success confirmation.
**Actual Behavior:** The screen always shows "Check your inbox — we sent a password reset link" once the awaited call returns without an *uncaught* exception — and it never will throw uncaught, because `AuthNotifier.sendPasswordReset` (`lib/providers/auth_provider.dart:94-102`) catches `FirebaseAuthException` internally, stores it in its own Riverpod state, and does **not rethrow**. `ForgotPasswordScreen` (`lib/screens/auth/forgot_password_screen.dart:36-46`) never watches `authNotifierProvider` or checks `.error` after the `await` — it just proceeds to `setState(() => _sent = true)` unconditionally.
**Root Cause:** Two-layer swallow: the notifier eats the exception without rethrowing, and the screen doesn't check provider error state as a fallback.
**Evidence:** `lib/screens/auth/forgot_password_screen.dart:36-46`; `lib/providers/auth_provider.dart:94-102`.
**Affected Users:** Any user who hits a real Firebase-side rejection while requesting a password reset — most plausibly a user who taps the button multiple times (rate-limited) or an account in an edge-case Auth state.
**Production Risk:** User is told their password reset is on the way when it is not, and has no way to discover this — they simply wait for an email that never arrives, with no recovery path surfaced (not even a "try again" prompt, since the screen believes it already succeeded).
**Recommended Fix:** One-line fix: either rethrow in the notifier, or have the screen watch `authNotifierProvider` and check `.error` after the await before setting `_sent = true`.
**Dependencies:** None.
**Verification Required:** **CONFIRMED LIVE (partial)** — the happy-path success-screen trigger mechanism was reproduced exactly as predicted (see Live Testing section, `07_live_auth_testing.md` item 8): the screen transitions to "success" purely because the call didn't throw *uncaught*, with no check of error state. Forcing the specific `too-many-requests` failure path live would require ~15-20 rapid requests against production Firebase Auth's real rate limiter, which was deliberately not attempted in this session to avoid abuse-flagging the real project. The code path itself is unambiguous (no conditional logic, a direct catch-without-rethrow), so confidence is high despite not forcing the failure branch live.

---

## 3. P1 — High

### P1-1: FCM push-notification deep links are broken — wrong Navigator API for a go_router app

**Severity:** P1
**Category:** Navigation / Notifications
**Screen/Feature:** Push notification tap → deep link into job/chat
**Exact Reproduction Steps:** Tap a push notification for a job update while the app is backgrounded, or cold-launch the app from a notification tap.
**Expected Behavior:** App navigates to the relevant job/chat screen.
**Actual Behavior:** `lib/providers/notification_provider.dart:107` and `:125` call `Navigator.of(ctx).pushNamed(route)`, but the app boots via `MaterialApp.router(routerConfig: router)` (go_router) with no `onGenerateRoute`/named-routes table anywhere in the codebase. Calling `.pushNamed()` on go_router's internally-managed Navigator throws instead of navigating — silently for the backgrounded case (thrown inside a `postFrameCallback`, becomes an uncaught Flutter framework error with no user-visible feedback), and the cold-launch case (`getInitialMessage`, lines 96-112) isn't even wrapped in a try/catch.
**Root Cause:** Mismatched navigation API — the notification handler was written against `Navigator.pushNamed` conventions that don't apply to this app's go_router setup.
**Evidence:** `lib/providers/notification_provider.dart:107,125`; `lib/main.dart:73-79` (confirms `MaterialApp.router`, no named routes).
**Affected Users:** All users who tap a push notification, on any platform with FCM (primarily mobile).
**Production Risk:** A core, marketed feature (tap notification → open the relevant job/chat) is silently broken. Not financial/security, but a significant functional gap that would be immediately visible to any real user relying on notifications.
**Recommended Fix:** Replace with `ref.read(routerProvider).go(route)` (or equivalent go_router-native navigation call).
**Dependencies:** None.
**Verification Required:** CODE-LEVEL ONLY — not reproducible in this session (requires a real FCM push delivered to a mobile device or web push subscription; the live-testing environment here was Flutter Web only).

---

### P1-2: `/payment/:jobId/webview` crashes or dead-ends on direct/deep navigation

**Severity:** P1
**Category:** Navigation / Payment / Flutter Web
**Screen/Feature:** Paystack payment webview (`/payment/:jobId/webview`)
**Exact Reproduction Steps:** Refresh the browser (or open a bookmark/typed URL) while on the in-progress Paystack payment webview screen.
**Expected Behavior:** Graceful recovery or a clear "please restart your payment" message.
**Actual Behavior:** `router.dart:258-268` defaults `url` to `''` when `extra` is null (true on direct nav); `payment_webview_screen.dart:39-54` calls `..loadRequest(Uri.parse(widget.url))` in `initState` with no try/catch — an empty string is not a valid absolute URI, so this throws synchronously and uncaught. Even in a build where it didn't throw, the screen has no real recovery: `_retryAfterFailure` (`:96`) just calls `context.pop()`, a no-op/app-exit if this was the first page in the navigation stack (as it would be on direct nav).
**Root Cause:** Same `extra`-only payload pattern as P0-4, applied to a payment-critical screen.
**Evidence:** `router.dart:258-268`; `payment_webview_screen.dart:39-54,96`.
**Affected Users:** Any customer mid-payment who refreshes the browser, or whose Paystack redirect lands back on a URL the browser treats as a fresh load.
**Production Risk:** Crash/dead-end during an active payment attempt — high user-trust impact even though no money is lost by this bug specifically (the underlying Paystack transaction state lives server-side).
**Recommended Fix:** Encode `url`/`reference` as query params, or show a clear "resume payment" / "start over" state instead of attempting `Uri.parse('')`.
**Dependencies:** None.
**Verification Required:** CODE-LEVEL ONLY.

---

### P1-3: Every Cloud Functions `onCall` throws plain `Error`, discarding all custom validation messages before they reach the client

**Severity:** P1
**Category:** Error Handling / Cloud Functions
**Screen/Feature:** Payment initialization, payment verification, AI job analysis, admin user deletion (all `onCall` functions)
**Exact Reproduction Steps:** Trigger any validation failure inside `initializePaystackTransaction`, `verifyPayment`, `analyzeJob`, or `adminDeleteUser` (e.g., submit a job with an invalid/zero amount).
**Expected Behavior:** The client receives the specific, actionable error the function intended to send (e.g., "amount must be a positive number").
**Actual Behavior:** Every one of these functions throws a plain `Error(...)` instead of `functions.https.HttpsError(...)`. The Firebase Functions SDK silently replaces any non-`HttpsError` throw with a generic `{code:'internal', message:'INTERNAL'}` before it reaches the client (confirmed by reading the SDK source itself: `functions/node_modules/firebase-functions/lib/common/providers/https.js:477-480`). `index.js` never imports `HttpsError` (zero grep matches). The client then shows something like "Payment could not be started: [firebase_functions/internal] INTERNAL" — never the real reason. This also breaks `ai_provider.dart`'s carefully-written `_messageForCode(e.code)` switch (lines 82-93), since every code arrives as `'internal'` regardless of the actual cause.
**Root Cause:** Missing use of `HttpsError` throughout `functions/index.js`.
**Evidence:** `functions/index.js:917,921,924` (initializePaystackTransaction); `:981,985,1001` + `_lockEscrow` internal throws at `:138,142` (verifyPayment); `:1040,1047,1050,1089` (analyzeJob); `:1142,1146,1151,1158` (adminDeleteUser); `functions/node_modules/firebase-functions/lib/common/providers/https.js:477-480` (SDK behavior).
**Affected Users:** Any user hitting a validation error on payment initiation, payment verification, AI job-description analysis, or (admin) user deletion.
**Production Risk:** Directly undermines the audit's core error-handling requirement ("users must never see... internal error codes unless genuinely useful") for exactly the flows where a clear message matters most (payment). Also makes support/debugging harder since the real cause is lost.
**Recommended Fix:** Import `HttpsError` from `firebase-functions/v2/https` and use `throw new HttpsError('invalid-argument'|'unauthenticated'|'permission-denied', '<message>')` at each site listed above.
**Dependencies:** None — fixable independent of Blaze/deployment status (though the bug is inert until Functions are actually deployed).
**Verification Required:** CODE-LEVEL ONLY — cannot be live-verified since these functions are currently undeployed (INFRASTRUCTURE BLOCKED, see §6). SDK-replacement behavior confirmed by reading the actual installed SDK source, not assumed.

---

### P1-4: `paystackWebhook` verifies its signature against a re-serialized JSON body instead of the raw request bytes

**Severity:** P1
**Category:** Payment / Webhook Integrity
**Screen/Feature:** Paystack webhook handler (`paystackWebhook`)
**Exact Reproduction Steps:** Not independently forceable without live Paystack traffic; the defect is structural. A legitimate `charge.success` webhook arrives from Paystack.
**Expected Behavior:** Signature verification succeeds for any genuine Paystack webhook payload.
**Actual Behavior:** `functions/index.js:32-35` computes the HMAC over `JSON.stringify(req.body)` — the framework's already-parsed-then-re-serialized JSON object — instead of the original raw bytes Paystack actually signed. `JSON.stringify()` is not guaranteed to byte-match the original payload (key order, whitespace, numeric formatting can differ). If it doesn't match, the function returns HTTP 400 "Invalid signature" and **silently drops a real, successful payment confirmation**, leaving escrow un-locked despite money having been captured, with only a `console.error` line as a trace (no `admin_alerts` entry).
**Root Cause:** Using `req.body` (parsed) instead of `req.rawBody` (the `Buffer` Firebase Functions v2 exposes specifically to avoid this class of bug) for signature verification.
**Evidence:** `functions/index.js:32-35`.
**Affected Users:** Any customer whose real charge happens to produce a body that doesn't round-trip identically through `JSON.stringify` — frequency depends on payload shape, not deterministic.
**Production Risk:** Sits directly in the money path — a dropped webhook means a customer is charged but escrow never locks, with no automatic alerting.
**Recommended Fix:** Use `req.rawBody` instead of `JSON.stringify(req.body)` for the HMAC computation.
**Dependencies:** None.
**Verification Required:** CODE-LEVEL ONLY / UNABLE TO VERIFY live (requires real Paystack webhook traffic against a deployed function to observe an actual mismatch, which is INFRASTRUCTURE BLOCKED today).

---

### P1-5: No idempotency guard on `initializePaystackTransaction` — double-charge scenario has no alerting or auto-refund

**Severity:** P1
**Category:** Payment / Idempotency
**Screen/Feature:** Payment initiation
**Exact Reproduction Steps:** Open two independent payment sessions for the same job (two tabs/devices, or a retried network request after a slow/ambiguous response) and complete both charges.
**Expected Behavior:** Second charge attempt is prevented or automatically refunded/flagged.
**Actual Behavior:** `functions/index.js:913-974` creates a brand-new `payments` document and Paystack transaction reference on every call, with no check for an existing pending/`escrowHeld` payment on the same `jobId`. Client-side, `payment_screen.dart` only disables the button within a single session (`_loading` flag) — doesn't protect against a second device/tab/retried call. The first `charge.success` webhook locks escrow normally; the second's `_lockEscrow` throws (status no longer `paymentPending`), the webhook returns 500, Paystack retries then gives up — leaving the customer double-charged with no automatic refund and no `admin_alerts` record (only `console.error`).
**Root Cause:** Missing an "existing pending payment for this job" guard before creating a new transaction.
**Evidence:** `functions/index.js:913-974`; `payment_screen.dart:29,285,332` (session-only guard).
**Affected Users:** Customers who retry a payment across sessions/devices, or hit a slow/ambiguous network response and retry.
**Production Risk:** Real financial harm to customers (double-charged, no auto-recovery) once live.
**Recommended Fix:** Check for an existing non-terminal `payments` doc for the `jobId` before creating a new transaction; alternatively make `paymentRef` deterministic per job+attempt.
**Dependencies:** None.
**Verification Required:** CODE-LEVEL ONLY.

---

### P1-6: No handling for Paystack transfer OTP-required responses — silent, invisible payout failure if the Paystack account has transfer-OTP enabled

**Severity:** P1 (contingent on an external account setting)
**Category:** Payment / Payout / Failure Handling
**Screen/Feature:** Escrow payout (`processEscrowRelease`)
**Exact Reproduction Steps:** Not independently forceable from this environment — depends on the live Paystack account's "Enable OTP for transfers" setting.
**Expected Behavior:** If a transfer requires OTP finalization, the release should be flagged/handled, not silently stuck.
**Actual Behavior:** `functions/index.js:499-507` only handles `resp.data.data.status === 'success'`, mapping everything else through as-is. If the Paystack account requires OTP, transfer-initiate returns `status: 'otp'`, requiring a follow-up `/transfer/finalize_transfer` call — no code anywhere handles this. `reconcileStuckEscrowReleases` (`:587-606`) only matches `status in ['pending','processing']`, so an `'otp'`-stuck release is **never even flagged** by the reconciliation sweep.
**Root Cause:** Missing handling for one of Paystack's documented transfer-initiate response states.
**Evidence:** `functions/index.js:499-507,587-606`.
**Affected Users:** All artisans awaiting payout, if this Paystack account setting is enabled — every transfer would be affected, not just an edge case.
**Production Risk:** Potentially systemic, invisible payout failure — but entirely contingent on a Paystack dashboard setting this audit could not observe.
**Recommended Fix:** Handle `status:'otp'` explicitly (either disable transfer-OTP at the Paystack account level for programmatic transfers, which is the standard approach for automated payout systems, or implement the finalize-transfer OTP flow); widen `reconcileStuckEscrowReleases`'s status filter to include `'otp'`.
**Dependencies:** Requires checking the live Paystack account's transfer-OTP setting — **INFRASTRUCTURE BLOCKED / UNABLE TO VERIFY** from this environment.
**Verification Required:** UNABLE TO VERIFY — cannot inspect Paystack account configuration from this session.

---

### P1-7: Raw Firebase/Dart exception text shown directly to users on payment, escrow, and dispute screens

**Severity:** P1 (this severity applies specifically to payment/escrow/dispute screens; the same pattern elsewhere is P2, see §4)
**Category:** Error Handling / UX
**Screen/Feature:** Job detail (payment/quote actions), Wallet, Payment, Payment Webview, Dispute
**Exact Reproduction Steps:** Trigger any Firestore/Functions error during a payment-, escrow-, or dispute-related action (e.g., accept a quote while offline or mid a rules rejection).
**Expected Behavior:** A clean, translated message (per the audit's explicit requirement: never raw Firebase codes/package paths).
**Actual Behavior:** Raw `'$e'`/`e.toString()` is interpolated directly into `showErrorSnackbar`/`Text`/`SnackBar` content at, e.g., `job_detail_screen.dart:44,702,715,735,981,993,1894,1907`, `wallet_screen.dart:60,149`, `payment_screen.dart:50,330`, `payment_webview_screen.dart:81`, `dispute_screen.dart:52,336`. Concrete example: a customer with a flaky connection tapping "Accept Quote" and hitting a Firestore rules rejection mid-transaction would see "Could not accept quote: [cloud_firestore/permission-denied] Missing or insufficient permissions." verbatim in a snackbar. The app clearly knows the correct pattern — `auth_service.dart::friendlyError`, `open_jobs_feed_screen.dart:929-940`'s `_friendlySubmitError()`, and `admin_dashboard_screen.dart:4482-4493`'s `_deleteUser` all do it right — it just isn't applied consistently to the highest-stakes screens.
**Root Cause:** `lib/widgets/error_snackbar.dart::showErrorSnackbar` performs no sanitization itself; each of ~70+ call sites across the app independently decides whether to pass a friendly string or the raw exception, and most on payment/dispute screens pass the raw one.
**Evidence:** File:line list above; `lib/widgets/error_snackbar.dart` (no sanitization).
**Affected Users:** Any user hitting a Firestore/Functions error during payment or dispute actions.
**Production Risk:** Directly violates an explicit, named requirement of this audit ("users must never see Dart stack traces... Firebase internal codes"), on the highest-trust-sensitivity screens in the app.
**Recommended Fix:** Introduce a shared `friendlyMessage(Object e)` helper (extending the existing `AuthService.friendlyError`/`_friendlySubmitError` patterns to cover `FirebaseException`/`FirebaseFunctionsException` generally) and use it at every call site, starting with the payment/escrow/dispute screens listed above.
**Dependencies:** None.
**Verification Required:** CODE-LEVEL ONLY in this pass — live reproduction requires an authenticated session mid-job-workflow, pending test account verification.

---

## 4. P2 — Medium

Condensed format: **Finding / Screen / Repro & Impact / Evidence / Fix / Verification.**

**P2-1 — Duplicate real Cloud Function write-layers create a reintroduction risk for a previously-fixed payout-timing bug.** `lib/core/services/escrow_service.dart` is a complete second job-state-machine (confirmed zero call sites anywhere in the app today) that duplicates `JobService` but without its audit-log write or optimistic-concurrency fields, and with a different (7-day, set-at-lock-time) auto-release timing than `JobService`'s current (14-day, set-at-submission-time) fix. If anyone ever wires a screen to `EscrowService` instead of `JobService`, this silently reintroduces a bug `design/PAYOUT_RACE_CONDITION_AUDIT.md` describes as already fixed once. Evidence: `escrow_service.dart:102-110` vs `job_service.dart`. Fix: delete `EscrowService` (dead code, no reason to keep it as a landmine). CODE-LEVEL ONLY.

**P2-2 — `lib/core/services/payment_service.dart::simulatePayment` is an ungated fake-payment path.** Unlike the properly `kDebugMode`-double-gated `DemoEscrowScreen` path, this one has **no debug gate at all** and writes real `escrowHeld` status + calls `JobService.lockEscrow` directly. Currently unreferenced from any screen (dead code today), but a live landmine if ever wired to a button in a release build. Evidence: `payment_service.dart:15-42`. Fix: delete, or add the same `kDebugMode` guard the demo path already has. CODE-LEVEL ONLY.

**P2-3 — Fake reviews can be attributed to any artisan.** `firestore.rules:456-463`'s review-create rule checks the reviewer is the job's real customer and the job is completed, but never checks `artisanId` matches the job's actual artisan, and doesn't bind the doc ID to the job. Any customer with ≥1 completed job can create arbitrary-ID review docs citing that job but pointing `artisanId` at any artisan platform-wide, with any rating/comment — fabricated praise or sabotage reviews for artisans never transacted with. (Note: the companion write to `artisans/{uid}.rating` is correctly blocked by the protected-field list, so this doesn't escalate to score manipulation — but it does mean the client-side rating-aggregation write silently fails via an empty `catch(_){}`, see P2-8.) Evidence: `firestore.rules:456-463`; `review_screen.dart:216`. Fix: require `request.resource.data.artisanId == getJob(jobId).artisanId` and bind doc ID to `jobId`. CODE-LEVEL ONLY.

**P2-4 — Job photos and dispute evidence in Storage are readable by any authenticated user, not just the involved parties.** `storage.rules:24-29` (`jobs/{jobId}/{uid}/**`) and `:62-67` (`disputes/{disputeId}/{uid}/**`) both gate reads on `isSignedIn()` only. Firestore's own `jobs`/`disputes` collections correctly scope reads to parties+admin; Storage doesn't mirror that for personal/sensitive images (home interiors, dispute evidence). Exposure is mitigated by auto-ID unguessability but is exactly the over-broad "any authenticated user" pattern this audit was asked to hunt for. Fix: scope reads to job/dispute parties + admin, matching the Firestore rules. CODE-LEVEL ONLY.

**P2-5 — Admin data tables render the desktop column layout on wide Android devices instead of the mobile card layout.** `admin_data_table.dart:114`'s `narrow` breakpoint check is missing the `kIsWeb &&` guard every other responsive check in the codebase correctly uses (confirmed via `breakpoints.dart:46,53,57` and sibling admin components). On Android at width ≥640px (landscape phones, larger devices), this flips to the desktop table layout meant only for web. This is precisely the failure mode named in the audit brief ("Android must NEVER accidentally enter a desktop-only layout"), just admin-scoped rather than customer-facing, limiting exposure to internal users. Fix: add `kIsWeb &&` to the check at `admin_data_table.dart:114`. CODE-LEVEL ONLY (not live-tested — requires an admin session and an Android-width viewport).

**P2-6 — `/favorites` is a fully built, functional screen with zero UI entry point.** Route exists (`router.dart:196-200`), `FavoritesScreen` works, and the underlying favorite/unfavorite feature is wired (`artisan_profile_screen.dart:137`), but no button/link anywhere in the app navigates to it — users can save artisans but have no way to view their saved list short of typing the URL. Fix: add a nav entry point (e.g. in the customer home tab or profile menu). CODE-LEVEL ONLY.

**P2-7 — Dual-role "which mode?" interstitial (`/role-select`) is practically unreachable.** `UserModel.activeRole` always defaults to `roles.first` (`user_model.dart:47,89`) so it can never be null, but the router's redirect trigger for showing `/role-select` is exactly "`activeRole` is not explicitly customer/artisan" — a condition that, given the default, essentially never evaluates true. A feature described in the router's own code comments (lines 149-153) doesn't fire for real dual-role users. Fix: either give dual-role users an explicit `null`/"unset" sentinel value distinguishable from a normal default, or remove the dead interstitial and default silently instead. CODE-LEVEL ONLY.

**P2-8 — Artisan rating/trust-score silently fails to update on a transient review-submission error.** `review_screen.dart:247-265`'s `_updateArtisanRating` is wrapped in `catch (_) {}` with a comment "handled by Cloud Function in production" — but the Cloud Function (`onArtisanRatingChanged`) only fires when `rating`/`totalRatings` actually change on the artisan doc; if the client-side transaction throws (offline, transient conflict), the review document itself still saves (customer sees success) but the artisan's public rating is silently never updated for that review, with no retry and no visibility to anyone. Fix: surface/retry this failure rather than silently swallowing it. CODE-LEVEL ONLY.

**P2-9 — `ImagePicker` calls outside their `try/catch` block on three screens** (`job_completion_screen.dart:215-217`, `portfolio_manager_screen.dart:52-56`, `settings_screen.dart:424-428`): a `PlatformException` from the picker itself (camera/permission issues) propagates uncaught from a gesture callback with zero user feedback — the button silently appears to do nothing, and users retry repeatedly. This is exactly the failure mode `verification_upload_screen.dart` was explicitly hardened against elsewhere in the same app, just not applied consistently. Fix: wrap the picker call itself in try/catch, matching the verification-upload screen's existing pattern. CODE-LEVEL ONLY.

**P2-10 — Notification spam/spoofing to arbitrary users.** `firestore.rules:551-563` lets any signed-in user create a `notifications` doc targeting any *other* `userId`, with no relationship/job-party check, as long as `type` is whitelisted and `isRead:false` — title/body content otherwise attacker-controlled. Fix: require the target `userId` to have a real relationship to the sender (shared job, etc.) or restrict notification creation server-side only. CODE-LEVEL ONLY.

**P2-11 — Raw exception text shown to users on non-payment screens** (the bulk of the ~70+ site pattern described in P1-7, outside payment/escrow/dispute): `verification_upload_screen.dart:140,163`, `portfolio_manager_screen.dart:63,76,97,106`, `settings_screen.dart:375,405,438,470,841,938,1058`, `bank_details_screen.dart:119`, `business_profile_screen.dart:99`, `notifications_screen.dart:91,160`, and more (full list in working file `04_error_handling_audit.md`). Same fix as P1-7 (shared `friendlyMessage()` helper), just lower individual stakes per screen. CODE-LEVEL ONLY.

**P2-12 — Suspend/role-select router gates don't distinguish "profile still loading" from "profile genuinely null."** `router.dart:128-134,154-162` treat a null profile the same whether it's mid-load or truly absent (unlike the admin gate at `:142-147`, which explicitly checks `isLoading`). A suspended user can briefly land on `/home` on a cold refresh before being bounced to `/suspended` on the next redirect evaluation. Converges, not an infinite loop, but a real timing gap. Fix: mirror the admin gate's `isLoading` check. CODE-LEVEL ONLY.

**P2-13 — `/chat/:jobId` degrades silently (not a crash) on direct/deep navigation** — `otherUserId` defaults to `''` when reached without `extra`, producing a broken-looking chat header (resolving a counterpart user with an empty ID) rather than a crash. Same root pattern as P0-4/P1-2, lower severity since it doesn't throw. CODE-LEVEL ONLY.

---

## 5. P3 — Low

Compact list — polish, minor visual inconsistencies, dead code, edge cases with graceful degradation.

- **Dead code cleanup candidates** (no user-facing impact, but worth removing to prevent future accidental reintroduction of fixed bugs): `EscrowService` (see P2-1), `lib/core/services/admin_audit_log_service.dart` (unused duplicate of `admin_audit_service.dart`; if ever used, would also mis-serialize `AdminAction.betaTesterChanged` as `betaTesterChanged` instead of the expected `beta_tester_changed`), `ArtisanDashboardScreen` class in `artisan_dashboard_screen.dart:26` (unreachable — only its sibling `ArtisanHomeTabContent` is used), `lib/firebase/auth/auth_repository.dart` / `firebase_auth_service.dart` / `lib/firebase/messaging/icon_service.dart` (empty stub files, 0 lines each), `lib/screens/jobs/` and `lib/screens/payments/` (empty leftover directories from a singular/plural rename), `google_fonts` package in `pubspec.yaml:48` (declared, zero usages anywhere in `lib/`).
- **`/artisans/:jobId`, `/artisan/:uid`, `/demo-payment/:jobId`, `/open-jobs`** all lose their `extra`-carried payload on direct/deep navigation like P0-4/P1-2/P2-13, but all degrade gracefully (nullable defaults) rather than crashing. Fix (low priority): move to query params for correctness. CODE-LEVEL ONLY.
- **Messages `isRead` flag can be toggled by any signed-in user**, not just job parties (`firestore.rules:282-284`, no `isJobParty` check) — minor griefing/integrity issue, no content exposure. CODE-LEVEL ONLY.
- **`artisan_private` (bank details) and `users` writes lack field-level schema validation** (`firestore.rules:110-113`, `:46-66`) — not currently exploitable (no client code trusts an arbitrary extra field for authorization), but a latent defense-in-depth gap for future code. CODE-LEVEL ONLY.
- **Demo escrow screen's payment-triggering `initState` callback has no `kDebugMode` check of its own** (only `build()` does) — currently safe because its only caller is itself debug-gated, but structurally fragile if that changes. CODE-LEVEL ONLY.
- **Minor non-null-assertion risks**, both essentially unreachable in practice: `auth_service.dart:28` (`credential.user!` right after successful account creation), `profile_service.dart:116,132` (`user.email!`, safe today since auth is email/password-only, would NPE if phone/anonymous auth is ever added). CODE-LEVEL ONLY.
- **`lib/core/utils/safe_firestore.dart` intentionally converts stream failures (including `permission-denied`) into empty lists/null** rather than surfacing an error — a documented, deliberate tradeoff, but means a genuine ongoing permission bug (e.g. an admin whose claim was revoked mid-session) is indistinguishable from "no data" in the UI, which could mask a real access bug from support/QA. CODE-LEVEL ONLY, informational.
- **`flutter analyze` — 12 minor issues**, none blocking: 1 unused import (`platform_io.dart`), 1 unnecessary import, 2 uses of a deprecated Flutter API (`FormField.value`, `Geolocator.desiredAccuracy`), 8 `use_build_context_synchronously` lint warnings all in `settings_screen.dart` (guarded by a `mounted` check that the linter flags as "unrelated" to the specific async gap — worth a look but not evidence of an active bug in each case). **CONFIRMED LIVE** (ran directly, see §7).
- **Accessibility: form field accessible names use hint text, not the visible label**, on the login/register screens (`aria-label="name@company.com"` rather than "Email Address") — a screen reader announces the placeholder, not the field's actual label. Minor WCAG polish item, discovered incidentally during live testing. **CONFIRMED LIVE.**

---

## 6. Infrastructure Blockers

These are correct-or-benign in code but currently inert due to external platform/config state — **not counted as code defects** per the audit brief.

**IB-1 — All 15 Cloud Functions are undeployed.** Directly confirmed via a live, read-only `firebase functions:list` against the production `handytrust` project: "No functions found in project handytrust." This is the standard Spark-plan limitation (2nd-gen Cloud Functions categorically require the Blaze plan), applying uniformly regardless of whether a given function makes outbound calls. All function code passed `node --check` (syntax valid) and the Node runtime versions match (`firebase.json`'s `nodejs20` vs `functions/package.json`'s `engines.node: "20"`), so nothing in the code itself blocks deployment once billing is upgraded. **Practical consequence for this audit:** payment initialization/verification, escrow release/payout, admin user deletion, AI job analysis, and all notification-triggering functions cannot be live-tested end-to-end in this session — any attempt to trigger them from the app will surface a Functions "not found"/"unavailable" error, which is itself worth confirming shows a clean message rather than a raw error (see §8, Live Testing).

**IB-2 — `PAYSTACK_SECRET_KEY` and `GEMINI_API_KEY` live values in Secret Manager could not be verified** from this environment (no Secret Manager read access in this session's scope) — a second, independent prerequisite on top of the Blaze upgrade itself before payment functions can actually work once deployed.

**IB-3 — Admin custom claims are never actually granted in practice today.** `onAdminGranted`/`onAdminRevoked` (the functions that mirror the `/admins/{uid}` Firestore doc into a Firebase Auth custom claim) are undeployed (part of IB-1), **and** no in-app UI writes to `/admins/{uid}` at all — granting admin status currently requires a manual Firestore write outside the app (e.g. via Firebase Console). This matters because `firestore.rules`' `isAdmin()` reads the Firestore doc directly (unaffected), but `storage.rules`' `isAdmin()` reads the **custom claim** — so admin-gated Storage operations will silently fail `isAdmin()` even for a real, Firestore-doc-confirmed admin until these functions are deployed and that admin's ID token refreshes.

**IB-4 — Cloud Functions region defaults to `us-central1` while Firestore's actual location is `eur3` (Europe)** — no function specifies an explicit region. Not a blocker, but adds real cross-region latency once deployed; worth setting `region()`/`setGlobalOptions` to match.

**IB-5 — No Firebase Local Emulator Suite is configured for this project** (`firebase.json` has no `emulators` block). All live testing in this audit ran against the real production Firebase project using disposable test accounts, per explicit user approval — there is currently no safe way to test destructive/financial flows without either touching production data or setting one up (which itself requires code changes to point the app at the emulator, out of scope for an audit-only pass).

**IB-6 — Paystack account's "Enable OTP for transfers" setting is unknown** (relevant to P1-6) — cannot be inspected from this environment; must be checked directly in the Paystack dashboard before relying on `processEscrowRelease` for real payouts.

---

## 7. Build / Static Checks — CONFIRMED LIVE (run directly in this session)

- **`flutter analyze`**: 12 issues, 0 errors — 1 warning (unused import), 11 info-level (2 deprecated-API usages, 8 `use_build_context_synchronously` lints in `settings_screen.dart`, 1 unnecessary import). No blockers.
- **`flutter test`**: **85/85 tests passed.** Notably includes dedicated regression-guard suites for the job/escrow state machine (`job_service_agreement_test.dart` — agreement confirmation, payout idempotency, escrow release timing/auto-release-window correctness), artisan eligibility + beta-tester bypass rules (`artisan_eligibility_test.dart`), and admin audit-log/navigation contracts. This is a real, substantive test suite, not placeholder coverage — and it directly corroborates that the *intended* state-machine logic (as implemented in `JobService`/`firestore.rules`' transition function) is internally consistent; it does **not** cover the rules-level bypass findings in P0-1/2/3, since those are Firestore-rules-permissiveness bugs orthogonal to what the Dart-side state machine itself allows.
- **`flutter build web`**: succeeded, output in `build/web`. Only warnings were WASM-compatibility notes (`flutter_secure_storage_web` uses `dart:html`/`dart:js_util`, incompatible with a future `--wasm` build target — not relevant to the current JS-compiled web target, informational only).

## 8. Live Browser Testing — CONFIRMED LIVE (against real production Firebase, this session)

Method: `flutter build web` release output served locally via `serve -s` (mirroring Firebase Hosting's SPA rewrite config), driven with Playwright through Flutter's accessibility-semantics DOM tree (clicking the `flt-semantics-placeholder` node exposes real, interactable `<input>`/ARIA elements). Two disposable test accounts created against the live `handytrust` Firebase Auth project with explicit user approval (customer: `dannyrotimi11+htaudit1@gmail.com`, artisan: `dannyrotimi11+htaudit2@gmail.com`), both still pending the user's manual email-verification click at the time of writing this report.

**CONFIRMED LIVE and working correctly:**
1. Register screen empty-field validation (inline errors, no crash/navigation).
2. Register screen invalid-input validation (malformed email, weak password both blocked client-side).
3. Successful customer signup end-to-end (real Firebase Auth user created, correctly routed to Verify Email screen).
4. Successful artisan signup end-to-end (same, with Artisan role selected).
5. Duplicate-email signup shows a clean "An account with this email already exists." message — no raw error.
6. Wrong-password login shows "Email or password is incorrect."
7. Non-existent-account login shows the **identical** message as wrong-password (good security practice — doesn't leak account existence).
8. Forgot-password happy path: shows "Check your inbox" success screen, confirming the success-trigger mechanism behind P0-5 fires exactly as the code predicts (see P0-5 for the untested failure-path caveat).
9. Session persistence across a hard browser refresh while signed in but unverified — correctly stays on `/verify-email`, does not lose session or bounce to `/login`.
10. Social sign-in buttons (Google/Apple) show a clean "coming soon" message with no crash, no OAuth popup attempt, zero page errors — honestly-labeled unimplemented features, not broken ones.
11. Dark mode renders correctly on Login/Register screens (forced via direct `localStorage` injection of the app's own theme-persistence key, since the in-app toggle lives behind auth) — good contrast, no invisible text/icons, no light-mode leftovers.
12. Responsive layout at 360px/800px/1440px widths on auth screens — correctly centers within a constrained max-width at every size, no overflow/stretching.

**NOT YET LIVE TESTABLE — blocked on pending email verification (user action, in progress) and, separately, on admin-status grant (requires a manual Firestore write per IB-3, no in-app path exists):**
- Customer dashboard, Find Jobs/Browse Artisans, artisan profile view, Post Job flow, job detail lifecycle screen, chat, wallet, notifications, settings, profile, favorites.
- Artisan onboarding step 2, verification upload, bank/payout details, portfolio management, business profile, Find Jobs feed, quote submission.
- Full job state machine walk-through (requested → matched → inChat → paymentPending → escrowLocked → inProgress → submitted → completed) and whether the Dart-level `JobService` guards actually prevent the invalid transitions `firestore.rules` P0-1/2/3 leave open when attempted through the real app UI (as opposed to a raw SDK call, which was not attempted against production per audit rules).
- Payment/escrow screens' behavior against currently-undeployed Cloud Functions (IB-1) — i.e., whether tapping "Pay" surfaces a clean "service unavailable" message or a raw error when `initializePaystackTransaction` doesn't exist server-side. This is a specific, valuable live check once an account is available, since it directly tests the error-handling requirement against a real infrastructure-blocked condition.
- Admin dashboard (all 11 sections), disputes, reviews moderation, support tickets, beta tester toggle, user suspend/delete.
- Reviews, disputes, verification workflows end-to-end.
- Double-tap/race-condition testing on real actions (job submission, quote acceptance, etc.) — requires an authenticated multi-step workflow to reach.

This audit will be updated with a live-testing addendum once account verification is complete, if the user would like that follow-up pass.

---

## 9. Final Release Verdict

### RELEASE BLOCKERS (must fix before any real-money usage)
1. **P0-1, P0-2, P0-3** — the three Firestore-rules gaps that together let a customer fabricate or duplicate a real escrow payout without paying. These are rules-only fixes, deployable independent of Blaze/Functions status, and should be fixed **immediately**, before Cloud Functions are ever deployed to production (once `processEscrowRelease` is live, these become actively exploitable for real money).
2. **P0-4** — `/portfolio-project` crash on direct/deep Flutter Web navigation (reliability, not financial, but a hard crash on ordinary browser use).
3. **P0-5** — forgot-password false-success state (users silently never receive a reset they were told was sent, with no recovery path).

### HIGH-PRIORITY FIXES (before beta/wider testing)
- P1-1 (broken push-notification deep links), P1-2 (`/payment/.../webview` crash on direct nav), P1-3 (Cloud Functions swallow all validation messages via missing `HttpsError`), P1-4 (webhook signature check against re-serialized JSON, money-path risk), P1-5 (no payment-initiation idempotency guard), P1-7 (raw exception text on payment/escrow/dispute screens).
- P1-6 (Paystack transfer-OTP handling) — verify the Paystack account setting first; only a code fix if that setting is (or might be) enabled.

### MEDIUM-PRIORITY FIXES
All of §4 (P2-1 through P2-13) — dead-code landmines, review/notification integrity gaps, Storage over-broad reads, the one ungated Android-admin-table breakpoint, the unreachable `/favorites` and `/role-select` screens, remaining raw-error-text sites, and the profile-loading-vs-null router timing gap.

### UI/POLISH ITEMS
All of §5 (P3) — dead file/dependency cleanup, minor accessibility (aria-label) fix, `flutter analyze`'s 12 low-severity lints, minor `!`-unwrap tidiness, and the documented-intentional `safe_firestore` tradeoff (informational, no action required unless the team wants stricter error surfacing for debugging).

### INFRASTRUCTURE BLOCKERS (not code defects — see §6 for full detail)
- All Cloud Functions undeployed (Spark plan) — IB-1.
- Paystack/Gemini secret values unverified in Secret Manager — IB-2.
- No in-app path to grant admin; Storage-side admin checks will fail until admin claim functions are deployed and tokens refresh — IB-3.
- Functions region/Firestore region mismatch (latency, not correctness) — IB-4.
- No emulator suite configured — IB-5.
- Paystack transfer-OTP account setting unknown — IB-6.

### FEATURES VERIFIED WORKING (CONFIRMED LIVE, this session)
Signup (customer + artisan) with full client-side validation, duplicate-email/wrong-password/non-existent-account error handling, forgot-password happy path, session persistence across refresh, social-login "coming soon" graceful stubs, dark mode on auth screens, responsive layout on auth screens at 3 breakpoints. Plus `flutter analyze`/`test`/`build web` all passing/succeeding.

### FEATURES NOT YET VERIFIABLE
Everything behind email verification and admin-status grant — the full customer job-posting-through-review journey, the full artisan onboarding-through-payout journey, the entire admin dashboard, and — most importantly — **the actual payment/escrow pipeline could not be live-tested at all**, both because Cloud Functions are undeployed (IB-1) and because live testing didn't reach an authenticated session with a job to pay for. This is the single biggest gap in this audit's live-verification coverage, and it's also the highest-stakes area.

### FEATURES THAT FAILED (CONFIRMED LIVE)
None of the live-testable pre-auth flows failed in this session — everything reachable without a verified account worked correctly. The confirmed-broken items in this report (P0-4, P1-1, P1-2, and the rules-level P0-1/2/3) are all CODE-LEVEL ONLY findings pending live confirmation once authenticated access is available.

---

### Answers to the five required questions

**1. Is the app currently safe for internal testing?** Yes, with caveats — internal testers using their own accounts for functional walkthroughs (not touching real payment flows, since Cloud Functions are undeployed and payment can't functionally complete anyway) face low risk. The P0 rules gaps require a deliberate, technically-informed attempt to exploit (raw SDK calls, not something a normal tester stumbles into via the UI) and are financially inert today since no Cloud Function would act on a fabricated `escrow_releases` doc yet.

**2. Is it safe for beta testing?** Not yet, as-is. Before opening to beta testers: fix P0-4 (a crash any web tester will hit via ordinary browser refresh) and P0-5 (silently broken password reset — a real support-burden generator). The P0-1/2/3 rules gaps should also be fixed before beta, even though they're financially inert while Functions are undeployed, because leaving them in place risks someone deploying Functions for an unrelated reason (e.g. to test AI job analysis) and inadvertently making the escrow exploit live without realizing it.

**3. Is it safe for real-money transactions?** **No.** Do not enable live Paystack keys or deploy `processEscrowRelease` until P0-1, P0-2, and P0-3 are fixed and independently verified (rules-playground or emulator test, ideally with a permanent regression test alongside the existing `job_service_agreement_test.dart` suite). Additionally, P1-4 (webhook signature check) and P1-5 (no payment idempotency) should be fixed before real money flows, and P1-6 needs the Paystack OTP setting checked. The payment/escrow pipeline was **not live-verified at all** in this audit (infrastructure-blocked) — that live verification, on a real Blaze-plan project with test-mode Paystack keys, is a mandatory step before going further, independent of the rules fixes.

**4. Is it production-ready?** **No.** Beyond the P0/P1 items above, roughly 70% of the requested live-testing scope (the full customer/artisan/admin authenticated journeys) was not reachable in this session and remains CODE-LEVEL ONLY or NOT YET VERIFIABLE. Production-readiness requires completing that live pass, fixing the P0/P1 findings, and — critically — a genuine end-to-end payment/escrow test against a real (test-mode) Paystack integration on a Blaze-plan project, which cannot happen on the current Spark plan.

**5. What exact issues must be fixed before each stage?**
- **Before internal testing:** nothing strictly blocking; recommended: fix P0-4 and P0-5 first since they're one-line-scale fixes with outsized impact.
- **Before beta testing:** P0-1 through P0-5 all fixed and verified; P1-1 and P1-2 fixed (both are visible, dead-end/crash bugs a beta tester will find quickly).
- **Before real-money transactions:** all P0 findings fixed and independently verified; P1-3 through P1-7 fixed; Paystack account settings (P1-6/IB-6) confirmed; a genuine live payment/escrow/payout test executed end-to-end on a Blaze-plan project with Paystack test-mode keys (not yet done — this audit could not do it, infrastructure-blocked).
- **Before general production release:** the above, plus the P2 medium findings addressed (particularly the security-adjacent ones: P2-3 fake reviews, P2-4 Storage over-read, P2-10 notification spoofing), plus the full live-testing pass of customer/artisan/admin workflows this audit could not complete this session.

---

## Appendix A: Full Working Files

The condensed findings above are drawn from seven detailed working documents, checked into this repo alongside this report at `design/qa_audit_working_files/` — each contains full file:line-level detail, additional minor observations not promoted into the severity buckets above, and (for the security/payment files) longer exploit-chain narratives:
- `01_feature_inventory.md` — full route table, screen inventory, services, providers, dead-code findings.
- `02_cloud_functions_audit.md` — full Cloud Functions inventory table (trigger/caller/auth/secrets/deployment status per function).
- `03_navigation_audit.md` — full navigation/routing findings (redirect-loop analysis, go-vs-push audit, responsive-gating audit).
- `04_error_handling_audit.md` — full error-handling sweep (all 12 categories requested in the audit brief).
- `05_payment_escrow_audit.md` — full payment/escrow pipeline trace (7 findings, idempotency analysis).
- `06_security_audit.md` — full Firestore/Storage rules audit, collection-by-collection.
- `07_live_auth_testing.md` — live pre-auth browser testing detail (screenshots referenced by filename, captured during this session).


