# Stage 8.2 — backend notification implementation report

**Dates:** first written 5 November 2026; **revised 6 November 2026** after the A1 corrections.

**Approvals:**
- "Stage 8.2 notification backend changes", approved.
- A1, approved with conditions: corrections F-1 to F-10 from `STAGE8_2_NOTIFICATION_FINAL_CODE_REVIEW.md`, F-11 addressed, reports corrected (F-12).

**Status:**
- Implemented and tested on the **local Firebase emulators only**.
- **Not deployed:** no rules, index or Functions deployment to any project.
- **Not committed:** commit approval A2 is pending the owner's review of the Gate N1 evidence.
- Real push delivery on a device is **not verified**.

**Corrections to the first version (F-12):**

| First version said | Correction |
|---|---|
| Delivered meant "received from the server in a live listener" | The first version also sent receipts from cache-only snapshots; now fixed (F-3) |
| "Older apps keep working throughout" | Tapping a message push on an older app opened a dead-end screen; now fixed (F-1) |
| Test counts | See §4 for the current figures |

## 1. Changes

| Req. | What changed | Files |
|---|---|---|
| A. Preference enforcement | `_deliverPush` reads `users/{uid}.notificationsEnabled`; `false` → no push. The in-app `notifications/{id}` record is still kept. A missing field means enabled (existing default). It is the only place push is sent (`messaging.sendEach`) | `functions/index.js` |
| B. Invalid-token cleanup | Only FCM `registration-token-not-registered` / `invalid-registration-token` remove a registration, via **compare-and-delete in a transaction** (a token refreshed meanwhile is kept). Transient errors never remove. Structured log per delivery: `{event, notifId, type, devices, sent, removed, transient}`, with no tokens logged | `functions/index.js` |
| C. Per-device tokens | See below | `functions/index.js`, `firestore.rules`, `firestore.indexes.json`, `lib/providers/notification_provider.dart`, `lib/firebase/messaging/local_notification_service.dart`, `lib/providers/auth_provider.dart`, `lib/main.dart` |
| D. Privacy | See below | `functions/index.js`, `lib/core/services/push_logic.dart`, `lib/models/notification_model.dart` |
| E. Read authorisation | Rule: only the **recipient** may update a message; only `isRead` false → true (once), optional `readAt == request.time`, optional `deliveredAt` once at `request.time`. Sender and receiver can't change; nothing else can change; empty writes are refused. Older apps' `{isRead: true}` still works. **The read receipt writes only `isRead` and `readAt` (F-2)**, so it can't collide with a delivery receipt in flight | `firestore.rules`, `lib/core/services/chat_service.dart` |
| F. Delivered | See §2. Receipts come only from **server-confirmed** snapshots (F-3). A refused receipt waits before retrying (60 s, doubling to 30 min) and batches hold at most 450 writes (F-10). The listeners are auto-disposed, so they end when the app root stops watching at sign-out (F-4) | `chat_service.dart`, `conversation_logic.dart`, `lib/providers/chat_provider.dart`, `message_model.dart`, chat UI |

**C. Per-device tokens, in detail:**
- **Registration:** `fcm_tokens/{uid}/devices/{deviceId}` `{token, platform, updatedAt}`, one per installation. The `deviceId` is a per-install lowercase UUID, and the rules require that format (F-8).
- **Sending:** to the **10 most recently refreshed** registrations only, plus the legacy `fcm_tokens/{uid}.token` from older app versions, de-duplicated by token. Sends go out in groups of up to 500 (F-8).
- **Pruning:** registrations beyond 10 are pruned on every registration write.
- **Stale sweep:** registrations not refreshed for **270 days** are removed by the daily scheduled function `sweepStaleDeviceTokens`. It runs only once deployed.
- **Logout:**
  - `AuthNotifier.signOut` runs the pre-sign-out hook for **at most 8 s** (F-5), then always signs out.
  - The hook deletes this device's registration (3 s limit) while still signed in, then invalidates the FCM token (4 s limit).
  - A failed invalidation is **remembered and retried** while nobody is signed in: at app start and whenever the device comes back online (F-6).
- **Account switch:** the trigger `onDeviceTokenWritten` makes the **newest registration the only owner** of a token (F-7):
  - newest `updatedAt` wins, with ties broken by document path;
  - each removal re-reads the registration in a transaction;
  - an event that no longer matches the stored registration does nothing.

**D. Privacy, in detail:**
- **Push text (F-9):** no stored body is ever sent in a push.
  - Every type gets a fixed, reviewed body.
  - Message, dispute and payout types also get a generic title; other titles are fixed server strings.
  - The in-app record keeps the full text.
- **Android:** channel `handy_trust_main`, visibility `private`. That only hides text on a secure lock screen when the device is set to hide sensitive content.
- **Message routes (F-1):** a message notification keeps `route: /job/{jobId}`, which older app versions open correctly, and adds `chatWith: {senderId}`. New versions open `/chat/{jobId}?with={senderId}`.
- **Recipient in the payload (F-6/F-11):** pushes carry the recipient `uid`. The app hides a **foreground** notification that isn't for the signed-in account.

## 2. Message state transitions (exact events)

| State | Event that sets it | Evidence quality |
|---|---|---|
| **Sending** | Message written to the sender's local Firestore cache; `metadata.hasPendingWrites == true` | Local only |
| **Sent** | Server acknowledged the write (`hasPendingWrites` becomes false) | Server stored the document |
| **Delivered** | The **recipient's** app saw the message in a **server-confirmed** snapshot of a live listener (`metadata.isFromCache == false`, no pending writes) and wrote `deliveredAt = request.time`. Only the recipient can set it, once (rules). Cache-only snapshots (cold start, offline) never produce it | The message reached the recipient's device from the server. FCM acceptance or a sent push is **never** used |
| **Read** | The recipient opened that conversation **with the app in the foreground**, and the server accepted `isRead: true` + `readAt` | Server-accepted recipient write. Read outranks Delivered in the UI, so a read message without `deliveredAt` shows Read |

**Limit:** Delivered requires the recipient's app to be running and signed in. A push shown while the app is closed doesn't mark delivery, by design.

## 3. Schema, rules and index changes (documented; not deployed)

**Collections and fields:**
- **New collection:** `fcm_tokens/{uid}/devices/{deviceId}`.
  - Owner-only create, update and delete; client read denied.
  - Fields limited to `token` (10–4096 characters), `platform` (`android` | `ios` | `web`) and `updatedAt == request.time`.
  - **`deviceId` must be a lowercase UUID** for create and update; delete stays open to the owner for any ID.
- **New message fields:** `readAt`, `deliveredAt` (server timestamps).
- **New notification field:** `chatWith`, on `message_received` only.
- **New push `data` fields:** `chatWith`, `uid`, all strings.

**Rules:** the messages `update` rule changed. **Breaking for senders:** they can no longer change `isRead`. No app version ever did this; the initial commit had no read-marking callers.

**New indexes** (field overrides on the `devices` collection group):

| Field | Scopes | Why |
|---|---|---|
| `token` | COLLECTION ascending; COLLECTION_GROUP ascending | Ownership release (`_releaseTokenElsewhere`) |
| `updatedAt` | COLLECTION ascending and **descending**; COLLECTION_GROUP ascending | Newest-10 selection and pruning use the collection-scope descending index; the stale sweep uses the collection-group one |

A field override replaces Firestore's automatic indexes for that field, so the collection-scope `updatedAt` indexes are listed explicitly.

**Functions:**
- **New:** `onDeviceTokenWritten` (trigger), `sweepStaleDeviceTokens` (scheduled, daily).
- **Changed:** `onNotificationCreated` (logic in `_deliverPush`), `_handleMessageCreated` (`chatWith`), `_sendInAppNotification` (optional `chatWith`).

**Deployment order (when approved):**
1. indexes;
2. rules;
3. Functions;
4. app release.

**The new rules must be live before the new app is released.** Its read and delivery writes include `readAt`/`deliveredAt`, which the old rules refuse.

**Older app versions** keep working at every step:
- legacy token honoured;
- `{isRead: true}` accepted;
- message taps open `/job/{jobId}` as before;
- unknown data fields ignored.

## 4. Tests (exact counts, 6 November 2026; all after the A1 corrections)

| Suite | Result | Where |
|---|---|---|
| Functions push tests `stage8_2_push_emulator.test.js` (preference, multi-device, legacy de-dupe, invalid/transient cleanup, refresh race, account switch, **newest-wins ownership: late, stale, concurrent, tie, duplicate, refresh-after-lookup**, **10-device cap, pruning, 270-day sweep**, payload privacy for **every** type, `chatWith`/`uid` data, `/job` route, duplicate trigger) | **24 / 24** | Firestore emulator; FCM replaced by an injected sender |
| All Functions (16 files, each in its own process) | **290 / 290** | Emulator |
| Messaging rules `stage8_2_messaging_rules.test.js` (read/delivered authorisation, duplicates, server time, shape, cross-user, unauthenticated, **delivery-then-read sequence (F-2)**, **UUID device IDs**) | **23 / 23** | Emulator |
| All Firestore rules | **162 / 162** | Emulator |
| Storage rules | **9 / 9** | Emulator |
| End-to-end (Functions + Firestore + Pub/Sub; dummy secret created and deleted) | **16 / 16**; 0 external calls; new functions loaded | Emulators |
| Client `stage8_2_backend_client_test.dart` (states; **cache-only snapshots never acknowledged**; **read payload is `isRead` + `readAt` only**; **`chatWith` routing and unsafe-ID fallback**; **foreground recipient check**; sign-out hook order, failure and **hang (8 s cap)**; **failed invalidation remembered and retried at start and on reconnect**; **4 s token-delete timeout**; **back-off and 450-write batches**; **listeners end on sign-out**; Delivered UI) | **21 / 21** | Unit and widget, fakes |
| All Flutter tests | **351 / 351** | — |
| Visual goldens | **654 / 654** (no golden changed) | — |
| `flutter analyze` | 0 errors, 0 warnings, 0 non-deprecation infos | — |

## 5. Not tested

- Real FCM delivery and taps on a physical device (foreground, background, terminated).
- The platform's `deleteToken()` behaviour when offline.
- Deployment to any Firebase project, and index builds in a real project. The emulator doesn't enforce indexes.
- `ChatService.markDelivered` back-off against real Firestore. The back-off and batching logic is unit-tested; the project has no fake-Firestore dependency.

These need physical devices and a non-production project on Blaze, since Functions can't be deployed on Spark.
