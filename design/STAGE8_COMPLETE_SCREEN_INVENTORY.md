# HandyTrust — Complete Application Screen Inventory (Stage 8 / 8.1)

Date: 2026-11-04 · Branch: `stage-8-ui-replacement` (uncommitted) · Status: **audit only.** No screen has been deleted or replaced in this step.

## How this inventory was built

The audit covered **all of `lib/`**, not only the dashboards:

| Area | Method |
|---|---|
| Routes | Every `GoRoute` / `ShellRoute` in `lib/routes/router.dart`: 50 paths, including the `/admin` redirect and 12 admin sections |
| Page widgets | Every class that builds a `Scaffold`: a scan found 45, then each was checked by hand. Tab bodies without their own `Scaffold` were added by tracing `HomeScreen`, `CustomerShell`, `MainShellScreen` and `AdminShell` |
| Overlays | Every dialog, bottom sheet, picker, popup menu and imperative push: 55 call sites, de-duplicated to 47 distinct interfaces |
| Deep links | Push-notification taps (`getInitialMessage`, `onMessageOpenedApp` → `safeNotificationRoute` allow-list); the Paystack checkout webview; the Firebase email action links (verification and password reset, which open Firebase-hosted pages); the "cannot open directly" fallback |
| Reachability | Role switches (`_RoleAware`, `WalletScreen`, `AllJobsScreen`) and widget importers, to find obsolete code with evidence |

The scan tool is `scan_ui.js` (scratchpad). Each finding was verified by reading the code.

## Summary

| | Count |
|---|---|
| **Live page-level screens** | **60** |
| Proposed new screen sections (approved: Finance) | 1 |
| Requested by you but **not present** in the app today | 4 (§6) |
| **Distinct overlays** (dialogs, sheets, pickers, menus) | **47** live (+1 proposed: payout freeze) |
| Obsolete views and widgets (with evidence) | 6 |
| **Total distinct user-facing interfaces audited** | **107 live** |

### Role breakdown (60 live screens)

| Role | Screens |
|---|---|
| All roles: system, onboarding, authentication | 13 |
| Customer only | 14 |
| Shared customer + artisan (admins use them as users too) | 10 |
| Artisan only | 10 |
| Admin only (shell + 12 sections) | 13 |

### Classification (60 live screens)

| Class | Count | Meaning |
|---|---|---|
| **S8** | 12 | Already redesigned in Stage 8 from the approved Stitch references |
| of which **S8-R** | 4 | S8, but shared with artisans or admins, so they need a role review: Chat, Notifications, Profile, Verification |
| **NEW** | 42 | No Stitch reference; a new proposed design is required (previews rendered, awaiting approval) |
| **SHARED** | 6 | No Stitch reference and shared between roles; a proposed design requires review for every role: Job detail, Chat list, Settings, Support, About, Portfolio viewer |
| **Stitch available, not yet implemented** | 0 | — |
| **OBS** | 6 items | Obsolete, with evidence (§5); not counted in the 60 |

No live screen keeps the old visual system after Phase C. Every **NEW** and **SHARED** screen has a rendered preview or a documented reuse of a previewed layout (`STAGE8_MISSING_DESIGNS.md`).

**Key to the tables:**
- **Stitch:** reference numbers from `design/stitch_reference/`.
- **Old:** the pre-Stage 8 theme (`AppTheme` / `context.colors`).
- **Admin:** the separate `AdminPalette`.
- **Preview:** a file in `design/stage8_1_previews/`.

---

## 1. System, onboarding and authentication (all roles): 13

| ID | Screen | File · route | Purpose and existing functionality | Backend | Current visual | Stitch | Proposed design | Class |
|---|---|---|---|---|---|---|---|---|
| SY-01 | App initialisation | `main.dart` `_InitializationScreen` (before router) | Loading while Firebase initialises | Firebase init | Old | — | Same as AU-00 splash | NEW |
| SY-02 | Startup error | `widgets/startup_error_screen.dart` | Init failure + Retry | — | Old | — | `au00b_startup_error` | NEW |
| SY-03 | Splash | `screens/auth/splash_screen.dart` · `/` | Waits for auth and onboarding flag, then redirects | Auth state, prefs | Old | — | `au00_splash` | NEW |
| SY-04 | Route not found | GoRouter default error page (no `errorBuilder`) | Unknown URL | — | **Unstyled framework default** | — | `sy01_not_found` (new copy) | NEW |
| SY-05 | Cannot open directly | `widgets/cannot_open_directly_screen.dart` (`/portfolio-project` without `extra`) | Deep-link and refresh fallback + Go back | — | Old | — | `sy02_cannot_open_directly` | NEW |
| ON-01 | Onboarding / welcome | `ui/screens/onboarding_screen.dart` · `/onboarding` | Get Started / Skip, shown once | prefs | **New** | #13, #14 | — | S8 |
| AU-01 | Sign In | `screens/auth/login_screen.dart` · `/login` | Email/password sign-in, forgot password, sign up | `AuthService.signIn`, `friendlyError` | Old | — | `au01_login`, `au01b_login_error`, `au01c_login_loading` | NEW |
| AU-02 | Sign Up | `screens/auth/register_screen.dart` · `/register` | Role choice, name, email, city, password ×2; sends verification email | `AuthService.register` (+ `users` doc), `sendEmailVerification` | Old | — | `au02_register`, `au02b_register_errors` | NEW |
| AU-03 | Password recovery | `screens/auth/forgot_password_screen.dart` · `/forgot-password` | Send reset link; "Check your inbox" state | `sendPasswordResetEmail` (`user-not-found` treated as success) | Old | — | `au03_forgot_password`, `au03b_reset_link_sent` | NEW |
| AU-04 | Verify email | `screens/auth/verify_email_screen.dart` · `/verify-email` | Resend link, use a different account; auto-advance | `sendEmailVerification`, router guard | Old | — | `au04_verify_email` | NEW |
| AU-05 | Role selection | `screens/auth/role_selection_screen.dart` · `/role-select` | Dual-role users choose the active role | `ProfileService.setActiveRole` | Old | — | `au05_role_select` | NEW |
| AU-06 | Artisan registration | `screens/auth/artisan_registration_screen.dart` · `/register/artisan` | Category, skills, about, service area → review | `artisans`/`users` writes (rules) | Old | — | `au06_artisan_registration` | NEW |
| AU-07 | Suspended | `screens/auth/suspended_screen.dart` · `/suspended` | Explains suspension; existing jobs (restricted types); sign out | Router suspension guard | Old | — | `au07_suspended` | NEW |

## 2. Customer only: 14

| ID | Screen | File · route | Purpose and existing functionality | Backend | Current visual | Stitch | Proposed design | Class |
|---|---|---|---|---|---|---|---|---|
| CU-01 | Customer shell | `ui/screens/customer_shell.dart` · `/home` | Bottom nav: Discovery · Bookings · Payments · Profile | — | New | #4–6, #19, #21, #22 | — | S8 |
| CU-02 | Discovery | `ui/screens/discovery_screen.dart` · tab, `/browse-artisans` | Search, category chips, featured artisans | `featuredArtisansProvider` | New | #8, #15 | — | S8 |
| CU-03 | Artisan public profile | `ui/screens/artisan_profile_screen.dart` · `/artisan/:uid` | Stats, about, skills, portfolio, reviews, favourite, Book | artisans, reviews, portfolio, favourites, `acceptArtisan` | New | #2, #16 | — | S8 |
| CU-04 | Post a Job | `ui/screens/post_job_screen.dart` · `/request` | Photos, category, description, location, budget | `submitRequest`, `ImagePrivacy`, `LocationService` | New | #3, #17 | — | S8 |
| CU-05 | Choose an artisan (matched) | `screens/artisan/artisan_list_screen.dart` · `/artisans/:jobId` | Top / Rising professionals; Select | `matchingProvider`, `acceptArtisan` | Old | — | `cu06_matched_artisans` | NEW |
| CU-06 | Secure booking | `screens/artisan/secure_booking_screen.dart` · `/secure-booking/:artisanId` | Task, schedule (date picker), proposed budget, 5% fee preview, send request | `JobService` create + direct hire | Old | — | `cu05_secure_booking` | NEW |
| CU-07 | My Bookings | `ui/screens/bookings_screen.dart` · tab, `/jobs` | Active/Completed/Disputed, lifecycle, Approve & Release, Pay | jobs, quotes, `confirmComplete` | New | #4, #19 | — | S8 |
| CU-08 | Confirm & Pay | `ui/screens/confirm_pay_screen.dart` · `/payment/:jobId` | Server breakdown, Paystack init | `getPaymentBreakdown`, `initializePaystackTransaction` | New | #10, #18 | — | S8 |
| CU-09 | Paystack checkout | `screens/payment/payment_webview_screen.dart` · `/payment/:jobId/webview` | Hosts the Paystack page | Paystack (third-party page) | Old frame | — | `cu10_payment_checkout` (frame only; Paystack page not restyled) | NEW |
| CU-10 | Payment result | same file, `_PaymentResultView` | Verifying / Successful / Not Completed; Try Again; View Job | `verifyPayment` | Old | — | `cu08_payment_result`, `cu08b_payment_not_completed`, `cu08c_payment_verifying` | NEW |
| CU-11 | Payments (history) | `ui/screens/payments_screen.dart` · tab, `/wallet` | Escrow summary, active contracts, transactions → job | `customerPaymentsProvider` | New | #5, #21 | — | S8 |
| CU-12 | Saved artisans | `screens/artisan/favorites_screen.dart` · `/favorites` | Favourites list, remove, Hire | `favorites` | Old | — | `cu07_favorites` | NEW |
| CU-13 | Raise dispute | `screens/dispute/dispute_screen.dart` · `/dispute/:jobId` | Reason chips, details, evidence photos | `DisputeService.raiseDispute` | Old | — | `cu03_dispute` | NEW |
| CU-14 | Leave a review | `screens/review/review_screen.dart` · `/review/:jobId` | Stars, comment, skip | review service | Old | — | `cu04_review` | NEW |

## 3. Shared customer and artisan: 10

| ID | Screen | File · route | Purpose and existing functionality | Backend | Current visual | Stitch | Proposed design | Class |
|---|---|---|---|---|---|---|---|---|
| SH-01 | **Job detail** (role-aware) | `screens/job/job_detail_screen.dart` · `/job/:jobId` | Status, quotes inbox (sort Price/Trust; accept/decline/chat), agreement (confirm/accept/request changes), appointment slots (propose/confirm; date/time pickers), start, progress, rework, dispute countdown and thread, cancel / paid-cancellation / decline / withdraw, location, photos, timeline. 19 escrow actions | `JobService` transactions, `artisanWithdrawFromJob`, disputes | Old | — | `ar04_job_detail` (artisan), `cu12_job_detail_customer_quotes` (customer), `ar04c_propose_slots`, `dl06`, `dl07`, `dl08` | SHARED |
| SH-02 | Chat conversation | `ui/screens/chat_screen.dart` · `/chat/:jobId` | Text/image messages, price proposal, workflow chips | chat services | New | #11, #20 | — | S8-R |
| SH-03 | **Chat list** | `screens/chat/my_chats_screen.dart` · `/my-chats` | Conversations, unread, search | chat providers | Old | — | `ar12_messages` | SHARED |
| SH-04 | Notifications | `ui/screens/notifications_screen.dart` · `/notifications` | Filters, mark read / all, deep link via allow-list | notifications | New | #12, #24 | — | S8-R |
| SH-05 | Profile | `ui/screens/profile_screen.dart` · tab, `/profile` | Avatar upload, stats, menu, dark mode, Artisan Mode, admin entry, log out | profile service | New | #6, #22 | — | S8-R |
| SH-06 | **Settings** (account, security, privacy, notifications) | `screens/settings/settings_screen.dart` · `/settings` | Username, display name, change email (re-auth), change password (re-auth), active mode, verification link, dark mode, push notifications on/off, artisan payout / business / portfolio links, help articles and FAQ, contact, request / cancel account deletion, remove photo, sign out | `ProfileService`, `AuthService`, `users` | Old | — | `cu01_settings`, `dl01`–`dl05` | SHARED |
| SH-07 | **Help & Support** | `screens/support/contact_support_screen.dart` · `/support` | Submit ticket; your tickets (Open/Resolved) | `SupportTicketService` | Old | — | `cu02_support` | SHARED |
| SH-08 | **About** | `screens/support/about_screen.dart` · `/about` | Version, Terms, Privacy Policy links | — | Old | — | `cu09_about` | SHARED |
| SH-09 | Identity verification | `ui/screens/verification_screen.dart` · `/verification` | ID + selfie upload, status | verification service | New | #7, #23 | — | S8-R |
| SH-10 | **Portfolio viewer** (full screen) | `widgets/portfolio_viewer.dart` (`showPortfolioViewer`) | Swipe through project photos | — | Old | — | `sh01_portfolio_viewer` | SHARED |

## 4. Artisan only: 10

| ID | Screen | File · route | Purpose and existing functionality | Backend | Current visual | Stitch | Proposed design | Class |
|---|---|---|---|---|---|---|---|---|
| AR-00 | Artisan shell | `widgets/premium_scaffold.dart` `MainShellScreen` via `HomeScreen._ArtisanHome` · `/home` | Tabs today: Home · Jobs · Chats · Profile | — | Old | — | 5-item nav (approved D-2), visible in AR previews | NEW |
| AR-01 | Artisan home | `screens/artisan/artisan_dashboard_screen.dart` `ArtisanHomeTabContent` | Verification status, stats, trust-score card (+ breakdown sheet), quick actions, recent jobs | jobs, artisan, verification | Old | — | `ar01_home`, `ar01b_trust_score_sheet` | NEW |
| AR-02 | Find Work | `screens/artisan/open_jobs_feed_screen.dart` · `/open-jobs` | Search, status filter (All Matched / Recent / Urgent), Ready-to-work toggle, job cards, quote submit / edit / withdraw sheet, chat | `openJobsFeedProvider`, `QuoteService`, `ChatService` | Old | — | `ar02_find_work`, `ar02b_quote_sheet` | NEW |
| AR-03 | My Jobs | `screens/home/all_jobs_screen.dart` · `/jobs` (artisan), tab | Active/Completed bookings, open chat | `artisanJobsProvider` | Old | — | `ar03_my_jobs` | NEW |
| AR-04 | Work submission | `screens/job/job_completion_screen.dart` · `/job/:jobId/submit` | Completion photos + notes → submitted (14-day review) | `submitCompletion`, Storage | Old | — | `ar05_submit_work` | NEW |
| AR-05 | Earnings | `screens/wallet/wallet_screen.dart` `_ArtisanEarningsView` · `/wallet` (artisan) | Released / in escrow / pending / completed totals, payout readiness, transactions | `artisanPaymentsProvider`, `artisanPayoutReadyProvider` | Old | — | `ar06_earnings` | NEW |
| AR-06 | Business profile | `screens/artisan/business_profile_screen.dart` · `/business-profile` | Individual/Business, name, registration no., address, service area (GPS) | `artisans/{uid}` | Old | — | `ar07_business_profile` | NEW |
| AR-07 | Payout details | `screens/artisan/bank_details_screen.dart` · `/bank-details` | Bank name, account number, account name | `artisan_private/{uid}` | Old | — | `ar08_payout_details` | NEW |
| AR-08 | Portfolio manager | `screens/artisan/portfolio_manager_screen.dart` · `/portfolio` | Projects/Photos, view counts, add, delete | `PortfolioService` | Old | — | `ar09_portfolio` | NEW |
| AR-09 | Portfolio project editor | `screens/artisan/portfolio_project_screen.dart` · `/portfolio-project` | Add/edit project: title, category, description, photos | `PortfolioService`, Storage | Old | — | `ar10_portfolio_project` | NEW |

## 5. Admin only: 13 (+1 approved new section)

| ID | Section | Class · route | Existing functionality | Backend | Current visual | Stitch | Proposed design | Class |
|---|---|---|---|---|---|---|---|---|
| AD-00 | Admin shell | `AdminShell` + `admin_sidebar.dart` + `_AdminTopBar` · `/admin/*` | Sidebar/drawer, global search, notifications, theme, back to app | `isAdmin` guard | Admin | — | in every AD preview; `ad14_search`, `ad15_notifications` | NEW |
| AD-01 | Dashboard | `_DashboardHomeTab` · `/admin/dashboard` | KPIs, operational alerts + finance actions, charts, pending actions, activity, platform health | many streams; finance callables | Admin | — | `ad01_dashboard_desktop`, `ad01_dashboard_mobile` | NEW |
| AD-02 | Users | `_UsersTab` · `/admin/users` | Search/filter, suspend (type) / reactivate, delete (`adminDeleteUser`), beta tester, contact, activity | users, callable | Admin | — | `ad02_users`, `ad16_delete_user_dialog` | NEW |
| AD-03 | Artisans | `_ArtisansSection` · `/admin/artisans` | Pending applications approve/reject; all artisans | artisans/users | Admin | — | `ad03_artisans_pending` | NEW |
| AD-04 | Jobs | `_JobsTab`, `_JobDetailSheet` · `/admin/jobs` | Search/filter, detail, delete request | jobs, quotes, messages | Admin | — | `ad05_jobs` | NEW |
| AD-05 | Verifications | `_VerificationCenterTab` · `/admin/verifications` | ID/selfie review, approve/reject (reason), image zoom | `VerificationService` | Admin | — | `ad04_verifications` | NEW |
| AD-06 | Disputes | `_DisputesTab` · `/admin/disputes` | Resolve: release / refund / split (+ reason), evidence zoom | `adminResolveDispute` | Admin | — | `ad06_disputes_settlement` | NEW |
| AD-07 | Reviews | `_ReviewsTab` · `/admin/reviews` | Search, delete (rating recalculated) | reviews/artisans | Admin | — | `ad07_reviews` | NEW |
| AD-08 | Support tickets | `_SupportTicketsTab` · `/admin/support` | Filter, Respond & Resolve | `SupportTicketService` | Admin | — | `ad08_support` | NEW |
| AD-09 | Deletion requests | `_DeletionRequestsTab` · `/admin/deletions` | Mark Resolved | `account_deletion_requests` | Admin | — | `ad09_deletions` | NEW |
| AD-10 | Audit logs | `_ActivityTab` · `/admin/audit-logs` | Read-only admin actions | `admin_audit_logs` | Admin | — | `ad10_audit_logs` | NEW |
| AD-11 | Analytics | `_AnalyticsTab` · `/admin/analytics` | Growth, category and rating distributions, funnel counts | streams | Admin | — | `ad11_analytics` | NEW |
| AD-12 | Admin settings | `_AdminSettingsTab` · `/admin/settings` | Account, appearance, sign out | theme, auth | Admin | — | `ad12_settings` | NEW |
| AD-13 | **Finance** *(approved new section; existing records only)* | — · `/admin/finance` | Read-only chargebacks, platform losses, refunds, settlements; payout freeze | rules allow admin read; `adminSetPayoutFreeze` | — | — | `ad13_finance`, `ad13b_payout_freeze` | NEW (approved D-3) |

## 6. Requested areas that don't exist as separate screens today

| Requested | Finding (evidence) | Proposal |
|---|---|---|
| Notification details | No screen. A notification tap marks it read and opens its allow-listed route (`safeNotificationRoute`); the list already shows the full title and body | **None proposed:** the destination screen *is* the detail view (avoids an invented screen). Your call if you want one |
| Transaction details | No screen. Payments rows open the job (`/job/:id`) | **Optional proposed sheet** `cu11_transaction_detail`, using only existing `PaymentModel` fields (amount, platform fee, total, Paystack reference, paid/released dates, status). **Needs your approval** |
| Privacy settings | No dedicated screen. The privacy-related controls live in Settings: push notifications on/off, account deletion request; About links to Privacy Policy and Terms | Grouped under Settings in the proposal; no new privacy controls invented |
| Password reset (choose a new password) | Completed on Firebase's hosted page from the email link; no in-app screen or `confirmPasswordReset` | Not proposed without your approval (design spec Q-2) |
| Profile editing | Exists: avatar upload/remove (Profile, Settings), username and display name dialogs, email and password dialogs (Settings); artisan business profile | Covered by SH-05, SH-06 (`dl01`–`dl03`), AR-06 |
| Security and password | Exists: change password and change email (re-authentication with the current password) in Settings | `dl02`, `dl03` |

## 7. Obsolete views and widgets (evidence; removal proposed in Phase C)

| ID | Item | Evidence | Proposed action |
|---|---|---|---|
| OBS-1 | `_CustomerWalletView` (`wallet_screen.dart`) | `/wallet` sends customers to `PaymentsScreen` through `_RoleAware` (`router.dart:477`: `isArtisan && activeRole == 'artisan'`); `WalletScreen` is built only for that artisan branch, and uses the same test (`wallet_screen.dart:38`) | Remove with AR-05 |
| OBS-2 | `AllJobsScreen` customer branch (customer jobs list, "Post a Job" card) | `/jobs` sends customers to `BookingsScreen`; `AllJobsScreen` is built only for artisans (`router.dart:224`, `home_screen.dart:50`). **Note F-11** | Remove with AR-03 |
| OBS-3 | `ArtisanDashboardScreen` wrapper class | No constructor call anywhere; comment says "kept only for compatibility" | Remove with AR-01 |
| OBS-4 | `widgets/cancellation_reason_dialog.dart` | Only referenced in a comment (`job_detail_screen.dart:2158`) | Remove |
| OBS-5 | `widgets/artisan_card.dart` | No importers | Remove |
| OBS-6 | `widgets/loading_indicator.dart` | No importers | Remove |

**F-11 (pre-existing bug, found in this audit).** `AllJobsScreen` selects artisan mode with `user.isArtisan && !user.isCustomer` (`all_jobs_screen.dart:38`), not `activeRole`. A **dual-role user in Artisan Mode sees their customer jobs** in My Jobs. The proposed AR-03 uses `activeRole`, consistent with `_RoleAware` and `WalletScreen`.

## 8. Overlays: 47 distinct live interfaces (+1 proposed)

**Key:** **S8** = already new; **P** = previewed; **R** = reuses a previewed pattern (dialog card, sheet, reason dialog, confirm sheet).

| ID | Overlay | Where (file:line) | Role | Design |
|---|---|---|---|---|
| OV-01 | Confirm sheet (`htConfirm`): book artisan, approve & release, log out | `ui/components/ht_components.dart:907` (+ 3 uses) | C | S8 |
| OV-02 | Review detail dialog | `ui/screens/artisan_profile_screen.dart:308` | C | S8 |
| OV-03 | Propose price sheet | `ui/screens/chat_screen.dart:91` | C/A | S8 |
| OV-04 | Attach photo sheet | `ui/screens/chat_screen.dart:137` | C/A | S8 |
| OV-05 | Job location sheet | `ui/screens/post_job_screen.dart:94` | C | S8 |
| OV-06 | ID photo source sheet | `ui/screens/verification_screen.dart:51` | A | S8 |
| OV-07 | Secure booking date picker | `secure_booking_screen.dart:87` | C | P (`dl08_date_picker`: themed Material picker) |
| OV-08 | Request agreement changes | `job_detail_screen.dart:2163` | C | P `dl07_request_changes` |
| OV-09 | Request rework changes | `job_detail_screen.dart:579` | C | R (`dl07` pattern) |
| OV-10 | Cancel / decline / withdraw reason dialog | `job_detail_screen.dart:800` | C/A | P `dl06_cancel_job` |
| OV-11 | Paid-cancellation request dialog | `job_detail_screen.dart:856` | C/A | R (`dl06`) |
| OV-12 | Appointment date picker | `job_detail_screen.dart:2223` | A | P `dl08` |
| OV-13 | Appointment time picker | `job_detail_screen.dart:2230` | A | R (`dl08` theme) |
| OV-14 | Submit/edit quote sheet | `open_jobs_feed_screen.dart:813` | A | P `ar02b_quote_sheet` |
| OV-15 | Trust-score breakdown sheet | `widgets/trust_score_card.dart:187` | A | P `ar01b_trust_score_sheet` |
| OV-16 | Edit username | `settings_screen.dart:227` | all | R (`dl01`) |
| OV-17 | Edit name | `settings_screen.dart:246` | all | P `dl01_edit_name` |
| OV-18 | Change email (re-auth) | `settings_screen.dart:265` | all | P `dl02_change_email` |
| OV-19 | Change password (re-auth) | `settings_screen.dart:272` | all | P `dl03_change_password` |
| OV-20 | Switch active mode | `settings_screen.dart:280` | dual role | P `dl05_switch_mode` |
| OV-21 | Sign out confirm | `settings_screen.dart:307` | all | R (OV-01 sheet) |
| OV-22 | Request account deletion (optional reason) | `settings_screen.dart:331` | all | P `dl04_request_deletion` |
| OV-23 | Cancel deletion request | `settings_screen.dart:381` | all | R (OV-01) |
| OV-24 | Remove profile photo | `settings_screen.dart:445` | all | R (OV-01) |
| OV-25 | Admin global search | `admin_dashboard_screen.dart:232, 624` | Ad | P `ad14_search` |
| OV-26 | Admin notifications | `admin_dashboard_screen.dart:969` | Ad | P `ad15_notifications` |
| OV-27 | Chart period menu | `admin_dashboard_screen.dart:1494` | Ad | R (chip menu in `HtChartCard`) |
| OV-28 | Settlement dialog (paid cancellation; dispute) | `admin_finance_dialogs.dart:53` (uses at `:2151`, `:3751`) | Ad | P `ad06_disputes_settlement` |
| OV-29 | Reason dialog (refund charge / retry refund / retry payout) | `admin_finance_dialogs.dart:150` (uses at `:2165`, `:2174`, `:2182`) | Ad | R (`ad13b` dialog pattern) |
| OV-30 | Suspension type dialog | `admin_finance_dialogs.dart:197` (use at `:4603`) | Ad | R (`dl05` option cards) |
| OV-31 | Approve/reject artisan confirm | `admin_dashboard_screen.dart:2464` | Ad | R (`ad16`) |
| OV-32 | Reject verification (reason) | `:3482` | Ad | R (`ad13b`) |
| OV-33 | Verification image zoom | `:3541` | Ad | R (`sh01_portfolio_viewer`) |
| OV-34 | Dispute evidence zoom | `:3777` | Ad | R (`sh01`) |
| OV-35 | Beta tester confirm | `:4344` | Ad | R (`ad16`) |
| OV-36 | Delete user confirm | `:4535` | Ad | P `ad16_delete_user_dialog` |
| OV-37 | Suspend / reactivate confirm | `:4607` | Ad | R (`ad16`) |
| OV-38 | User contact details | `:4882` | Ad | R (detail panel, `ad02`) |
| OV-39 | User activity sheet | `:4945` | Ad | R (detail panel, `ad02`) |
| OV-40 | Respond & resolve ticket | `:5436` | Ad | P (panel in `ad08_support`) |
| OV-41 | Delete review confirm | `:5783` | Ad | R (`ad16`) |
| OV-42 | Job detail sheet | `:6060` | Ad | P (panel in `ad05_jobs`) |
| OV-43 | Delete job confirm | `:6226` | Ad | R (`ad16`; gated per F-1) |
| OV-44 | Data-table row sheet (narrow screens) | `admin_data_table.dart:308` | Ad | R (bottom-sheet detail) |
| OV-45 | Snackbars (success/error) | across screens | all | S8 `htSnack` |
| OV-46 | Image picker (camera/gallery, system UI) | job, chat, verification, portfolio, avatar | all | System UI (not restyled); entry sheets themed |
| OV-47 | Portfolio viewer push | `portfolio_manager_screen.dart:390` | A | P `sh01` |
| OV-P1 | **Payout freeze confirm** (approved, new exposure) | — | Ad | P `ad13b_payout_freeze` |

---

## 9. Your 22-category checklist → where each is covered

| # | Category | IDs |
|---|---|---|
| 1 | Onboarding | ON-01 |
| 2 | Sign In and Sign Up | AU-01, AU-02 |
| 3 | Authentication and password recovery | SY-01–03, AU-03–07 (§6 password reset) |
| 4 | Customer dashboard and discovery | CU-01, CU-02 |
| 5 | Artisan dashboard | AR-00, AR-01 |
| 6 | Admin dashboard | AD-00, AD-01 |
| 7 | Artisan profiles | CU-03 (public), AR-06, AR-08, AR-09, SH-10 |
| 8 | Job creation and management | CU-04, CU-07, AR-03 |
| 9 | Job details and booking | SH-01, CU-05, CU-06 |
| 10 | Quote management | AR-02 (+ OV-14), SH-01 quotes inbox |
| 11 | Chat list and conversations | SH-03, SH-02 (+ OV-03, OV-04) |
| 12 | Notifications | SH-04, OV-26 (§6 details) |
| 13 | Customer and artisan profiles | SH-05, CU-03 |
| 14 | Profile editing | SH-05 avatar, SH-06 (OV-16–OV-19, OV-24), AR-06 |
| 15 | Security and password settings | SH-06 (OV-18, OV-19) |
| 16 | Privacy and account settings | SH-06 (notifications, deletion OV-22/23), SH-08 policies |
| 17 | Payments and transaction history | CU-08–CU-11, AR-05 (§6 transaction details) |
| 18 | Disputes and refunds | CU-13, SH-01 dispute thread, AD-06, AD-13, OV-28/29 |
| 19 | Reviews and ratings | CU-14, CU-03 reviews, AD-07 |
| 20 | Help and support | SH-07, SH-06 help articles, AD-08 |
| 21 | Admin financial management | AD-01 alerts, AD-06, AD-13, OV-28, OV-29, OV-P1 |
| 22 | Additional screens discovered | SY-01, SY-02, SY-04, SY-05, CU-09, CU-10, SH-10, AR-09, OBS-1–6, OV-07–OV-44 |

---

## 10. Owner decisions applied (2026-11-04)

| Decision | Effect on the inventory |
|---|---|
| Q-1 | AD-04: deletion stays blocked for paid and disputed jobs; chat history and dispute evidence are preserved; no archive field |
| Q-2 | AU-03: Firebase-hosted reset kept; only the surrounding screens are redesigned |
| Q-3 | AU-02 and SH-06 (OV-19): one `PasswordPolicy` (8+ characters, uppercase letter, number) for new and changed passwords; sign-in unaffected |
| Q-4 | AD-13: Finance read-only; chargeback close/investigate not exposed |
| Q-5 | AD-13, AD-02, AD-04: payout-freeze state displayed from the existing server fields (additive read-only model parse) |
| Q-6 | Unverified timing promises removed (list in `STAGE8_FINAL_AUTHORIZATION_PACKAGE.md`); the booking window is read from config |
| Q-7 | **New approved overlay:** transaction details sheet over CU-11 (existing `PaymentModel` fields only) |
| Q-8 | No notification-details screen; SH-04 keeps navigation to the destination |
| Q-9 | AR-03: F-11 fixed (`activeRole`) |
| Additional | SY-04 styled not-found **approved**; AU-07 Contact support **approved** (destination verified); AR-01 payout reminder **approved** (bound to `artisanPayoutReadyProvider`) |

**New finding:** F-12. The Settings account-deletion copy states preconditions ("Active jobs and escrow must be resolved first") that aren't enforced anywhere (`ProfileService.requestAccountDeletion`, `adminDeleteUser`). The replacement copy is proposed in the authorization package (U-1).

Per-screen design status (Approved / Ready / Unresolved) is in `STAGE8_FINAL_AUTHORIZATION_PACKAGE.md` §3.
