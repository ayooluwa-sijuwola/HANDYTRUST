# Stage 8.1 — Artisan presentation layer: implementation report

**Date:** 5 November 2026
**Branch:** `stage-8-ui-replacement` (uncommitted; nothing pushed or deployed)
**Scope:** the artisan experience only. Customer, authentication and admin replacement still await separate authorization (U-1 to U-3, plus the checkpoint-commit question).
**Approved design:** `design/STAGE8_ARTISAN_REDESIGN_PREVIEW.md` and the `ar*` previews in `test_visual/previews/goldens/`.
**Visual evidence:** `design/STAGE8_1_VISUAL_QA_REPORT.md` and `design/stage8_1_artisan_vs_approved/` (54 side-by-side sheets).

---

## 1. Outcome

The old artisan presentation layer is deleted and replaced by a new artisan experience, "HandyTrust Pro". It was built from scratch in `lib/ui/artisan/` and is visually and structurally distinct from the customer app.

- **Navigation (approved D-2):** Home · Find Work · My Jobs · Earnings · Profile. Messages and notifications sit in every tab's header, with live unread counts.
- **Mode switching (F-11):** the active role decides which app a user sees. A dual-role user in Artisan Mode sees only artisan work; in Customer Mode, only customer screens. A customer-only account never gets the artisan app, even with `activeRole = 'artisan'`.
- **Backend:** every artisan workflow uses the same existing services, notifier methods and Cloud Functions as before. No backend code, Firestore rule, Storage rule, Paystack flow or Firebase Auth code changed.
- **Moved writes:** Firestore writes that used to sit inside artisan widgets now live in `ArtisanProfileService`, with byte-identical payloads (D-5).

## 2. Proof that the old artisan UI is gone

| Check | Result |
|---|---|
| 26 legacy artisan screens/widgets deleted (§3) | `test/artisan_ui_test.dart` › "deleted artisan screens and widgets do not exist" — **pass** |
| No code references the deleted classes (`ArtisanDashboardScreen`, `OpenJobsFeedScreen`, `BankDetailsScreen`, `PortfolioManagerScreen`, `AllJobsScreen`, `WalletScreen`, `JobCompletionScreen`) | source guard — **pass** |
| New artisan UI imports no legacy screens, `lib/widgets/`, `MainShellScreen`, `premium_scaffold`, `AppTheme`, `context.colors` or `job_detail_screen` | source guard — **pass** |
| No Firebase SDK use in `lib/ui/artisan` (writes go through services) | source guard — **pass** |
| Every artisan route renders a new screen (`/home`, `/open-jobs`, `/jobs`, `/wallet`, `/profile`, `/notifications`, `/my-chats`, `/job/:id`) | router tests against a real `GoRouter` — **pass** |
| Visual: new screens vs approved previews | 54 comparison sheets, `design/stage8_1_artisan_vs_approved/` |

`lib/screens/artisan/` now holds only three **customer** screens: `artisan_list_screen`, `secure_booking_screen` and `favorites_screen`. They belong to the customer phase.

## 3. Files

### Deleted (artisan scope)

- **Screens:**
  - `lib/screens/artisan/`: `artisan_dashboard_screen`, `open_jobs_feed_screen`, `business_profile_screen`, `bank_details_screen`, `portfolio_manager_screen`, `portfolio_project_screen`
  - `lib/screens/home/all_jobs_screen`
  - `lib/screens/wallet/wallet_screen`
  - `lib/screens/job/job_completion_screen`
  - `lib/screens/auth/artisan_registration_screen`
- **Widgets (`lib/widgets/`):** `artisan_card`, `balance_card`, `cancellation_reason_dialog`, `earnings_summary_card`, `job_booking_card`, `loading_indicator`, `pill_tab_selector`, `portfolio_viewer`, `premium_scaffold`, `service_area_card`, `shimmer_loaders`, `transaction_card`, `trust_score_card`

Other deletions in the working tree (`demo_escrow_*`, the old chat, notifications and profile screens, etc.) come from Stage 8. Backups are listed in §10.

### Created

**Logic and services** (pure or service layer, unit-tested):

- `lib/core/services/artisan_work_logic.dart` holds the derived state:
  - a job's stage and pipeline column;
  - the six-step work stepper;
  - the action queue;
  - deadlines from server windows;
  - My Jobs grouping;
  - withdraw and cancellation eligibility;
  - F-11 `isArtisanMode`.
- `lib/core/services/artisan_earnings_summary.dart` computes the Earnings figures from the artisan's own payment documents only.
- `lib/core/services/artisan_profile_service.dart` holds the writes moved out of widgets (D-5):
  - `setAvailability`
  - `saveBusinessProfile`
  - `saveServiceArea`
  - `loadBankDetails` / `saveBankDetails`
  - `registerArtisan`

**Presentation:**

- `lib/ui/components/ht_kit.dart` adds shared building blocks: timeline, photo grid and viewer, sheets, text fields, toggles.
- `lib/ui/artisan/artisan_shell.dart` contains the shell, tab state, header, page frames and the loading/error frame.
- `lib/ui/artisan/components/pro_components.dart` holds the HandyTrust Pro components: nav bar, header, action cards, pipeline, countdown ring, tickets, work stepper, progress meter, stats, month bars, ledger, segments, tabs and action bar.
- `lib/ui/artisan/screens/`:
  - `artisan_home_screen`
  - `find_work_screen`
  - `quote_composer_screen`
  - `my_jobs_screen`
  - `work_order_screen` (booking request, work order tabs, rework, dispute)
  - `submit_work_screen`
  - `earnings_screen`
  - `payout_account_screen`
  - `artisan_profile_screen` (class `ArtisanProProfileScreen`)
  - `business_profile_screen`
  - `artisan_verification_screen`
  - `portfolio_screen` (list and project editor)
  - `artisan_inbox_screens` (messages and notifications)
  - `artisan_registration_screen`
  - `work_ui` (shared helpers)

**Tests:**

- `test/artisan_work_logic_test.dart` (35)
- `test/artisan_earnings_summary_test.dart` (5)
- `test/artisan_ui_test.dart` (34: screens, actions, dual-role users, router, source guards)
- `test_visual/artisan_visual_test.dart` (210: goldens and responsive sweep)

### Modified

| File | Change |
|---|---|
| `lib/routes/router.dart` | Imports and routes point to the new screens. `_RoleAware` serves `/wallet`, `/jobs`, `/notifications`, `/my-chats`, `/verification` and `/profile`. `_JobRoute` gives the job's own artisan the work order and everyone else the customer job detail. D-6 redirects non-artisans away from artisan-only paths (UI only; rules enforce access). |
| `lib/screens/home/home_screen.dart` | `/home` shows `ArtisanShell` in Artisan Mode and `CustomerShell` otherwise. |
| `lib/ui/screens/profile_screen.dart` | Artisan-only rows removed from the customer profile; they live in the artisan Profile tab. |
| `lib/ui/screens/chat_screen.dart` | The job's artisan sees a work-order strip (reference, price, six-step stepper) that opens the work order. The customer view is unchanged. |
| `lib/ui/components/ht_components.dart` | `HtStatusPill` gains an optional `maxLines` (default 1, so existing screens are unchanged). |
| `lib/ui/components/ht_format.dart`, artisan screens | `DateTime.now()` → `clock.now()`. Identical at runtime; lets tests fix the time. |
| `pubspec.yaml` / `pubspec.lock` | `clock: ^1.1.2` promoted from transitive to direct dependency. The lockfile change is only the label (same version 1.1.2, no new download). |
| `lib/core/services/workflow_gate_service.dart` | F-9 copy: "after 48 hours" → "when the 14-day review period ends" (server `REVIEW_WINDOW_MS` = 14 days). |
| `lib/ui/screens/verification_screen.dart` | Q-6: removed the "within 24–48 hours" promise. |
| `lib/screens/settings/settings_screen.dart` | Mandatory FAQ corrections: escrow "7 days" → 14-day review period; removed "24–48 hours" from the verification FAQ. The account-deletion dialog (F-12/U-1) is **not** changed; it awaits your decision. |
| `test/portfolio_project_route_test.dart` | Points at the new portfolio project editor. |
| `test/stage8_ui_test.dart` | The "no wallet actions" guard now allows "Withdraw" inside `lib/ui/artisan` only, because withdrawing a quote and withdrawing from a job are real backend actions. Wallet phrasing ("Withdraw funds", "Wallet balance", …) is still banned there. |
| `artisan_eligibility.dart`, `artisan_provider.dart`, `admin_dashboard_screen.dart` | Comments only. |

## 4. Workflow coverage (every artisan action → existing backend path)

| Workflow | Screen | Call (unchanged service/notifier) |
|---|---|---|
| Go available / unavailable | Home, Find Work | `ArtisanProfileService.setAvailability` (same batch to `artisans` + `users`) |
| Quote, edit, withdraw quote | Quote composer | `QuoteService.submitQuote` / `withdrawQuote`; same validation (labour > 0, platform minimum) |
| Chat before booking | Find Work | `ChatService.getOrCreateJobChat` |
| Accept / decline booking (server window, default 24 h) | Booking request | `confirmBooking` / `withdrawFromJob` (callable `artisanWithdrawFromJob`) |
| Review the customer's agreement | Work order › Agreement | `acceptAgreement` / `requestAgreementChanges(reason)` |
| Propose appointment times (scheduled jobs, before payment) | Work order › Schedule | `proposeAppointmentSlots` |
| Start work after escrow funded | Work order | `startWork` |
| Progress updates (8 stages) | Work order › Overview | `updateProgress` |
| Submit work (before + after photos) | Submit work | `StorageService` upload → `submitCompletion` |
| Respond to the one rework request | Work order › Rework | `respondToRework` |
| Respond to a dispute with evidence | Dispute | evidence upload → `DisputeService.respondToDispute` |
| Withdraw before payment / request paid cancellation | Work order | `withdrawFromJob` / `requestPaidCancellation` |
| Earnings, escrow, awaiting release, payout status | Earnings | `artisanPaymentsProvider` + job `payoutStatus` (read-only) |
| Payout account | Payout account | `ArtisanProfileService.loadBankDetails` / `saveBankDetails` (`artisan_private`, owner + admin) |
| Business profile, service area | Business profile | `saveBusinessProfile` / `saveServiceArea` (same geohash fields) |
| Portfolio projects and photos | Portfolio | `PortfolioService` add / remove / reorder / delete |
| Verification | Verification hub | status from `verificationStatusProvider`; uploads reuse the Stage 8 `VerificationScreen` flow |
| Avatar, switch to Customer mode, sign out | Profile | `ProfileService.uploadAvatar` / `setActiveRole` · `authNotifier.signOut` |
| Messages and notifications | Header → inbox | `artisanChatJobsProvider`, `NotificationService.markRead` / `markAllRead` |
| Registration | `/register/artisan` | `ArtisanProfileService.registerArtisan` (same fields and validators) |

**Failure handling:** every work action checks the notifier's error state afterwards. The escrow notifier stores errors instead of throwing, so a rejected call now shows an error and never a success message. This fixes the old completion screen, which reported success even when the server rejected the submission.

## 5. Deviations from the approved previews (each forced by the real backend or by a defect)

1. **Work stepper says "Funded", not "Scheduled".** Scheduling happens before payment (customer confirms a slot, then funds escrow), so "Funded" is the true fourth milestone.
2. **The artisan reviews the agreement; they don't draft it.** The customer drafts scope and price (`confirmAgreement`); the artisan accepts or requests changes. The preview's "Send agreement" became "Accept agreement / Request changes".
3. **No customer names or street addresses for artisans.** Artisans cannot read customers' `users` documents. Screens show the job's area, category and "Customer". The exact address appears only through `jobPrivateLocationProvider` once the rules allow it (after booking confirmation).
4. **Pipeline columns** follow the real stages: Requests · Agreement · Awaiting payment · Working · In review, plus a Disputed column on the board when one exists.
5. **"My quotes"** lists quotes on jobs still in the artisan's open matches. The backend has no cross-job quote query; adding one would need a collection-group index and a rules change, which are out of scope.
6. **Portfolio category** is a dropdown of `ServiceCategories.all`, matching the backend's allowed values.
7. **New-artisan Home** shows the real zero pipeline and ₦0 totals instead of the preview's "No jobs yet" card. Nothing is invented.
8. **Titles are sentence case** ("Work order", "Payout account"), matching the rest of the design system.
9. **Customer `job_detail_screen`** stays, for customers only, until the customer phase. `_JobRoute` never shows it to the job's artisan.
10. **The verification hub** reuses the Stage 8 upload flow (one upload implementation, same Storage paths and rules).
11. **Artisan registration** keeps a category dropdown and free-text skills instead of the preview's chips. `skills` is one text field in the backend, and the existing validators are kept unchanged.

## 6. Defects found and fixed during verification

| Defect | Found by | Fix |
|---|---|---|
| Rework card heading overflowed by 20 px at 320 pt | responsive sweep | heading wrapped in `Expanded` |
| Funded in-progress job showed "Not funded yet" when `escrowLockedAt` was absent | side-by-side review | pill derived from job status (escrowLocked / inProgress / submitted / disputed are only reachable after funding) or `escrowLockedAt` |
| Disputed jobs missing from the tablet board | side-by-side review | Disputed column added when present |
| Open-job budget truncated ("₦20,000 – …") | side-by-side review | budget takes all free row space |
| Section headers truncated beside a trailing link ("HOW CUSTOMERS S…") | side-by-side review | label takes all space the link doesn't need |
| Stage pills truncated on narrow board columns | side-by-side review | two-line pills on board tickets |

## 7. Verification evidence (all run on 5 November 2026)

| Suite | Result |
|---|---|
| `flutter analyze` (excluding the out-of-scope `work_sphere_ai/`) | **0 errors, 0 warnings.** 8 info-level `deprecated_member_use` notes in existing customer/admin files (`Radio.groupValue`), none in the new code |
| `flutter test` (all unit/widget tests) | **267 / 267 pass** (incl. 74 new artisan tests) |
| `flutter test test_visual` | **468 / 468 pass**: Stage 8 customer 88 (unchanged), approved previews 170 (unchanged), artisan 210 |
| Cloud Functions (Node 22, Firestore emulator, demo project) | **266 / 266 pass** (each of the 15 files in its own process; see §8.2) |
| Firestore security rules | **139 / 139 pass** |
| Storage rules | **9 / 9 pass** |
| End-to-end trigger and schedule suite (functions + firestore + pubsub emulators) | **16 / 16 pass** on Node 22; 0 calls to Paystack or any external host |

**Safety:** all emulator runs used `demo-*` project IDs. The dummy `functions/.secret.local` (`sk_test_DUMMY_STAGE81_EMULATOR_ONLY`) was created for the e2e run, deleted in the same command, and confirmed absent. Leftover local emulator processes from those runs were stopped. Nothing touched production Firebase or Paystack.

**Artisan scenarios covered by widget tests:**

- **Shell and Home:** the shell's five tabs and header unread counts; Home's action queue (real actions only, payout reminder, caught-up state).
- **Lists:** My Jobs grouping and empty state; Find Work feed and search; Earnings figures (no wallet wording).
- **Profile:** the switch-to-Customer row (dual-role only) and the admin entry (admins only).
- **Accept booking:** success; server rejection shows an error, never a success message; blocked once the server window has passed.
- **Other work actions:** start work; progress update; accept agreement; no Schedule tab on ASAP jobs; no withdraw once funded; 14-day review with no "48".
- **Payout and theme:** payout account; notifications; dark theme.

**Router tests:**

- An artisan's deep links land on the right artisan tab or page, and `/job/:id` opens the work order for the job's own artisan.
- A customer-only account is redirected home from `/open-jobs`, `/bank-details`, `/business-profile`, `/portfolio` and `/job/:id/submit`.
- A dual-role user in Customer Mode gets customer screens on shared paths and can still reach artisan-only pages they hold the role for.

## 8. Observations recorded, not changed

1. **Router redirect uses `ref.watch` inside the GoRouter callback** (`router.dart`, present in the 7.3 baseline). Under tests, providers resolving after the router is built trip Riverpod's debug assertion. Changing it to `ref.read` is the usual fix, because `AuthChangeNotifier` already refreshes the router. It's left unchanged here because it touches the auth guard; recommended for a later, separately reviewed change. The router tests resolve auth and profile before building the router.
2. **Functions suite in one shared emulator.** The repo's `firebase.json` sets `singleProjectMode: true`. When all 15 Functions test files share one emulator process, they interfere (leftover "already locked" / "already exists" state). Each file passes in its own process (266/266). Test harness only; no product impact.
3. **`escrow_service.dart:40`** carries a client-side 7-day `autoReleaseAt` path and comment. The server sets the real 14-day window (`REVIEW_WINDOW_MS`). Not changed: it's a financial-workflow file.
4. **Customer dispute screen** still promises review "within 48 hours" (`dispute_screen.dart:145, :333`). It belongs to the customer phase (Q-6).
5. **Settings account-deletion dialog** (F-12, "within 7 days", unenforced preconditions) awaits U-1.
6. **`withdrawFromJob`** in the escrow notifier calls `FirebaseFunctions.instance` directly. Existing code, unchanged.

## 9. Not done in this phase

- Customer, authentication and admin replacement (awaiting your final authorization: U-1 to U-3, plus whether to make a checkpoint commit).
- No commit, push, deployment, production Firebase change or real Paystack transaction.

## 10. Recovery

- `C:\PROJECTS\handy_trust_backups\stage8_8.1_2026-11-04\` — 334/334 files verified byte-exact.
- `C:\PROJECTS\handy_trust_backups\stage8_8.1_pre_artisan_20261104_2341\` — pre-artisan-replacement snapshot: patch, tars, MANIFEST and `RESTORE.md`. Not restore-tested.
- Baseline commit `7e16eb1` (Stage 7.3).
