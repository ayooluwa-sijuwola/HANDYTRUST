# HandyTrust — Complete UI Replacement: Final Authorization Package

Date: 2026-11-04

**Status:** your decisions Q-1 to Q-9 and the additional approvals are recorded and applied to the previews and specification. **No screen has been deleted or replaced, and the app, backend and rules are untouched.** Waiting for your explicit final authorization.

This package answers the six items in your approval condition.

---

## 1. Preview gallery (all 140 images)

**`design/STAGE8_PREVIEW_GALLERY.html`**: open it in any browser. It's self-contained and works offline, with no external scripts or fonts.

**Accessibility:**
- semantic headings per group, plus a skip link;
- every image has descriptive alt text (screen ID, title, theme, status, notes);
- keyboard-operable filter buttons (Theme: Both / Light / Dark; Status: Approved / Ready / Unresolved) with `aria-pressed`, and a live count of images shown;
- a keyboard-accessible enlarge dialog;
- light/dark page theme.

**Contents:**
- 70 screens × 2 themes = **140 images**, loaded from `test_visual/previews/goldens/`.
- The generator checks that every render exists and that none is left out.
- Checked by opening it in headless Edge: all images load and the filters work.

**Also available:**
- `STAGE8_COMPLETE_DESIGN_PREVIEW_REPORT.md`: the same images as light/dark pairs, with captions.
- The renders are reproducible: `flutter test test_visual/previews` → **140 passed**.

**Changes since your review (from your decisions):**
- Account-deletion copy no longer promises "within 7 days" or claims unenforced preconditions (Q-6, F-12).
- Change password shows the sign-up rule (Q-3).
- The transaction sheet is marked approved (Q-7).
- The Settings deletion row is reworded (F-12).

## 2. Updated screen inventory and navigation map

- **`STAGE8_COMPLETE_SCREEN_INVENTORY.md`**: 60 live screens, 47 overlays, the approved Finance section, obsolete items. §10 records your decisions.
- **`STAGE8_COMPLETE_NAVIGATION_MAP.md`**: 50 routes (+ `/admin/finance`), redirects, auth flows, role navigation, deep links. §8 records your decisions.

## 3. Design status of every screen

**Key:**
- **Approved:** Stitch-approved (Stage 8) or explicitly approved by your decisions.
- **Ready:** the preview complies with all your decisions and waits only for your final design sign-off.
- **Unresolved:** needs a specific answer from you.
- **Fix:** mandatory corrections that apply in implementation (copy, validation, behaviour); they don't change the design.

### 3.1 Screens (60 live + Finance)

| ID | Screen | Status | Fix in implementation |
|---|---|---|---|
| ON-01 | Onboarding | Approved (Stitch) | — |
| CU-01 | Customer shell | Approved (Stitch) | — |
| CU-02 | Discovery | Approved (Stitch) | — |
| CU-03 | Artisan public profile | Approved (Stitch) | — |
| CU-04 | Post a Job | Approved (Stitch) | — |
| CU-07 | My Bookings | Approved (Stitch) | Verify 14-day copy (already correct) |
| CU-08 | Confirm & Pay | Approved (Stitch) | 14-day copy correct (`confirm_pay_screen.dart:174`) |
| CU-11 | Payments | Approved (Stitch) | 14-day copy correct (`payments_screen.dart:151`); add the approved transaction sheet |
| SH-02 | Chat | Approved (Stitch) | Role review only |
| SH-04 | Notifications | Approved (Stitch) | Q-8: keep navigation to the destination; no details screen |
| SH-05 | Profile | Approved (Stitch) | Role review only |
| SH-09 | Identity verification | Approved (Stitch) | **Remove "within 24–48 hours"** (`verification_screen.dart:98`, my Stage 8 code) |
| SY-01 | App initialisation | Ready | — |
| SY-02 | Startup error | Ready | — |
| SY-03 | Splash | Ready | — |
| SY-04 | Page not found | **Approved** | New router `errorBuilder` |
| SY-05 | Cannot open directly | Ready | — |
| AU-01 | Sign In (+ error, loading) | Ready | Sign-in keeps "required" only; **no new rule at sign-in** (existing users are never forced to change) |
| AU-02 | Sign Up (+ errors) | Ready | Shared `PasswordPolicy` |
| AU-03 | Password recovery | Ready | Firebase-hosted reset kept (Q-2) |
| AU-04 | Verify email | Ready | — |
| AU-05 | Role selection | Ready | — |
| AU-06 | Artisan registration | Ready | **Remove "usually takes 24–48 hours"** (`artisan_registration_screen.dart:136`) |
| AU-07 | Suspended | **Approved** (Contact support) | Destination verified: router allows `/support` while suspended; the ticket-create rule has no suspension check |
| CU-05 | Choose an artisan | Ready | — |
| CU-06 | Secure booking | Ready | — |
| CU-09 | Paystack checkout frame | Ready | — |
| CU-10 | Payment result | Ready | — |
| CU-12 | Saved artisans | Ready | — |
| CU-13 | Raise dispute | Ready | **Remove "within 48 hours"** (`dispute_screen.dart:145`, `:333`) |
| CU-14 | Leave a review | Ready | — |
| SH-01 | Job detail | Ready | **Correct the 48-hour artisan copy** (`workflow_gate_service.dart:193`). Read the booking window from `platformConfig.bookingConfirmationHours` (`:84`, `:85`). Q-1 gating |
| SH-03 | Chat list | Ready | — |
| SH-06 | Settings | **Unresolved** (F-12 copy) | **Correct the 7-day FAQ** (`settings_screen.dart:1153`). **Remove** "24–48 hours" (`:1113`) and "within 7 days" (`:340`). **Remove the unenforced "Active jobs and escrow must be resolved first"** (`:341`). Shared `PasswordPolicy` in change password (`:1044`) |
| SH-07 | Help & Support | Ready | — |
| SH-08 | About | Ready | — |
| SH-10 | Portfolio viewer | Ready | — |
| AR-00 | Artisan shell / nav | Approved (D-2) | — |
| AR-01 | Artisan home | Ready (contains the **approved** payout reminder) | Reminder bound to `artisanPayoutReadyProvider` (genuine status). **Remove "24–48 hours"** (`artisan_dashboard_screen.dart:222`, `:390`) |
| AR-02 | Find Work | Ready | — |
| AR-03 | My Jobs | Ready | **F-11: use `activeRole`** (`all_jobs_screen.dart:38`) |
| AR-04 | Work submission | Ready | 14-day copy correct (`job_completion_screen.dart:145`) |
| AR-05 | Earnings | Ready | — |
| AR-06 | Business profile | Ready | — |
| AR-07 | Payout details | Ready | — |
| AR-08 | Portfolio manager | Ready | — |
| AR-09 | Portfolio project editor | Ready | — |
| AD-00 | Admin shell | Ready | — |
| AD-01 | Dashboard | **Unresolved** ("View in Finance" links) | **28 alert labels with original ids** |
| AD-02 … AD-11 | Users, Artisans, Jobs, Verifications, Disputes, Reviews, Support, Deletions, Audit logs, Analytics | Ready | Q-1 job-deletion gating (AD-04) |
| AD-12 | Admin settings | Ready | F-3 "Administrator" |
| AD-13 | **Finance** + payout freeze | **Approved** (D-3, Q-4 read-only, Q-5 freeze display) | Freeze status via the additive model parse (§5) |

**Overlays:**
- Approved: 7 Stage 8 overlays, the payout-freeze dialog (D-3) and the transaction sheet (Q-7).
- Unresolved: account-deletion dialog `dl04` (F-12 copy).
- Ready: the remaining 38.
- Not restyled: system camera and gallery pickers.

### 3.2 Unresolved items (3)

| # | Item | Proposed answer |
|---|---|---|
| U-1 | **Account-deletion copy** (Settings row + dialog). The current text promises "within 7 days" and says "Active jobs and escrow must be resolved first". **Neither is enforced:** `ProfileService.requestAccountDeletion` writes the request without checks, and `adminDeleteUser` checks only admin rights and self-deletion | Use: "An administrator will review your request. Your job history, payments and reviews are kept." (The last sentence matches what `adminDeleteUser` preserves.) Adding real enforcement is a backend change and isn't proposed |
| U-2 | **"View in Finance"** links on chargeback alerts | Navigation only (to `/admin/finance`, filtered to the alert's record); no new action. Approve or drop |
| U-3 | Provisional design assets carried over from Stage 8: heading font (Plus Jakarta Sans, my closest match) and the onboarding hero photo (a crop) | Supply the Stitch font name and the original photo, or approve the provisional ones |

## 4. Proposed file changes (Phase C, after your authorization)

`lib/` has 171 Dart files today. Every deletion happens **only after its replacement passes its tests**.

### 4.1 Delete

**`lib/screens/`: all 36 files (the directory is removed)**

| Folder | Files |
|---|---|
| `admin/` | `admin_charts`, `admin_dashboard_screen`, `admin_data_table`, `admin_finance_dialogs`, `admin_palette`, `admin_sidebar`, `admin_widgets` |
| `artisan/` | `artisan_dashboard_screen`, `artisan_list_screen`, `bank_details_screen`, `business_profile_screen`, `favorites_screen`, `open_jobs_feed_screen`, `portfolio_manager_screen`, `portfolio_project_screen`, `secure_booking_screen` |
| `auth/` | `artisan_registration_screen`, `forgot_password_screen`, `login_screen`, `register_screen`, `role_selection_screen`, `splash_screen`, `suspended_screen`, `verify_email_screen` |
| `chat/` | `my_chats_screen` |
| `dispute/` | `dispute_screen` |
| `home/` | `all_jobs_screen`, `home_screen` |
| `job/` | `job_completion_screen`, `job_detail_screen` |
| `payment/` | `payment_webview_screen` |
| `review/` | `review_screen` |
| `settings/` | `settings_screen` |
| `support/` | `about_screen`, `contact_support_screen` |
| `wallet/` | `wallet_screen` |

**`lib/widgets/`: all 26 files (the directory is removed)**

| Kind | Files |
|---|---|
| Unused today (OBS-4 to OBS-6) | `cancellation_reason_dialog`, `artisan_card`, `loading_indicator` |
| Replaced by new components | `app_snackbars`, `auth_scaffold`, `balance_card`, `cannot_open_directly_screen`, `earnings_summary_card`, `error_snackbar`, `job_booking_card`, `job_status_badge`, `notification_bell`, `pill_tab_selector`, `portfolio_viewer`, `premium_scaffold`, `review_tile`, `service_area_card`, `shimmer_loaders`, `star_rating`, `startup_error_screen`, `transaction_card`, `trust_score_card`, `user_avatar`, `web_content_wrapper`, `workflow_status_card`, `workflow_timeline` |

**`lib/theme/`: all 4 files**
- `app_colors.dart`, `app_design_system.dart`, `app_theme.dart`, `breakpoints.dart` (once nothing imports them).

**Obsolete inside deleted files:**
- `_CustomerWalletView`, the `AllJobsScreen` customer branch and the `ArtisanDashboardScreen` wrapper (OBS-1 to OBS-3) go with their files.

**Total deletions: 66 files.**

### 4.2 Create

| Area | Files |
|---|---|
| `lib/ui/components/` | Promote the preview-kit components: `ht_kpi_tile`, `ht_filter_bar`, `ht_data_table` (+ list card), `ht_side_nav` / `ht_admin_frame`, `ht_alert_row`, `ht_chart_card` (+ chart tokens), `ht_sheet` / `ht_dialog_card` / `ht_danger_button`, `ht_job_card`, `ht_timeline`, `ht_toggle_row`, `ht_photo_grid` / viewer, field-error state; `ht_theme_data` (Material theme from `HtPalette`, used by `main.dart`) |
| `lib/ui/screens/` (system, auth) | `splash`, `startup_error`, `not_found`, `cannot_open`, `login`, `register`, `forgot_password`, `verify_email`, `role_select`, `artisan_registration`, `suspended` |
| `lib/ui/screens/` (customer, shared) | `matched_artisans`, `secure_booking`, `payment_checkout` (+ result states), `favorites`, `dispute`, `review`, `transaction_detail_sheet`, `job_detail` (+ section widgets), `chat_list`, `settings` (+ dialogs), `support`, `about`, `portfolio_viewer` |
| `lib/ui/screens/artisan/` | `artisan_shell`, `artisan_home`, `find_work` (+ quote sheet), `artisan_jobs`, `submit_work`, `earnings`, `business_profile`, `payout_details`, `portfolio_manager`, `portfolio_project` |
| `lib/ui/screens/admin/` | `admin_shell`, `dashboard`, `users`, `artisans`, `jobs`, `verifications`, `disputes`, `reviews`, `support`, `deletions`, `audit_logs`, `analytics`, `settings`, `finance` (+ settlement, reason, suspension, freeze dialogs) |
| `lib/core/services/` (logic, pure + tested) | `password_policy.dart` (Q-3); `admin_alert_catalogue.dart` (28 labels + original ids); `admin_service.dart` (D-5: the admin writes moved from widgets, identical payloads); `job_actions_logic.dart` (job-detail per-status actions, from the 2,518-line screen) |
| `lib/providers/` | `admin_providers.dart` (the 12 private admin providers, unchanged queries); `admin_finance_providers.dart` (read-only chargebacks, platform losses, refunds, settlements) |
| `test/` | Widget and logic tests per area; router tests (redirects, D-6, `errorBuilder`); alert catalogue covers all 28 ids; password policy; F-1 / Q-1 delete predicate; F-11 |
| `test_visual/` | Goldens + responsive sweeps for every new screen (replacing the preview goldens) |

### 4.3 Modify

| File | Change |
|---|---|
| `lib/routes/router.dart` | Point every route at the new screens; add `/admin/finance`, `errorBuilder` (SY-04) and the artisan-route redirect (D-6). **Guards are unchanged** |
| `lib/main.dart` | `ThemeData` from `HtPalette` (`ht_theme_data`); new init and startup-error screens |
| `lib/core/services/workflow_gate_service.dart` | **Copy only:** 48 hours → 14 days (`:193`); booking window from config (`:84`, `:85`) |
| `lib/core/services/auth_service.dart` | **Copy only:** the `weak-password` message uses the policy text |
| `lib/models/job_model.dart`, `lib/models/artisan_model.dart` | **Additive, read-only parse** of `payoutFrozen`, `payoutFreezeReason`, `payoutFreezeBy`, `payoutFreezeAt` (Q-5); see §5 |
| `lib/ui/screens/verification_screen.dart` | Remove the 24–48-hour promise (`:98`) |
| `lib/ui/screens/payments_screen.dart` | Open the approved transaction sheet from transaction rows |
| `lib/ui/components/ht_bottom_nav.dart` | Add `artisanItems` (5 items) |
| `test/portfolio_project_route_test.dart`, `test/stage8_ui_test.dart` | Point to the new files; extend the source guards (no imports of deleted files; no "Super Administrator"; no unverified timing strings) |
| `pubspec.yaml` | No new packages (`fl_chart` is already a dependency) |

**Not modified:** `functions/`, `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json`, Paystack configuration.

## 5. Backend and data-model changes

| Area | Change | Notes |
|---|---|---|
| Cloud Functions | **None** | No deploy needed for Phase C |
| Firestore rules | **None** | Admin reads of `chargebacks`, `platform_losses`, `refunds`, `settlements`, jobs and artisans are already allowed |
| Storage rules | **None** | — |
| Firestore indexes | **None planned** | The finance lists are single-field ordered queries (automatic indexes). If a composite index ever proved necessary, I'd stop and ask |
| Firebase Authentication | **None** | Email/password, verification and hosted reset unchanged. The password rule is client-side validation for new and changed passwords only; no Firebase password-policy change, and existing users can still sign in |
| Paystack | **None** | — |
| Data in Firestore | **None** | No migration, no new fields written, no schema change |
| **Client data model** | **One additive, read-only change (Q-5):** `JobModel` and `ArtisanModel` parse the existing server-written fields `payoutFrozen`, `payoutFreezeReason`, `payoutFreezeBy` and `payoutFreezeAt` | Written only by `adminSetPayoutFreeze` (unchanged). Missing fields parse as "not frozen". Displayed to admins in Finance and the detail panels; nothing new is shown to customers |
| Client services | Admin writes moved from widgets into `AdminService` (D-5) | Same collections, payloads and batches; the existing rules tests keep proving them |
| Client copy | Workflow and auth strings corrected (§3) | — |

## 6. Recoverability

| Work | Recoverable from | Verified |
|---|---|---|
| Stages 1–7.3 | Local branch **`stage-7.3-verified-baseline` @ `7e16eb1`** (committed, not pushed) | Yes: it's the base commit of the current branch |
| **Stage 8 + 8.1** (uncommitted) | **Not from git alone.** This work is uncommitted on `stage-8-ui-replacement`, so the baseline branch doesn't contain it | — |
| Stage 8 + 8.1: verified backup (made today, no commit) | `C:\PROJECTS\handy_trust_backups\stage8_8.1_2026-11-04\`: a binary patch vs `7e16eb1` (4 modified, 11 deleted), the 4 modified files byte-for-byte, a tar of all 330 untracked files, `MANIFEST.sha256` and `RESTORE.md` | **Yes:** restored into a scratch directory from `7e16eb1`; **334/334 checksums match** byte-for-byte, and the 11 deleted files are absent |

**Recommendation, before any destructive step:** authorize a **local commit** of the current Stage 8 + 8.1 state on `stage-8-ui-replacement` (no push). Phase C would then be fully reversible with git itself, and the file backup remains a second copy. **I haven't committed anything.**

---

## Mandatory defect corrections: where each lands

| # | Correction | Location(s) | Phase C action |
|---|---|---|---|
| 1 | 7-day FAQ | `settings_screen.dart:1153` | New Settings FAQ: "…or automatically 14 days after the artisan submits the work" |
| 2 | 48-hour artisan auto-release | `workflow_gate_service.dart:193` | "…releases automatically 14 days after you submitted" (same as `job_detail_screen.dart:510`) |
| 3 | 14-day references | Correct today: `confirm_pay_screen.dart:174`, `payments_screen.dart:151`, `job_completion_screen.dart:145`, `job_detail_screen.dart:510`, `:589`, `workflow_gate_service.dart:170`. Wrong: the two above | All match the backend `REVIEW_WINDOW_MS = 14 days` (`functions/index.js:709`) and the client `JobService.releaseWindow` (14 days). A source-guard test blocks other durations |
| 4 | Password validation | `register_screen.dart:188-190` (8 / uppercase / number), `settings_screen.dart:1044` (6), `auth_service.dart:168` (6) | One shared `PasswordPolicy` for sign-up and change password; sign-in unchanged |
| 5 | Dual-role My Jobs (F-11) | `all_jobs_screen.dart:38` | Artisan jobs come from `activeRole == 'artisan'`; customer jobs stay in Bookings |
| 6 | 28 alert labels | `admin_dashboard_screen.dart` `_AdminAlertRow` (16 unlabelled) | `admin_alert_catalogue.dart`: label + severity + original id; a test enumerates all 28 |
| Q-6 | Unverified timing promises | `artisan_dashboard_screen.dart:222`, `:390`; `artisan_registration_screen.dart:136`; `dispute_screen.dart:145`, `:333`; `settings_screen.dart:340`, `:1113`; `verification_screen.dart:98` | Removed. Kept: the booking-response window, read from config (backend-enforced) |

---

**STOP. Waiting for your explicit final authorization (and answers to U-1 to U-3, plus whether to make the local checkpoint commit) before deleting or replacing any screen.**
