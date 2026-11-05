# Stage 8.2 — deletion and creation manifest

**Recovery point (verified before any deletion):**
- Branch `stage-8-ui-replacement`.
- Local checkpoint commit **`19814caed59efd780c6486ee44dbd31f757ad2c4`** ("Stage 8 + 8.1 checkpoint"): 566 files, matches the working tree exactly. Not pushed.
- Stage 7.3 recovery point preserved: branch `stage-7.3-verified-baseline` → `7e16eb1`.
- External backups verified on 5 November 2026 against their SHA-256 manifests:
  - `handy_trust_backups/stage8_8.1_2026-11-04/` (334/334);
  - `handy_trust_backups/stage8_8.1_pre_artisan_20261104_2341/` (387/387).
- The checkpoint deliberately excludes `.claude/` tool settings and `android/build/` output. It's 87 MB, mostly PNG goldens. Review the size before any future push.

**Restore any deleted file:** `git checkout 19814ca -- <path>`.

## 1. Deleted (presentation only; 14 files, 11,926 lines)

| File | Lines | Blob | Why it's safe to delete |
|---|---|---|---|
| `lib/screens/admin/admin_dashboard_screen.dart` | 7,881 | `cbb73db8a863` | Presentation. Its queries moved to `providers/admin_provider.dart`; its writes moved, with identical payloads, to `core/services/admin_service.dart` |
| `lib/screens/admin/admin_sidebar.dart` | 274 | `dc89e95b76c0` | Navigation UI; `AdminSection` re-created in `ui/admin/admin_shell.dart` with the same paths (+ `/admin/finance`) |
| `lib/screens/admin/admin_widgets.dart` | 445 | `31ef55c3b1a7` | Widgets only |
| `lib/screens/admin/admin_data_table.dart` | 394 | `6b9d8fe176f5` | Widget only |
| `lib/screens/admin/admin_charts.dart` | 305 | `accabf43555e` | Widgets only |
| `lib/screens/admin/admin_palette.dart` | 84 | `3364214fc9a2` | Colours only |
| `lib/screens/admin/admin_finance_dialogs.dart` | 231 | `4f458397f7e2` | Dialogs rebuilt in `ui/admin/admin_kit.dart` with the same outcomes and validation (reason ≥ 10, split amounts > 0). The held-funds read moved to `AdminService.heldFunds` |
| `lib/screens/settings/settings_screen.dart` | 1,226 | `c10fb6ca3360` | Replaced by `ui/settings/settings_screens.dart`; same service calls |
| `lib/screens/support/contact_support_screen.dart` | 212 | `e037b9a60d78` | Replaced by `SupportCentreScreen` (same `createTicket` / `userTicketsProvider`) |
| `lib/screens/support/about_screen.dart` | 105 | `2f9d6f439704` | Replaced by `AboutHandyTrustScreen`. Its placeholder links (`handytrust.example.com`) are removed |
| `lib/screens/chat/my_chats_screen.dart` | 617 | `2b71a45d1bec` | Replaced by `ui/screens/messages_screen.dart` and the conversation providers |
| `lib/widgets/app_snackbars.dart` | 125 | `87656ba10206` | Zero remaining references |
| `lib/widgets/job_status_badge.dart` | 59 | `ff570f935a2f` | Zero remaining references (only the old admin used it) |
| `lib/widgets/notification_bell.dart` | 72 | `2a9e43f3f9d1` | Zero remaining references |

**Kept on purpose:** `lib/core/network/*` and `lib/core/auth/*` (unused Dio client). It isn't presentation code; it's recorded as an H1.1 finding.

## 2. Created (19 app files, 4,662 lines; plus tests)

| Area | Files |
|---|---|
| Admin logic | `core/services/admin_service.dart` (writes, F-1 gating), `core/services/admin_catalog.dart` (28 alert labels; metrics), `providers/admin_provider.dart` (queries, count() totals, finance), `models/finance_record.dart` |
| Admin UI | `ui/admin/admin_shell.dart`, `admin_kit.dart`, `admin_overview.dart` (dashboard, analytics, alerts), `admin_people.dart` (users, artisans, verifications), `admin_operations.dart` (jobs, disputes, support, reviews, deletions), `admin_finance_compliance.dart` (finance, audit logs, settings) |
| Conversations and receipts | `core/services/conversation_logic.dart`, `providers/connectivity_provider.dart`, `ui/screens/messages_screen.dart` |
| Settings and help | `ui/settings/settings_screens.dart` (hub, personal information, notification preferences, security and password), `ui/settings/help_screens.dart` (About, Support Centre), `core/validation/password_policy.dart`, `core/constants/app_info.dart` |
| Push | `core/services/push_logic.dart` |
| Tests | `test/stage8_2_logic_test.dart` (23), `test/stage8_2_ui_test.dart` (40), `test_visual/stage8_2_visual_test.dart` (186; 40 goldens in `test_visual/goldens/stage8_2/`) |

## 3. Modified

| File | Change |
|---|---|
| `lib/routes/router.dart` | New admin sections (incl. `/admin/finance`); `/settings/personal`, `/settings/notifications`, `/settings/security`; Support/About to the new screens; customer `/my-chats`; `/chat/:jobId?with=` |
| `lib/core/services/chat_service.dart` | Pending-write metadata; conversation-scoped `markAllAsRead` with an in-flight guard; `watchPairUnreadCount`; `watchCounterparts`; removed the unused `watchUnreadCount` |
| `lib/providers/chat_provider.dart` | Removed the denied collection-group providers; added conversation, unread and counterpart providers |
| `lib/providers/notification_provider.dart` | `PushPlatform` abstraction; single-listener tap routing; registration follows the preference and sign-out |
| `lib/firebase/messaging/local_notification_service.dart` | Tap callback; launch-tap capture; `deleteToken`; lock-screen privacy; type-aware destination; removed unused show helpers |
| `android/app/src/main/AndroidManifest.xml` | FCM default notification channel `handy_trust_main` |
| `lib/models/{user,artisan,job}_model.dart` | Parse-only `payoutFrozen` / `payoutFreezeReason` (Q-5) |
| `lib/models/message_model.dart` | Non-serialised `isPending` |
| `lib/models/admin_audit_log_model.dart` | Parse-only `actionId` (the recorded action string) |
| `lib/ui/screens/chat_screen.dart` | Receipt icon (Sending / Sent / Read); conversation-scoped, foreground-only read marking; mark on resume; "Choose a conversation" fallback |
| `lib/ui/screens/profile_screen.dart` | Exact Settings destinations; unread count on My Chats; role-correct subtitle |
| `lib/ui/screens/notifications_screen.dart`, `lib/ui/artisan/screens/artisan_inbox_screens.dart` | Type-aware notification destinations; exact Settings link; artisan Messages on the conversation providers |
| `lib/ui/artisan/artisan_shell.dart` | Header message badge from artisan-side conversations |
| `lib/screens/auth/register_screen.dart`, `lib/core/services/auth_service.dart` | Shared password policy; corrected weak-password copy |
| `test/artisan_ui_test.dart`, `test_visual/artisan_visual_test.dart` | Overrides for the new providers |
| Goldens (4) | `profile_{light,dark}` (role-correct subtitle), `artisan/messages_{light,dark}` (search hint) |

## 4. Not changed

`functions/`, `firestore.rules`, `storage.rules`, `firestore.indexes.json`, Paystack code and any escrow, payout or refund logic. No new Firestore collections or fields are written by the client.
