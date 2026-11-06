# Stage 8.2 — notification backend: final code review

**Date:** 5 November 2026.

**Scope:** the uncommitted notification changes on branch `stage-8-ui-replacement`, compared with HEAD `7ff140c`:

| Area | Files |
|---|---|
| Backend | `functions/index.js`, `firestore.rules`, `firestore.indexes.json`, `functions/package.json` |
| Client | `lib/core/services/chat_service.dart`, `conversation_logic.dart`, `push_logic.dart`, `lib/models/message_model.dart`, `lib/providers/auth_provider.dart`, `chat_provider.dart`, `notification_provider.dart`, `lib/main.dart`, `lib/ui/screens/chat_screen.dart`, `messages_screen.dart` |
| Tests | `test/stage8_2_backend_client_test.dart`, `firestore-tests/stage8_2_messaging_rules.test.js`, `functions/test/stage8_2_push_emulator.test.js` |

**Checked against:** `STAGE8_2_BACKEND_SECURITY_REVIEW.md` and `STAGE8_2_BACKEND_NOTIFICATION_IMPLEMENTATION_REPORT.md`.

**Method:**
- I read the diff and the code around it.
- To check what older app versions do, I read the code at the initial commit `efe5398` and at the Stage 7.3 baseline `7e16eb1`.
- I read the new tests to see what they actually prove.

**Not done:**
- No implementation file was changed.
- No test was re-run; the test counts in the implementation report are from the 5 November runs.
- Nothing was deployed or committed.

**Evidence labels:**
- **Code:** read directly in the source.
- **Test:** an existing test proves it.
- **History:** older app code, from git history.
- **Analysis:** reasoned from Firestore, FCM or Riverpod behaviour, and not reproduced on a device or emulator.

**Severity:**
- **High:** breaks a required property or a primary user flow. Fix before the local commit.
- **Medium:** fix before any staging deployment.
- **Low:** track, and fix before production.

---

## 1. Verdict on the nine required checks

| # | Requirement | Verdict | Findings |
|---|---|---|---|
| 1 | Delivered receipts can't come from cache-only snapshots | **Not met** | F-3 |
| 2 | Sign-out always completes safely if token removal fails | **Partly met.** A *failing* removal or token delete is handled; a *hanging* token delete can block sign-out, and an offline sign-out leaves the registration active | F-5, F-6 |
| 3 | Concurrent registrations can't leave inconsistent token ownership | **Not met** | F-7 |
| 4 | Device registration can't create unlimited notification targets | **Not met** | F-8 |
| 5 | Invalid-token cleanup can't delete refreshed tokens | **Met on the delivery path** (Code + Test). **Not met on the account-switch path** | F-7 |
| 6 | Notification preference enforced server-side | **Met** | §3 |
| 7 | Sensitive information excluded from relevant push payloads | **Partly met** | F-9 |
| 8 | Only the recipient can change read/delivery state | **Met** | §3 |
| 9 | Older app versions stay compatible | **Partly met.** Tapping a message push on an older app now opens a dead-end screen | F-1 |

Two High defects were also found outside the checklist (F-2, plus F-1 above), and one Medium (F-4).

**Recommendation:** don't commit as-is.
- F-1 and F-2 are High and small to fix.
- F-3, F-4 and F-5 are client-only and small. They're best fixed in the same pass.
- F-6 to F-9 must be fixed before any staging deployment.

---

## 2. Findings

| ID | Severity | Title | Main files |
|---|---|---|---|
| F-1 | **High** | Message-push taps break on older app versions | `functions/index.js:2569` |
| F-2 | **High** | The read-receipt write is rejected when a delivery receipt for the same message is in flight | `chat_service.dart:261`, `firestore.rules` `_validReceiptChange` |
| F-3 | Medium | Delivery receipts are generated from cache-only snapshots | `chat_service.dart:272-277`, `chat_provider.dart:275-292` |
| F-4 | Medium | Delivery-receipt listeners survive sign-out | `chat_provider.dart:266, 275` |
| F-5 | Medium | Sign-out can wait indefinitely on `deleteToken()` | `notification_provider.dart:143`, `auth_provider.dart:141-148` |
| F-6 | Medium | Offline sign-out leaves the previous account's push registration active indefinitely | `notification_provider.dart:130-144, 224-227` |
| F-7 | Medium | Releasing a token from other accounts is neither ordered nor atomic | `functions/index.js:1129-1159` |
| F-8 | Medium | No limit on device registrations per account | `firestore.rules:984`, `functions/index.js:1049, 1055, 1151` |
| F-9 | Medium | Some push bodies still carry amounts and text written by the other party | `functions/index.js:2198, 2489, 2509, 2523` |
| F-10 | Low | Delivery receipts retry with no backoff; batches can exceed 500 writes | `chat_service.dart:256-264, 284-299` |
| F-11 | Low | A stolen token lets the thief's own (partly controllable) notifications reach the victim's device | design (S6) |
| F-12 | Low | Inaccurate statements in the two Stage 8.2 reports | `design/STAGE8_2_*` |

### F-1 (High): message-push taps break on older app versions

**Evidence (Code + History):**
- `_handleMessageCreated` now stores and sends `route: /chat/{jobId}?with={senderId}` (`functions/index.js:2569`). Before this change, the route defaulted to `/job/{jobId}`.
- In the Stage 7.3 app (`7e16eb1`):
  - `safeNotificationRoute` allows `/chat/` (`lib/providers/notification_provider.dart:137-142`), and the tap handler pushes that route as-is.
  - The `/chat/:jobId` route builds `ChatScreen` with `otherUserId` taken **only from `state.extra`** (`lib/routes/router.dart:252-260`). A notification tap has no `extra`, and the old screen ignores the query string.
  - With an empty `otherUserId`, that `ChatScreen` shows *"Chat is not available until an artisan has been selected for this job."* (`lib/screens/chat/chat_screen.dart:144-157`).

**Impact:**
- Stage 8.2 isn't released, so every installed app is an older version.
- From the moment the Functions change is deployed, every message-notification tap on those phones leads to a dead end. Today it opens the job page.
- The in-app notification record gets the same route, so taps in the old Notification Centre break too.

**Correction:**
- Keep `route: /job/{jobId}` for message notifications, as before.
- Add a separate field `chatWith: {senderId}`, in both the push `data` and the notification document.
- In `PushLogic.destination` (new client): for `message_received`, a valid `chatWith` goes to `/chat/{jobId}?with={chatWith}`. Otherwise use the current fallback.

**Tests to add:**
- A Functions test that the stored route is `/job/j1` and `chatWith` is `cust1`.
- Flutter `destination` tests: with and without `chatWith`, plus an unsafe `chatWith` (contains `/`).

### F-2 (High): the read-receipt write is rejected when a delivery receipt is in flight

**Evidence (Code + Test + Analysis):**
- The rule allows `deliveredAt` only if it's absent: `!('deliveredAt' in resource.data)`. The rules test *"deliveredAt cannot be set twice"* proves it.
- `markAllAsRead` adds `deliveredAt` when `doc.data()['deliveredAt'] == null` (`chat_service.dart:261`).
- When a message arrives while the chat is open, two writes start from the same snapshot:
  - `deliveryAckProvider` (app root) writes the delivery receipt;
  - `ChatScreen` calls `markAllAsRead`, which waits for a `get()` and then writes.
- Firestore applies pending local writes to `get()` results, and a pending server timestamp reads as `null` by default. So `markAllAsRead` sees `deliveredAt == null` and includes it.
- Writes reach the server in order, so the delivery receipt lands first. The read batch then changes an existing `deliveredAt`, and **the whole batch is denied**.

**Impact:**
- The message isn't marked Read, so the sender keeps seeing "Delivered", and the recipient's unread badge may persist.
- It may correct itself on the next message, on resume or on reopening, depending on event order. Not reproduced; probable from the code path.

**Correction:**
- Stop writing `deliveredAt` in `markAllAsRead` and `markAsRead`.
- Read already outranks Delivered in `ReadReceipts.of`, so nothing is lost, and the rule needs no change.

**Test to add:** a fake-Firestore test that the read payload contains only `isRead` and `readAt`.

### F-3 (Medium): delivery receipts are generated from cache-only snapshots (requirement 1)

**Evidence (Code):**
- `watchIncomingUnread` uses `.snapshots()` without `includeMetadataChanges` and never looks at `metadata.isFromCache` (`chat_service.dart:272-277`).
- `DeliveryReceipts.toAcknowledge` filters only on `hasPendingWrites`, `deliveredAt` and `isRead`.
- The only cache-aware listener in the service is `_pairStream`, which isn't used for receipts.

**Impact:**
- At every cold start, Firestore first emits from the local cache, and receipts are written from that data. Offline, they're queued and committed later, so `deliveredAt` records the reconnection time.
- The cached message was received earlier, so the receipt isn't false. But on multi-device accounts a stale cache produces writes that the server denies. Through F-10 these can repeat.
- The implementation report's claim, "received the message **from the server in a live listener**", is not what the code does.

**Correction:**
- Listen with `includeMetadataChanges: true`.
- Emit the messages together with `fromCache`.
- Send receipts only when the snapshot is not from cache and the document has no pending writes.

**Test to add:** a unit test that a cache-only snapshot produces no receipt, and a server snapshot does.

### F-4 (Medium): delivery-receipt listeners survive sign-out

**Evidence (Code + Analysis):**
- `incomingUnreadProvider` is a `StreamProvider.family` and `deliveryAckProvider` a `Provider.family`. Neither is `autoDispose`.
- On sign-out the root stops watching `deliveryAckProvider(uid)`, but the provider isn't disposed. Riverpod keeps non-autoDispose providers alive for the life of the `ProviderScope`, so its `ref.listen` subscriptions and their Firestore listeners keep running.

**Impact:**
- Each listener is re-evaluated against whoever is signed in next:
  - for an unrelated account, the listeners fail with permission-denied (wasted work);
  - if the next account is the **other party** of the previous account's chats, the query is allowed, because that account is the sender. The old provider then writes receipts for the previous account's messages under the new account's auth. They're denied, and the cycle repeats (F-10).
- No data is exposed, because the rules still apply.

**Correction:**
- Make both providers `autoDispose`, or invalidate them when the signed-in user changes.

**Test to add:** a container test that, after unwatching, the fake stream's `onCancel` fires.

### F-5 (Medium): sign-out can wait indefinitely on `deleteToken()` (requirement 2)

**Evidence (Code + Test):**
- `AuthNotifier.signOut` awaits the hook with no time limit (`auth_provider.dart:143`).
- In `unregisterPushDevice`, only the Firestore delete has a 4-second timeout. `platform.deleteToken()` (`notification_provider.dart:143`) has no timeout.
- Existing tests prove that a hook which **throws** doesn't stop sign-out, and that a failed removal still invalidates the token. No test covers a hook that **never completes**.
- How the platform `deleteToken` behaves offline isn't documented or verified here.

**Impact:** the user taps Sign out and nothing happens until the platform call returns.

**Correction:**
- `await _beforeSignOut?.call().timeout(const Duration(seconds: 6))` inside the existing try/catch.
- Give `deleteToken()` its own timeout and catch.

**Test to add:** a hook that never completes still signs out (fake async, advance 6 s).

### F-6 (Medium): offline sign-out leaves the previous account's registration active

**Evidence (Code + Analysis):**
- An offline sign-out times out the device-document delete. Firestore keeps that pending write queued for the user who made it, and sends it only when that user signs in again.
- `deleteToken()` fails offline, and nothing retries it:
  - the `unregisterDevice` branch (`notification_provider.dart:224-227`) runs once;
  - after an app restart while signed out, `PushLogic.decide` returns `none`.

**Impact:**
- The signed-out device keeps receiving the previous account's pushes until another account registers on it. The titles and bodies of the non-generic types are visible.
- The security review (S5) calls this a "narrow window". It isn't.

**Correction:**
- Store a "token invalidation pending" flag in SharedPreferences when sign-out cleanup fails.
- Retry `deleteToken()` at app start and when connectivity returns, while signed out, until it succeeds.
- Optional: add the target `uid` to the push `data`, and have the app suppress foreground display when the signed-in user differs.

**Test to add:** unit tests for the pending flag: it's set on failure, retried at start, and cleared on success.

### F-7 (Medium): releasing a token from other accounts is neither ordered nor atomic (requirements 3 and 5)

**Evidence (Code):**
- `_releaseTokenElsewhere` queries every registration holding the token, then deletes them one by one with no re-check (`functions/index.js:1129-1148`).
- `onDeviceTokenWritten` uses the event's `after` data without re-reading the document (`:1151`).
- Firestore triggers are delivered at least once, in no guaranteed order.

**Scenarios:**
- **(a) Late or duplicate event.** An event for an older registration (account A) arrives after account B registered the same token. It deletes B's current registration, so B gets no pushes until the next app start re-registers.
- **(b) Refresh between query and delete.** A registration whose token was refreshed between the query and the delete is removed. This is a refreshed-token deletion on this path.
- **(c) Near-simultaneous registrations.** Two accounts register the same token at almost the same time and each deletes the other, leaving no owner.

**Correction:**
- In the trigger, re-read the triggering document. Stop if it's gone, or if its `token` or `updatedAt` differs from the event.
- Delete each other registration in a transaction, only if `token === T && updatedAt <= mine` (newest registration wins).
- Clear a legacy token only if it still equals `T`.

**Tests to add (emulator):**
- a stale event doesn't remove a newer registration;
- a registration refreshed before the delete is kept;
- the same event delivered twice is idempotent.

### F-8 (Medium): no limit on device registrations per account (requirement 4)

**Evidence (Code + Analysis):**
- The rules check the shape of a device document but can't count them (`firestore.rules:984-992`), so any `deviceId` of 64 characters or fewer is accepted.
- `_collectTokens` reads every device for each notification (`:1055`).
- `messaging.sendEach` accepts at most 500 messages per call (Admin SDK limit), so above 500 registrations every push to that account fails (`:1049`).
- Every device write starts `onDeviceTokenWritten`, which runs two queries.
- A syntactically invalid token may return `messaging/invalid-argument`, which the code treats as transient, so such tokens would never be removed. Which error code FCM returns here is **unverified**.

**Impact:**
- Abuse is limited to the attacker's **own** account, so there's no cross-user spam.
- It allows Function and read-cost amplification and unbounded stored documents, and an account can disable its own pushes.

**Correction:**
- Send to at most the 10 most recent devices (`orderBy('updatedAt','desc').limit(10)`).
- Delete registrations beyond 10 in `onDeviceTokenWritten`.
- Split sends into groups of 500.
- Delete registrations not refreshed for 60 days in a scheduled cleanup (needs Blaze).
- Restrict `deviceId` to the UUID format in the rules.
- App Check enforcement later, per its own plan.

**Tests to add:** 12 devices produce 10 sends; pruning keeps the newest 10.

### F-9 (Medium): some push bodies still carry amounts and the other party's text (requirement 7)

**Evidence (Code):** only four types get generic text (`PUSH_GENERIC`). These still pass their body to the push:

| Type | Body content | Line |
|---|---|---|
| `quote_received` | Artisan's name and **₦ amount** | 2523 |
| `agreement_changes_requested` | Artisan's **free text** (≤ 300 characters) | 2489 |
| `job_status_update` "Job Cancelled" | Canceller's **free text** (≤ 200) | 2509 |
| `job_status_update` "Cancellation Request Declined" | Admin's free-text reason | 2198 |
| `review_received` | Star rating (low sensitivity) | 3498 |

`visibility: 'private'` hides content only on **secure** lock screens, and only when the device is set to hide sensitive content. iOS follows its own *Show Previews* setting. The device's default behaviour wasn't verified, so generic text is the only control the server can rely on.

**Impact:**
- Amounts, and possibly addresses or phone numbers typed into free-text fields, appear on lock screens.
- The other party can choose part of the text of a push sent to someone else. That is the risk Stage 6 (HT-015) meant to close.

**Correction:**
- Default to generic: send a fixed, reviewed body per type, and use the stored body only for types on an explicit safe list.
- The in-app record keeps the full text.

**Test to add:** for every type the server emits, the push body contains no `₦`, no digit runs of 6 or more, and none of the free-text input.

### F-10 (Low): delivery receipts retry with no backoff; batches can exceed 500 writes

**Evidence (Code + Analysis):**
- `_acking` is cleared in `finally`. A rejected write rolls back locally, the listener fires again, and the write is retried at once.
- Causes of permanent failure:
  - the new app is released before the new rules are deployed;
  - F-4;
  - more than 500 unread messages in one conversation (the Firestore batch limit). `markAllAsRead` already had this limit before this change.

**Correction:**
- Back off per message after a failure (60 s, doubling up to 30 min).
- Split batches into groups of 450 or fewer.

### F-11 (Low): stolen-token scenario is understated (S6)

**Impact:** someone who obtains a victim's FCM token can register it under their own account. Through F-7 that releases the victim's registration, so the victim stops getting pushes. The thief's own notifications then reach the victim's phone, including free text they can supply through a second account (F-9).

**Mitigation:**
- Getting the token needs device access; clients can't read it from Firestore.
- F-7 and F-9 reduce the effect, and App Check would add a further control.

### F-12 (Low): report corrections needed

| Report | Statement | Correction |
|---|---|---|
| Implementation report §2 | Delivered means "from the server in a live listener" | Not true until F-3 is fixed |
| Implementation report §3 | "Older apps keep working throughout" | Message taps break (F-1). The rules must also be deployed before the app release, or new-app read receipts are denied |
| Security review S5 | Offline sign-out is a "narrow window" | Indefinite (F-6) |
| Security review S7 | `visibility: private` presented as a control | Device-setting dependent (F-9) |
| Security review S10 | "Low impact" | Includes the 500-message send limit and cost amplification (F-8) |
| Both | Test counts | From the 5 November runs; not re-run for this review |

---

## 3. Confirmed correct

### Requirement 6: server-side preference (Met)

- `_deliverPush` reads `users/{uid}.notificationsEnabled` and sends nothing when it's `false` (`functions/index.js:1079`). A test covers this.
- It is the only place push is sent: `messaging.sendEach` appears once (`:1049`), and `_sendNotification` only writes notification documents (`:3642`).
- The only preference screen (`/settings/notifications`) writes `users/{uid}.notificationsEnabled` through `updateUserProfile` (`settings_screens.dart:343`, `auth_service.dart:153`). Both the customer and the artisan paths link to it (`artisan_inbox_screens.dart:243`, `profile_screen.dart:221`).
- A missing field counts as enabled, which matches the client default.

### Requirement 8: recipient-only receipts (Met)

- Message updates require `resource.data.receiverId == request.auth.uid` (`firestore.rules:546`).
- Sender and receiver can't change, and only `isRead`, `readAt` and `deliveredAt` may be affected.
- `_validReceiptChange` (`:23-36`) enforces:
  - `isRead` goes false → true only;
  - `readAt` only with `isRead`, and equal to the server time;
  - `deliveredAt` once only, equal to the server time;
  - deleting any of these fields fails, because the comparison is against a missing value;
  - an empty write is refused.
- No other rule grants writes to messages: there's no recursive wildcard, and admins have delete only.
- 19 rules tests cover the sender, a non-party, reset, duplicates, client-chosen time, content edits and unauthenticated access.

### Requirement 5 on the delivery path (Met)

- Cleanup runs only for `registration-token-not-registered` and `invalid-registration-token`.
- It uses a transaction that re-reads the registration and deletes it only if it still holds the failed token (`functions/index.js:1108-1118`).
- Tests cover a refresh during delivery and transient errors.

### Requirement 9 apart from F-1 (Met)

- **Legacy tokens:** `efe5398` and `7e16eb1` both write `fcm_tokens/{uid}.token`. The server still reads it and removes duplicates (tested).
- **Read marking:** the initial app never marked messages read (`markAsRead` had no callers). `7e16eb1` writes `{isRead: true}` only on messages where `receiverId == viewer`. The recipient-only rule therefore denies nothing older apps send.
- **Notification channel:** `handy_trust_main` already exists in the app and as the manifest default (`AndroidManifest.xml:26-27`).
- **New fields:** older models ignore the new message fields.

---

## 4. Resolution under A1 (6 November 2026)

All corrections are local and uncommitted. Test evidence is in `STAGE8_2_A1_CORRECTIONS_REPORT.md`.

| ID | Status | What changed | Evidence |
|---|---|---|---|
| F-1 | **Fixed** | Message notifications keep `route: /job/{jobId}` and carry `chatWith`; the new client builds `/chat/{jobId}?with=…` from it, accepting only safe IDs | Functions: route and `chatWith` test, data-field test. Client: `chatWith` routing and unsafe-ID tests |
| F-2 | **Fixed** | Read receipts write only `isRead` + `readAt` (`ChatService.readReceiptUpdate`) | Client payload test. Rules: delivery-then-read accepted; the old payload refused after delivery |
| F-3 | **Fixed** | Receipts come from a metadata-aware stream; cache-only snapshots never produce one | Client: logic test and provider test (cache snapshot → nothing; server snapshot → receipt) |
| F-4 | **Fixed** | `incomingUnreadProvider` and `deliveryAckProvider` are auto-disposed | Client: the stream is cancelled when the root stops watching. Riverpod 2.6.1 caveat in the security review (S12) |
| F-5 | **Fixed** | Hook capped at 8 s; device delete 3 s; token delete 4 s | Client: a never-completing hook still signs out at 8 s; a hanging token delete times out |
| F-6 | **Fixed (residual documented)** | `deleteToken` reports failure; a persisted flag is retried while signed out, at start and on reconnect, and cleared after a successful registration. Foreground pushes for another account are hidden. Background pushes during the offline window are still shown by the OS (generic text) | Client: remembered and retried; retry at start and on reconnect; foreground check |
| F-7 | **Fixed** | Newest registration wins (`updatedAt`, then path); stale events ignored; compare-and-delete transactions | Functions: late, stale, concurrent, tie, duplicate and refresh-after-lookup tests |
| F-8 | **Fixed** | UUID device IDs (rules); 10 newest devices used; pruning; sends in groups of 500; 270-day daily sweep (scheduled; runs once deployed); `devices.updatedAt` index override | Functions: cap, prune and sweep tests. Rules: UUID tests |
| F-9 | **Fixed** | No stored body is pushed: fixed body per type, fixed titles | Functions: every type checked against amounts, digits, names and free text |
| F-10 | **Fixed** | Back-off of 60 s, doubling to 30 min; batches ≤ 450 writes (receipts and reads) | Client: back-off and batching tests (logic level) |
| F-11 | **Partly mitigated; residual unresolved** | No text controlled by someone else (F-9); foreground recipient check; newest registration wins. Background display and repeated take-over need App Check or data-only messages | Security review S6 |
| F-12 | **Fixed** | Implementation report and security review rewritten | Those two documents |

**Change from this review's recommendation:** the stale-registration sweep uses **270 days**, not 60. The app refreshes its registration only when it starts while signed in, so 60 days would cut off valid but dormant installs. For example, an artisan who waits for booking pushes without opening the app would stop receiving them. 270 days matches the inactivity period after which FCM itself treats an Android token as expired.
