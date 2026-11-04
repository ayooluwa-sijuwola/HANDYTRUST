# Part 9 — Chat System

## Conversation creation
There is **no separate chat/conversation document** — confirmed directly in `ChatService`'s own code comment: "a job's `messages` subcollection IS its chat thread, already keyed 1:1 by jobId... there is nothing to create." `ChatService.getOrCreateJobChat` exists only to fail fast with a clear error (missing job, customer mismatch) before the UI navigates to a chat screen that would otherwise show a confusing empty state — it performs no write.

## Message sending ✅
Four message types (`MessageType` enum): `text`, `image`, `negotiation`, `system`. `ChatService.sendText`/`sendImage`/`sendNegotiation`/`sendSystemMessage` each write directly to `jobs/{jobId}/messages`. `sendNegotiation` is the one exception to "chat is simple writes" — it's implemented in `JobService`, not `ChatService`, specifically so the chat message and the job's `agreedAmount` field update happen in one atomic transaction (confirmed by direct reading of `JobService.sendNegotiation`).

## Read receipts ⚠️ — data exists, no UI renders it
`isRead: boolean` exists on every message (`ChatService.markAsRead`, `watchUnreadCount`/`unreadCount` for badge counts) and rules restrict message `update` to exactly that one field. **But `chat_screen.dart`'s `_MessageBubble` widget does not render any read/unread indicator at all** — confirmed by reading the widget's full build method: it shows the bubble content and a timestamp, nothing else. The unread count is used elsewhere (chat-list badges, notification bell) but never surfaced inside the thread itself as a "seen" marker.

## Attachments ⚠️ — images only, real
`_pickAndSendImage` (gallery picker → client-side compression above 500KB → `ChatService.sendImage`) is a genuine, working feature. **No voice notes, no document/file attachments, no video** exist anywhere in the message model or UI.

## Permissions (rules-enforced, confirmed by direct reading)
- Full-thread read/write: both job parties (`isJobParty`), once matched.
- **Pre-match exception, deliberately scoped**: while a job is still `status: 'requested'`, *any* registered artisan can read/send messages to that job's customer — but read access is additionally filtered to only messages where that specific artisan is sender or receiver, preventing one interested artisan from reading another's private pre-match conversation with the same customer on the same job. This scoping is explained in the rules file's own comment as a deliberate fix for an earlier, stricter version that accidentally broke the pre-match chat UI for unverified-but-registered artisans.
- `update` is restricted to the `isRead` field only, regardless of who's writing.
- `delete` is admin-only (used when an admin deletes a spam job and cleans up its thread).

## Storage
Chat images are uploaded via `StorageService` to Firebase Storage under a `/jobs/{jobId}/{uid}/...` path pattern (shared with other job-photo uploads, not chat-exclusive). **Storage read rule for this path is `isSignedIn()`** — any authenticated user, not just job parties — confirmed in prior analysis of `storage.rules` and re-confirmed as still the case: broader than the Firestore message-read rule it's attached to. A stranger with the direct file URL (not discoverable through the app's own navigation, but not access-controlled either) could load a chat image.

## Deletion
Message-level: admin-only, as above. Thread-level: no explicit "delete conversation" action exists for either customer or artisan — a thread persists for the life of its job document.

## Encryption ❌ — none
No client-side or field-level encryption of message content was found. Messages are stored as plain text/URLs in Firestore, protected only by the access rules above (standard Firestore transport encryption applies, as it does to every collection, but that's not message-specific encryption).

## Notifications
`message_received` exists in the whitelisted notification-type set (Part 10), but **no call site sending it was found in `ChatService`** — none of `sendText`/`sendImage`/`sendNegotiation`/`sendSystemMessage` calls `NotificationService.send`. This type may be intended to be triggered elsewhere (a Cloud Function trigger on message creation was not found either) — as far as this audit could confirm by reading the actual send paths, a chat message does not currently generate a push or in-app notification. Local/foreground push display (`LocalNotificationService`) would still fire for any FCM message a device receives, but nothing in the traced write paths appears to originate one for a new chat message.

## Verified UI gap tying back to Part 6
The chat screen's app-bar "Pay Now" action renders and is tappable whenever the job's `status == 'inChat'`, with no read of the newer `agreementStatus` field — a customer can attempt to initiate payment from chat before the Agreement Confirmation checkpoint is satisfied, and would only be blocked when the actual payment-initiation write hits the (correctly enforced) gate in `JobService`/rules. The chat screen also displays only the raw `job.status.label` as its subtitle — a viewer gets no visibility into the agreement sub-state from this screen at all.
