# Feature Inventory (from Explore agent)

Confirmed `AdminAuditLogService` is fully dead (constructor referenced only in its own file, zero call sites). Now I have everything needed for the complete report.

---

# HandyTrust — Code-Verified Feature Inventory
*(Evidence-based; prior docs in `v1-audit/*.md` and `design/*.md` used only as a starting checklist, then re-verified against current code as of 2026-08-17. Where old audit claims no longer hold, that's noted explicitly.)*

## 1. Routes (`lib/routes/router.dart`, go_router)

**Global redirect logic** (`redirect:` callback, router.dart:86-164):
- Splash (`/`) shows while `authStateChangesProvider` is loading.
- Not signed in (or anonymous) + path not in `{/login, /register, /register/artisan, /forgot-password}` → redirect `/login`.
- Signed in but `emailVerified == false` + path != `/verify-email` → redirect `/verify-email`.
- Signed in + verified + on `{/login, /, /verify-email, /register}` → redirect `/home`.
- `profile.isSuspended == true` + path != `/suspended` → redirect `/suspended` (and reverse redirect back to `/home` if not suspended but on `/suspended`).
- Any `/admin/*` path → gated on `isAdminProvider` (Firestore doc at `/admins/{uid}`); non-admin → redirect `/home`.
- Dual-role users (`profile.hasBothRoles`) landing on `/home` with no `activeRole` set → redirect `/role-select`.

| Path | Screen | Auth required | Role gate | Notes |
|---|---|---|---|---|
| `/` | `SplashScreen` | no | — | initial location |
| `/login` | `LoginScreen` | no (public) | — | |
| `/register` | `RegisterScreen` | no (public) | — | |
| `/register/artisan` | `ArtisanRegistrationScreen` | no (public, but really step-2 onboarding) | artisan-role onboarding | reachable even when verified, per redirect exception (router.dart:117) |
| `/verify-email` | `VerifyEmailScreen` | yes (signed-in, unverified) | — | |
| `/forgot-password` | `ForgotPasswordScreen` | no (public) | — | |
| `/suspended` | `SuspendedScreen` | yes | suspended accounts only | sign-out only action |
| `/role-select` | `RoleSelectionScreen` | yes | dual-role users | writes `activeRole` |
| `/support` | `ContactSupportScreen` | yes (implicit — no public exception) | — | |
| `/about` | `AboutScreen` | yes | — | |
| `/settings` | `SettingsScreen` | yes | — | |
| `/wallet` | `WalletScreen` | yes | — | also embedded as customer bottom-nav tab |
| `/home` | `HomeScreen` | yes | renders customer vs artisan UI based on `activeRole` | |
| `/jobs` | `AllJobsScreen` | yes | — | also embedded as bottom-nav tab (both roles) |
| `/notifications` | `NotificationsScreen` | yes | — | |
| `/request?category=` | `ServiceRequestScreen` | yes | customer flow (post job) | |
| `/browse-artisans` | `BrowseArtisansScreen` | yes | — | public browse, no job required |
| `/favorites` | `FavoritesScreen` | yes | customer | |
| `/artisans/:jobId` | `ArtisanListScreen` | yes | customer | extras: category, lat, lng |
| `/artisan/:uid` | `ArtisanProfileScreen` | yes | — | extra: jobId |
| `/chat/:jobId` | `ChatScreen` | yes | — | extras: otherUserId/otherUserName |
| `/my-chats` | `MyChatsScreen` | yes | — | also embedded as artisan bottom-nav "Inbox" tab |
| `/payment/:jobId` | `PaymentScreen` | yes | customer (payer) | |
| `/demo-payment/:jobId` | `DemoEscrowScreen` | yes | — | demo/simulated escrow, **ungated in prod build** |
| `/payment/:jobId/webview` | `PaymentWebviewScreen` | yes | — | extras: url, reference (Paystack webview) |
| `/job/:jobId` | `JobDetailScreen` | yes | — | central job-lifecycle screen, 2123 lines |
| `/job/:jobId/submit` | `JobCompletionScreen` | yes | artisan (submits work) | |
| `/review/:jobId` | `ReviewScreen` | yes | customer | |
| `/dispute/:jobId` | `DisputeScreen` | yes | — | |
| `/admin` | redirect → `/admin/dashboard` | yes | admin | |
| `/admin/dashboard` …`/admin/settings` (11 sections) | `AdminDashboardScreen(section:)` inside `AdminShell` (ShellRoute) | yes | admin only | sections: dashboard, users, artisans, jobs, verifications, disputes, reviews, support, deletions, audit-logs, analytics, settings — enum in `admin_sidebar.dart:10-42` |
| `/verification` | `VerificationUploadScreen` | yes | artisan | |
| `/bank-details` | `BankDetailsScreen` | yes | artisan | |
| `/business-profile` | `BusinessProfileScreen` | yes | artisan | |
| `/portfolio` | `PortfolioManagerScreen` | yes | artisan | |
| `/portfolio-project` | `PortfolioProjectScreen` | yes | artisan | extras: artisanId, existing |
| `/open-jobs` | `OpenJobsFeedScreen` | yes | artisan | extra: category |
| `/profile` | `ProfileTabContent` (wrapped in bare `Scaffold`) | yes | — | also embedded directly as bottom-nav "Profile" tab in both role UIs |

**Broken/dead findings:**
- No routes point to nonexistent screens (all `GoRoute` builders resolve to real classes) — no broken routes found.
- `lib/screens/jobs/` and `lib/screens/payments/` (plural) directories exist but are **completely empty** — leftover from a rename to singular `job/` / `payment/`; not referenced anywhere.

## 2. Screens Inventory (by subfolder)

### `admin/` (6 files — all support the single admin shell, no independent routes)
| File | Purpose | Reached via |
|---|---|---|
| `admin_dashboard_screen.dart` (7765 lines) | Monolith holding `AdminDashboardScreen` + `AdminShell` + all 11 section tab widgets (`_UsersTab`, `_ArtisansSection`, `_JobsTab`, `_VerificationCenterTab`, `_DisputesTab`, `_ReviewsTab`, `_SupportTicketsTab`, `_DeletionRequestsTab`, `_ActivityTab`, `_AnalyticsTab`, `_AdminSettingsTab`) selected via `switch (section)` at admin_dashboard_screen.dart:364-377 | `/admin/*` |
| `admin_sidebar.dart` | `AdminSection` enum (route-path source of truth), `AdminSidebar` nav widget | embedded in `AdminShell` |
| `admin_charts.dart` | Chart widgets for analytics tab | embedded |
| `admin_data_table.dart` | Reusable data-table widget for users/jobs/disputes lists | embedded |
| `admin_palette.dart` | Admin-specific color palette constants | embedded |
| `admin_widgets.dart` | Misc shared admin UI (stat cards, badges) | embedded |

### `artisan/` (10 files)
| File | Purpose | Reached via |
|---|---|---|
| `artisan_list_screen.dart` | Ranked artisan matches for a job | `/artisans/:jobId` |
| `artisan_profile_screen.dart` | Public artisan profile view (portfolio, reviews, trust score) | `/artisan/:uid` |
| `browse_artisans_screen.dart` | Free browse of artisans (no job context) | `/browse-artisans` |
| `favorites_screen.dart` | Customer's saved/favorited artisans | `/favorites` |
| `bank_details_screen.dart` | Artisan payout/bank account form | `/bank-details` |
| `business_profile_screen.dart` | Artisan business info editor | `/business-profile` |
| `open_jobs_feed_screen.dart` | Feed of open jobs artisan can quote on | `/open-jobs` |
| `portfolio_manager_screen.dart` | Manage portfolio project list + analytics | `/portfolio` |
| `portfolio_project_screen.dart` | Add/edit single portfolio project | `/portfolio-project` |
| `artisan_dashboard_screen.dart` (817 lines) | Contains `ArtisanHomeTabContent` (used) **and** `ArtisanDashboardScreen` class | `ArtisanHomeTabContent` is embedded via `home_screen.dart:67` as the artisan bottom-nav "Find Jobs" tab. **`ArtisanDashboardScreen` itself has NO route and NO call site anywhere else in the codebase (grep confirms only its own class/constructor/debug-log reference it) — dead/unreachable screen.** |

### `auth/` (8 files) — all reached
`login_screen.dart` (`/login`), `register_screen.dart` (`/register`, contains role-picker `_RoleTile`), `artisan_registration_screen.dart` (`/register/artisan`, "Step 2 of artisan onboarding" per its own doc-comment), `forgot_password_screen.dart` (`/forgot-password`), `verify_email_screen.dart` (`/verify-email`), `role_selection_screen.dart` (`/role-select`), `suspended_screen.dart` (`/suspended`), `splash_screen.dart` (`/`).

### `chat/`, `dispute/`, `home/`, `job/`, `notifications/`, `payment/`, `profile/`, `review/`, `settings/`, `support/`, `verification/`, `wallet/` — all files reached
- `chat/chat_screen.dart` → `/chat/:jobId`; `chat/my_chats_screen.dart` → `/my-chats` + embedded artisan "Inbox" tab.
- `dispute/dispute_screen.dart` → `/dispute/:jobId`.
- `home/home_screen.dart` → `/home`; `home/all_jobs_screen.dart` → `/jobs` + embedded tab; `home/service_request_screen.dart` → `/request`.
- `job/job_detail_screen.dart` → `/job/:jobId`; `job/job_completion_screen.dart` → `/job/:jobId/submit`.
- `notifications/notifications_screen.dart` → `/notifications`.
- `payment/payment_screen.dart` → `/payment/:jobId`; `payment/demo_escrow_screen.dart` → `/demo-payment/:jobId`; `payment/payment_webview_screen.dart` → `/payment/:jobId/webview`.
- `profile/profile_screen.dart` → `/profile` + embedded "Profile" tab (both roles).
- `review/review_screen.dart` → `/review/:jobId`.
- `settings/settings_screen.dart` → `/settings`.
- `support/contact_support_screen.dart` → `/support`; `support/about_screen.dart` → `/about`.
- `verification/verification_upload_screen.dart` → `/verification`.
- `wallet/wallet_screen.dart` → `/wallet` + embedded customer bottom-nav "Wallet" tab.

### `jobs/`, `payments/` (both directories) — **empty, no files, dead leftover folders**

## 3. Services

### `lib/core/services/` (22 files)
| File | Purpose |
|---|---|
| `auth_service.dart` | Firebase Auth wrapper (sign in/up/out, password reset, `userChanges()` stream — doc comment explains why not `authStateChanges()`) |
| `profile_service.dart` | Avatar upload, username/email/password changes, account-deletion requests, active-role switching — explicitly NOT artisan trust/verification fields |
| `job_service.dart` | **Single authoritative write layer for `/jobs`** — all state-machine transitions, validated & transactional |
| `escrow_service.dart` | A **second, parallel** job-state-machine (`transitionTo`) — confirmed by grep to have **zero call sites anywhere in the app** (not even the demo path uses it — that uses `DemoEscrowService` instead). Dead code. |
| `demo_escrow_service.dart` | Demo-only simulated escrow; routes all writes through `JobService` so it stays audit-consistent; used by `demo_payment_provider.dart` → `/demo-payment/:jobId` |
| `payment_service.dart` | `simulatePayment()` — legacy/demo Paystack simulation, locks escrow via `JobService` |
| `paystack_service.dart` | Client facade over Cloud Functions `initializePaystackTransaction`/`verifyPayment` (secret key kept server-side) |
| `quote_service.dart` | Write layer for `jobs/{jobId}/quotes/{artisanId}` — submit/edit/withdraw; accept delegates to `JobService.acceptQuote` |
| `chat_service.dart` | Real-time message stream + send for `jobs/{jobId}/messages` |
| `dispute_service.dart` | Raise/resolve disputes — writes both `/jobs` and `/disputes` atomically via `JobService` |
| `matching_service.dart` | Ranks up to 5 artisans per job (3 top-score + 2 "rising professionals" fairness slots); only approved + identity-verified artisans surfaced |
| `favorite_service.dart` | Customer favorites at `users/{uid}/favorites/{artisanId}` |
| `portfolio_service.dart` | Artisan portfolio CRUD + view-count analytics |
| `verification_service.dart` | Identity-verification pipeline write layer (`verifications/{uid}` + derived `artisans/{uid}.verificationStatus`) |
| `admin_audit_service.dart` | Single write layer for `admin_audit_logs/{logId}` — **actively used** (verification_service.dart, admin_dashboard_screen.dart) |
| `admin_audit_log_service.dart` | A second, near-duplicate `admin_audit_logs` writer — grep confirms **zero call sites outside its own file**. Dead code (previous audit flagged this as "not individually re-traced"; now confirmed dead). |
| `notification_service.dart` | Consolidated single write layer for `notifications/{autoId}`, replacing 3 formerly-duplicated inline writers |
| `support_ticket_service.dart` | Write layer for `/support_tickets` |
| `trust_score_service.dart` | Client-side display-only mirror of the Cloud Functions trust-score formula (30/25/20/15/10 weighting) — never writes |
| `storage_service.dart` | Firebase Storage uploads; 5MB general cap, 10MB verification-photo cap |
| `firestore_service.dart` | Thin generic Firestore collection/document accessor |
| `workflow_gate_service.dart` | Single source of truth for "what phase is this job in / what's next" — replaces duplicated logic previously in `job_detail_screen.dart` and `chat_screen.dart` |
| `artisan_eligibility.dart` | Pure client mirror of `firestore.rules`' `isArtisanEligible()`/`isReallyVerified()` |

### `lib/firebase/`
| File | Purpose |
|---|---|
| `auth/auth_repository.dart` | **Empty file (0 lines)** — dead stub |
| `auth/firebase_auth_service.dart` | **Empty file (0 lines)** — dead stub |
| `firestore/collections.dart` | Collection-name string constants |
| `firestore/firestore_repository.dart` | Job creation (`generateJobId`, `createJob`) — **actively used** by `job_provider.dart`'s `JobRequestNotifier` (the Post-Job flow), contradicting the earlier v1-audit claim this layer was "largely unused" |
| `messaging/icon_service.dart` | **Empty file (0 lines)** — dead stub |
| `messaging/local_notification_service.dart` | FCM background message handler + local notification display |

## 4. Providers (`lib/providers/`)

| File | State/data managed |
|---|---|
| `auth_provider.dart` | `AuthState`, `authStateChangesProvider`, `currentUserProvider`/`currentUserProfileProvider` (Firestore profile stream), `isAdminProvider` (admin doc check, router.dart:143) |
| `job_provider.dart` | `JobRequestState`/`JobRequestNotifier` — job creation submission (Post Job) |
| `job_service_provider.dart` | Shared singleton `JobService` instance for escrow_provider/chat_provider |
| `escrow_provider.dart` | Job lifecycle mutations/streams — despite the name, owns *every* job-state transition, not just escrow (per its own doc comment) |
| `quote_provider.dart` | Quote submission/list/accept state, wraps `QuoteService` |
| `chat_provider.dart` | Message stream + send (text/image), wraps `ChatService` |
| `dispute_provider.dart` | Dispute record stream/raise/resolve |
| `payment_provider.dart` | Customer/artisan payment history (Wallet screen), `simulatePaymentProvider` |
| `demo_payment_provider.dart` | Demo escrow service provider + state, parallel to `payment_provider.dart` |
| `matching_provider.dart` | Ranked artisan matches per job (wraps `MatchingService`) |
| `artisan_provider.dart` | Single artisan profile live stream |
| `favorites_provider.dart` | Customer's favorited-artisan-ID set stream |
| `portfolio_provider.dart` | Portfolio project list + live view-count |
| `review_provider.dart` | Single job's review stream (doc ID = jobId) |
| `verification_provider.dart` | Artisan verification-record stream |
| `notification_provider.dart` | Notification list/unread count, FCM token registration, local-notification bridge |
| `support_ticket_provider.dart` | User's support tickets stream |
| `theme_provider.dart` | `ThemeMode` (light/dark), persisted via SharedPreferences (`theme_mode` key), default light |
| `init_provider.dart` | `firebaseInitializationProvider` — app-startup Firebase init gate (30s timeout) |
| `ai_provider.dart` | `JobAiSuggestion` — Cloud Functions call for job-description AI enhancement/category suggestion |

## Dead-code / discrepancy findings worth flagging for QA scope

1. **`ArtisanDashboardScreen`** class (`lib/screens/artisan/artisan_dashboard_screen.dart:26`) — no route, no call site anywhere except its own definition. Only its sibling `ArtisanHomeTabContent` (same file) is actually used. Not previously flagged in `v1-audit/19-dead-code.md`.
2. **`EscrowService`** (`lib/core/services/escrow_service.dart`) — confirmed to have **zero** call sites at all now (prior audit said it was used by the demo path; that's no longer true either — demo path uses `DemoEscrowService`). Fully dead.
3. **`AdminAuditLogService`** (`lib/core/services/admin_audit_log_service.dart`) — confirmed dead (no consumers), duplicate of the actively-used `AdminAuditService`.
4. **`lib/firebase/auth/auth_repository.dart`**, **`firebase_auth_service.dart`**, **`lib/firebase/messaging/icon_service.dart`** — literally empty files (0 lines each).
5. **`lib/firebase/firestore/firestore_repository.dart`** — contrary to the prior audit note calling this layer "largely unused," it **is** actively used by the Post Job flow (`job_provider.dart`).
6. **`google_fonts` package** — declared in `pubspec.yaml:48`, zero usages found anywhere in `lib/`. Dead dependency.
7. **`lib/screens/jobs/`** and **`lib/screens/payments/`** — empty directories, no files.
8. Stale claims in `v1-audit/19-dead-code.md` no longer valid: `phone_login_screen.dart` and `customer_registration_screen.dart` — **these files no longer exist in the repo at all** (confirmed via search), so they've since been removed rather than merely being dead code. Prior-audit "dead screens" finding is now moot.
9. `/demo-payment/:jobId` remains a live, ungated route in production routing — worth explicit scoping decision (should it be admin/debug-gated or removed) before workflow testing treats it as in-scope for customer/artisan flows.
10. No dedicated "Beta tester" admin management screen was found in current code, despite being named in the requested feature checklist — needs confirmation whether this was descoped or lives elsewhere (e.g., a Firestore-only flag with no UI).
