# Part 10 — Notification System

Two layers: an in-app feed (`notifications` Firestore collection) and FCM push, connected by `functions/index.js`'s `_sendNotification` for server-originated pushes and by `notification_provider.dart`/`LocalNotificationService` for the client-side registration/display half.

## In-app notifications (Firestore-backed) ✅
- **Writer**: `NotificationService.send()` — the single write path, confirmed as the only caller of `notifications.add`/`.set` found across the services layer.
- **Whitelist, exact, confirmed by direct reading of `firestore.rules`**: `quote_received`, `quote_accepted`, `quote_rejected`, `quote_withdrawn`, `dispute_raised`, `review_received`, `job_assigned`, `job_status_update`, `appointment_scheduled`, `message_received`, `verification_approved`, `verification_rejected` — **exactly 12 types**, all transactional (something just happened). **No reminder-class type exists** — no escrow reminder, appointment reminder, review-nudge, or arrival alert. `dispute_raised` has no `dispute_resolved` counterpart — a party is told a dispute was opened against them but not told when it closes.
- **Server-only additions from the newest work in this codebase**: `payout_blocked` and `payout_completed`, written directly by Cloud Functions via the Admin SDK, which bypasses the client-facing rules whitelist entirely — these are real, live notification types in the running system, just not ones a client could ever forge, and not present in the rules file's documented whitelist (Admin SDK writes were never subject to it, so no rules change was needed or made).
- **Read/write rules**: a user reads only their own; `isRead`/`readAt` are the only client-updatable fields; no delete permitted.
- **Actual call sites confirmed by direct reading of the services layer**: `QuoteService` sends `quote_received`/`quote_withdrawn`/`quote_rejected`/`quote_accepted`. `VerificationService` sends the two verification-outcome types (per this codebase's established service pattern, not independently re-read line-by-line for this Part). **`ChatService` sends nothing** — see Part 9's finding that no chat action triggers `message_received` despite that type existing in the whitelist.

## Push notifications (FCM) ✅ — server-originated only
- **Token registration**: `notification_provider.dart`'s `notificationInitProvider` requests permission, gets the device's FCM token, and writes it to `fcm_tokens/{uid}` (not `users/{uid}.fcmToken`, a field a prior version of this code wrote to that the Cloud Functions side never actually read — a corrected mismatch, per that provider's own code comment). Re-registers automatically on token refresh.
- **Sending**: exclusively server-side, from `functions/index.js`'s `_sendNotification`/`_buildMessages` — no client code anywhere calls FCM's send API. Templates exist for exactly four event types: `escrowLocked`, `submitted`, `completed`, `disputed` — triggered from `onJobCompleted`'s Firestore-update trigger, not from every status change (e.g., no push template exists for `matched` or `inProgress`).
- **`fcm_tokens` is unreadable by any client** (`allow read: if false` per this codebase's rules, confirmed in earlier work on this repository) — write-only from the owning user's perspective, read only by the Admin SDK.

## Background handlers ✅
`firebaseMessagingBackgroundHandler` (`local_notification_service.dart`), a top-level `@pragma('vm:entry-point')` function registered via `FirebaseMessaging.onBackgroundMessage` in `main()` — required for Android to deliver background pushes; currently just logs receipt (`debugPrint`), doing nothing further, since Android/iOS both display background FCM notifications using the OS's own default handling without needing this callback to build anything.

## Foreground handlers ✅
`LocalNotificationService.startForegroundListener` — listens to `FirebaseMessaging.onMessage`, and (if a live `isEnabled()` check passes, tied to `UserModel.notificationsEnabled`, re-checked per message rather than only at registration time) displays a local notification via `flutter_local_notifications`, since FCM does not auto-display foreground messages the way it does background ones.

## Deep-linking on tap
`routeFromMessage` (`local_notification_service.dart`) parses a route from the FCM payload's `data` map — checks an explicit `route` field first, falling back to `jobId`→`/job/{id}` or `chatJobId`→`/chat/{id}`. **Verified precisely**: the server's own `_sendNotification` only ever sets `data: {jobId, eventType}` — it never sets a `route` or `chatJobId` field — so every server-originated push deep-link actually resolves via the `jobId` fallback path, not the primary `route` field that path was seemingly designed around. This works correctly today, but only via the fallback, which is worth knowing precisely rather than assuming the primary path is what's exercised.

- `notificationInitProvider` additionally wires `FirebaseMessaging.getInitialMessage()` (app opened from terminated state via a notification tap) and `FirebaseMessaging.onMessageOpenedApp` (app opened from background) to the same `routeFromMessage`-based navigation. **This exact code previously failed to compile** — `notification_provider.dart` used `FirebaseMessaging.instance`/`FirebaseMessaging.onMessageOpenedApp` without importing the `firebase_messaging` package at all (it only imported `local_notification_service.dart`, which imports that package internally, but Dart imports aren't transitive). This has since been fixed with the missing import added; confirmed by both `flutter analyze` and a subsequent full release build succeeding.

## Local notification content
Two dedicated show-methods exist beyond the generic FCM-triggered display: `showMessageNotification` and `showJobStatusNotification` — both build the notification body client-side and call the same underlying `_show` primitive. Neither appears to be called from any chat or job-status write path traced for this audit (consistent with Part 9's finding that no chat send triggers a notification) — they exist as ready-to-use methods without a confirmed caller.

## Notification preferences ⚠️ — one real toggle, not a full preference system
`UserModel.notificationsEnabled` (boolean) is read by `LocalNotificationService`'s foreground-display gate and is toggled from two separate screens that both write the same field consistently: the Notifications screen's app-bar mute icon, and a "Push Notifications" toggle in Settings. There is no per-category granularity (no way to mute chat notifications but keep dispute ones, for example) and no push/in-app split — a single global on/off switch is the entire preferences system that exists.

## Missing implementation, stated plainly
- Reminder-class notifications (escrow, appointment, review) — zero exist.
- `dispute_resolved` — no counterpart to `dispute_raised`.
- `message_received` — whitelisted but never actually triggered by any confirmed chat call site.
- Per-category notification preferences.
- Notification content encryption/redaction — payloads carry `jobId`/`eventType` only, not sensitive content, so this is a non-issue rather than a gap.
