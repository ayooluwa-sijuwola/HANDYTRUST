# Phase 10 — Authenticated Workflow + Paystack Test-Mode Validation

**Date:** 2026-08-17
**Scope:** Complete the authenticated QA the original audit could not reach, and validate the payment architecture against Paystack TEST mode, per the P0 remediation that shipped in `design/P0_REMEDIATION_PLAN.md` §13.

**Headline result: Phase 10A (authenticated customer/artisan/admin workflow QA) and Phase 10C (live Paystack TEST-mode transaction flow) are BLOCKED and were NOT executed**, for reasons re-confirmed live at the start of this phase, not assumed from the task brief:

1. **Neither disposable test account is email-verified.** The task brief stated "the two audit accounts should now be verified" — this was checked live (attempted login as both `dannyrotimi11+htaudit1@gmail.com` and `dannyrotimi11+htaudit2@gmail.com`) and both still land on `/verify-email`, not the app. No authenticated screen — customer, artisan, or admin — is reachable without a verified session; the router redirects any signed-in-but-unverified user to `/verify-email` regardless of destination.
2. **Zero Cloud Functions are deployed to the `handytrust` project**, re-confirmed via a live, read-only `firebase functions:list` → *"No functions found in project handytrust."* This is unchanged from the original audit. `initializePaystackTransaction`, `verifyPayment`, `paystackWebhook`, and `processEscrowRelease` do not exist as callable/reachable endpoints anywhere. There is no staging/test Firebase project available in this environment, and `handytrust` is the only project this work has access to — so deploying anything at all, even nominally "for testing," would mean deploying to the same project the task explicitly forbids deploying to, and would additionally require upgrading it to the Blaze billing plan, a financial/billing action outside this session's authority. Per the task's own explicit stop condition — *"STOP and report if: Paystack TEST mode cannot be safely exercised"* — this phase stops here rather than attempting a workaround, a simulation, or a partial/fabricated result.

Everything in this phase that does **not** depend on those two blockers was completed: the Phase 10B code-level payment-architecture hardening (transaction-initialization idempotency, webhook signature verification), and the full Phase 10D regression suite. These are reported in full below, with real, reproduced results — not assumed ones.

---

## 1. Test environment

- **Firebase project:** `handytrust` (the only project available; no staging/test project exists for this app)
- **Cloud Functions:** 0 deployed (Spark plan; re-confirmed live via `firebase functions:list`)
- **Paystack:** no keys of any kind (test or live) were used, read, or exercised at any point in this phase — there is no reachable endpoint to use them against
- **Test accounts:** `dannyrotimi11+htaudit1@gmail.com` (customer), `dannyrotimi11+htaudit2@gmail.com` (artisan) — both created against real production Firebase Auth in the original audit, **both still email-unverified** as of this phase (re-checked live)
- **Browser/device:** Playwright + Chromium, driving the release `flutter build web` output (rebuilt fresh this phase after the Phase 10B code changes) served locally via `serve -s` (mirrors Firebase Hosting's SPA rewrite behavior), at viewport 480×900
- **Local test infrastructure:** Firestore emulator (port 8090, via `firebase emulators:exec --only firestore`) for the Rules suite and the Cloud Functions idempotency tests; plain `node --test` for the pure-function Cloud Functions tests; `flutter test` for Dart

No secret keys of any kind appear anywhere in this document.

---

## 2. Authenticated workflow results — Phase 10A

| Role | Result |
|---|---|
| Customer | **BLOCKED** — cannot authenticate past `/verify-email`; zero of the requested checks (dashboard, job creation, quotes, chat, payment initiation, escrow status, completion, disputes, portfolio viewing, refresh/deep-link, error handling) were reachable |
| Artisan | **BLOCKED** — same reason |
| Admin | **BLOCKED** — same reason, and additionally: per the original audit's security findings (`design/FULL_PRODUCTION_QA_AUDIT.md`), there is no in-app path to grant admin status at all — it requires a manual Firestore write to `/admins/{uid}` outside the app. Neither test account has ever been granted admin, so admin workflow testing would be blocked by a second, independent gap even if email verification were resolved today. |

**What was reconfirmed instead (pre-auth surface only, no account needed):** the Phase 10D browser regression pass (§5.2) re-exercised login, registration, and forgot-password against the freshly rebuilt post-Phase-10B web app and confirmed no regression — see §5.2 for full detail. This is real, live, reproduced evidence; it is not a substitute for the authenticated workflow QA this phase was scoped to complete, which remains outstanding.

**To unblock:** either (a) verify the two existing test account emails (the user previously agreed to click the links themselves; this has not yet happened), or (b) provide credentials for an already-verified test account, or (c) authorize an alternative verification path. For admin testing specifically, an admin-flagged test account (or the ability to grant one) is additionally required. This phase does not recommend or attempt any workaround (e.g., extracting Firebase CLI tokens to force-verify accounts) — that path was already raised and declined by the classifier/user earlier in this engagement.

---

## 3. Payment results — Phase 10B/10C

### 3.1 What Phase 10C's 10-step live flow would have covered — status of each, honestly

| Step | Status |
|---|---|
| 1. Customer creates job | Not attempted this phase (would require a verified account — see §2) |
| 2. Artisan accepts/quotes | Not attempted (same) |
| 3. Customer initiates payment | **Code-level only** — `initializePaystackTransaction` was rewritten in the P0 pass to derive the charged amount exclusively from `job.agreedAmount` server-side (client `amount` no longer trusted at all — confirmed by reading the current code, `functions/index.js`), and this phase added an idempotency claim (§3.2) verified by unit test. Never exercised through a real HTTP call, because no deployed endpoint exists. |
| 4. Paystack TEST transaction | **BLOCKED** — no deployed function for the client to call, no endpoint for Paystack to reach |
| 5. Payment verification | **BLOCKED**, same reason (`verifyPayment` not deployed) |
| 6. Webhook | **BLOCKED for live delivery** — `paystackWebhook` is not deployed, so Paystack has nothing to call. The **signature-verification logic itself** was fixed and is unit-tested in isolation (§3.3) — this proves the algorithm is now correct, but does not prove the deployed endpoint behaves correctly, since there is no deployed endpoint. |
| 7. Escrow | **BLOCKED** for a live transition; the server-side preconditions `processEscrowRelease` now enforces were proven via the Firestore Rules emulator suite (26/26, unchanged from the P0 pass, re-run this phase — §5.1) and the Cloud Functions unit tests (§5.1) |
| 8. Job completion | Not attempted (requires a verified account) |
| 9. Escrow release | Same rules/function-level coverage as step 7; no live trigger possible |
| 10. Paystack TEST transfer | **BLOCKED** — no deployed function, no Paystack call of any kind was made |

**Bottom line: none of Phase 10C's live, end-to-end Paystack TEST-mode flow was executed.** This is not a partial pass — it is fully blocked by the deployment gap, and no substitute (mocked HTTP layer standing in for a "real" test, a fabricated transaction record, etc.) was used to manufacture a result. The task's own instruction — *"Do not claim a PASS for anything that was not actually tested"* — is being followed literally here: this entire step range is reported as BLOCKED, not PASS, not FAIL.

### 3.2 Transaction initialization idempotency — Phase 10B-1 (implemented and tested, not deployment-dependent)

**Investigation finding:** confirmed by reading the current (post-P0) `initializePaystackTransaction` — every call created a brand-new `payments` document and a fresh Paystack transaction reference, with no check for an existing in-flight or recently-completed attempt for the same job. A double-click, a client retry, a browser refresh-and-resubmit, or two genuinely concurrent requests could each have produced a separate real Paystack transaction for the same job. A Firestore document write alone (e.g. checking `payments` for an existing `pending` row) was explicitly **not** treated as sufficient, per the task's instruction — a plain read-then-write has a race window between two concurrent invocations.

**Fix implemented:** a per-job claim document (`payment_init_locks/{jobId}`, no client-facing Firestore rule at all — written/read exclusively by this Cloud Function under the Admin SDK) coalesces concurrent/duplicate requests via an atomic Firestore transaction:
- The first caller for a job claims the lock and proceeds.
- A caller arriving while a claim is genuinely in-flight polls briefly (bounded, up to 5 seconds total) and then reuses the *same* result once the first caller resolves it — no second Paystack call is made, and no client-visible error occurs for the ordinary double-click/retry case.
- A caller arriving after a completed initialization, within a 30-minute reuse window (matching Paystack's own authorization-URL lifetime), reuses that same result outright.
- A stale, abandoned claim (the prior attempt crashed mid-flight and never resolved) is reclaimed after 60 seconds rather than blocking the job forever.
- On a genuine failure (Paystack call or Firestore write throws), the claim is released immediately so a retry isn't blocked for the full stale window.

**Tests:** `functions/test/payment_init_idempotency.test.js` (new, 5 cases, against the Firestore emulator — no Paystack call involved, this tests the claim/resolve/release primitives directly): first-caller claims; a concurrent second caller waits and then reuses the first caller's result; a caller after a recent completion reuses without waiting; a released claim is immediately reclaimable; two different jobs never contend with each other. **Result: 5/5 passed.**

**What this does NOT prove:** that the full `initializePaystackTransaction` callable — including the real `axios.post` to Paystack — is idempotent end-to-end against a live Paystack endpoint. That requires a deployed function and a reachable Paystack API, both currently unavailable (§0). The claim mechanism itself, which is the actual concurrency-safety primitive, is proven; the function's use of it was verified by code review (the claim is acquired before the `axios.post` and the payments-doc write, and released on failure), not by an end-to-end call.

### 3.3 Paystack webhook HMAC verification — Phase 10B-2 (implemented and tested, not deployment-dependent)

**Investigation, using Paystack's current documentation as the source of truth (fetched live this phase, not recalled from training data):**
> "Every delivery carries an `x-paystack-signature` header: a hex-encoded HMAC-SHA512 of the request body, keyed with your Paystack secret key... you compute the hash over the **raw bytes**, not a re-serialized JSON object. If your framework parses the JSON body and you then `JSON.stringify` it back, the whitespace or key ordering might differ from what Paystack sent, and the signature will not match" — this is described as "the single most common webhook bug."

This confirms the original audit's finding was correct and current: the previous implementation (`JSON.stringify(req.body)`) was exactly this bug. Separately confirmed (via search of current Firebase documentation and community references) that Firebase Cloud Functions v2's `onRequest` handler automatically populates `req.rawBody` as a `Buffer` ahead of JSON parsing, specifically to support this class of signature verification — no additional middleware configuration is needed for a plain JavaScript function (the caveat found in research — needing a TypeScript type augmentation to access `req.rawBody` — does not apply here, since `functions/index.js` is plain JS).

**Fix implemented:**
1. Extracted a pure, dependency-free `_computePaystackSignature(rawBody, secretKey)` helper (HMAC-SHA512, no Firestore/network dependency) so the algorithm itself can be unit-tested in isolation.
2. `paystackWebhook` now verifies against `req.rawBody` instead of `JSON.stringify(req.body)`, and explicitly fails closed (400, not a silent fallback) if `req.rawBody` is ever unavailable, or if the `x-paystack-signature` header is missing entirely (previously unchecked — a missing header would have produced `hash !== undefined`, which happens to still correctly reject, but did so accidentally rather than with an explicit, intentional check and a clear log line).
3. **Duplicate-delivery idempotency fix, found during this investigation and fixed alongside the signature bug:** the `charge.success` handler previously treated "this reference already locked the job" (a benign, expected outcome of Paystack's at-least-once webhook delivery) identically to a genuine error — both returned HTTP 500, which per Paystack's own retry behavior would trigger further retries for what is actually already-successfully-handled state. `_lockEscrow` now distinguishes the two: the exact same reference re-locking an already-`escrowLocked` job is a no-op that lets the handler proceed to a 200 response; any other unexpected state still throws and still returns 500.

**Tests:** `functions/test/webhook_signature.test.js` (new, 5 cases, pure — no emulator needed): computed signature matches a manual HMAC-SHA512 of the same bytes; a single tampered byte produces a completely different signature; differently-formatted-but-logically-identical JSON produces a different signature (directly demonstrating why the original bug was real, not theoretical); confirms SHA-512 specifically, not SHA-256 (Paystack's documentation calls this out as the non-default choice most integrators get wrong); a different secret key changes the signature. **Result: 5/5 passed.**

**What this does NOT prove:** that a real Paystack webhook delivery, hitting the actual deployed `paystackWebhook` endpoint, is correctly verified end-to-end. That requires deployment, which is unavailable (§0). The algorithm is proven correct in isolation against Paystack's documented requirements; the deployed endpoint's behavior is unverified.

---

## 4. Security test results — adversarial tests

Every adversarial test explicitly listed in the task brief was mapped against what's actually testable without a live deployment:

| Requested adversarial test | Coverage |
|---|---|
| Change amount / change job ID / change customer ID / change artisan ID (payment manipulation) | **Covered — Firestore Rules emulator suite** (unchanged from the P0 pass, re-run this phase, 26/26 passing): `payments` create rule is now `if false` for all clients, closing this entirely at the rules layer regardless of what a malicious client attempts |
| Forge payment status / forge Paystack reference / reuse an old reference | **Covered — same suite.** A forged `payments` doc cannot be created client-side at all (rule is `if false`); reference reuse is a Cloud-Function-internal concern (`_lockEscrow`'s reference-matching query) unaffected by client behavior |
| Invalid signature / altered body / missing signature (webhook attacks) | **Covered — `functions/test/webhook_signature.test.js`**, in isolation (§3.3). NOT covered end-to-end against a live endpoint (§0) |
| Duplicate webhook / replay webhook | **Covered at the logic level** — `_lockEscrow`'s new same-reference-is-a-no-op behavior (§3.3) — but not exercised via an actual duplicate HTTP delivery, since there is no live endpoint to deliver to |
| Release before payment / release from invalid job state / release wrong job / release twice / concurrent release / altered amount / altered artisan (escrow attacks) | **Covered — Firestore Rules emulator suite** (all of these map directly to the P0-1 regression tests: job-status-gated release creation, `releaseId==jobId` pinning, immutability after creation, the exact documented exploit chain and two variants, a concurrent-release-attempt test) |
| Initialize twice / initialize concurrently / retry after simulated timeout / refresh during initialization (transaction attacks) | **Covered — `functions/test/payment_init_idempotency.test.js`** (§3.2), all 5 cases map directly to these scenarios |

**Not covered by any test in this phase, and explicitly flagged as such:** any adversarial test that requires a live, deployed Cloud Function or a real Paystack API call (a forged Paystack reference that must round-trip through a real `transaction/verify` call; a genuinely concurrent HTTP request race against a live `initializePaystackTransaction` endpoint rather than against the local claim primitive directly; a real duplicate webhook delivery). These require the infrastructure blocked in §0.

---

## 5. Idempotency results

| Path | Result |
|---|---|
| Transaction initialization | **Fixed and unit-tested locally** (§3.2), not deployment-verified |
| Webhook (duplicate delivery) | **Fixed and unit-tested locally at the logic level** (§3.3), not deployment-verified |
| Escrow release | **Unchanged from the P0 pass — already correct**, re-confirmed via the re-run Rules/Functions test suites this phase (the atomic `pending → processing` claim transaction and the `releaseId==jobId` fixed-ID rule together prevent any double-release, proven by the "concurrent release attempts" test in the emulator suite) |
| Payout (Paystack transfer) | **Not verifiable this phase** — no deployed function ever calls Paystack's `/transfer` endpoint in this environment |

---

## 5.1/5.2 — Phase 10D regression (executed in full)

### 5.1 Automated suite

| Suite | Result |
|---|---|
| Firestore Rules emulator (`firestore-tests/`) | **26/26 passed** (re-run, unchanged from the P0 pass — no rules were touched in Phase 10B) |
| Cloud Functions unit tests (`functions/test/`) | **29/29 passed** — the original 19 (P0 pass) + 5 new webhook-signature tests + 5 new payment-init-idempotency tests |
| `flutter analyze` | 12 issues (1 warning, 11 info) — identical to every prior baseline this session; 0 new issues |
| `flutter test` | **94/94 passed** — unchanged from the P0 pass; no Dart code was touched in Phase 10B |
| `flutter build web` | Succeeded; rebuilt fresh this phase to pick up the Phase 10B Cloud Functions changes (which don't affect the Dart build, but the rebuild also re-validates the whole client compiles clean post-P0) |

### 5.2 Browser regression (pre-auth surface only — the only surface reachable without account verification, §2)

Live, against the freshly rebuilt `build/web`, Playwright + Chromium:
1. **Login screen** loads correctly, zero page errors.
2. **Wrong password** still shows the clean "Email or password is incorrect." message (P0/pre-existing behavior regression check — confirms nothing in the auth-provider rewrite for P0-3 broke the sign-in error path it didn't touch).
3. **Forgot-password happy path** still works correctly post-Phase-10B-and-P0-3 changes: submitted a real request for the existing (unverified but real) test account, got "Check your inbox — We sent a password reset link to dannyrotimi11+htaudit1@gmail.com." This is the exact P0-3 fix's primary code path, reconfirmed live in this phase, not just by unit test.
4. **Register screen** still renders and validates correctly (role picker, form fields present).

Zero `pageerror` events captured across the entire run. **This is the full extent of live browser verification possible this phase** — customer/artisan/admin dashboards, job posting, quotes, chat, payment screen, escrow status, and every other authenticated screen remain unverified live, blocked by §2.

---

## 6. Remaining issues

**P0 — none new this phase.** All P0s from the original audit were remediated in the prior pass (`design/P0_REMEDIATION_PLAN.md` §13); this phase found no new P0.

**P1:**
- Phase 10A (authenticated customer/artisan/admin workflow QA) is entirely unexecuted — this is the largest open item from the original audit's scope, still open.
- Phase 10C (live Paystack TEST-mode transaction flow) is entirely unexecuted, for the same infrastructure reason.
- The webhook and transaction-initialization fixes in this phase are code-level/unit-test-verified only — **not verified against a real deployment**. A real deployment could surface an integration issue (Secret Manager access, IAM, region latency, an actual Paystack account quirk) that no local test can catch.

**P2:**
- `processEscrowRelease`'s `BANK_CODES` table (pre-existing, unrelated to this phase) remains unverified against Paystack's live bank list.
- No refund/cancellation-after-payment mechanism exists (unchanged from the original audit and the P0 pass — deliberately out of scope for both, confirmed still out of scope for this phase too, per explicit instruction).

**P3:** none newly identified this phase.

**Architectural work still needed before production:**
- Refund/cancellation-after-payment design (flagged in both prior documents, still outstanding).
- A staging/test Firebase project, if real pre-production Paystack testing is ever to happen without deploying directly to what is currently the only (and therefore de facto production) project.

**Known limitations of this phase's verification:**
- Everything reported as "tested"/"passed" in this document was verified locally (Firestore emulator, Node unit tests, Flutter tests, and browser testing against a locally-served build) — nothing was verified against a real deployment or real Paystack traffic, and this document does not claim otherwise anywhere.

---

## 7. Production readiness

**Not assessed as ready, and this phase does not move that determination forward in any direction that matters for the real question.** The P0 vulnerabilities are fixed and locally proven; the payment-architecture hardening in this phase (idempotency, webhook signature) is implemented and locally proven. But the two things that would actually demonstrate the system is safe with real infrastructure and real (even test-mode) money — the full authenticated workflow QA (Phase 10A) and a live Paystack TEST-mode transaction (Phase 10C) — remain completely unexecuted, blocked by unverified test accounts and an undeployed Cloud Functions codebase respectively. Both are outside what this session can unblock on its own: the first requires the user to click two email links (or provide an alternative verified credential), and the second requires a deliberate decision to upgrade the project to Blaze and deploy — a financial/infrastructure decision this session is not authorized to make unilaterally.

---

## Final report (per task requirements)

1. **Authenticated customer workflow result:** BLOCKED — not executed (account unverified).
2. **Authenticated artisan workflow result:** BLOCKED — not executed (account unverified).
3. **Authenticated admin workflow result:** BLOCKED — not executed (no verified account, and no admin-flagged account exists either).
4. **Transaction initialization result:** Code-level fix implemented (idempotency claim mechanism) and unit-tested (5/5 passed, local Firestore emulator). Not tested against a live/deployed endpoint.
5. **Webhook signature verification result:** Code-level fix implemented (raw-body HMAC-SHA512, verified against Paystack's current live documentation) and unit-tested (5/5 passed, pure logic test). Not tested against a live/deployed endpoint or real Paystack delivery.
6. **Paystack TEST transaction result:** BLOCKED — not attempted. No deployed endpoint exists for either the client or Paystack to call.
7. **Escrow result:** Server-side preconditions (job status, verified-payment requirement, amount cross-check) verified via the Firestore Rules emulator suite (26/26) and Cloud Functions unit tests (29/29, unchanged logic from the P0 pass). Not verified against a live release/payout.
8. **Paystack TEST transfer result:** BLOCKED — not attempted, same reason as #6.
9. **Duplicate transaction result:** Local claim-mechanism tests pass (5/5); no duplicate real Paystack transaction was possible to attempt or rule out live, since none can be created at all right now.
10. **Duplicate webhook result:** Local logic-level idempotency fix verified (§3.3); not exercised via an actual duplicate delivery.
11. **Duplicate payout result:** Unchanged from the P0 pass — already proven safe via the Rules emulator's concurrent-release test and the pre-existing (unmodified) atomic claim transaction in `processEscrowRelease`. Not live-verified against a real payout.
12. **All adversarial test results:** see §4's table — every test that does not require live deployment passed; every test that does require it was not attempted, not faked.
13. **All files modified this phase:** `functions/index.js` (webhook HMAC fix, `_lockEscrow` idempotency, `initializePaystackTransaction` claim mechanism), `functions/package.json` (test script updated to include the 2 new test files), `functions/test/webhook_signature.test.js` (new), `functions/test/payment_init_idempotency.test.js` (new), `design/PHASE_10_AUTHENTICATED_PAYMENT_QA.md` (this document, new).
14. **All tests executed:** Firestore Rules emulator (26/26), Cloud Functions unit tests (29/29), `flutter analyze` (12 pre-existing issues, 0 new), `flutter test` (94/94), `flutter build web` (succeeded), live browser regression on the pre-auth surface (4/4 checks passed, 0 page errors).
15. **Remaining P0/P1/P2/P3 issues:** see §6 in full.
16. **Whether production deployment is now safe:** **Not determined by this phase, and not claimed to be.** The P0 fixes are real and locally proven; whether the system is safe *in production, with real infrastructure and real money* cannot be established without the still-outstanding authenticated workflow QA and live Paystack TEST-mode validation — both blocked, neither faked.
17. **Explicit confirmation:** no live Paystack credentials were used, read, or referenced at any point in this phase. No test-mode Paystack credentials were used either — no Paystack API call of any kind was made, because no deployed endpoint exists to make one through. No real-money transaction occurred. No `firebase deploy` command was run. No Cloud Function was enabled or deployed.
