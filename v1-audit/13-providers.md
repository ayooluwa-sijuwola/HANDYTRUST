# Part 13 — Providers (Complete Riverpod Inventory)

Every top-level provider declaration, grepped directly from `lib/providers/*.dart` — not inferred from consumption sites. Grouped by file/domain. "Consumers" are stated where confirmed by this audit's direct screen reads elsewhere in this document; not independently re-traced for every single provider given the volume (60+).

## Auth (`auth_provider.dart`)
| Provider | Type | Purpose |
|---|---|---|
| `authServiceProvider` | `Provider<AuthService>` | DI wrapper |
| `profileServiceProvider` | `Provider<ProfileService>` | DI wrapper |
| `authNotifierProvider` | `StateNotifierProvider<AuthNotifier, AuthState>` | Sign-in/sign-up/sign-out mutations (Part 2) |
| `authStateChangesProvider` | `StreamProvider<User?>` | Raw Firebase Auth state — feeds the router's `refreshListenable` |
| `currentUserProfileProvider` | `StreamProvider<UserModel?>` | Live `users/{uid}` doc for the signed-in user |
| `currentUserProvider` | alias | `= currentUserProfileProvider` — same stream, a second name for it |
| `isAdminProvider` | `StreamProvider<bool>` | Resolved admin-claim state — drives the router's `/admin/*` guard and the conditional Profile menu row |

## Jobs (split across two files — a naming/organization quirk worth noting)
`escrow_provider.dart` actually owns the job read streams and the write notifier, despite the name: `jobStreamProvider`, `customerJobsProvider`, `artisanJobsProvider`, `jobPaymentProvider`, `escrowNotifierProvider` (the `EscrowNotifier` covering every job-lifecycle mutation, Part 6). `job_provider.dart` (a differently-named, easily-confused file) holds only `jobRequestNotifierProvider` — the job-posting form's state, including the AI-suggestion flow. `job_service_provider.dart` holds just `jobServiceProvider` (DI wrapper for `JobService` itself).

## Quotes (`quote_provider.dart`)
`quoteServiceProvider`, `jobQuotesProvider` (family, per-job quote list), `artisanQuoteForJobProvider` (an artisan's own quote on a specific job), `openJobsFeedProvider` (family by category — the Open Jobs Feed's data source).

## Chat (`chat_provider.dart`)
`chatServiceProvider`, `messagesStreamProvider`, `messagesUnreadCountProvider`, `jobHasChatProvider`, `lastMessageProvider`, `chatUnreadCountProvider`, `storageServiceProvider` (DI wrapper, lives in this file rather than a dedicated storage-provider file), `chatNotifierProvider` (family, the write notifier for sendText/sendImage/sendNegotiation). Two underscore-prefixed (private/internal) providers, `_artisanMessagedJobIdsProvider` and `_jobsByIdsProvider`, exist as intermediate composition steps feeding `artisanChatJobsProvider` (the artisan's "My Chats" list).

## Escrow/Payment
- `payment_provider.dart`: `paymentServiceProvider`, `customerPaymentsProvider`/`artisanPaymentsProvider` (family — the real payment records, confirmed as what the Wallet screen consumes), `paymentNotifierProvider`, and — coexisting in the same file — `simulatePaymentProvider`, the demo/fake payment path (Part 19).
- `demo_payment_provider.dart`: `demoEscrowServiceProvider`, `demoPaymentNotifierProvider`, `jobRawStreamProvider` — an entirely separate demo-payment provider surface, confirmed to still wire `EscrowService` (Part 19's dead-code finding).

## Disputes (`dispute_provider.dart`)
`disputeServiceProvider`, `disputeForJobProvider`, `openDisputesProvider`.

## Reviews (`review_provider.dart`)
`jobReviewProvider`, `artisanReviewListProvider`, `allReviewsProvider`.

## Verification (`verification_provider.dart`)
`verificationServiceProvider`, `verificationStatusProvider`, `pendingVerificationsProvider` (the admin queue's data source).

## Artisan discovery (`artisan_provider.dart`, `matching_provider.dart`)
`artisanProfileProvider`, `artisanReviewsProvider`; `matchingServiceProvider`, `matchingProvider` (family, keyed on a `MatchingParams` object — the ranked-artisan-list result for a job, Part 3's finding about `matchScore` vs. `trustScore` applies here).

## Favorites (`favorites_provider.dart`)
`favoriteServiceProvider`, `favoriteIdsProvider`, `favoriteArtisansProvider`.

## Portfolio (`portfolio_provider.dart`)
`portfolioServiceProvider`, `portfolioViewCountProvider`, `portfolioProjectsProvider`.

## Support (`support_ticket_provider.dart`)
`supportTicketServiceProvider`, `userTicketsProvider`, `allTicketsProvider` (admin).

## Notifications (`notification_provider.dart`)
`notificationServiceProvider`, `userNotificationsProvider`, `unreadNotificationCountProvider`, `notificationInitProvider` (the FCM-registration bootstrap provider watched once at the app root — Part 10). This file previously failed to compile in release mode due to a missing `firebase_messaging` import; fixed (Part 10).

## AI (`ai_provider.dart`)
`aiServiceProvider` — wraps the `analyzeJob` Cloud Functions callable (Part 17).

## Theme (`theme_provider.dart`)
`themeProvider` — `StateNotifierProvider<ThemeNotifier, ThemeMode>`, persists the light/dark choice locally.

## Bootstrap (`init_provider.dart`)
`firebaseInitializationProvider` — a `FutureProvider<void>` gating `HandyTrustApp`'s `.when(data:/loading:/error:)` branch in `main.dart`; the entire app's UI tree is downstream of this one provider resolving.

## Initialization order (confirmed by direct reading of `main.dart`)
`WidgetsFlutterBinding.ensureInitialized()` → `initializeFirebase()` (awaited directly in `main()`, with a fallback retry via `firebaseInitializationProvider` if the first attempt fails) → `LocalNotificationService.instance.init()` (must run after Firebase init — its own constructor touches `FirebaseMessaging.instance`) → `runApp`. Inside the widget tree, `notificationInitProvider` is only watched by `_HandyTrustRouterApp`, which itself only renders once `firebaseInitializationProvider` resolves to `data` — so FCM registration structurally cannot run before Firebase is ready, confirmed by the provider dependency graph, not just code comments.

## Potential issues found
- **Two files both plausibly named for "jobs"** (`job_provider.dart` vs. `escrow_provider.dart` actually owning the job streams) is a real discoverability/naming issue for anyone extending this codebase — confirmed by grep, not assumed.
- **Two parallel payment-provider surfaces** (`payment_provider.dart`'s real `customerPaymentsProvider`/`artisanPaymentsProvider` vs. `demo_payment_provider.dart`'s simulated path) exist side by side with no gating between them at the provider layer — consistent with Part 19's dead-code finding that the demo payment screen remains reachable in the router.
- **`currentUserProvider` as a bare alias for `currentUserProfileProvider`** — harmless, but means two names resolve to the exact same provider instance; a future contributor could reasonably assume they're independent and introduce subtle confusion.
