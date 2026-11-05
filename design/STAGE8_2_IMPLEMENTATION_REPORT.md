# Stage 8.2 — implementation report

**Date:** 5 November 2026. **Branch:** `stage-8-ui-replacement`. **Checkpoint:** `19814ca` (local; nothing pushed or deployed).
**Companions:**
- `STAGE8_2_VISUAL_QA_REPORT.md`
- `STAGE8_2_NAVIGATION_AUDIT.md`
- `STAGE8_2_NOTIFICATION_AUDIT.md`
- `STAGE8_2_DELETION_AND_CREATION_MANIFEST.md`

## 1. Status by requirement

| Req. | Item | Status | Notes |
|---|---|---|---|
| A | Admin dashboard rebuild | **Done** | See §2 |
| B | Customer My Chats rebuild | **Done** | Real conversations including pre-booking threads; last message, time, per-conversation unread; search and Unread filter over loaded data; loading/empty/error/offline; opens the exact conversation; role-separated |
| C | Settings destructive replacement | **Done** | Hub + Personal information, Notification preferences, Security and password, About, Support Centre; old screen deleted |
| D | Exact destinations | **Done** | Profile rows fixed; back navigation and deep links tested |
| E | About | **Done** | Verified facts only; real version (tested against `pubspec.yaml`); placeholder links removed |
| F | Support Centre | **Done** | Tickets are the only real channel; FAQs use live config (fee %, booking window); topic links open real screens; no invented contacts or response times |
| G | Security and password | **Done** | Re-authentication; one policy (8+, uppercase, number) for change and registration; visibility toggles; specific errors; Firebase-hosted reset link |
| H | Read receipts | **Done for sending / sent / read.** **"Delivered" blocked:** needs backend approval (B6) | Seven client defects fixed |
| I | Push notifications | **Client side done; delivery not device-verified.** Server-side items need approval (B1–B4) | Channel, taps (all states), single listeners, preference, sign-out token, destinations, lock-screen privacy (foreground) |
| J | Design rules | **Done** | Light/dark, phone/tablet/desktop, states; 654 visual tests |
| K | Backend preservation | **Done** | No Functions, rules, Paystack, escrow or payout change |
| L | Testing | See §4 | — |
| M | Change control | **Done** | Branch, tree and backups verified; checkpoint `19814ca`; manifest written |

## 2. Admin rebuild

- **Structure:** sidebar (desktop), rail (tablet), drawer (phone).
- **Sections:** Dashboard, Analytics, Users, Artisans, Verifications, Jobs, Disputes, Support, Reviews, Deletion requests, **Finance (new, read-only)**, Audit logs, Settings.
- **Top bar:** search across sections, users and jobs; pending-work notifications; theme toggle; Back to app.
- **Business logic preserved:**
  - every write moved unchanged into `AdminService`;
  - every query moved into `admin_provider.dart`;
  - settlement, refund, retry and resolve actions still call the same callables through `AdminFinanceService`, with the same reason (≥ 10) and split validation;
  - verification approve/reject use the same service and audit entries.
- **Fixes delivered with the rebuild:**
  - **F-1:** job deletion is offered only when the rules allow it; eligibility is checked before any write; the job is deleted before its messages.
  - **F-2:** all 28 alert types have readable labels, and the raw ID is always shown.
  - **F-3:** the role is shown as "Administrator".
  - **Genuine totals:** exact counts via count(); previously "Total users" could never exceed 200.
  - **Audit log accuracy:** shows the recorded action (server actions used to display as "admin override").
- **Payout freeze (Q-5):** status shown read-only on users, artisans, jobs and finance records. No freeze action (per Stage 8.2).
- **Not added:** "View in Finance" (U-2), chargeback close/investigate (Q-4), any new admin roles.

## 3. Other fixes

- Header message badges were always 0, because collection-group queries are denied by the rules (proved on the emulator). They're now computed from per-conversation counts.
- Change-password allowed 6-character passwords, while registration required 8 + uppercase + number. Both now use the same `PasswordPolicy`.
- The account-deletion copy uses the approved U-1 wording, not "within 7 days".

## 4. Tests executed (5 Nov 2026)

| Suite | Result |
|---|---|
| `flutter analyze` (excl. `work_sphere_ai/`) | 0 errors, 0 warnings, 0 non-deprecation infos; 4 existing deprecation infos (`secure_booking_screen`), down from 8 |
| `flutter test` | **330 / 330** (incl. 63 new: 23 logic, 40 UI/flow/router) |
| `flutter test test_visual` | **654 / 654** (incl. 186 new) |
| Cloud Functions (Node 22, emulator, each file in its own process) | **266 / 266** |
| Firestore rules | **139 / 139** |
| Storage rules | **9 / 9** |
| End-to-end (functions + firestore + pubsub emulators) | **16 / 16**, 0 external calls; dummy secret removed |
| Collection-group rules probe | 4 / 4 (temporary; deleted) |

**Coverage areas:**
- Dual-role users: mode switch, role-separated chats, `/home` shell choice.
- Customer chat, admin dashboard, settings navigation, security/password, read receipts.
- Push logic, light/dark, and phone/tablet/desktop layouts.

**Not executed:** real push delivery or notification taps on a device (§4 of the notification audit).

## 5. Remaining defects and out-of-scope screens

- **Backend proposals awaiting approval:** B1–B7 (notification audit §5).
- **Legacy screens still in the old style** (not in Stage 8.2's A–I list):
  - `job/job_detail_screen.dart` (customer job page), `artisan/secure_booking_screen.dart`, `artisan/artisan_list_screen.dart`, `artisan/favorites_screen.dart`;
  - `dispute/dispute_screen.dart` (still says "within 48 hours"), `review/review_screen.dart`, `payment/payment_webview_screen.dart`;
  - the authentication screens.
- **U-3:** provisional heading font and onboarding photo unchanged.
- **Debug signing, app ID, App Check, backups:** H1.1, not implemented.
- **Uncommitted:** Stage 8.2 work is not committed (only the pre-deletion checkpoint was authorised).
