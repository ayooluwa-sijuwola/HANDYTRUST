# Stitch Notification Audit — Group 9

Backend-and-UI task. No `JobService`/`WorkflowGateService`/escrow/payment logic touched — the Cloud Functions changes below are strictly notification delivery (writing a doc, sending a push), not business logic.

---

## Current notification flow — traced end to end, every path found

**Event sources found**: job status transitions (`onJobCompleted` Firestore trigger, reacting to `escrowLocked`/`submitted`/`completed`/`disputed`), Paystack transfer webhooks (`payout_completed`/`payout_blocked`), and Dart-client writes from `QuoteService`/`DisputeService`/`VerificationService` (via `NotificationService.send()`, all funneling into the same in-app collection).

**The actual mechanism, and the bug**: there were **two entirely separate, non-overlapping notification pipelines**, and almost nothing went through both:

| Path | Writes `notifications/{id}` (in-app inbox) | Sends FCM push |
|---|---|---|
| `_sendNotification` (Cloud Functions) — escrowLocked/submitted/completed/disputed | **No** | Yes |
| `_sendInAppNotification` (Cloud Functions) — payout_completed/payout_blocked | Yes | **No** |
| `NotificationService.send()` (Dart client) — quotes/disputes/verification/agreement events | Yes | **No** |

Every job-status push (escrow locked, work submitted, payment released, dispute raised) called `messaging.send()` directly and never touched the `notifications` collection at all. Every other notification type wrote the Firestore doc and stopped there — no push ever went out.

**Why this explains all three symptoms the task asked about**:
- **"Unread count does not update correctly"** — not a bug in the count itself (`NotificationService.watchUnreadCount`/`userNotificationsProvider` are live Firestore streams, correctly reactive; `firestore.rules`' `allow update` on `isRead`/`readAt` is correctly scoped to the owner). The badge is *accurate* — it's just counting a collection that most of what a user actually experiences (job status changes) never wrote to. A customer who got a push saying "Work Submitted" and taps it finds no matching entry in the Notification Center and no badge increment, because that event never created one.
- **"Background/app-closed notifications fail"** — for the job-status path specifically, background/terminated delivery is actually implemented *correctly*: `_sendNotification` sends a proper `notification: {title, body}` block (required for the OS to auto-display when the app isn't running), the client registers `FirebaseMessaging.onBackgroundMessage` with a top-level `@pragma('vm:entry-point')` handler, permissions are requested, and the token is saved to `fcm_tokens/{uid}` (the collection Cloud Functions actually read — an earlier fix already corrected a prior mismatch where tokens were saved to `users/{uid}.fcmToken`, a field nothing read). The real failure mode is different: for every notification type *except* job-status ones, no push was ever attempted at all — so "background notification" isn't failing, it's simply never sent.

**Read tracking**: `_NotificationTile.onTap` calls `NotificationService.markRead` when a notification is unread — correct in principle, but as a bare `ref.read(...).markRead(...)` with no `await` and no error handling. A failed write (network blip, anything) fails completely silently — no snackbar, no log, no retry. Low-frequency but real.

**Minor, unrelated to the above**: `notification_provider.dart` carried three pre-existing analyzer warnings (an `onError` callback with a mismatched return type, two unnecessary `?.` null-aware operators on a non-nullable `navigatorKey`) — cosmetic, cleaned up alongside the real fix since they were sitting in the exact file this audit covers.

---

## Fix implemented

Added **one** new Cloud Function, `onNotificationCreated` (Firestore trigger on `notifications/{notifId}` document creation), which reads the new doc's `userId`, looks up their `fcm_tokens` entry, and sends the FCM push — the same `messaging.send()` shape `_sendNotification` already used. This becomes the single, unified push-delivery mechanism for **every** notification source at once, since every source already writes (or, after this fix, now writes) to the same collection:

- `_sendNotification` (job-status events) now **writes to `notifications`** instead of calling `messaging.send()` directly — the new trigger picks it up and pushes automatically. This is the one behavior change to an existing function, and it's additive: the push still goes out, exactly as before, just via one shared path instead of a bespoke one.
- `_sendInAppNotification` (payout events) and the Dart-side `NotificationService.send()` (quotes/disputes/verification/agreement) needed **no changes** — they already wrote to `notifications`, so they now get pushes automatically, for free, from the same new trigger.

Net effect: every notification type now reliably does both — appears in the in-app Notification Center *and* sends a push — through one mechanism, not four different hand-maintained ones.

**Not touched**: `firestore.rules`' notifications type-whitelist (governs client writes only; Cloud Functions use the Admin SDK and bypass it entirely, so no rule change was needed for any of this). `JobService`, `WorkflowGateService`, escrow/payment logic — none of the events above changed what triggers them, only what happens once they fire.

---

## Backend requirements / limitations still open

- FCM delivery still silently no-ops if a user has no `fcm_tokens` doc (never granted permission, or it's stale) — expected, not a bug, but worth knowing: those users still get the in-app entry (now guaranteed by this fix), just no push.
- No dead-token cleanup exists — a stale/uninstalled-app token in `fcm_tokens` will fail `messaging.send()` silently (caught, logged, not retried or removed). Not fixed here; flagged as a real but separate hardening task.
