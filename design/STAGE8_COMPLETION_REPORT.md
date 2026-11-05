# HandyTrust — Stage 8 Completion Report: Full UI Replacement

Date: 2026-11-04

## Status at a glance

| Item | State |
|---|---|
| Work branch | `stage-8-ui-replacement` |
| Recovery point | Local branch `stage-7.3-verified-baseline`, commit `7e16eb1` (not pushed) |
| Stage 8 changes | **Uncommitted.** Nothing has been pushed or deployed |
| Production | Untouched: no Firebase deploy, no rules, data, Functions or Paystack change, and no real transactions |
| Backend diff vs. baseline | **Empty** for `functions/`, `firestore.rules`, `storage.rules`, `firestore.indexes.json` and `firebase.json` |
| Stop conditions (§9) | **None reached.** Every design conflict could be resolved by omitting or rewording the element, without changing the backend, security, data model or financial infrastructure |

Companion documents:
- `STAGE8_SCREEN_INVENTORY.md`
- `STAGE8_IMPLEMENTATION_PROGRESS.md`
- `STAGE8_BACKEND_INTEGRATION_MAP.md`
- `STAGE8_VISUAL_QA_REPORT.md`

---

## 1. Screens replaced (old implementation deleted)

| Designed screen | Refs (dark / light) | New file (`lib/ui/screens/`) | Replaced (deleted) | Route |
|---|---|---|---|---|
| Discovery | #8 (#9, #1) / #15 | `discovery_screen.dart` | customer home tab in `home_screen.dart`; `artisan/browse_artisans_screen.dart` | `/home` tab, `/browse-artisans` |
| Artisan Profile | #2 / #16 | `artisan_profile_screen.dart` | `artisan/artisan_profile_screen.dart` | `/artisan/:uid` |
| Post a Job (step 1) | #3 / #17 | `post_job_screen.dart` | `home/service_request_screen.dart` | `/request` |
| My Bookings | #4 / #19 | `bookings_screen.dart` | customer view of `all_jobs_screen` (the artisan view is retained) | `/home` tab, `/jobs` (customer) |
| Confirm & Pay | #10 / #18 | `confirm_pay_screen.dart` | `payment/payment_screen.dart` | `/payment/:jobId` |
| Chat | #11 / #20 | `chat_screen.dart` | `chat/chat_screen.dart` | `/chat/:jobId` |
| Payments (adapted Wallet) | #5 / #21 (= #25) | `payments_screen.dart` | customer view of `wallet_screen` (the artisan earnings view is retained) | `/home` tab, `/wallet` (customer) |
| Profile | #6 / #22 | `profile_screen.dart` | `profile/profile_screen.dart` | `/home` tab, `/profile` |
| Identity Verification | #7 / #23 | `verification_screen.dart` | `verification/verification_upload_screen.dart` | `/verification` |
| Notifications | #12 / #24 | `notifications_screen.dart` | `notifications/notifications_screen.dart` | `/notifications` |

## 2. Screens created

- **`onboarding_screen.dart`** (#13 / #14) on the new public route `/onboarding`. It's shown once, and its flag is stored locally.
- **`customer_shell.dart`**: the customer tab shell with the floating bottom nav (Discovery · Bookings · Payments · Profile).

## 3. Screens intentionally retained

These have no reference design. Under §6 they're kept so no workflow breaks, and they still use the previous theme. They're listed in `STAGE8_SCREEN_INVENTORY.md` §5.

- **Auth:** splash, login, register, artisan registration, verify email, forgot password, role selection, suspended.
- **Job flow:**
  - job detail (agreement, schedule, quotes, cancellation, refund, rework, dispute window), work submission;
  - matched-artisan list, secure booking;
  - payment webview (Paystack checkout + verification);
  - review, dispute.
- **Artisan:**
  - artisan home (`MainShellScreen` with `ArtisanHomeTabContent`) and open-jobs feed;
  - jobs (`all_jobs_screen`), earnings (`wallet_screen`);
  - bank details, business profile, portfolio manager / project.
  - The new Profile screen is also used for artisans, with their artisan-only rows.
- **Admin:** `admin_dashboard_screen` and its widgets.
- **Other:** settings, support, about, favourites, chat list.

## 4. Files

### Deleted (11 files, 3 directories)
- `lib/screens/home/service_request_screen.dart`
- `lib/screens/artisan/artisan_profile_screen.dart`, `lib/screens/artisan/browse_artisans_screen.dart`
- `lib/screens/chat/chat_screen.dart`
- `lib/screens/payment/payment_screen.dart`, `lib/screens/payment/demo_escrow_screen.dart`
- `lib/screens/profile/profile_screen.dart` (directory removed)
- `lib/screens/verification/verification_upload_screen.dart` (directory removed)
- `lib/screens/notifications/notifications_screen.dart` (directory removed)
- `lib/providers/demo_payment_provider.dart`, `lib/core/services/demo_escrow_service.dart`

### Created
- **Design system:**
  - `lib/ui/theme/ht_theme.dart`
  - `lib/ui/components/ht_components.dart`, `ht_bottom_nav.dart`, `ht_format.dart`
- **Screens:** 12 files under `lib/ui/screens/`.
- **Logic:**
  - `lib/core/services/customer_booking_logic.dart`, `payment_summary.dart`, `notification_category.dart`, `location_service.dart`
  - `lib/providers/paystack_provider.dart`, `onboarding_provider.dart`
- **Assets:**
  - `assets/fonts/PlusJakartaSans/` (5 weights + `OFL.txt`)
  - `assets/images/stitch/onboarding_hero.jpg` (a stand-in crop)
- **Tests:**
  - `test/stage8_ui_test.dart`
  - `test_visual/stage8_visual_test.dart`, `test_visual/compare_references.py`
  - `test_visual/goldens/` (22 PNG)
- **Design records:**
  - `design/stitch_reference/1–25.png` (the uploaded references)
  - `design/stage8_visual_qa/` (22 side-by-side images)
  - the five `design/STAGE8_*.md` documents

### Modified
- **`lib/routes/router.dart`:**
  - 11 routes repointed to the new screens;
  - `/onboarding` added as a public route; the splash redirect is aware of onboarding;
  - `/demo-payment` removed;
  - `_RoleAware` sends customers to the new Payments/Bookings and artisans to the retained earnings/jobs screens.
  - **All guards are unchanged.**
- **`lib/screens/home/home_screen.dart`:** customers get `CustomerShell`; artisans get the retained artisan shell.
- **`lib/screens/settings/settings_screen.dart`:** 6 guard expressions changed from `mounted` to `context.mounted`. Behaviour is identical, and it clears the 8 pre-existing `use_build_context_synchronously` infos.
- **`pubspec.yaml`:** the `assets/images/stitch/` asset folder and the `HtDisplay`/`HtText` font families. **No new packages.**
- **`.gitignore`** (baseline step): `node_modules/`, `.firebase/`.

## 5. Architecture changes

1. **New presentation layer under `lib/ui/`:** theme, components and screens, separate from the retained `lib/screens/` and `lib/widgets/`.
   - Screens read the palette through `context.ht`, so dark and light both follow the existing `themeProvider`.
   - The "Obsidian Dark Mode" toggle in Profile drives that provider.
2. **No Firebase SDK in the presentation layer.** A source-scan test fails the build if a `lib/ui` file imports Firestore, Auth, Storage or Functions.
3. **Logic moved out of widgets into pure, unit-tested classes:**
   - booking tab, action and lifecycle (`CustomerBookingLogic`);
   - payment totals and labels (`PaymentSummary`);
   - notification categories;
   - formatting (`HtFormat`);
   - location lookup (`LocationService`).
4. **Customer and artisan shells are split.** Customers use the new `CustomerShell`; artisans keep `MainShellScreen`. `/wallet` and `/jobs` are role-aware.
5. **The demo payment path is removed entirely:** route, screen, provider and service. A source guard test makes sure it doesn't come back.

## 6. Backend integrations

See `STAGE8_BACKEND_INTEGRATION_MAP.md` for the per-screen route, provider, service, model, Firebase operation and authorization, and the loading, empty and error states.

| Kind | Used by the new screens |
|---|---|
| Callables | `getPaymentBreakdown`, `initializePaystackTransaction`, `verifyPayment` (via the retained webview) |
| State transitions (rules-enforced, via `JobService` transactions) | `acceptArtisan`, `initPayment`, `confirmComplete` |
| Uploads (all through `StorageService`, with EXIF stripping by `ImagePrivacy`) | Job photos, chat images, verification photos, avatar |

## 7. Deviations from Stitch

| ID | Deviation | Reason |
|---|---|---|
| D-01 | **Wallet → "Payments" / "Escrow Payments"** (and "Wallet" → "Payments" in the nav). The Wallet layout is kept: a summary card with held-in-escrow and released totals, active escrow contracts, recent transactions and a protection banner. Balance, Add Money, Withdraw and Vaults are removed. A "not withdrawable" note is added | No stored-value wallet exists. §5 forbids wallet infrastructure, fabricated balances and presenting escrow as withdrawable |
| D-02 | The fee is shown as **"Platform fee (5 %)"** with server values (₦85,000 + ₦4,250 = ₦89,250) | Approved fee policy; the ₦1,500 / 1.7 % in the mock is incorrect |
| D-03 | One payment method, "Card, Bank or Transfer" via Paystack checkout | No saved cards, wallet source or dedicated accounts |
| D-04 | Single release with a 14-day auto-release disclosure; no milestones or 20 % deposit | Approved one-time escrow model |
| D-05 | Unsupported claims removed or reworded (CBN, multi-sig, NIMC, NIN/BVN, biometrics, NDPR, 256-bit, 12,400+, 98.4 %, 100 % escrow, tiers, ₦250k protection) | §5 verification and trust claims |
| D-06 | No prices, rates or experience on artisan cards and profiles; skills and "Rates agreed per job" are shown instead | `ArtisanModel` has no such fields; §5 forbids inventing them |
| D-07 | Post a Job has no title field; the budget is one amount (min = max) | `JobModel` has no title; no data-model change was made |
| D-08 | Bookings tabs are Active / Completed / Disputed, with no Drafts tab | Drafts don't exist in the backend |
| D-09 | Approve & Release appears only when the job is `submitted` | Server state machine |
| D-10 | Chat has no phone call, receipt cards, checklists, gate code or location pin | Unsupported message types |
| D-11 | Onboarding is a single slide with no pager dots | There's no design or copy for further slides; inventing it is forbidden |
| D-12 | Copy errors corrected: the #7 title is "Verify Your Identity" and the #12 title is "Notifications" | Errors in the design |
| D-13 | #15's duplicate top header is dropped; #1 isn't used as a target; #8's chip order is used | Export artefacts |
| D-14 | Reviews show "Verified customer" instead of reviewer names | Review documents carry no public reviewer name |
| D-15 | Profile shows real stats: customer posted/active/completed, artisan jobs/rating/trust score. Verification, Earnings and My Reviews rows appear for artisans only | No customer trust score exists; verification is an artisan workflow |
| D-16 | The heading font is Plus Jakarta Sans (an estimate) | The Stitch font is unconfirmed |
| D-17 | The onboarding hero photo is a crop of the screenshot | No original asset was supplied |

## 8. Unsupported features excluded

- Stored-value wallet, Add Money, Withdraw, Vaults, wallet top-up, wallet as a payment source.
- Saved cards; dedicated or virtual bank accounts.
- Milestone payments, 20 % deposit release, 48 h auto-release.
- NIN/BVN/NIMC checks, biometric or 3D verification, verification tiers and limits, 2FA/FaceID.
- Customer trust scores; fabricated statistics.
- Artisan rates, starting prices, years of experience.
- Job drafts; job titles.
- Chat calls, receipts, checklists, location pins, gate codes.
- Security-event notifications.
- Additional onboarding slides.

## 9. Tests executed and results

All suites were run on 2026-11-04 against the current working tree. The counts match the Stage 7.3 configuration (`functions/package.json` and `firestore-tests/package.json` scripts, `test/` contents), plus the new Stage 8 tests.

| Suite | Command | Result |
|---|---|---|
| Flutter unit/widget | `flutter test` | **193 passed, 0 failed** (174 baseline + 19 Stage 8): `00:42 +193: All tests passed!` |
| Stage 8 functional | `flutter test test/stage8_ui_test.dart` | **19 passed** |
| Visual + responsive | `flutter test test_visual --update-goldens`, then `flutter test test_visual` | **88 passed** on both runs |
| Static analysis | `flutter analyze` (final run) | **0 errors, 0 warnings, 28 infos:** 19 in the excluded `work_sphere_ai/`; 9 `deprecated_member_use` in retained admin/artisan files, all present at the 7.3 baseline; **0 in `lib/ui`, new logic or tests.** The first run (before the Settings guard fix) had 36; the fix cleared 8 `use_build_context_synchronously` infos |
| Cloud Functions | Firestore emulator on 127.0.0.1:8090 (`firebase emulators:start --only firestore`); `FIRESTORE_EMULATOR_HOST=127.0.0.1:8090 node --test <the 15 files in npm test>` with **Node v22.23.4** | **266 passed, 0 failed** (58 suites) |
| Firestore rules | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8090 node --test escrow_payout.test.js security_regression.test.js` (firestore-tests, Node 22) | **139 passed, 0 failed** (25 suites) |
| Storage rules | `firebase emulators:exec --project demo-handytrust-storage --only firestore,storage "… node --test storage_rules.test.js"` (fresh ports 10390/10399, current rules copied) | **9 passed, 0 failed**; script exited with code 0 |
| E2E triggers + schedules | `firebase emulators:exec --project demo-handytrust-e2e --only functions,firestore,pubsub "node --test --test-concurrency=1 e2e_triggers… e2e_schedules…"` (Functions emulator using **node@22**; temporary emulator-only dummy `functions/.secret.local`, **deleted afterwards and confirmed absent**) | **16 passed, 0 failed**; 0 outbound Paystack/DNS calls in the log |

### Functional coverage by area

| Area | Covered by |
|---|---|
| Authentication | `auth_provider_password_reset_test`, `init_provider_test`; router redirect unchanged (onboarding path only adds a public route) |
| Role-based access | `stage8_ui_test` (admin card only for admins, role switch only for dual-role users), `admin_exit_navigation_test`, `stage2_authorization` (Functions), `security_regression` (rules) |
| Navigation | `stage8_ui_test` source guards (no demo route), `portfolio_project_route_test`, the 66-test responsive sweep |
| Job creation | `stage5_test`, `stage6_test`, `stage7_1_image_privacy_test`; rules tests for the job-create allow-list |
| Quote workflows | `job_service_agreement_test` (53), `artisan_eligibility_test`, `stage5_lifecycle_emulator` |
| Booking | `job_service_agreement_test`, `stage8_ui_test` (Bookings states and actions), `stage7_matching_test` |
| Payment initiation and verification | `payment_stage3_test`, `stage8_ui_test` (Confirm & Pay with server breakdown; not-ready state), `stage3_payments`, `payment_init_idempotency`, `webhook_signature` |
| Escrow release | `stage8_ui_test` (Release only when `submitted`), `escrow_release_guards`, `stage4_settlement_emulator`, `escrow_payout` rules, e2e schedules (14-day auto-release) |
| Cancellation and refunds | `stage5_lifecycle_emulator`, `stage7_1_chargeback_emulator`, `stage7_2_policy_trust_emulator` |
| Messaging | Chat golden and responsive tests (both themes); `security_regression` message rules |
| Notifications | `stage8_ui_test` (filters, mark-all disabled when nothing is unread, categories), e2e triggers |
| Profile and verification | `stage8_ui_test` (Profile gating), verification goldens, Storage rules (verification paths) |

**Not performed:**
- No manual run-through on a physical device or a live emulator-backed app.
- No end-to-end Paystack **test-mode** checkout. Real keys are deliberately not used.

## 10. Visual comparison results

See `STAGE8_VISUAL_QA_REPORT.md`. Every one of the 22 renders was compared with its reference:
- **Scores:** layout 85.6–93.8 %, colour 89.2–98.2 %.
- **Lowest:** Chat (light), because of excluded unsupported content.
- **Highest:** Profile (light), 93.8 / 97.9.
- **Responsive:** no overflow at 320, 360 or 430 pt widths in either theme.
- **Pixel-perfect output is not claimed.**

## 11. Outstanding issues

1. **Retained screens still use the old theme.** Auth, job detail, artisan, admin and settings screens look visually inconsistent with the new screens until designs are supplied.
2. **The heading font is an estimate and the onboarding hero is a stand-in crop.** The original Stitch font name and image file are needed.
3. **Payments labelling.**
   - The summary card's "Held in escrow" total is what the customer **paid**: service plus the 5 % fee (₦89,250).
   - Each contract line shows the agreed **service** amount (₦85,000 in escrow).
   - Both are accurate; you may want a single convention, which is a copy decision.
4. **Legacy code to clean up later (behaviour-neutral, outside the UI scope):**
   - `EscrowService` has no callers.
   - The `paid_escrow` → `escrowLocked` read mapping in `JobModel` (from the removed demo path) is kept for old documents.
   - The obsolete `lib/widgets/*` and `lib/theme/*` files are still used by retained screens, so they can't be removed yet.
5. **9 `deprecated_member_use` analyzer infos** remain in retained admin/artisan files (pre-existing).
6. **Two orphaned `dart`/`dartvm` processes** (PIDs 32860 and 32312, started 13:26) are left from a test run that stalled on Flutter's startup lock. Terminating them was refused by the permission check, so you may want to end them yourself. They don't affect the code.

## 12. Remaining blockers before launch

Carried over from Stage 7.3, plus Stage 8 items:

- **Paystack test-mode checkout,** end to end with real sandbox keys: payment, webhook, escrow lock, release, refund.
- **Device QA** on real Android and iOS phones, in both themes (safe areas, keyboard, camera and gallery permissions, location).
- **Designs** for the retained screens (§3), especially auth, job detail, quotes, payment result and the artisan workflows.
- **Legal and compliance:** the escrow licensing question (Stage 7.3 §12), and approved marketing and trust copy before any regulatory claim is shown.
- **Staging environment** and deployment of the Stage 1–7 backend (Functions, rules, indexes), including the data migrations.
- **Approval to commit Stage 8** on `stage-8-ui-replacement`, then review and merge.

---

**Stage 8 implementation is complete and verified locally. Nothing has been committed, pushed or deployed. I'm awaiting your explicit approval before any Stage 8 commit.**
