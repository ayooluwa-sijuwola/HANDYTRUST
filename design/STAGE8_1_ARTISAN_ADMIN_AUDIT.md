# HandyTrust — Stage 8.1 Phase A: Artisan & Admin UI Audit

Date: 2026-11-04 · Branch: `stage-8-ui-replacement` (Stage 8 still uncommitted) · Status: **audit only. No file was changed, deleted or created except this report and the design specification.**

## 1. Summary

| | Artisan | Admin |
|---|---|---|
| Screens (files) | 11 artisan-only + 4 shared with customers | 1 screen file (7,881 lines) with 12 sections, plus 6 helper files |
| Old-visual-system references (`context.colors`, `AppColors`, `AdminPalette`, …) | 285 across artisan files | 408 across admin files |
| Business logic inside widgets | Moderate. Direct Firestore writes in dashboard, business profile, bank details and registration | **High.** 12 private providers and ~10 direct Firestore writes/deletes inside widgets; `adminDeleteUser` is called from the widget |
| Stitch references | **None** | **None** |
| Route guard | No router-level artisan guard; Firestore rules and in-screen checks enforce it | `/admin/*` guarded by `isAdminProvider` (mirrors the rules' `isAdmin()`) |

**Every artisan and admin screen lacks a design.** Per the Stage 8.1 brief, each needs an approved proposal before any deletion: `STAGE8_1_DESIGN_SPECIFICATION.md`.

---

## 2. Artisan screens: features, actions and backend map

**How the artisan side is wired:**
- **Shell.** `HomeScreen` sends users whose `activeRole == 'artisan'` to `_ArtisanHome` = `MainShellScreen` (`lib/widgets/premium_scaffold.dart`, old system).
- **Tabs.**
  1. Home: `ArtisanHomeTabContent`
  2. Jobs: `AllJobsScreen`, artisan mode
  3. Chats: `MyChatsScreen`
  4. Profile: the new Stage 8 `ProfileScreen`

| # | Screen (file, lines) | Route | Features and actions | Providers | Service → backend operation | Models |
|---|---|---|---|---|---|---|
| A1 | Artisan home (`artisan/artisan_dashboard_screen.dart`, 817): `ArtisanHomeTabContent`, `ArtisanDashboardScreen` | `/home` tab 0 (artisan) | Greeting; verification status card (deferred, under review, rejected, verified) → `/verification`; stats (Completed, Rating, Trust Score); trust-score card; quick actions (Browse Open Jobs → `/open-jobs`, Business Profile, Portfolio, Payout Details, My Chats); recent jobs list → `/job/:id`; notification bell; sign-out | `artisanJobsProvider`, `artisanProfileProvider`, `currentUserProfileProvider`, `verificationStatusProvider`, `authNotifierProvider` | Firestore streams `jobs` (artisanId), `artisans/{uid}`, `verifications/{uid}`; `AuthService.updateUserProfile`; **direct** `artisans`/`users` reads in the widget | `JobModel`, `ArtisanModel`, `UserModel`, `VerificationStatus` |
| A2 | Open jobs feed (`artisan/open_jobs_feed_screen.dart`, 1,379) | `/open-jobs` | Search; status filter (All Matched, Recent, Urgent; there's no category or distance filter); matching within the configured service radius; "Ready to work" toggle; job cards (category, area, budget, posted time, distance, Urgent); **Submit quote** sheet (labour/service cost, materials (optional), estimated duration in days, notes); **Edit quote**; **Withdraw quote**; Chat (get or create the job chat); empty and no-match states; loading skeleton | `openJobsFeedProvider`, `artisanProfileProvider`, `currentUserProfileProvider`, `platformConfigProvider` (`defaultServiceRadiusKm`), `quoteServiceProvider`, `chatServiceProvider` | `QuoteService.submitQuote` / `withdrawQuote` (`jobs/{id}/quotes`, eligibility rules); `ChatService.getOrCreateJobChat`; "ready to work" written **directly** to `artisans`/`users` | `JobModel`, `QuoteModel`, `ArtisanModel`, `PlatformConfig` |
| A3 | My jobs (`home/all_jobs_screen.dart`, 485, artisan mode) | `/jobs` (artisan, via `_RoleAware`), shell tab 1 | Tabs Active/Completed; booking cards (`job_booking_card`) → `/job/:id`; open chat (`openChat`); empty state | `artisanJobsProvider`, `artisanProfileProvider`, `currentUserProvider`, `escrowNotifierProvider` | `jobs` where `artisanId == uid`; `JobService.openChat` | `JobModel` |
| A4 | Job detail, **shared** (`job/job_detail_screen.dart`, 2,518) | `/job/:jobId` | **Artisan:** confirm or decline booking (24 h), propose / accept / request changes to the agreement, propose appointment slots, start work, update progress, withdraw from job (callable `artisanWithdrawFromJob`), respond to rework, respond in the dispute thread, view the location (private), chat. **Customer:** quotes inbox (sort, accept), confirm the agreement, confirm a slot, cancel / paid cancellation (reason dialog), request rework, raise dispute (countdown banner), confirm completion. Workflow status card and timeline | `escrowNotifierProvider` (19 methods), `jobStreamProvider`, `jobQuotesProvider`, `jobPrivateLocationProvider`, `disputeForJobProvider`, `jobHasChatProvider`, … | `JobService` transactions (rules + `WorkflowGateService`); callable `artisanWithdrawFromJob`; `DisputeService.respondToDispute` | `JobModel`, `QuoteModel`, `DisputeModel` |
| A5 | Work submission (`job/job_completion_screen.dart`, 305) | `/job/:jobId/submit` | After photos (via `StorageService` + `ImagePrivacy`), notes "Describe what was done…", Submit for Review | `escrowNotifierProvider.submitCompletion` | `JobService.submitCompletion` → `submitted`, which starts the 14-day review | `JobModel` |
| A6 | Earnings (`wallet/wallet_screen.dart`, 526, `_ArtisanEarningsView`) | `/wallet` (artisan, via `_RoleAware`) | Payout-readiness banner (→ `/bank-details`); totals (Released, In Escrow, Pending Escrow, Completed); transactions list → `/job/:id`; empty, loading and error states | `artisanPaymentsProvider`, `artisanPayoutReadyProvider`, `jobStreamProvider` | `payments` where `payeeId == uid`; `artisan_private/{uid}` presence | `PaymentModel` |
| A7 | Business profile (`artisan/business_profile_screen.dart`, 310) | `/business-profile` | Individual or Business type; business name, registration number, address; service-area card (GPS on tap, radius) | `artisanProfileProvider`, `currentUserProvider` | **Direct** `artisans/{uid}` update (rules allow-list) | `ArtisanModel` |
| A8 | Payout bank details (`artisan/bank_details_screen.dart`, 296) | `/bank-details` | Bank name, account number, account name → save | `currentUserProvider` | **Direct** write to `artisan_private/{uid}` (rule: owner or admin may read and write) | — |
| A9 | Portfolio manager (`artisan/portfolio_manager_screen.dart`, 460) | `/portfolio` | Tabs Projects/Photos; project tiles (view count) → `/portfolio-project`; Add Project; delete project | `portfolioProjectsProvider`, `portfolioViewCountProvider`, `portfolioServiceProvider` | `PortfolioService` (`portfolio_projects`, `portfolio_analytics`) | `PortfolioProject` |
| A10 | Portfolio project editor (`artisan/portfolio_project_screen.dart`, 307) | `/portfolio-project` | Title, description, before/after photos, save | `portfolioServiceProvider` | `PortfolioService` + `StorageService` | `PortfolioProject` |
| A11 | Artisan registration (`auth/artisan_registration_screen.dart`, 223) | `/register/artisan` | Skills, categories and profile setup → `/home` | `authStateChangesProvider`, `currentUserProvider` | **Direct** `artisans`/`users` writes (rules) | `ArtisanModel` |
| A12 | Chat list, **shared** (`chat/my_chats_screen.dart`, 617) | `/my-chats`, shell tab 2 | Conversation list, unread counts, search → `/chat/:id` | chat providers | `ChatService` | `MessageModel`, `JobModel` |
| A13 | Identity verification (**already new**, Stage 8) | `/verification` | — | — | — | — |
| A14 | Profile (**already new**, Stage 8) | shell tab 3 | Artisan rows: My Reviews, Earnings & Payouts, Identity Verification; Artisan Mode switch | — | — | — |
| A15 | Notifications and Chat (**already new**, Stage 8) | `/notifications`, `/chat/:id` | — | — | — | — |

### Other artisan facts
- **Eligibility to quote:** `ArtisanEligibility.canQuote` checks approval, verification, suspension and Ready-to-work. It's enforced again by the rules and by `stage2_authorization`.
- **Payout readiness:** `artisanPayoutReadyProvider`; bank details live in `artisan_private` (owner and admin access).
- **Trust score:** computed server-side (Stage 7.2 definition) and only displayed in the client.

---

## 3. Admin dashboard: sections, actions and backend map

**Shell:**
- `ShellRoute` → `AdminShell` (sidebar from 1,024 px, drawer below) + `_AdminTopBar` (global search sheet, admin notification bell, back to app).
- Sections use the `/admin/<section>` URLs from `AdminSection`.

**12 private providers** are declared inside `admin_dashboard_screen.dart`:
- `_allUsersProvider`, `_allJobsProvider`, `_jobPeopleNamesProvider`, `_pendingArtisansProvider`
- `_deletionRequestsProvider`, `_adminAlertsProvider`, `_allPaymentsProvider`, `_allDisputesProvider`
- `_adminCountProvider`, `_allVerificationsProvider`, `_recentAuditLogsProvider`, `_allArtisansProvider`

**Shared public providers it uses:** `pendingVerificationsProvider`, `openDisputesProvider`, `allTicketsProvider`, `allReviewsProvider`, `adminFinanceServiceProvider`, `themeProvider`.

| # | Section (class) | Route | Features and actions | Backend operation | Notes |
|---|---|---|---|---|---|
| D1 | Dashboard (`_DashboardHomeTab`) | `/admin/dashboard` | **KPI cards:** Total Users, Total Artisans, Active Jobs, Escrow Volume, Completed Jobs, Pending Verifications, Average Rating (week-over-week trends computed from timestamps). **Charts:** Jobs Overview, Users Overview, Top Categories. **Lists:** Recent Activity (audit logs), Pending Actions (links to sections). **Operational Alerts** (`_AdminAlertRow`): Resolve, plus finance actions per alert type. **Platform Health:** completion, verification, response time and dispute rates | Streams: `users`, `artisans`, `jobs`, `payments`, `disputes`, `verifications`, `support_tickets`, `reviews`, `admins` (count), `admin_audit_logs`, `admin_alerts` (`resolved == false`, limit 100) | All figures are **derived from real documents** (no hardcoded numbers found). The whole user/job/payment collections are loaded client-side (a scale concern, §6) |
| D2 | Users (`_UsersTab`, `_UserListTile`, `_UserActivitySheet`) | `/admin/users` | Search and filter (role, suspended); user tile; **Suspend / Unsuspend** (suspension type: full or restricted, via `showSuspensionTypeDialog`, reason); **Delete user** (callable `adminDeleteUser`, reason); beta-tester switch; eligible-to-quote row; activity sheet (jobs, payments) | Direct batch writes to `users` / `artisans` (+ audit log); callable `adminDeleteUser` | Writes from the widget |
| D3 | Artisans (`_ArtisansSection`: `_PendingArtisansTab`, `_AllArtisansTab`, `_ArtisanApplicationCard`, `_ArtisanListTile`) | `/admin/artisans` | Pending applications: **Approve / Reject** with confirmation (approvalStatus); all artisans list with filters (Approved, Rejected, …); open profile | Direct batch `artisans` + `users` updates (+ audit) | — |
| D4 | Jobs (`_JobsTab`, `_JobDetailSheet`) | `/admin/jobs` | Search and status filter; job detail sheet (people, status, quotes, chat existence, private location, dispute, photos); **Delete Job Request** | Reads `jobs`, `quotes`, `messages`; deletes `messages` then `jobs/{id}` (+ audit) | **Defect, see §6 F-1** |
| D5 | Verifications (`_VerificationCenterTab`, `_VerificationReviewCard`, `_VerificationThumb`) | `/admin/verifications` | Pending verifications with ID and selfie thumbnails; **Approve / Reject** (reason) | `VerificationService.approve` / `reject` (transactional) | — |
| D6 | Disputes (`_DisputesTab`, `_DisputeReviewCard`) | `/admin/disputes` | Open disputes; **Resolve** via the settlement dialog: release to the artisan, full refund, or split (amounts) + reason | Callable **`adminResolveDispute`** (`AdminFinanceService`) | Server-side settlement |
| D7 | Reviews (`_ReviewsTab`, `_AdminReviewCard`) | `/admin/reviews` | List and filter; **Delete review** (reason) | Direct batch: delete `reviews/{id}` + update the artisan's rating fields | Writes from the widget |
| D8 | Support tickets (`_SupportTicketsTab`, `_TicketReviewCard`) | `/admin/support` | Filter open/resolved; **Respond & Resolve** | `SupportTicketService.resolveTicket` | — |
| D9 | Deletion requests (`_DeletionRequestsTab`) | `/admin/deletions` | Pending account-deletion requests; **Mark Resolved** | Direct batch: `account_deletion_requests` + audit | — |
| D10 | Audit logs (`_ActivityTab`) | `/admin/audit-logs` | Recent admin actions (actor, action, target, time) | `AdminAuditService.watchAll` (`admin_audit_logs`, admin read only) | Read-only |
| D11 | Analytics (`_AnalyticsTab`) | `/admin/analytics` | User & Job Growth (last 8 weeks), Category Distribution, Rating Distribution, New Users, New Jobs, Avg Trust Score, appointment and before-photo funnel counts | Same streams as D1 | Derived from real data |
| D12 | Settings (`_AdminSettingsTab`) | `/admin/settings` | Admin account card; appearance (dark/light); sign out | `themeProvider`, `authNotifierProvider` | Shows a hardcoded **"Super Administrator"**, but no admin tiers exist (§6 F-3) |

**Operational-alert finance actions (D1)**, through `AdminFinanceService`:
- `adminResolveCancellation` (decline, full refund or split) for `paid_cancellation_request`.
- `adminRefundCharge` for `charge_requires_refund`.
- `adminRetryRefund` for `refund_failed`.
- `adminRetryPayout` for `payout_frozen`, `autorelease_blocked` and `transfer_failed`.
- Resolve (marks the alert resolved) for any type.

**Helper files:**
- `admin_sidebar.dart` (sections and nav), `admin_charts.dart` (fl_chart), `admin_data_table.dart`
- `admin_widgets.dart`, `admin_palette.dart` (separate admin colour system)
- `admin_finance_dialogs.dart` (settlement, reason and suspension-type dialogs)

---

## 4. Shared screens between roles (old visual system unless noted)

| Screen | Roles | Status |
|---|---|---|
| Job detail (`/job/:id`), work submission | Customer + artisan | Old |
| Chat list (`/my-chats`) | Customer + artisan | Old |
| Settings, support, about | All | Old |
| Dispute (`/dispute/:id`), review (`/review/:id`) | Customer (artisan views disputes in job detail) | Old |
| Auth (splash, login, register, verify email, forgot password, role select, suspended) | All | Old |
| Chat, notifications, profile, verification | All / artisan | **New (Stage 8)** |
| Admin access from Profile | Admin | **New** entry card; destination is old |

---

## 5. Old-visual-system inventory

| Group | Files |
|---|---|
| Theme | `lib/theme/app_colors.dart`, `app_design_system.dart`, `app_theme.dart` (+ `breakpoints.dart`); `lib/screens/admin/admin_palette.dart` (admin-only palette) |
| Widgets: artisan/admin consumers | `premium_scaffold` (`MainShellScreen`), `trust_score_card`, `workflow_timeline`, `workflow_status_card`, `shimmer_loaders`, `notification_bell`, `pill_tab_selector`, `job_booking_card`, `balance_card`, `earnings_summary_card`, `transaction_card`, `portfolio_viewer`, `service_area_card`, `job_status_badge`, `review_tile`, `error_snackbar`, `web_content_wrapper`, `user_avatar`, `star_rating` |
| Widgets with **no importers** (dead) | `artisan_card`, `cancellation_reason_dialog`, `loading_indicator` (verify before deleting) |
| Widgets used only by non-artisan/admin old screens | `auth_scaffold` (auth), `app_snackbars` (settings), `startup_error_screen` (main/splash), `cannot_open_directly_screen` (router) |

The theme files can only be removed once **every** old screen is replaced, including auth and settings (see the scope decision D-1 in the design specification).

---

## 6. Findings (pre-existing, found during the audit; not yet changed)

| ID | Finding | Risk | Proposed handling in Phase C |
|---|---|---|---|
| F-1 | **Admin "Delete Job Request" isn't gated by status and deletes the chat first.** The rules allow job deletion only in `requested`, `matched` or `inChat` (or unpaid `cancelled`), and admins may delete messages. On a paid job the messages batch succeeds, then the job delete is refused. Result: **chat history (dispute evidence) is lost** and the job remains | High (data loss) | Show the action only in the deletable statuses (same predicate as the rule); delete the job first or in one ordered service call; move it into a service |
| F-2 | **Alerts render as raw type strings.** *Corrected during preview work, after re-extracting every `admin_alerts` write in `functions/index.js`:* **16** types hit the `default:` branch. These are `dispute`, 12 chargeback types (`chargeback_opened`, `chargeback_after_payout`, `chargeback_event_after_close`, `chargeback_paystack_resolved`, `chargeback_reference_mismatch`, `chargeback_unmatched`, `chargeback_unverified`, `chargeback_event_unsupported`, `chargeback_webhook_invalid`, `chargeback_payout_completed`, `chargeback_closed`, `chargeback_fraud_confirmed`) and 3 refund types (`refund_held_chargeback`, `refund_webhook_unmatched`, `refund_amount_mismatch`). My earlier summary said "twelve" and wrongly listed `platform_loss_recorded` and `payout_failed`, which are `financial_events`, not alerts | Medium (operator clarity) | Human-readable titles and severity for all 28 alert types, keeping the original identifier visible; no new actions (spec §6) |
| F-3 | Hardcoded "Super Administrator" role label | Low (inaccurate) | "Administrator" |
| F-4 | **Admins can read finance records but have no screen for them.** `chargebacks`, `platform_losses`, `refunds` and `settlements` are admin-readable by rule. `AdminFinanceService.setPayoutFreeze` (callable `adminSetPayoutFreeze`) exists but is **not reachable from any UI** | Medium (operational gap) | Decision D-3 (spec): read-only Finance section and an optional payout-freeze control, using existing endpoints only |
| F-5 | Business logic and Firestore access inside admin and artisan widgets (12 private providers, ~10 direct writes, the `adminDeleteUser` call) | Maintainability; bypasses the "no Firebase in presentation" guard used for `lib/ui` | Extract into `lib/providers/admin_providers.dart` and an `AdminService` / `ArtisanProfileService` with identical writes. Behaviour-preserving, rules unchanged |
| F-6 | Admin streams load entire `users`/`jobs`/`payments` collections client-side | Performance at scale | Out of Stage 8.1 scope (presentation layer). Noted; KPIs stay exactly as computed today |
| F-7 | No router-level guard for artisan-only routes (`/open-jobs`, `/bank-details`, …); a customer who navigates there sees artisan UI, but every write is denied by the rules | Low (UX) | **Approved (D-6):** role-aware redirect for artisan routes. It's UI-only; rules stay the security boundary |
| F-8 | **Stale customer copy.** The Settings FAQ says escrow holds payment "until you mark the job complete or 7 days after job submission" (`settings_screen.dart:1153`). The approved review period is **14 days** | Medium (misleading financial copy) | Correct to 14 days in the replacement Settings screen |
| F-9 | **Stale artisan copy.** `WorkflowGateService` tells artisans "payment releases automatically after 48 hours" (`workflow_gate_service.dart:193`), shown in job detail. Contradicts the 14-day policy | Medium (misleading financial copy) | Correct the string to 14 days. Text only; no logic change |
| F-10 | **Password rules disagree.** Sign-up requires ≥ 8 characters with an uppercase letter and a number (`register_screen.dart`). `AuthService.friendlyError('weak-password')` says "at least 6 characters", and Settings' change-password check accepts 6 | Low–medium (inconsistent security rule) | **Decision needed (spec Q-3):** apply the sign-up rule everywhere, or keep as is |
| F-11 | **Dual-role My Jobs shows the wrong jobs.** `AllJobsScreen` picks artisan mode with `user.isArtisan && !user.isCustomer` (`all_jobs_screen.dart:38`) instead of `activeRole`, so a dual-role user in Artisan Mode sees their *customer* jobs | Medium (wrong data shown to artisans) | Use `activeRole`, consistent with `_RoleAware` / `WalletScreen` (Q-9) |

---

## 7. Missing designs

**No Stitch reference exists for any artisan or admin screen,** and none for the shared job detail, chat list, auth, settings, support, dispute or review screens.

`STAGE8_1_DESIGN_SPECIFICATION.md` proposes designs for all of them. The proposals are derived strictly from the Stage 8 customer design system and keep every feature listed in §2–§3. **They require your approval before Phase C starts.**

## 8. Existing tests touching these areas

| Area | Tests |
|---|---|
| Admin, artisan and workflow logic | `admin_audit_log_test`, `admin_exit_navigation_test`, `artisan_eligibility_test`, `artisan_model_test`, `job_service_agreement_test` (53), `stage4`–`stage7` tests, `portfolio_project_route_test` (imports `portfolio_project_screen`, so it must be updated if that file is replaced) |
| Backend | Functions (266), rules (139), Storage (9), e2e (16): admin finance callables, `adminDeleteUser`, verification and quote rules |
| Artisan/admin widgets | **None today.** Phase D adds widget, golden and responsive tests |
