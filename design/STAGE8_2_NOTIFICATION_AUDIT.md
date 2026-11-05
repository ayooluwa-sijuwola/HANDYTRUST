# Stage 8.2 — messaging, read-receipt and push-notification audit

**Scope:** sections H (read receipts) and I (push notifications). Client changes are implemented and tested. **Backend changes are proposed only (§5); they need your approval.**

## 1. Messaging architecture (audited)

- **Storage:** messages live in `jobs/{jobId}/messages/{msgId}` with `senderId`, `receiverId`, `isRead` and `createdAt`. One job can hold several conversations before booking (each interested artisan with the customer).
- **Rules:**
  - read/create: job party, or a pre-booking artisan for their own messages;
  - update: sender **or** receiver, `isRead` only, with no constraint on the value.
- **Server:** `onMessageCreated` writes an in-app notification for the receiver (type `message_received`, body = the first 120 characters of the text, route = `/job/{jobId}`); `onNotificationCreated` sends the push.

## 2. Defects found and fixed (client only)

| # | Defect | Evidence | Fix |
|---|---|---|---|
| R1 | **Message badges always showed 0.** `collectionGroup('messages')` queries are denied by `firestore.rules` (no recursive `{path=**}/messages` rule) | Emulator probe, 5 Nov: both collection-group queries fail; per-job queries succeed | Unread totals are summed from per-conversation queries (`unreadMessagesTotalProvider`), separately for the customer and artisan sides |
| R2 | Artisans' pre-booking conversations never listed (same denied query) | Same probe | Discovered per open feed job (`watchCounterparts`) |
| R3 | Customers' pre-booking conversations hidden (`status != requested` filter) | Code | One conversation per artisan who wrote, on each open job |
| R4 | **False "sent":** a tick showed before the server had the message | Stream ignored pending-write metadata | `includeMetadataChanges`; *Sending* (clock) until the server acknowledges |
| R5 | **Read receipts written while the app was in the background** (chat left open) | Marked on every snapshot | Only while the app is resumed; marks on resume |
| R6 | **Opening one conversation marked other artisans' messages read** (receiver-only filter) | Code | `markAllAsRead(..., otherPartyId)`; per-conversation counts |
| R7 | Duplicate concurrent read batches | No guard | In-flight guard per conversation |

**Receipt states now shown:**
- *Sending*: local write not yet acknowledged.
- *Sent*: on the server, not yet read.
- *Read*: the recipient opened the conversation in the foreground.

**"Delivered" is not shown:** nothing in the data model records delivery (§5).

## 3. Push notifications

| Check | Finding | Status |
|---|---|---|
| Android 13+ permission | `POST_NOTIFICATIONS` declared; requested via FCM on registration | OK (existing) |
| Channel | `handy_trust_main` (high importance) created at start; **background notifications used FCM's fallback channel** | **Fixed:** manifest default channel set |
| Foreground | Shown locally when the preference is on | OK; lock-screen visibility now *private* |
| Background / terminated display | Shown by the system from the `notification` block; nothing shown again by the app, so no duplicates | OK (by design) |
| Tap: background | `onMessageOpenedApp` → route. **A new listener was added on every rebuild and never cancelled**, so one tap could navigate several times | **Fixed:** one listener per session |
| Tap: terminated | `getInitialMessage`; handled once after sign-in | **Fixed:** once-only |
| Tap: foreground notification | **Did nothing** (no tap callback) | **Fixed:** `onDidReceiveNotificationResponse`, plus launch details |
| Destination | Messages opened the job page | **Fixed:** `message_received` → `/chat/{jobId}`; others use the allow-listed server route; unsafe routes → `/notifications` |
| Token registration and refresh | Saved to `fcm_tokens/{uid}`; refresh saved | OK; the refresh listener is now replaced, not duplicated |
| **Preference** (`notificationsEnabled`) | Only suppressed foreground pop-ups; background pushes still arrived | **Fixed client-side:** off → this device's token deleted and `fcm_tokens/{uid}` removed; on → re-registered |
| **Logout / account switch** | The device kept the previous account's token | **Fixed:** sign-out deletes this device's FCM token |
| Invalid-token cleanup | The server only logs failures | **Backend proposal B2** |
| Role targeting | Notifications are per user; taps resolve the role-correct screen (`_JobRoute`; the chat derives the counterpart) | OK |
| Admin authorisation | Admin alerts are in-app (`admin_alerts`), not pushed; `/admin` is not in the tap allow-list | OK |
| Sensitive previews | Server push body contains message text | **Partly fixed** (foreground private on the lock screen); **backend proposal B3** for background |

## 4. What was actually tested (and what wasn't)

**Executed and passing:**
- **Logic:** `test/stage8_2_logic_test.dart` covers receipt states, foreground-only marking, push destinations and the allow-list, and registration decisions.
- **Widget and integration with fakes** (`test/stage8_2_ui_test.dart`):
  - register on sign-in;
  - unregister when the preference is off;
  - delete the token on sign-out;
  - one navigation per tap across rebuilds;
  - the terminated-launch tap handled once;
  - unsafe payload contained;
  - receipts rendered (Sending/Sent/Read, no Delivered);
  - read marking scoped to the conversation;
  - nothing written while backgrounded;
  - marking on resume.
- **Emulator:** collection-group denial probe (4/4); Functions 266/266 (notification creation and dedupe unchanged); e2e 16/16.

**Not tested:** **real push delivery, and taps with the app foregrounded, backgrounded or terminated on a device.** This needs a physical device or emulator with Google Play services, a non-production Firebase project and a real FCM send. It was not possible here, so **push delivery is not verified**.

Manual device checklist for a staging project:
1. Grant or deny the permission.
2. Send `message_received` and `job_status_update` in each app state.
3. Confirm the channel name.
4. Confirm one navigation per tap.
5. Toggle the preference off and confirm no pushes arrive.
6. Sign out, send to the old account, and confirm nothing arrives.

## 5. Backend changes proposed — STOP for approval (not implemented)

| ID | Change | Files | Why | Tests to add |
|---|---|---|---|---|
| **B1** | `onNotificationCreated`: skip the push when `users/{uid}.notificationsEnabled == false` | `functions/index.js` | Enforce the preference server-side for devices still holding tokens | Functions emulator: preference off → no send |
| **B2** | On `messaging/registration-token-not-registered` or `invalid-argument`, delete `fcm_tokens/{uid}` when the stored token equals the failed one | `functions/index.js` | Invalid-token cleanup | Fake messaging error → doc removed |
| **B3** | Message pushes: body "New message about your job" (no text), `android.notification.channelId: 'handy_trust_main'`, `visibility: 'private'`; route `/chat/{jobId}?with={senderId}` | `functions/index.js` (`_messagePreview` caller, send options) | Privacy on lock screens; exact conversation on tap | Payload snapshot test |
| **B4** | Multi-device tokens: `fcm_tokens/{uid}/devices/{tokenHash}`, sending to all with `sendEachForMulticast`; rule: owner write/delete per device | rules + Functions + client | The last device currently wins | Rules and Functions tests |
| **B5** | Messages rule: only the **receiver** may update, and only `isRead` false → true | `firestore.rules` | Prevents fake or reset read state | Rules tests (sender denied; true→false denied) |
| **B6** | "Delivered": a `deliveredAt` field the receiver's client sets once (on stream receipt), rule-limited to the receiver, set once | rules + client | Genuine delivered state | Rules tests + widget test |
| **B7** (optional) | Recursive rule `match /{path=**}/messages/{id}` limited to `receiverId == uid` or `senderId == uid`, plus collection-group indexes | rules + indexes | Cheaper totals than per-conversation listeners | Rules tests |

None of B1–B7 is applied. The client works correctly without them, within the limits stated above.
