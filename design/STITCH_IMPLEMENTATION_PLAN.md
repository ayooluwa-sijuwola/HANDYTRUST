# Stitch Redesign — Implementation Plan

Architecture preparation only — no visual design decisions made here. This is the document whoever implements the Stitch redesign should read first: what exists today, what workflow states it must represent, and what's already reusable versus needs building fresh. **The Stitch URL has not been opened or used to inform this document.**

Cross-references rather than duplicates: `v1-audit/15-screens-inventory.md` has the full 43-screen inventory with completion %/known-issues; `design/SCREEN_MAPPING.md` covered the core lifecycle screens with an earlier, lighter structure. This document is the authoritative, comprehensive one going forward — grouped and fielded exactly as requested for implementation planning.

---

## 1. Current screen inventory

### Authentication
**Login** — `lib/screens/auth/login_screen.dart` — Purpose: email/password sign-in. Important data: none (form-only). Available actions: sign in, forgot password, go to signup. Dependencies: `authNotifierProvider`.

**Signup** — `lib/screens/auth/register_screen.dart` — Purpose: account creation, role selection. Important data: none. Available actions: create account, go to login. Dependencies: `authNotifierProvider`.

**Forgot Password** — `lib/screens/auth/forgot_password_screen.dart` — Purpose: password reset. Important data: none. Available actions: send reset link. Dependencies: `authNotifierProvider`.

**Verify Email** — `lib/screens/auth/verify_email_screen.dart` — Purpose: blocking email-verification gate. Important data: Firebase Auth email-verified state (polled). Available actions: resend, "I've verified." Dependencies: `authNotifierProvider`, Firebase Auth.

**Artisan Registration** — `lib/screens/auth/artisan_registration_screen.dart` — Purpose: step-2 artisan profile (category, skills, bio, business info). Important data: none yet (creates the profile). Available actions: submit. Dependencies: `profileServiceProvider`.

**Role Selection** — `lib/screens/auth/role_selection_screen.dart` — Purpose: dual-role mode picker. Important data: `UserModel.roles`. Available actions: choose customer/artisan. Dependencies: `profileServiceProvider`.

**Dead, not to be carried into the redesign without a product decision**: `phone_login_screen.dart`, `customer_registration_screen.dart` — both built, neither routed. Resolve before redesigning, not during.

### Customer

**Home / Explore** — `lib/screens/home/home_screen.dart` (`_CustomerHomeTab`) — Purpose: daily entry point. Important data: active jobs, categories. Available actions: post a job, browse artisans, view a job. Dependencies: `customerJobsProvider`, `WorkflowTimeline` (compact).

**Post Job** — `lib/screens/home/service_request_screen.dart` — Purpose: create a job request. Important data: none (form). Available actions: submit, optional AI description assist. Dependencies: `jobRequestNotifierProvider`, `aiServiceProvider`.

**My Tasks / Job History** — `lib/screens/home/all_jobs_screen.dart` — Purpose: filterable list of the customer's jobs. Important data: job list, status filters (All/Active/Completed/Disputed). Available actions: filter, open a job. Dependencies: `customerJobsProvider`.

**Browse Artisans** — `lib/screens/artisan/browse_artisans_screen.dart` — Purpose: general artisan discovery. Important data: artisan list (approved+verified only). Available actions: view profile. Dependencies: `MatchingService`/artisan query.

**Artisan List (job-linked)** — `lib/screens/artisan/artisan_list_screen.dart` — Purpose: ranked artisans for a specific job. Important data: same as above, scoped to one job. Available actions: view profile, select. Dependencies: `MatchingService`.

**Artisan Profile** — `lib/screens/artisan/artisan_profile_screen.dart` — Purpose: evaluate one artisan. Important data: `ArtisanModel`, reviews, portfolio. Available actions: chat, hire (if job-linked), favorite. Dependencies: `artisanProfileProvider`, `artisanReviewsProvider`.

**Favorites** — `lib/screens/artisan/favorites_screen.dart` — Purpose: saved artisans. Important data: favorite list. Available actions: view profile, unfavorite. Dependencies: `favoriteArtisansProvider`.

**Job Details** — `lib/screens/job/job_detail_screen.dart` — Purpose: single source of truth for a job's entire lifecycle. Important data: `JobModel` (status, agreementStatus, schedulingStatus, appointments, photos), quotes, disputes. Available actions: **now sourced from `WorkflowGateService`** — continue negotiation, view/confirm/accept agreement, propose/confirm schedule, pay into escrow, confirm completion, raise dispute, leave a review, cancel. Dependencies: `jobStreamProvider`, `escrowNotifierProvider`, `WorkflowGateService`, `WorkflowTimeline`, `WorkflowStatusCard`, `_AgreementSection`, `_AppointmentSection`.

**Chat** — `lib/screens/chat/chat_screen.dart` — Purpose: per-job messaging + negotiation. Important data: message stream, job status/agreementStatus. Available actions: send text/image, propose price, view agreement (if required), pay into escrow (if ready). Dependencies: `chatNotifierProvider`, `WorkflowGateService`.

**My Chats** — `lib/screens/chat/my_chats_screen.dart` — Purpose: conversation list. Important data: chat previews, unread counts. Available actions: open a thread. Dependencies: `artisanChatJobsProvider`/equivalent customer stream.

**Payment / Escrow** — `lib/screens/payment/payment_screen.dart` + `payment_webview_screen.dart` — Purpose: Paystack checkout. Important data: `PaymentModel`, checkout URL. Available actions: pay. Dependencies: `PaystackService`, Paystack webhook (server-side).

**Wallet** — `lib/screens/wallet/wallet_screen.dart` — Purpose: payment history. Important data: `payments` collection (not milestone-aware — no milestone data model exists). Available actions: view a payment's detail. Dependencies: `customerPaymentsProvider`.

**Review** — `lib/screens/review/review_screen.dart` — Purpose: rate a completed job. Important data: existing review (if any), job status gate. Available actions: submit rating + comment. Dependencies: `jobReviewProvider`.

**Dispute** — `lib/screens/dispute/dispute_screen.dart` — Purpose: raise a dispute. Important data: reason options, evidence photos. Available actions: submit. Dependencies: `disputeServiceProvider`, `StorageService`.

**Notifications** — `lib/screens/notifications/notifications_screen.dart` — Purpose: in-app feed. Important data: 12-type notification whitelist (Part 10, v1-audit). Available actions: mark read, mute. Dependencies: `userNotificationsProvider`.

**Profile / Settings / Support** — `lib/screens/profile/profile_screen.dart`, `settings_screen.dart`, `contact_support_screen.dart` — Purpose: account management. Dependencies: `authServiceProvider`, `profileServiceProvider`, `supportTicketServiceProvider`.

### Artisan

**Dashboard** — `lib/screens/artisan/artisan_dashboard_screen.dart` — Purpose: approval/verification state, availability, active jobs. Important data: `ArtisanModel` (approvalStatus, verificationStatus, isAvailable). Available actions: toggle availability, navigate to verification/portfolio/jobs. Dependencies: `artisanProfileProvider`, `WorkflowTimeline` (compact).

**Open Jobs Feed** — `lib/screens/artisan/open_jobs_feed_screen.dart` — Purpose: browse + quote open jobs. Important data: open jobs (category-filtered), own quote per job, **own eligibility (approval/verification, now live-checked)**. Available actions: chat, submit/edit/withdraw quote — **now correctly disabled with a reason shown if ineligible**. Dependencies: `openJobsFeedProvider`, `artisanQuoteForJobProvider`, `artisanProfileProvider`.

**Quote Submission** — `_SubmitQuoteSheet` (same file as Open Jobs Feed, a modal bottom sheet, not a standalone screen) — Purpose: labor/materials/duration/notes form. Important data: existing quote (if editing). Available actions: submit, withdraw. Dependencies: `quoteServiceProvider`.

**Active Jobs** — same as customer's My Tasks (`all_jobs_screen.dart`), role-branched internally, not a separate file.

**Portfolio** — `lib/screens/artisan/portfolio_manager_screen.dart` + `portfolio_project_screen.dart` — Purpose: showcase work. Important data: photo gallery, projects. Available actions: add/remove/reorder photos, add/edit projects. Dependencies: `portfolioServiceProvider`.

**Business Profile / Bank Details / Verification** — `business_profile_screen.dart`, `bank_details_screen.dart`, `verification_upload_screen.dart` — Purpose: profile completeness required for eligibility and payout. Dependencies: `verificationServiceProvider`, `artisan_private` writes.

**Earnings** — no dedicated screen exists; the Wallet screen (shared with customers, artisan-filtered variant) is the closest equivalent today. **Flagged as a real gap for the redesign to consider** — an artisan-specific earnings view (trends, per-job breakdown) doesn't exist.

### Admin
Covered fully in `v1-audit/05-admin-features.md`; not re-detailed here since the admin surface is architecturally separate (its own `ShellRoute`, its own color system) and wasn't part of this workflow-stabilization scope.

---

## 2. Current workflow states

Full detail in `design/WORKFLOW_AUDIT.md`. Summary for redesign planning purposes — every state a screen needs to be able to represent:

`requested → matched → inChat (negotiating → agreementConfirmed → [awaitingSchedule →] readyForPayment) → paymentPending → escrowLocked → inProgress → submitted → completed`, with `disputed`/`resolved`/`cancelled` as branches reachable from multiple points. The parenthetical `inChat` sub-states are not separate `JobStatus` values — they're computed from `agreementStatus`/`schedulingStatus`/`urgency` via `WorkflowGateService.describeStep`, which is now the **one place** this branching logic lives.

---

## 3. Required screens after redesign

No new screens are functionally required by this pass — the workflow gaps found and fixed were logic/gating issues, not missing screens. Two real content gaps worth the redesign considering as new screens, not just restyled existing ones (already flagged in `SCREEN_MAPPING.md`):
- **Artisan Earnings** — doesn't exist distinctly from Wallet today.
- **Notification Preferences** — per-category granularity doesn't exist (a single global toggle is the entire preference system today, per `v1-audit/10-notification-system.md`).

---

## 4. Components that should be reusable

| Component | File | Role |
|---|---|---|
| `WorkflowGateService` | `lib/core/services/workflow_gate_service.dart` | **New in this pass.** Pure decision layer — phase, waiting-on, next action. Not a widget, but everything workflow-status-related should read from it, not re-derive its own conditions. |
| `WorkflowStatusCard` | `lib/widgets/workflow_status_card.dart` | Phase + description + waiting-on + primary/secondary action. The visual unit `WorkflowGateService`'s decisions render into. |
| `WorkflowTimeline` | `lib/widgets/workflow_timeline.dart` | Full-lifecycle stepper (compact chip + detailed vertical modes), replaces three previously-overlapping widgets. |
| `AppBadge`, `appCardDecoration()` | `lib/theme/app_design_system.dart` | Existing design-system primitives both of the above are built on — untouched by this pass, should stay the foundation. |
| Job/quote/dispute/review status chips | various | Existing, consistent color-token usage — not modified. |

**Explicitly not touched, not to be redesigned as part of "reusable component" work**: colors, typography, spacing tokens, `AppTheme` — per this task's own instruction, those wait for the Stitch reference.
