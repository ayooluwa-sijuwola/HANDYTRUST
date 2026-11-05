# HandyTrust — Stage 8.1 Design Specification (all three roles), v2

Date: 2026-11-04

**Status:** decisions D-1 to D-7 are approved in principle, with your conditions. Rendered previews are produced and awaiting your approval: see `STAGE8_1_PREVIEW_REVIEW.md`. **No screen has been built into the app, and none has been deleted.**

**Inputs:**
- `STAGE8_1_ARTISAN_ADMIN_AUDIT.md` (features, backend map, findings F-1 to F-10).
- The Stage 8 customer design system (`lib/ui/`).
- Your approval message.
- The authentication addendum (auth replacement is mandatory and must stay fully functional).

**Rules applied to every screen:**
- Every control maps to an existing provider, service or callable.
- Nothing is removed. No metric, permission, method or figure is invented.
- Where data doesn't exist, the element isn't shown.
- Visual change and functional change are always listed separately (§9 and the preview review).

---

## 1. Approved decisions and their conditions

| ID | Decision | Conditions carried into Phase C |
|---|---|---|
| D-1 | **Full UI replacement:** customer, artisan, admin and authentication; every remaining old screen | One design system; `lib/theme/app_*`, the admin palette and the obsolete `lib/widgets/*` are deleted at the end |
| D-2 | Artisan nav **Home · Find Work · My Jobs · Earnings · Profile**; Messages and Notifications in the header | — |
| D-3 | Admin **Finance** (read-only, existing records) + **payout freeze** | Admin authorization (server `_requireAdmin`, router `isAdmin` guard); mandatory reason (server enforces ≥ 10 characters); confirmation dialog; audit log (server writes `admin_audit_logs` + `financial_events` in the same batch); status feedback; no new financial infrastructure |
| D-4 | Fix F-1, F-2, F-3 | **F-1:** the eligibility check happens *before* anything is deleted; chat and dispute evidence on paid jobs is preserved; archival preferred (see Q-1). **F-2:** readable labels **plus** the original identifier, for all alert types (16 unlabelled, §6). **F-3:** "Super Administrator" is removed; plain "Administrator" (no role hierarchy exists) |
| D-5 | Admin and artisan writes move into services | Same writes, permissions, validation and transactions; rules untouched |
| D-6 | Artisan route redirect | UI convenience only; rules and Cloud Functions remain the security boundary |
| D-7 | Rendered previews before any destructive step | Done, 86 renders (`STAGE8_1_PREVIEW_REVIEW.md`) |
| Auth addendum | Replace the full auth presentation layer, fully functional | Firebase Auth (email/password), `AuthService`, account models, role assignment, email verification, session handling and the router guards are unchanged. **No new sign-in methods** |

---

## 2. Design system (one system, three roles)

**Unchanged from Stage 8:**
- `HtPalette` dark/light (via `themeProvider`), `HtType` (Plus Jakarta Sans display + Inter text), `HtSpace`, `HtRadius`.
- The Stage 8 components (headers, buttons, chips, segmented tabs, pills, cards, banners, stat tiles, menu rows, avatar, lifecycle, form fields, state views, snackbar, confirm sheet, floating bottom nav).

**Additions, prototyped in `test_visual/previews/preview_kit.dart`** (moved to `lib/ui/components/` in Phase C):

| Addition | Use |
|---|---|
| Chart series tokens: light `#6E7D31 #2A78D6 #D55181`, dark `#8E9F45 #3987E5 #D55181` | Validated with the data-viz palette checks (lightness, chroma, colour-blind separation, normal-vision floor, contrast); all pass in both modes |
| `htInfo` | Informational alert tone |
| `HtKpiTile` | Metric + definition. Trend shown as arrow + signed % + "vs last week"; metrics without a trend show their definition (e.g. "Payments currently held in escrow") |
| `HtFilterBar` | Search + chips (stacks below 900 px) |
| `HtDataTable` / `HtListCard` | Wide tables / narrow rows; numeric columns right-aligned with a gutter |
| `HtSideNav`, `AdminFrame`, `HtAdminTopBar` | Admin rail (≥ 1,024 px) / drawer; right-side detail panel (≥ 1,024 px) or bottom sheet |
| `HtAlertRow` | Severity icon + label + **original type id** + actions |
| `HtChartCard` (+ line chart, bar list) | Legend for ≥ 2 series, 2 px lines, 4 px rounded bar ends, "View as table" |
| `HtSheet`, `HtDialogCard`, `HtDangerButton` | Sheets, admin dialogs, destructive actions |
| `HtJobCard`, `HtTimeline`, `HtToggleRow`, `HtPhotoTile` / photo grid | Artisan feed, workflow history, switches, photos |
| Field error state | Danger border + message under the field (auth and forms) |

**Breakpoints:**
- **Phone:** < 600 px.
- **Tablet:** 600–1,023 px. Content is max 640–720 wide; admin uses the drawer with a 2-column KPI grid.
- **Desktop:** ≥ 1,024 px. Admin uses the rail, a 4-column KPI grid, tables and the side panel.

---

## 3. Complete screen inventory (all roles)

**Status key:**
- **S8** = already replaced in Stage 8.
- **P** = proposed and previewed (file in `design/stage8_1_previews/`).
- **P*** = proposed and specified but not separately previewed, because it reuses previewed layouts (listed in the preview review).

### 3.1 Authentication and app entry (all roles)

| ID | Screen | Route | Current file (to replace) | Status | Preview |
|---|---|---|---|---|---|
| AU-00 | Splash / loading | `/` | `auth/splash_screen.dart` | P | `au00_splash` |
| AU-00b | Startup error (retry) | (app start) | `widgets/startup_error_screen.dart` | P | `au00b_startup_error` |
| AU-OB | Onboarding / welcome | `/onboarding` | — | **S8** | (Stage 8 #13/#14) |
| AU-01 | Sign In (+ error, loading) | `/login` | `auth/login_screen.dart` | P | `au01_login`, `au01b_login_error`, `au01c_login_loading` |
| AU-02 | Sign Up (role, fields; + validation and server errors) | `/register` | `auth/register_screen.dart` | P | `au02_register`, `au02b_register_errors` |
| AU-03 | Password recovery (+ link sent) | `/forgot-password` | `auth/forgot_password_screen.dart` | P | `au03_forgot_password`, `au03b_reset_link_sent` |
| AU-03c | Password reset (new password) | Firebase-hosted action page | — | **Not an app screen today** (Q-2) | — |
| AU-04 | Verify email | `/verify-email` | `auth/verify_email_screen.dart` | P | `au04_verify_email` |
| AU-05 | Role selection (dual-role users) | `/role-select` | `auth/role_selection_screen.dart` | P | `au05_role_select` |
| AU-06 | Artisan registration / profile setup | `/register/artisan` | `auth/artisan_registration_screen.dart` | P | `au06_artisan_registration` |
| AU-07 | Suspended | `/suspended` | `auth/suspended_screen.dart` | P | `au07_suspended` |

### 3.2 Customer

| ID | Screen | Route | Current file | Status | Preview |
|---|---|---|---|---|---|
| C-1 … C-11 | Discovery, Artisan Profile, Post a Job, Bookings, Confirm & Pay, Payments, Chat, Profile, Verification, Notifications, Shell | various | `lib/ui/screens/*` | **S8** | Stage 8 goldens |
| CU-01 | Settings | `/settings` | `settings/settings_screen.dart` | P | `cu01_settings` |
| CU-02 | Help & Support (+ tickets) | `/support` | `support/contact_support_screen.dart` | P | `cu02_support` |
| CU-03 | Raise dispute | `/dispute/:jobId` | `dispute/dispute_screen.dart` | P | `cu03_dispute` |
| CU-04 | Leave a review | `/review/:jobId` | `review/review_screen.dart` | P | `cu04_review` |
| CU-05 | Secure booking | `/secure-booking/:artisanId` | `artisan/secure_booking_screen.dart` | P | `cu05_secure_booking` |
| CU-06 | Choose an artisan (matched list) | `/artisans/:jobId` | `artisan/artisan_list_screen.dart` | P | `cu06_matched_artisans` |
| CU-07 | Saved artisans | `/favorites` | `artisan/favorites_screen.dart` | P | `cu07_favorites` |
| CU-08 | Payment result (success / not completed / verifying) | `/payment/:jobId/webview` | `payment/payment_webview_screen.dart` (checkout webview kept; result states redesigned) | P | `cu08_payment_result` |
| CU-09 | About | `/about` | `support/about_screen.dart` | P | `cu09_about` |

### 3.3 Shared customer and artisan

| ID | Screen | Route | Current file | Status | Preview |
|---|---|---|---|---|---|
| AR-04 | Job detail (role-aware; all 19 actions) | `/job/:jobId` | `job/job_detail_screen.dart` | P | `ar04_job_detail` (artisan view; the customer view uses the same sections) |
| AR-12 | Messages (chat list) | `/my-chats` | `chat/my_chats_screen.dart` | P | `ar12_messages` |

### 3.4 Artisan

| ID | Screen | Route | Current file | Status | Preview |
|---|---|---|---|---|---|
| AR-00 | Artisan shell + 5-item nav | `/home` (artisan) | `home_screen.dart` `_ArtisanHome` / `premium_scaffold.dart` | P | (nav visible in all tab previews) |
| AR-01 | Home | `/home` tab 0 | `artisan/artisan_dashboard_screen.dart` | P | `ar01_home` |
| AR-02 | Find Work (search, status filter All Matched / Recent / Urgent, quote sheet) | `/open-jobs`, tab 1 | `artisan/open_jobs_feed_screen.dart` | P | `ar02_find_work`, `ar02b_quote_sheet` |
| AR-03 | My Jobs | `/jobs` (artisan), tab 2 | `home/all_jobs_screen.dart` | P | `ar03_my_jobs` |
| AR-05 | Submit work | `/job/:jobId/submit` | `job/job_completion_screen.dart` | P | `ar05_submit_work` |
| AR-06 | Earnings | `/wallet` (artisan), tab 3 | `wallet/wallet_screen.dart` | P | `ar06_earnings` |
| AR-07 | Business profile | `/business-profile` | `artisan/business_profile_screen.dart` | P | `ar07_business_profile` |
| AR-08 | Payout details | `/bank-details` | `artisan/bank_details_screen.dart` | P | `ar08_payout_details` |
| AR-09 | Portfolio manager | `/portfolio` | `artisan/portfolio_manager_screen.dart` | P | `ar09_portfolio` |
| AR-10 | Portfolio project editor | `/portfolio-project` | `artisan/portfolio_project_screen.dart` | P* | uses the AR-05 form + photo grid |
| AR-13 | Profile (artisan rows), verification, notifications, chat | tab 4 and others | `lib/ui/screens/*` | **S8** | Stage 8 goldens |

### 3.5 Admin

| ID | Section | Route | Current class | Status | Preview |
|---|---|---|---|---|---|
| AD-0 | Shell (rail / drawer, top bar) | `/admin/*` | `AdminShell`, `admin_sidebar.dart`, `_AdminTopBar` | P | all admin previews |
| AD-1 | Dashboard (desktop + mobile) | `/admin/dashboard` | `_DashboardHomeTab` | P | `ad01_dashboard_desktop`, `ad01_dashboard_mobile` |
| AD-2 | Users (+ detail panel, suspend, delete) | `/admin/users` | `_UsersTab` | P | `ad02_users` |
| AD-3 | Artisans (pending / all) | `/admin/artisans` | `_ArtisansSection` | P* | AD-2 table + AD-4 review card |
| AD-4 | Verifications | `/admin/verifications` | `_VerificationCenterTab` | P | `ad04_verifications` |
| AD-5 | Jobs (+ detail, gated delete) | `/admin/jobs` | `_JobsTab`, `_JobDetailSheet` | P | `ad05_jobs` |
| AD-6 | Disputes (+ settlement dialog) | `/admin/disputes` | `_DisputesTab` | P | `ad06_disputes_settlement` |
| AD-7 | Reviews | `/admin/reviews` | `_ReviewsTab` | P* | AD-6 card + reason dialog |
| AD-8 | Support tickets | `/admin/support` | `_SupportTicketsTab` | P* | CU-02 list + reason dialog |
| AD-9 | Deletion requests | `/admin/deletions` | `_DeletionRequestsTab` | P* | AD-2 table |
| AD-10 | Audit logs | `/admin/audit-logs` | `_ActivityTab` | P | `ad10_audit_logs` |
| AD-11 | Analytics | `/admin/analytics` | `_AnalyticsTab` | P* | AD-1 chart cards |
| AD-12 | Settings | `/admin/settings` | `_AdminSettingsTab` | P | `ad12_settings` |
| AD-13 | **Finance** (new section, read-only) + **payout freeze** | `/admin/finance` (new URL) | — | P | `ad13_finance`, `ad13b_payout_freeze` |

**Totals (superseded by the complete audit):**
- `STAGE8_COMPLETE_SCREEN_INVENTORY.md` is now the authoritative list: **60 live screens** (12 Stage 8, 42 new, 6 shared), **47 overlays**, the approved Finance section and 6 obsolete items.
- **70 previews / 140 renders** are in `STAGE8_COMPLETE_DESIGN_PREVIEW_REPORT.md`.
- The tables above use the Stage 8.1 IDs; the complete inventory's IDs are the reference for Phase C.

---

## 4. Navigation map

```
APP START
  /  Splash ──(startup failure)──► Startup error ──Retry──► /
   ├─ signed out, onboarding not seen ─► /onboarding ─Get Started─► /register
   │                                                 └─Skip──────► /login
   ├─ signed out ─► /login ──Sign Up──► /register ──► (verification email sent) ─► /verify-email
   │                 └─Forgot Password?─► /forgot-password ─► "Check your inbox"
   │                                       └─ email link ─► Firebase-hosted reset page ─► /login
   ├─ signed in, email not verified ─► /verify-email (Resend · Use a different account)
   ├─ suspended ─► /suspended (existing jobs, disputes, notifications, support only)
   ├─ dual role, no active role ─► /role-select ─► /home (customer | artisan)
   └─ /home

CUSTOMER  (bottom nav: Discovery · Bookings · Payments · Profile; header: bell)
  Discovery ─► /artisan/:uid ─► /secure-booking/:id ─► job created
  Post a Job (/request) ─► /artisans/:jobId (Choose an Artisan) ─► /job/:id
  Bookings ─► /job/:id · /chat/:id · /payment/:id ─► webview ─► Payment result ─► /job/:id
           └─ Approve & Release (sheet) · /dispute/:id · /review/:id
  Payments ─► /job/:id
  Profile ─► /jobs · /my-chats · /settings · /support · /about · /favorites
           · /verification (artisans) · /admin (admins only) · Artisan Mode (dual role)
  Notifications (bell) ─► allow-listed routes only (safeNotificationRoute)

ARTISAN  (bottom nav: Home · Find Work · My Jobs · Earnings · Profile; header: Messages · bell)
  Home ─► /verification · /bank-details · /business-profile · /portfolio · /open-jobs · /job/:id
  Find Work (/open-jobs) ─► quote sheet (submit / edit / withdraw) · /chat/:id
  My Jobs (/jobs) ─► /job/:id ─► confirm booking · agreement · slots · start · progress
                               · /job/:id/submit · rework · dispute reply · withdraw
  Earnings (/wallet) ─► /job/:id · /bank-details
  Profile (S8) ─► reviews · earnings · verification · settings · Customer Mode (dual role)
  Messages (header) ─► /my-chats ─► /chat/:id
  Artisan-only routes visited by a non-artisan ─► redirect to /home (D-6; UI only)

ADMIN  (/admin/*, isAdmin guard; rail ≥1024 px, drawer below; top bar: search · alerts · theme · Back to app)
  Overview:    Dashboard (alerts → Finance / job / retry actions) · Analytics
  People:      Users (detail: suspend / unsuspend / delete) · Artisans (approve / reject) · Verifications
  Operations:  Jobs (detail: gated delete) · Disputes (settlement) · Support · Reviews · Deletion requests
  Finance:     Chargebacks · Platform losses · Refunds · Settlements (read-only) · payout freeze
  Compliance:  Audit logs
  Settings     (account, appearance, sign out) · Back to app ─► /home
```

---

## 5. Authentication specification (must stay fully functional)

**Unchanged contract:**
- `AuthService`: `createUserWithEmailAndPassword` + `sendEmailVerification`, `signInWithEmailAndPassword`, `sendPasswordResetEmail`, sign-out.
- `authNotifierProvider` (password-reset handling, including `user-not-found` treated as success).
- `UserModel` roles and `activeRole`.
- The router `redirect`: email verification, suspension, dual-role, onboarding.

| Screen | Fields and actions (existing) | States |
|---|---|---|
| Sign In | Email, password, Forgot Password?, Login to Account, Sign Up | **Loading:** fields locked, button spinner. **Error banner:** `AuthService.friendlyError` text ("Email or password is incorrect.", "Too many attempts…", "No internet connection…", "This account has been disabled…"). **Inline validation:** "Email is required", "Enter a valid email address", "Password is required" |
| Sign Up | Role (Customer: "I need services" / Artisan: "I offer services"), Full Name, Email, City / Area (optional), Password, Confirm Password, Create Account, Sign In | **Inline validation:** existing rules (≥ 8 characters, an uppercase letter, a number, passwords match, valid email, name required). **Server error banner:** e.g. "An account with this email already exists." **Loading** |
| Password recovery | Email, Send Reset Link, Back to Login | **Success:** "Check your inbox" with the email address and an explanation that the link opens the secure Firebase page. Errors per `friendlyError` |
| Verify email | Resend verification email, Use a different account | **Sent confirmation:** "Verification email sent. Check your inbox."; the router advances automatically once verified |
| Role selection | Continue as Customer / Continue as Artisan (dual-role users only) | Selected card + primary CTA |
| Artisan registration | Primary category, skills, about, service area, Submit for review | "Your profile will be reviewed before appearing publicly." |
| Suspended | View My Existing Jobs (restricted suspensions), Sign Out; **proposed addition:** Contact support (`/support` is already permitted for suspended users) | — |
| Splash / startup error | Logo + progress; "Something went wrong while starting HandyTrust." + Retry | — |

**Not proposed (would change the auth architecture; needs your explicit approval):**
- Social or phone sign-in, biometrics, magic links.
- An in-app password-reset screen (Q-2).

---

## 6. Admin alert labels (F-2): all 28 types written to `admin_alerts`

The label and severity are shown next to the **unchanged identifier**. Existing actions stay as they are; no new actions are added.

| Type id | Label | Severity | Existing action |
|---|---|---|---|
| `stuck_escrow_release` | Escrow release stuck | Action required | Resolve |
| `dispute` | Dispute raised | Needs attention | Open dispute |
| `dispute_from_job` | Dispute raised from job | Needs attention | Open dispute |
| `paid_cancellation_request` | Paid cancellation request | Action required | Decline / Full refund / Split |
| `payout_authorization_failed` | Payout authorisation failed | Action required | Retry payout |
| `payout_frozen` | Payout frozen | Needs attention | Retry payout (as today) |
| `autorelease_blocked` | Auto-release blocked | Needs attention | Retry payout |
| `transfer_failed` | Transfer to artisan failed | Action required | Retry payout |
| `charge_requires_refund` | Charge needs a refund | Action required | Refund charge |
| `refund_failed` | Refund failed at Paystack | Action required | Retry refund |
| `refund_needs_attention` | Refund needs customer bank details | Needs attention | Resolve (in Paystack) |
| `refund_submit_unknown` | Refund outcome unknown (reconciling) | Information | Resolve |
| `non_domestic_card_payment` | Non-Nigerian card used | Information | Resolve |
| `chargeback_opened` | Chargeback opened: payout on hold | Action required | View in Finance |
| `chargeback_after_payout` | Chargeback opened after payout | Action required | View in Finance |
| `chargeback_event_after_close` | Chargeback update after case closed | Needs attention | View in Finance |
| `chargeback_paystack_resolved` | Paystack resolved the chargeback | Information | View in Finance |
| `chargeback_reference_mismatch` | Chargeback reference doesn't match payment | Action required | View in Finance |
| `chargeback_unmatched` | Chargeback not matched to a payment | Action required | View in Finance |
| `chargeback_unverified` | Chargeback couldn't be verified with Paystack | Needs attention | View in Finance |
| `chargeback_event_unsupported` | Unsupported chargeback event | Information | Resolve |
| `chargeback_webhook_invalid` | Invalid chargeback webhook | Needs attention | Resolve |
| `chargeback_payout_completed` | Payout completed while chargeback open | Needs attention | View in Finance |
| `chargeback_closed` | Chargeback closed | Information | View in Finance |
| `chargeback_fraud_confirmed` | Chargeback marked as confirmed fraud | Action required | View in Finance |
| `refund_held_chargeback` | Refund held: chargeback open | Needs attention | Resolve |
| `refund_webhook_unmatched` | Refund update not matched to a refund | Needs attention | Resolve |
| `refund_amount_mismatch` | Refund amount differs from request | Action required | Resolve |
| *(any other)* | Unrecognised alert | Information | Resolve; raw id shown |

The first 13 rows have labels today; the remaining 15 named types and `dispute` are the 16 new ones. "View in Finance" only navigates; it isn't a new financial action.

---

## 7. Admin finance, payout freeze and job deletion (D-3, F-1)

- **Finance (AD-13), read-only:**
  - tables over `chargebacks` (id, job, status `open` / `paystack_resolved` / `closed` + outcome `merchant_won` / `customer_refunded`, investigation status, payout state at open, charged amount, dates), `platform_losses`, `refunds` and `settlements`;
  - admin read is already allowed by the rules; amounts are shown exactly as stored (kobo → naira formatting only).
  - Closing a chargeback and setting its investigation status (`adminCloseChargeback`, `adminSetChargebackInvestigation`) exist on the server but are **not** exposed; see Q-4.
- **Payout freeze:**
  - **Where:** in the job and artisan detail panels.
  - **How:** a confirmation dialog (consequence statement, required reason ≥ 10 characters with live validation, "Recorded in the audit log…").
  - **Call:** `AdminFinanceService.setPayoutFreeze`, i.e. callable `adminSetPayoutFreeze`, which writes the freeze fields, `admin_audit_logs` and `financial_events` atomically.
  - **Feedback:** a success or error snackbar, then the panel shows the current state.
  - **Current-state display needs Q-5:** the `JobModel` / `ArtisanModel` don't parse `payoutFrozen` today.
- **Job deletion (F-1):**
  - "Delete Job Request" is shown only when the job is in a rule-deletable state: `requested`, `matched` or `inChat`, or `cancelled` with no `paymentReference`.
  - The check runs before any write. The job is deleted **before** its messages, so a refusal can't remove chat history.
  - For every other job the panel says the record, chat, photos and financial history are kept.
  - Archival isn't implemented (Q-1).

---

## 8. Phase C plan (after preview approval)

| Step | Work | Deleted only after its replacement passes |
|---|---|---|
| 1 | Promote preview-kit components to `lib/ui/components/` (+ tests) | — |
| 2 | Logic extraction (D-5): `admin_providers.dart`, `AdminService` (suspend, delete user, artisan approval, review deletion, gated job deletion, deletion requests, beta flag, alert resolution), artisan profile/availability/bank/registration writes into services; alert-label catalogue (pure, tested) | — |
| 3 | Authentication (AU-00 … AU-07) | `screens/auth/*`, `widgets/auth_scaffold.dart`, `widgets/startup_error_screen.dart` |
| 4 | Artisan shell + AR-01 … AR-10; route redirect (D-6) | `screens/artisan/{artisan_dashboard,open_jobs_feed,business_profile,bank_details,portfolio_manager,portfolio_project}_screen.dart`, `home/all_jobs_screen.dart`, `wallet/wallet_screen.dart`, `widgets/premium_scaffold.dart` |
| 5 | Shared: job detail, submit work, messages; F-9 copy | `job/*`, `chat/my_chats_screen.dart`, `widgets/workflow_*` |
| 6 | Customer CU-01 … CU-09; F-8 copy | `settings/*`, `support/*`, `dispute/*`, `review/*`, `artisan/{secure_booking,artisan_list,favorites}_screen.dart`, payment result UI |
| 7 | Admin AD-0 … AD-13; F-1, F-2, F-3 | `screens/admin/*` (7 files) |
| 8 | Remove the old visual system | Remaining unused `lib/widgets/*`, `lib/theme/app_colors.dart`, `app_design_system.dart`, `app_theme.dart` (and `breakpoints.dart` if unused); `main.dart` themes from `HtPalette` |

**Unchanged:** routes and URLs (plus the new `/admin/finance`), router guards, Firestore/Storage rules, Cloud Functions, Paystack flows, Firebase Auth.

## 9. Existing functionality vs proposed change (summary)

| Kind | Items |
|---|---|
| **Existing functionality, restyled only** | All auth flows; every artisan workflow (quotes, booking, agreement, slots, work submission, rework, withdrawal, earnings, profile, bank, portfolio); every admin action (users, artisans, verifications, jobs, disputes, reviews, support, deletions, audit logs, analytics, settings, alert actions); customer settings, support, dispute, review, secure booking, matched list, favourites, payment result |
| **Approved new exposure of existing endpoints** | Finance section (read-only); payout freeze control |
| **Fixes** | F-1 job-deletion gating and order; F-2 alert labels; F-3 role label; F-8/F-9 copy corrected to 14 days |
| **Navigation changes** | Artisan 5-item nav (Find Work and Earnings become tabs; Chats moves to the header); admin sidebar grouping; artisan route redirect |
| **Proposed small additions (need your nod)** | "Contact support" on the Suspended screen (route already permitted); "View in Finance" links on chargeback alerts (navigation only) |

## 10. Phase D test plan (unchanged scope, plus auth)

- **Auth widget tests:**
  - sign-in error and loading states use `friendlyError` messages;
  - sign-up validators (8 characters, uppercase, number, match);
  - reset-link success, including the `user-not-found` → success behaviour;
  - verify-email resend;
  - role selection only for dual-role users;
  - suspended-screen options by suspension type.
- **Router tests:** splash, onboarding, login, verify, role-select and suspended redirects; the artisan redirect (D-6); `/admin` guard.
- **Admin:** alert-label catalogue covers all 28 ids (test enumerates the types extracted from `functions/index.js`); payout-freeze dialog blocks reasons under 10 characters and calls the service once; F-1 delete predicate matches the rule list; job deleted before messages.
- **Everything in v1 §6:** artisan quote, booking and work matrix; earnings; KPIs; finance tables; goldens light/dark; responsive sweeps (phone 320/360/430; admin 390/768/1,280/1,440); source guards; full regression (Flutter, analyzer, Functions 266, rules 139, Storage 9, e2e 16).

## 11. Open questions (need your answer before or during Phase C)

| ID | Question | Why |
|---|---|---|
| **Q-1** | **Archival of jobs with financial or dispute history.** No `archived` state exists in `JobModel`, the rules or the admin queries. Options: (a) no delete for such jobs (proposed, no backend change); (b) add an admin-only archive flag (model + rules + query change) | You asked to prefer archival; (b) is a data-model and rules change, outside "no rules changes" without your approval |
| **Q-2** | **In-app password reset.** Reset currently completes on Firebase's hosted page from the email link. An in-app "choose new password" screen needs deep-link handling + `confirmPasswordReset` | Architectural change to auth; not proposed unless you approve |
| **Q-3** | **Password rule consistency (F-10).** Sign-up demands 8 characters, uppercase and a number; the Firebase error text and Settings' change-password accept 6 | Choose: apply the sign-up rule everywhere (client validation only) or keep as is |
| **Q-4** | Expose the existing chargeback actions (`adminCloseChargeback`, `adminSetChargebackInvestigation`) in Finance? | Your approval covered read-only Finance + payout freeze only |
| **Q-5** | Allow an additive, read-only parse of `payoutFrozen`, `payoutFreezeReason`, `payoutFreezeBy`, `payoutFreezeAt` in `JobModel` / `ArtisanModel` so the freeze state can be displayed | Needed for "clear status feedback"; no schema, data or rules change |
| **Q-6** | Keep the existing service-time promises in copy ("reviewed within 24–48 hours", "dispute reviewed within 48 hours", "deleted within 7 days")? | Operational commitments I can't verify; kept verbatim unless you say otherwise |
| **Q-7** | Approve the optional transaction detail sheet (existing `PaymentModel` fields only)? | Not in the app today; you listed transaction details |
| **Q-8** | Confirm no separate notification-details screen | The destination screen acts as the detail; avoids an invented screen |
| **Q-9** | Fix F-11 (dual-role My Jobs uses `isCustomer` instead of `activeRole`) in the AR-03 replacement? | Pre-existing bug found in the complete audit; recommended |
