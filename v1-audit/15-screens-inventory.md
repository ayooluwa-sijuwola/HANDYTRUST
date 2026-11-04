# Part 15 — Screens: Complete Inventory

Built directly from `router.dart`'s route table (read in full for this Part) cross-referenced against every screen file confirmed to exist in `lib/screens/`. Completion % is this audit's own judgment call based on what was verified across Parts 1–14, not a metric the codebase itself tracks.

## Auth / Onboarding

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `splash_screen.dart` | `/` | Loading gate while Firebase auth state resolves | 100% | — |
| `login_screen.dart` | `/login` | Email/password sign-in | 100% | Visual-only Google/Apple buttons (Part 2) |
| `register_screen.dart` | `/register` | Signup, role tile picker | 95% | Two-write non-atomicity (Part 2) |
| `artisan_registration_screen.dart` | `/register/artisan` | Artisan step-2 onboarding | 100% | Not linked to directly from signup — only reached via dashboard auto-redirect |
| `phone_login_screen.dart` | 🔒 **no route** | Phone-based sign-in | Dead code | Fully built, never imported into `router.dart` |
| `customer_registration_screen.dart` | 🔒 **no route** | A customer-specific registration variant | Dead code | Same as above |
| `forgot_password_screen.dart` | `/forgot-password` | Password reset | 100% | Raw error text, not `friendlyError`-mapped |
| `verify_email_screen.dart` | `/verify-email` | Email verification gate | 100% | — |
| `role_selection_screen.dart` | `/role-select` | Dual-role mode picker | 100% | — |
| `suspended_screen.dart` | `/suspended` | Suspended-account lockout | 100% | Text says "contact support" with no actual link to `/support` |

## Home / Customer

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `home_screen.dart` | `/home` | Role-branching shell entry (`MainShellScreen`) | 100% | — |
| `service_request_screen.dart` | `/request` | Post a job | 90% | No milestone/material breakdown (none exists in the data model) |
| `all_jobs_screen.dart` | `/jobs` | "My Tasks" — role-branched job list | 100% | Includes the Disputed filter chip (most recent work) |

## Artisan discovery (customer-facing)

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `artisan_list_screen.dart` | `/artisans/:jobId` | Ranked artisans for a specific job | 70% | Ranking uses `matchScore`, not `trustScore` (Part 3/4) |
| `browse_artisans_screen.dart` | `/browse-artisans` | General artisan browse | 70% | Same ranking issue |
| `artisan_profile_screen.dart` | `/artisan/:uid` | Artisan profile detail | 90% | — |
| `favorites_screen.dart` | `/favorites` | Saved artisans | 100% | — |

## Job lifecycle

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `job_detail_screen.dart` | `/job/:jobId` | The hub screen — status, agreement, appointment, photos, disputes, actions | 85% | Renders `JobProgressTracker`/`JobTimelineWidget`/`JobProgressTimeline` simultaneously — three components, overlapping information (never consolidated in code) |
| `job_completion_screen.dart` | `/job/:jobId/submit` | Artisan submits completion proof | 100% | — |

## Payment

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `payment_screen.dart` | `/payment/:jobId` | Initiate Paystack transaction | 90% | Reachable both from Job Detail and from chat's un-gated "Pay Now" button |
| `payment_webview_screen.dart` | `/payment/:jobId/webview` | Paystack checkout WebView | 100% | — |
| `demo_escrow_screen.dart` | `/demo-payment/:jobId` | Simulated payment | Reachable, ungated | Still routed with no build-flag/debug gate — a real user could reach a fake payment screen |

## Review / Dispute

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `review_screen.dart` | `/review/:jobId` | Leave a rating + comment | 100% | Correctly hard-gated to `completed` status |
| `dispute_screen.dart` | `/dispute/:jobId` | Raise a dispute | 90% | Only entry point in the app — no equivalent action inside `chat_screen.dart` |

## Artisan-side

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `artisan_dashboard_screen.dart` | (renders inside `/home`) | Artisan home tab | 90% | No rejected-application banner state |
| `open_jobs_feed_screen.dart` | `/open-jobs` | Browse + quote open jobs | 85% | No proactive unverified-artisan messaging before a blocked quote attempt |
| `portfolio_manager_screen.dart` | `/portfolio` | Photo/project portfolio | 100% | — |
| `portfolio_project_screen.dart` | `/portfolio-project` | Add/edit one project | 100% | — |
| `business_profile_screen.dart` | `/business-profile` | Business name/registration | 100% | — |
| `bank_details_screen.dart` | `/bank-details` | Payout bank info | 90% | Stores a display name, not a Paystack bank code (Part 4/8) |

## Verification

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `verification_upload_screen.dart` | `/verification` | Selfie + ID + "Verify Later" | 100% | — (a prior camera-lifecycle crash bug is already fixed, per its own code comment) |

## Chat

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `chat_screen.dart` | `/chat/:jobId` | Per-job messaging | 80% | No read-receipt UI, no typing indicator, un-gated "Pay Now" button (Part 9) |
| `my_chats_screen.dart` | `/my-chats` | Conversation list | 100% | — |

## Notifications / Profile / Settings / Support

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `notifications_screen.dart` | `/notifications` | In-app notification feed | 100% | Reflects only the 12-type whitelist (Part 10) |
| `profile_screen.dart` | `/profile` | Account menu | 100% | Prior mis-wired menu items ("My Reviews," "Payment Methods," "About HandyTrust") are confirmed fixed in the current codebase |
| `settings_screen.dart` | `/settings` | Account settings, theme, notification toggle | 100% | — |
| `contact_support_screen.dart` | `/support` | Create a support ticket | 100% | — |
| `about_screen.dart` | `/about` | About/legal info | 100% | New — the real destination for the previously-dead "About HandyTrust" button |

## Wallet (newest screen)

| Screen | Route | Purpose | Completion | Known issues |
|---|---|---|---|---|
| `wallet_screen.dart` | `/wallet` | Payment history | 70% | Not milestone-aware (no milestone model exists at all); built against the existing single-payment `PaymentModel` |

## Admin (all under `/admin/*`, `ShellRoute`-wrapped)

| Screen | Route | Purpose | Completion |
|---|---|---|---|
| `admin_dashboard_screen.dart` (+ `AdminShell`) | `/admin/dashboard`, `/admin/users`, `/admin/artisans`, `/admin/jobs`, `/admin/verifications`, `/admin/disputes`, `/admin/reviews`, `/admin/support`, `/admin/deletions`, `/admin/audit-logs`, `/admin/analytics`, `/admin/settings` | 12-section admin dashboard | ~5,000 lines, spot-verified not fully read line-by-line (Part 5) |

---

## Screen count summary
**43 total screen files confirmed to exist** (glob of `lib/screens/`), of which **41 are reachable** via `router.dart` and **2 are dead code** (`phone_login_screen.dart`, `customer_registration_screen.dart`) — both fully built, neither imported into the router at all.
