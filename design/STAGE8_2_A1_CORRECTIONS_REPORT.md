# Stage 8.2 — A1 corrections and A6 clean-up: evidence for Gate N1

**Date:** 6 November 2026. **Branch:** `stage-8-ui-replacement`; HEAD `7ff140c`, unchanged.

**Approvals used:**
- **A1** (approved with conditions): corrections F-1 to F-10; F-11 addressed; F-12 report corrections; the additional safeguards from the review.
- **A6** (approved with conditions): untrack `functions/node_modules`, after checks, without committing.

**Not done:**
- no commit (A2 is pending your review);
- no deployment, no push, no Blaze upgrade;
- no Paystack access;
- no production resource touched.

No external service was called; the end-to-end run counted 0 external calls.

---

## 1. A6: `functions/node_modules` untracked (staged in the index only; **not committed**)

**Checks before the change:**

| Check | Result |
|---|---|
| `.gitignore` covers it | `.gitignore:52 node_modules/` matches `functions/node_modules/…` (`git check-ignore --no-index`) |
| Tracked file count | **5,752**, all under `functions/node_modules`. No other tracked `node_modules` anywhere |
| Local edits to those tracked files | 0 |
| `functions/package.json`, `functions/package-lock.json` | Tracked, and remain tracked |
| Index before the change | Empty (nothing staged) |

**Exact change:** `git rm -r --cached --quiet functions/node_modules`

| After the change | Result |
|---|---|
| Staged | **5,752 deletions (`D`)**, all under `functions/node_modules/` (227 packages, including `.bin/`); 916,749 lines removed from the index |
| Staged outside `functions/node_modules/` | **0** |
| Files on disk | **5,752** (unchanged; dependency directory preserved) |
| Shown as untracked afterwards | 0 (ignored by `.gitignore`) |
| `package.json` / lockfile | Still tracked, not staged |

**Keeping A6 separate from A1:**
- The A6 removals exist **only in the index**.
- All A1 work is **unstaged** working-tree changes plus three untracked test files.
- A plain `git commit`, with no `-a`/`--all`, would therefore commit only the A6 clean-up.

**Proposed commit message (not run):**

```
Stop tracking functions/node_modules (dependencies come from package-lock.json)
```

**To undo the staging:** `git restore --staged functions/node_modules`

---

## 2. A1: changed-file manifest

### 2a. Files changed by A1 in this session

| File | Change | Findings |
|---|---|---|
| `functions/index.js` | Push block rewritten:<br>• fixed bodies for every type;<br>• `chatWith`/`uid` data;<br>• 10-device cap and pruning;<br>• sends in groups of 500;<br>• newest-wins ownership with compare-and-delete;<br>• 270-day sweep (`sweepStaleDeviceTokens`).<br>Also: `chatWith` on message notifications (route stays `/job/{id}`); optional `chatWith` in `_sendInAppNotification` | F-1, F-7, F-8, F-9 |
| `firestore.rules` | Device ID must be a lowercase UUID (create/update); delete unchanged | F-8 |
| `firestore.indexes.json` | Field override `devices.updatedAt`: COLLECTION ascending and descending, COLLECTION_GROUP ascending | F-8 |
| `lib/core/services/push_logic.dart` | `destination(chatWith)`, `isSafeId`, `shouldShowForeground` | F-1, F-6, F-11 |
| `lib/firebase/messaging/local_notification_service.dart` | `deleteToken()` returns success; foreground check receives the recipient `uid`; taps pass `chatWith` | F-1, F-6, F-11 |
| `lib/models/notification_model.dart` | `chatWith` field | F-1 |
| `lib/providers/notification_provider.dart` | `PushPlatform`: `deleteToken` → bool, `invalidationPending`/`setInvalidationPending`, recipient-aware foreground check. Plus `invalidateDeviceToken` (4 s), `retryPendingInvalidation`, retry at start and on reconnect while signed out, pending flag cleared after registration, bounded `unregisterPushDevice`, `chatWith` on in-app taps | F-5, F-6, F-1, F-11 |
| `lib/providers/auth_provider.dart` | Pre-sign-out hook capped at 8 s (`beforeSignOutTimeout`) | F-5 |
| `lib/core/services/chat_service.dart` | `readReceiptUpdate()` (`isRead` + `readAt` only); `watchIncomingForAck` (metadata-aware); `markDelivered` back-off and 450-write batches; `markAllAsRead` batches | F-2, F-3, F-10 |
| `lib/core/services/conversation_logic.dart` | `IncomingSnapshot`; `toAcknowledge(fromCache)`; `ReceiptBackoff`; `chunked` | F-3, F-10 |
| `lib/providers/chat_provider.dart` | Both receipt providers auto-disposed; receipts only from server-confirmed snapshots | F-3, F-4 |
| `test/stage8_2_backend_client_test.dart` (untracked) | 8 → **21** tests | All client findings |
| `test/stage8_2_ui_test.dart` | Push fake updated to the new interface | — |
| `functions/test/stage8_2_push_emulator.test.js` (untracked) | 14 → **24** tests | F-1, F-7, F-8, F-9 |
| `firestore-tests/stage8_2_messaging_rules.test.js` (untracked) | 19 → **23** tests; UUID device IDs | F-2, F-8 |
| `design/STAGE8_2_BACKEND_NOTIFICATION_IMPLEMENTATION_REPORT.md`, `design/STAGE8_2_BACKEND_SECURITY_REVIEW.md` | Rewritten | F-12 |
| `design/STAGE8_2_NOTIFICATION_FINAL_CODE_REVIEW.md` | Resolution section (§4) added | — |
| `design/STAGE8_2_A1_CORRECTIONS_REPORT.md` | This report (new) | — |

### 2b. Complete uncommitted notification change set against HEAD `7ff140c`

This is the earlier Stage 8.2 backend work plus A1. It excludes `.claude/`, `android/build/`, your `.firebaserc` alias, and the A6 index change.

**Tracked files, 18 changed, +800 / −88 lines:**

| Area | Files |
|---|---|
| Configuration and backend | `firestore.indexes.json`, `firestore.rules`, `functions/index.js`, `functions/package.json` |
| Services and models | `lib/core/services/chat_service.dart`, `conversation_logic.dart`, `push_logic.dart`, `lib/firebase/messaging/local_notification_service.dart`, `lib/main.dart`, `lib/models/message_model.dart`, `notification_model.dart` |
| Providers | `lib/providers/auth_provider.dart`, `chat_provider.dart`, `notification_provider.dart` |
| UI | `lib/ui/screens/chat_screen.dart`, `messages_screen.dart` |
| Tests | `test/stage8_2_logic_test.dart`, `test/stage8_2_ui_test.dart` |

**Untracked test files (3):**
- `test/stage8_2_backend_client_test.dart`
- `functions/test/stage8_2_push_emulator.test.js`
- `firestore-tests/stage8_2_messaging_rules.test.js`

**Secret check:** there is no `functions/.secret.local`, and no `.env`/secret file is tracked, staged or untracked. The only paths matching "secret" are `jose` library files inside the A6 removal.

---

## 3. Gate N1 test results (6 November 2026, after all A1 changes)

| Suite | Result | How it was run |
|---|---|---|
| `flutter analyze` | **0 errors, 0 warnings, 0 non-deprecation infos** | Whole project, excluding `work_sphere_ai` |
| All Flutter tests | **351 / 351** (338 before A1) | `flutter test` |
| Visual goldens | **654 / 654**, no golden changed | `flutter test test_visual` |
| New client tests | **21 / 21** | Included above |
| All Functions tests (16 files, each in its own process) | **290 / 290** (280 before A1) | Firestore emulator, `demo-handytrust`, Node 22 |
| New push tests | **24 / 24** | Included above |
| All Firestore rules tests | **162 / 162** (158 before A1) | Firestore emulator |
| New messaging rules tests | **23 / 23** | Included above |
| Storage rules | **9 / 9** | Separate emulators (`demo-handytrust-storage`) |
| End-to-end (Functions + Firestore + Pub/Sub) | **16 / 16**, **0 external calls**; the new trigger and scheduled function loaded | `demo-handytrust-e2e`; dummy emulator-only secret created and **deleted** (confirmed) |

**Gate N1 item 3** (receipt and read for a message arriving while the chat is open) is covered at two levels:
- **Rules level:** delivery receipt, then a read with `isRead` + `readAt`, is accepted; the old read payload is refused after delivery, which is the original defect.
- **Client level:** the read payload contains only those two fields.

A full device-level reproduction needs a real Firestore client and isn't possible in unit tests.

**Issues found while testing, all fixed or explained; no product code was changed for them:**

| Issue | Cause | Action |
|---|---|---|
| A back-off test used wrong arithmetic | Test bug | Corrected |
| A rules test passed `../other` as a device ID | The SDK rejects that path before any rule is evaluated | Replaced with a valid non-UUID ID |
| The first listener-disposal test failed | Riverpod 2.6.1 only cancels a source stream that has emitted (proven with isolated probes) | Firestore listeners always emit first, so the test now emits a snapshot first. The library behaviour is recorded as a residual risk |
| The first end-to-end attempt didn't start | A Pub/Sub emulator left over from an earlier session held port 9495 | That emulator process was stopped and the run repeated |

All emulator processes were stopped afterwards. The temporary probe tests were deleted.

---

## 4. Additional safeguards from the review, included

| Safeguard | Finding |
|---|---|
| UUID device IDs in the rules | F-8 |
| FCM sends split into groups of 500 | F-8 |
| Pruning above 10 devices | F-8 |
| Scheduled stale-registration sweep | F-8 |
| `devices.updatedAt` index override, including the collection-scope indexes an override would otherwise drop | F-8 |
| Recipient `uid` in the push payload and a foreground recipient check | F-6 / F-11 |
| Safe-ID check before building a chat route | F-1 |
| Delivery-then-read rules sequence test | Gate N1 item 3 |
| Test that every FCM data value is a string | — |

**Deviation:** the stale sweep uses 270 days instead of the review's 60. The reason is in the review's §4.

---

## 5. Remaining risks (after A1)

1. **F-11 (unresolved, documented).** Someone holding another person's FCM token can still:
   - have their own **background** pushes shown on that person's phone, now with fixed titles and generic text only;
   - repeatedly take that person's pushes away by re-registering the token.

   A fix needs App Check enforcement or data-only messages rendered by the app. Getting a token needs device access.
2. **Offline sign-out window (F-6).** Until the device reconnects and the retry succeeds, the OS shows background pushes for the previous account (generic text). Foreground pushes are hidden.
3. **Riverpod 2.6.1.** Auto-dispose doesn't cancel a stream that never emitted. Firestore emits at once, so there's no practical effect. The conversation-list providers (existing, not auto-disposed) outlive sign-out; their queries fail permission checks and stop.
4. **Not verified on devices:**
   - FCM delivery and taps;
   - `deleteToken()` behaviour offline;
   - lock-screen settings;
   - a pre-8.2 build opening a `/job` message push.
5. **Not verified against real Firestore:** `markDelivered` back-off (logic-tested only); index builds (the emulator doesn't enforce indexes).
6. **Scheduled sweep.** It needs deployment, and Cloud Scheduler means Blaze. Until then, registrations are bounded by the cap and pruning only.
7. **Malformed tokens.** Whether FCM returns `invalid-argument` for them is unverified. Such tokens are bounded by the cap and the sweep.
8. **Deployment order is mandatory:** indexes → rules → Functions → app. A new app against old rules has its read and delivery writes refused.
9. **Cost per registration write.** Each one still runs one Function invocation, and a user can loop writes against their own account. That is cost only; App Check would limit it.
10. **Inherent to client-side receipts.** Delivered needs the recipient's app running, and a modified recipient client can mark its own messages delivered or read.

---

## 6. Approvals: current state

| Approval | State |
|---|---|
| A1 | Done; evidence above |
| A6 | Staged, **not committed**; waiting for you to confirm the exact change in §1 |
| A2 (local commit of notifications) | **Not approved.** Waiting for your Gate N1 review |
| A3–A5 | **Not approved** |
| A7–A10 | **Not approved** |
| A11 | **Not approved** |
