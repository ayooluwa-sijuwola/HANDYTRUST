# HandyTrust — Stage 8 Backend Integration Map

Date: 2026-11-04 · Branch: `stage-8-ui-replacement` (uncommitted)

This document maps every new Stage 8 screen to the existing backend it uses.

**No backend contract changed.**
- `git diff stage-7.3-verified-baseline -- functions firestore.rules storage.rules firestore.indexes.json firebase.json` is **empty**.
- No model or collection was added or altered.
- New screens call only existing providers and services.
- The test `no Firebase SDK imports in lib/ui` (in `test/stage8_ui_test.dart`) fails if a presentation file imports `cloud_firestore`, `firebase_auth`, `firebase_storage` or `cloud_functions`.

**Layering:**
- **Widget** (`lib/ui/screens`) → **Riverpod provider/notifier** (`lib/providers`) → **service** (`lib/core/services`) → Firebase.
- HandyTrust has no separate repository layer. Services play that role, so the "Repository" column is merged into "Service".
- Pure presentation logic that was previously inline in widgets now lives in tested classes:
  - `CustomerBookingLogic`
  - `PaymentSummary`
  - `NotificationCategories`
  - `HtFormat`

**Route guard (unchanged):**
- The central `redirect` in `lib/routes/router.dart` requires a signed-in user with a verified email for every non-public route. It also handles suspension, `/admin` and dual-role checks.
- The only addition is the public `/onboarding` route. It shows once, uses a local flag, and redirects signed-in users to `/home`.

**Common states:**
- Loading → `HtLoadingView` (a real `AsyncLoading`, never a timer).
- Error → `HtErrorView` (the provider's real error text).
- Empty → `HtEmptyView` with a real next action.
- Action failures → `htSnack(..., error: true)` with the server message.
- No screen fakes loading or success.

---

| Screen (file) | Route(s) | Providers | Service → Firebase operation | Model(s) | Authorization | Loading / Empty / Error |
|---|---|---|---|---|---|---|
| **Onboarding** (`onboarding_screen.dart`) | `/onboarding` (public); `/` splash redirects here until seen | `onboardingSeenProvider` (`OnboardingNotifier`) | `SharedPreferences` key `onboarding_seen_v1` (local only; no server state) | — | Public; signed-in users are redirected to `/home` | Splash waits while the flag is `null`; no empty/error state needed |
| **Customer shell** (`customer_shell.dart`) | `/home` (customer role) | `customerTabProvider` (`StateProvider<CustomerTab>`) | — | — | Customer role (`HomeScreen` sends artisans to the retained artisan shell) | — |
| **Discovery** (`discovery_screen.dart`) | `/home` tab 0; `/browse-artisans` | `featuredArtisansProvider`, `currentUserProvider`, `unreadNotificationCountProvider` | Firestore query `artisans` where `approvalStatus == approved` and `verificationStatus in [id_verified, trusted]`, ordered by `rating`; `NotificationService.watchUnreadCount` | `ArtisanModel`, `UserModel` | Signed in; the `artisans` read rule applies | "Finding verified artisans…" / "No artisans found" (filter-aware) / error view |
| **Artisan Profile** (`artisan_profile_screen.dart`) | `/artisan/:uid` | `artisanProfileProvider(uid)`, `artisanReviewListProvider`, `portfolioProjectsProvider`, `favoriteIdsProvider`, `escrowNotifierProvider` | `artisans/{uid}` stream; `ReviewService` (`reviews`); `PortfolioService` (`portfolio_projects`); `FavoriteService.toggleFavorite` (`favorites`); **Book** with a job: `EscrowNotifier.acceptArtisan` → `JobService.acceptArtisan` (transactional, `matched`); otherwise → `/secure-booking/:artisanId` (retained flow) | `ArtisanModel`, `ReviewModel`, `PortfolioProject`, `JobModel` | Signed in; **Book** shown only if `ArtisanEligibility.canQuote` holds; the state transition is enforced by Firestore rules + `WorkflowGateService` | Loader / "Artisan not found" / "No reviews yet." / error view; a failed `acceptArtisan` shows an error snackbar and **does not** navigate |
| **Post a Job** (`post_job_screen.dart`) | `/request` (`?category=`) | `jobRequestNotifierProvider`, `platformConfigProvider`, `currentUserProvider` | `JobRequestNotifier.submitRequest` → `JobService` creates `jobs/{id}`; photos via `StorageService` with `ImagePrivacy` (EXIF stripping); `LocationService.currentArea()` (geolocator, optional) | `JobModel`, `PlatformConfig` | Signed in (customer); the `jobs` create rule (field allow-list) applies; client checks the budget against server `minJobValue` | Button spinner while `_submitting`; inline validation (≥ 1 photo, category, description 10–500, location, budget ≥ min); server error → snackbar |
| **My Bookings** (`bookings_screen.dart`) | `/home` tab 1; `/jobs` (customer, via `_RoleAware`) | `customerJobsProvider(uid)`, `jobQuotesProvider(jobId)`, `artisanProfileProvider`, `escrowNotifierProvider`, `unreadNotificationCountProvider` | `jobs` where `customerId == uid`; `jobs/{id}/quotes`; **Approve & Release**: `htConfirm` → `EscrowNotifier.confirmComplete` → `JobService.confirmComplete` (single transaction: job `completed` + `escrow_releases` entry; the payout is handled by Cloud Functions) | `JobModel`, `QuoteModel` | Participants only (`jobs` read rule); Release is shown **only when status is `submitted`** (`CustomerBookingLogic.actionFor`); Pay is shown only when `WorkflowGateService` allows it | Loader / per-tab empty ("No active bookings", "No completed bookings yet", "No disputes") / error view; release failure → error snackbar |
| **Confirm & Pay** (`confirm_pay_screen.dart`) | `/payment/:jobId` (replaces `payment_screen`; `/demo-payment` removed) | `jobStreamProvider(jobId)`, `paymentBreakdownProvider(jobId)`, `paystackServiceProvider`, `escrowNotifierProvider`, `currentUserProvider`, `artisanProfileProvider` | Callable **`getPaymentBreakdown`** (server-computed fee and total); if needed `EscrowNotifier.initPayment` → `JobService.initPayment` (amount read server-side, HT-004); callable **`initializePaystackTransaction`** → `/payment/:jobId/webview` (retained) → callable **`verifyPayment`** + Paystack webhook → escrow lock | `JobModel`, `PaymentBreakdown`, `PaymentModel` | Job customer only; the server rejects non-payers; no client-side fee maths; no saved cards | "Calculating your payment…" / "Not ready for payment yet" (wrong status) / "Payment received" (already funded) / error view; a missing email shows a clear error (the demo-email fallback was removed) |
| **Payments** (adapted Wallet) (`payments_screen.dart`) | `/home` tab 2; `/wallet` (customer, via `_RoleAware`; artisans keep the earnings `WalletScreen`) | `customerPaymentsProvider(uid)`, `customerJobsProvider(uid)`, `artisanProfileProvider`, `unreadNotificationCountProvider` | `payments` where `payerId == uid`, ordered by `createdAt`; jobs as above; totals computed by `PaymentSummary.of` from **real documents only** | `PaymentModel`, `JobModel` | `payments` read rule (payer/payee/admin) | Loader / "No payments yet" / error view; no balance, Add Money or Withdraw |
| **Chat** (`chat_screen.dart`) | `/chat/:jobId` | `jobStreamProvider`, `authStateChangesProvider`, `chatNotifierProvider(params)`, `messagesStreamProvider`, `chatServiceProvider`, `artisanProfileProvider` | `ChatService`: `jobs/{id}/messages` stream, send text/image (upload through `StorageService` + `ImagePrivacy`), `markAllAsRead`; price proposal via the existing chat notifier (in `inChat` only) | `MessageModel`, `JobModel` | Job participants only (`messages` rules); the other party is derived from the job (never from the URL); waits for the auth uid before deciding the viewer's role | Loader until auth and job resolve / "Start the conversation" / "Chat not available yet" / "Job not found"; send button disabled while `_sending` |
| **Profile** (`profile_screen.dart`) | `/home` tab 3; `/profile` | `currentUserProvider`, `customerJobsProvider`, `artisanProfileProvider`, `isAdminProvider`, `themeProvider`, `profileServiceProvider`, `authNotifierProvider` | `ProfileService.uploadAvatar` (Storage avatar path + `users/{uid}`); `ProfileService.setActiveRole` (dual-role users only); `ThemeNotifier.toggle` (local); `AuthNotifier.signOut` | `UserModel`, `ArtisanModel`, `JobModel` | Owner; the **Admin Dashboard card renders only when `isAdminProvider` is true** (and `/admin` is still guarded by the router); Artisan Mode only for dual-role users | Loader / error view; avatar upload spinner + error snackbar; log-out confirmation sheet |
| **Identity Verification** (`verification_screen.dart`) | `/verification` | `verificationStatusProvider(uid)`, `verificationServiceProvider`, `storageServiceProvider`, `currentUserProvider` | `StorageService.uploadVerificationPhoto` → `verifications/{uid}/{type}.jpg` (owner + admin read only); `VerificationService.submit` → `verifications/{uid}` (`pending`); `deferVerification` (`pending_later`); admin review (retained admin dashboard) | `VerificationStatus` | Owner (Storage + Firestore rules); camera/photo permission checks via `permission_handler` | Live status from the stream (pending / approved / rejected); upload progress state; permission-denied and upload errors → snackbar |
| **Notifications** (`notifications_screen.dart`) | `/notifications` | `userNotificationsProvider`, `notificationServiceProvider`, `currentUserProvider` | `NotificationService.watchForUser`, `markRead`, `markAllRead` (`notifications`) | `NotificationModel` | Owner only (`notifications` read rule); taps navigate only through the `safeNotificationRoute` allow-list | Loader / "No notifications" (per filter) / error view |

---

## Retained screens reached from new screens (contracts unchanged)

- `/payment/:jobId/webview`: `PaymentWebviewScreen`, Paystack checkout + `verifyPayment`.
- `/job/:jobId`: `JobDetailScreen`, the full lifecycle (agreement, schedule, cancellation, refund, rework, dispute window, quotes).
- `/artisans/:jobId` (matched artisans), `/secure-booking/:artisanId`, `/my-chats`, `/settings`, `/support`, `/about`, `/review/:jobId`, `/dispute/:jobId`.
- `/wallet` (artisan earnings), `/jobs` (artisan), `/admin`.

## Cloud Functions callables used by Stage 8 screens

| Callable | Caller | Purpose |
|---|---|---|
| `getPaymentBreakdown` | Confirm & Pay (`paymentBreakdownProvider`) | Server-computed service amount, 5 % platform fee and total |
| `initializePaystackTransaction` | Confirm & Pay | Creates the Paystack transaction for the server-frozen amount |
| `verifyPayment` | Retained payment webview | Server-side verification before escrow lock |

All other money movement is unchanged and server-side: escrow lock via webhook, single release after approval or the 14-day auto-release, refunds, chargebacks and payouts.

## Removed integrations

- `/demo-payment/:jobId` route.
- `DemoEscrowScreen`, `demo_payment_provider.dart`, `DemoEscrowService` (wrote `paid_escrow`).
- The `kDebugMode` hand-off in the old payment screen.

The legacy `paid_escrow` → `escrowLocked` read mapping in `JobModel.fromJson` was intentionally left in place, so any old documents still parse.

## Unused legacy code noticed (not changed)

`lib/core/services/escrow_service.dart` (`EscrowService`) has no callers. The escrow notifier uses the transactional `JobService`. It was left untouched because it predates Stage 8, and removing it is a backend-layer cleanup outside this authorization.
