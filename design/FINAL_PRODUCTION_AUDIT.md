# Final Production Audit — Group 11

Audit and stabilization only. No screens redesigned, no architecture rewritten. Companion document: `design/FINAL_USER_JOURNEY_AUDIT.md` (Task 1). This document covers Tasks 2–8 and the final report.

---

## Task 2 — Workflow consistency check

Cross-checked `JobService.allowedTransitions`, `WorkflowGateService.describeStep`, `firestore.rules`' `_isValidJobTransition`, and every UI surface that renders a status-specific action, for all 11 `JobStatus` values.

| Status | JobService transition | Rules-enforced | UI action present |
|---|---|---|---|
| requested | → matched, cancelled | ✅ (`isCust`, eligibility-checked artisan) | ✅ `WorkflowGateService` phase (customer: waiting; artisan: browse-jobs prompt) |
| matched | → inChat, cancelled | ✅ (`isCust`) | ✅ "Continue Negotiation" |
| inChat | → paymentPending, cancelled | ✅ (agreement + scheduling gated) | ✅ agreement/scheduling sections |
| paymentPending | → escrowLocked, cancelled | ✅ (`isAdmin() \|\| isCust`) | ✅ "Confirming Payment" transient state |
| escrowLocked | → inProgress, disputed, cancelled | ✅ (`isArt` for inProgress) | ✅ "Start Job" (artisan) |
| inProgress | → submitted, disputed | ✅ (`isArt`) | ✅ progress updates + submit |
| submitted | → completed, disputed | ✅ (`isCust` for completed) | ✅ explicit confirm/dispute switch case |
| completed | (terminal) | — | ✅ "Payment Released" card (added Group 7) + review |
| disputed | → resolved | ✅ (`isAdmin()`) | ✅ `_DisputeThreadSection` |
| resolved | (terminal) | — | ⚠️ **gap found** — see below |
| cancelled | (terminal) | — | ✅ `_CancellationInfoBox` |

**Gap found**: `resolved` has no case in `job_detail_screen.dart`'s action-buttons switch — it falls through to `_ => SizedBox.shrink()`. The resolution outcome is still visible via `_DisputeThreadSection` (rendered separately, not gated by that switch), so this isn't a silent/broken state, but there's no dedicated "this is now closed, here's the outcome" card the way `completed`/`cancelled` get. **Not fixed in this pass** (would require touching `job_detail_screen.dart`'s UI, out of scope for an audit-only group) — flagged as a small, well-scoped follow-up.

**No unreachable states, no buttons that cannot succeed, no missing transitions found** beyond the one documented above. Every button-triggering action was traced to a real `JobService` method with a matching `firestore.rules` transition clause.

---

## Task 3 — Payment and escrow final review

- **Customer money cannot bypass escrow**: `initPayment` requires `canInitPayment` (agreement confirmed + schedule satisfied), enforced identically client-side (pure predicate, unit-tested) and server-side (`firestore.rules`' `inChat → paymentPending` clause checks the same two conditions). `payments` collection: `allow update: if isAdmin();` only — a client cannot ever move a payment to `escrowHeld`/`released` directly; only `_lockEscrow`/`_releaseEscrow` (Cloud Functions, Admin SDK) can.
- **Artisan cannot falsely claim payment**: release only happens via `confirmComplete` (customer-only, requires `submitted` status) or the `autoReleaseEscrow` cron (time-gated, requires `submitted` status) — an artisan has no write path to `completed` or to `payments.status`.
- **Release creates a real payout**: verified in Group 7/8 — `processEscrowRelease` performs an actual Paystack Transfer (with bank-account-name verification before sending), not a status-flip-only "release."
- **Failed payouts are visible**: `escrow_releases.status` moves to `failed` on a `transfer.failed`/`transfer.reversed` webhook; `reconcileStuckEscrowReleases` (daily cron) catches anything stuck >2h and writes to `admin_alerts` — now readable by admins as of Group 10's rules fix.
- **Auto-release timing is correct**: fixed in the dedicated escrow-timing pass (between Groups 7–8) — `autoReleaseAt` and `disputeWindowEndsAt` are written together, from the same value, at submission time. Regression-tested (10 tests in `test/job_service_agreement_test.dart`'s "Escrow release timing" group).

**Remaining risk, documented not fixed**: the `BANK_CODES` table in `functions/index.js` (Paystack bank-code mapping) is explicitly flagged in its own source comment as unverified against Paystack's live bank list from this environment. A wrong code would be caught by the account-name-resolution safety check before money moves (transfer aborts rather than sending to an unverified account), so this is a *availability* risk (payout fails safely) not a *safety* risk (money can't misroute silently) — but it should be verified against Paystack's `GET /bank` before real payouts run in production.

---

## Task 4 — Notification verification

Re-confirmed the Group 9 fix holds: every notification source (job-status events via `_sendNotification`, payout events via `_sendInAppNotification`, and Dart-client writes from Quote/Dispute/Verification services) now writes to `notifications/{id}`, and the single `onNotificationCreated` trigger pushes for all of them uniformly.

| Event | In-app entry | Push |
|---|---|---|
| quote received | ✅ (client write, `QuoteService`) | ✅ (via unified trigger) |
| quote accepted | ✅ | ✅ |
| agreement confirmed | — | — |
| escrow locked | ✅ (`_sendNotification`) | ✅ |
| completion submitted | ✅ | ✅ |
| payment released | ✅ (`completed` event) | ✅ |
| dispute created | ✅ (`dispute_raised` type) | ✅ |
| verification approved | ✅ (client write, `VerificationService`) | ✅ |
| payout completed | ✅ (`_sendInAppNotification`) | ✅ |

**Gap noted, not new**: "agreement confirmed" has no notification event at all, in either direction — a real, minor gap (both parties only find out by opening the chat/job screen), not introduced by this program, not fixed here (would require adding a new notification call site, which is feature work, not audit/hardening).

Unread count / mark-read / background / terminated-app delivery: all re-verified structurally sound per the Group 9 audit — no new issues found this pass.

---

## Task 5 — Security review

- **`firestore.rules`**: no bare `allow write: if true` anywhere; every collection's rules were read this session across Groups 1–10 and again spot-checked here. `admin_alerts` (Group 10) was the one collection with zero rule coverage — now fixed.
- **`storage.rules`**: reviewed in full this pass (not covered by name in earlier groups). One thing worth confirming, now confirmed: **`storage.rules`' `isAdmin()` checks a custom Auth-token claim (`request.auth.token.admin == true`), a completely different mechanism from `firestore.rules`' `isAdmin()` (which checks `admins/{uid}` document existence)**. These could silently diverge — but `functions/index.js` already has `onAdminGranted`/`onAdminRevoked` triggers (Firestore-trigger on `admins/{uid}` create/delete) that keep the Auth custom claim in sync automatically, with an explicit doc comment describing exactly this reasoning. **Verified consistent, already correctly handled** — not a live bug. One real, minor, inherent Firebase constraint worth stating: a custom-claim change only takes effect on a client after their ID token refreshes (re-login, or up to ~1h automatically) — a newly-granted admin may see dashboard access before Storage access catches up.
- **Client cannot modify protected fields**: confirmed for jobs (transition-gated), payments (admin-only update), disputes (field-diff-scoped artisan response only), reviews (create-only, no update), portfolio analytics (field-scoped).
- **Users cannot access other users' private data**: `users/{uid}` read is owner/admin-only (confirmed in earlier sessions and unchanged); `artisan_private/{uid}` is owner/admin-only (relied on directly in Group 8's payout-readiness provider).
- **Artisan cannot bypass verification**: `isArtisanEligible()` (approval + verification) is checked server-side on both quote creation and the `matched` transition — not just client-side UI gating.
- **Customer cannot bypass payment**: covered under Task 3 above.

No new security issues found. The one real finding (`admin_alerts` unreadable) was already fixed in Group 10.

---

## Task 6 — Dead code & technical debt

Proved via `Grep` (zero references anywhere in `lib/`, not just router.dart) before listing anything here:

- **`lib/screens/auth/phone_login_screen.dart`** (`PhoneLoginScreen`) — zero references anywhere, including the router. Not reachable by any route. Confirmed fully dead, not just "unused but defensively kept" as its own comment claims.
- **`lib/screens/auth/customer_registration_screen.dart`** (`CustomerRegistrationScreen`) — same: zero references anywhere, not routed. Confirmed fully dead.
- **Demo payment path** (`demo_escrow_screen.dart`, `demo_escrow_service.dart`, `demo_payment_provider.dart`) — **not dead code**, verified: real references from `router.dart` and a `kDebugMode`-gated fallback in `payment_screen.dart`. Intentionally scoped to debug builds only, already correctly isolated from any release-mode path. Left as-is.
- Widget consolidation already completed in Groups 1–3 this program (`job_progress_tracker.dart`/`job_timeline_widget.dart`/`job_progress_timeline.dart` deleted after replacement by `WorkflowTimeline`, confirmed at the time via zero-reference check).

**Not exhaustively swept**: a full dead-code pass across the entire ~200+ file `lib/` tree was not performed given this task's time budget — the two confirmed-dead files above were specifically named in this program's own history as candidates and are now definitively proven, not just suspected. Recommend a dedicated follow-up sweep (e.g. `dart run dart_code_metrics` or similar unused-code tooling) before a real production cut, rather than continuing to hand-grep file-by-file.

**Recommendation, not executed**: delete `phone_login_screen.dart` and `customer_registration_screen.dart` — proven safe, but left for the user to action since deletion wasn't explicitly requested by this audit task.

---

## Task 7 — Performance check (recommendations only)

- **Per-row provider watches in list views**: `all_jobs_screen.dart`'s `_BookingCardTile`, `wallet_screen.dart`'s `_TransactionRow`, and `my_chats_screen.dart`'s `_ChatListTile` each `ref.watch` a `jobStreamProvider(id)`/`artisanProfileProvider(id)` per row (Groups 3, 6, 8). This is architecturally correct (each row needs its own live job/artisan data) but means a long list opens N individual Firestore listeners. Fine at current expected scale (a user's own jobs/payments/chats, realistically dozens not thousands); would need pagination or a batched-read pattern if any of these lists could grow into the hundreds.
- **`_allJobsProvider`/`_allUsersProvider`/`_allPaymentsProvider` (admin dashboard, Group 10)**: capped at `.limit(200)`/`.limit(500)` — reasonable for now, but the admin dashboard's stat cards (Total Users, Escrow Volume, etc.) are computed by summing/filtering these capped client-side lists. Once real user/payment counts exceed the limit, the dashboard's totals will silently undercount rather than error. Worth a Cloud Function-maintained aggregate counter (a common Firestore pattern) before real scale — not an issue today.
- **Image loading**: `Image.network` used throughout (artisan avatars, portfolio, chat images) with no explicit caching package (e.g. `cached_network_image`) observed — Flutter's default `Image.network` does have its own in-memory cache, but no disk cache, meaning avatars re-download on every cold app start. A real, common optimization opportunity, not a correctness issue.
- **`WorkflowGateService.describeStep`** is a pure, cheap function (no I/O), called freely per-row across many redesigned screens this program — no performance concern.

All of the above are recommendations. None were safe/obvious enough to fix inline without risking a regression in an audit-only pass (list-provider patterns and image caching are both cross-cutting changes that deserve their own dedicated, tested pass).

---

## Task 8 — Final testing

- `flutter analyze`: **13 issues**, all pre-existing (unrelated to this entire 11-group program — confirmed by tracking this exact count across every group's testing section; the count only ever *decreased*, from 18 to 13, as Groups 2 and 9 fixed issues incidentally found in files they were already touching). Zero issues introduced by this program.
- `flutter test`: **44/44 passing**, including the 10 escrow-timing regression tests added mid-program.
- `flutter build apk --release`: **succeeded** — `build/app/outputs/flutter-apk/app-release.apk`, 63.5MB. One non-blocking warning: the project's Kotlin version (2.0.10) is older than Flutter's soon-to-be-required minimum (2.1.0) — not a build failure today, but worth scheduling before it becomes one.

No issues were introduced by recent changes, so nothing required fixing in this task.

---

## FINAL REPORT

### 1. Production readiness score: 8.5 / 10

Both core user journeys are complete and source-verified with no blocking gaps. Workflow, payment/escrow, and notification systems all passed re-verification. The release build succeeds. The deductions are for the handful of documented, non-blocking gaps below — none of which block a launch, all of which are real and worth scheduling.

### 2. Completed systems
Authentication, job lifecycle (post → quote → negotiate → schedule → pay → work → complete → review), escrow lock/release (including the timing fix), notifications (unified push + in-app), wallet/earnings, admin operations (verification, disputes, users, and now alerts), and the full Stitch visual redesign across all 10 preceding groups.

### 3. Remaining blockers
**None.** Every gap found in this audit is documented as non-blocking.

### 4. Security risks
None found beyond the `admin_alerts` gap already fixed in Group 10. `storage.rules`' independent admin-check mechanism was verified consistent with `firestore.rules` via existing sync triggers, not assumed safe.

### 5. Payment risks
The unverified `BANK_CODES` table (fails safely — transfer aborts rather than misrouting money, but could block real payouts until verified against Paystack's live bank list). No integrity/bypass risks found.

### 6. UX issues
`resolved` job status shows no dedicated action-buttons-area card (outcome is still visible via the dispute thread, just not as prominently as `completed`/`cancelled` get). No "agreement confirmed" notification exists in either direction.

### 7. Performance concerns
Per-row provider watches in list screens (fine at current scale, needs revisiting if lists grow large); admin dashboard stat totals are computed from capped client-side lists (will silently undercount past the cap); no disk-level image caching.

### 8. Recommended launch checklist
1. Verify `BANK_CODES` against Paystack's live `GET /bank` endpoint before enabling real artisan payouts.
2. Deploy the Firestore composite index changes and rules changes made across this program (`admin_alerts`, plus any index-deployment notes flagged in earlier groups) — confirm via `firebase deploy --only firestore:rules,firestore:indexes`.
3. Delete (or confirm intentionally keeping) `phone_login_screen.dart`/`customer_registration_screen.dart` — proven dead this pass.
4. Schedule the Kotlin version upgrade (2.0.10 → 2.1.0+) before it becomes a hard build failure.
5. Add the missing "agreement confirmed" notification and the `resolved`-status action card as small, separate follow-up tickets — not blockers, but real polish gaps.
6. Consider a dedicated dead-code sweep tool pass and an image-caching package before a high-traffic launch.

This is the final verification stage of the Stitch redesign program. No further redesign groups follow.
