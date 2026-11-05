# HandyTrust — Artisan UI Redesign ("HandyTrust Pro"): Revised Previews

Date: 2026-11-04 · Status: **revised previews for your visual approval. No app code has changed, and no artisan file has been deleted.**

**This revision replaces the earlier artisan previews entirely.** Those reused customer layouts: the 4-stage escrow lifecycle, the customer card patterns, the floating pill nav and the brand header. They have been removed from the preview set. The superseded images are kept only in the comparison below.

## 1. Old vs revised: proof of a distinct artisan design

Each comparison shows the Stage 8 customer screen, the superseded first artisan preview and the revised artisan screen (light theme):

| Area | Comparison |
|---|---|
| Home | ![](stage8_artisan_comparison/home.png) |
| My Jobs | ![](stage8_artisan_comparison/jobs.png) |
| Job detail / work order | ![](stage8_artisan_comparison/job_detail.png) |
| Money | ![](stage8_artisan_comparison/money.png) |
| Profile | ![](stage8_artisan_comparison/profile.png) |

## 2. The artisan design language

**Coherent with the customer app:**
- the same `HtPalette` (light/dark), `HtType` (Plus Jakarta Sans + Inter), radii, status tones, inputs and buttons;
- the same brand gradient for primary actions.

**Purpose-built for artisans** (`test_visual/previews/artisan_pro_kit.dart`):

| Artisan element | Replaces / differs from customer |
|---|---|
| **Docked Pro work bar** (Home · Find Work · My Jobs · Earnings · Profile): full width, top indicator, filled icon | Customer uses a floating pill bar with 4 items |
| **Availability header**: avatar with green/grey availability ring, "Available · Plumber · Ibadan", messages + notifications with count badges | Customer uses a brand header (logo + HandyTrust) |
| **Action queue**: cards with a coloured rail, real deadline ("Respond within 18 h") and one action | No customer equivalent |
| **Work pipeline strip**: Requests · Agreement · Scheduled · Working · In review counts | No customer equivalent |
| **Work-order tickets**: date block, job, customer, stage chip, deadline, stage-specific action footer | Customer booking cards with the escrow lifecycle |
| **6-step work-order stepper**: Booked · Agreed · Scheduled · Working · Submitted · Paid | Customer 4-step escrow lifecycle (Funded → Released) |
| **8-step progress meter** over the real `JobProgressStage` (Accepted … Completed) | — |
| **Countdown rings** for the booking-response window, review window and verification steps | — |
| **Earnings ledger**: 6-month released bars, escrow / awaiting-release tiles, ledger rows with payout status | Customer Payments (escrow summary) |
| **Squared segmented controls, underline tabs, caps section labels with count badges** | Customer uses pill chips and title headers |
| **Board layout on tablet**: stage columns | Customer tablet = centred phone layout |

## 3. Revised artisan previews (29 screens × light and dark = 58 renders)

Every image is in the gallery (`STAGE8_PREVIEW_GALLERY.html`, Artisan section) and in `design/stage8_1_previews/`.

### Home
- `ar01_home`: today, action queue, pipeline, next appointment, this month, trust score.
- `ar01n_home_new_artisan`: setup steps, payout reminder, empty pipeline.
- `ar01b_trust_score_sheet`: trust-score breakdown.

![](stage8_1_previews/ar01_home.png)
![](stage8_1_previews/ar01n_home_new_artisan.png)
![](stage8_1_previews/ar01b_trust_score_sheet.png)

### Find Work and quote management
- `ar02_find_work`: job board.
- `ar02q_my_quotes`: my quotes.
- `ar02b_quote_composer`: quote composer.
- `ar02s_quote_sent`: quote sent (success).

![](stage8_1_previews/ar02_find_work.png)
![](stage8_1_previews/ar02q_my_quotes.png)
![](stage8_1_previews/ar02b_quote_composer.png)
![](stage8_1_previews/ar02s_quote_sent.png)

### Bookings, My Jobs, work order
- `ar03r_booking_request`: booking request with the response window.
- `ar03_my_jobs`: My Jobs pipeline; `ar03t_my_jobs_tablet`: tablet board.
- `ar04_work_order`: work order, overview and progress.
- `ar04a_agreement`: agreement; `ar04s_schedule`: schedule; `dl08_date_picker`: themed date picker.

![](stage8_1_previews/ar03r_booking_request.png)
![](stage8_1_previews/ar03_my_jobs.png)
![](stage8_1_previews/ar03t_my_jobs_tablet.png)
![](stage8_1_previews/ar04_work_order.png)
![](stage8_1_previews/ar04a_agreement.png)
![](stage8_1_previews/ar04s_schedule.png)
![](stage8_1_previews/dl08_date_picker.png)

### Work submission, review, rework, dispute
- `ar05_submit_work`: submit work.
- `ar05r_in_review`: in customer review.
- `ar06_rework`: rework requested.
- `ar07_dispute`: dispute response.

![](stage8_1_previews/ar05_submit_work.png)
![](stage8_1_previews/ar05r_in_review.png)
![](stage8_1_previews/ar06_rework.png)
![](stage8_1_previews/ar07_dispute.png)

### Earnings and payout
- `ar08_earnings`: earnings and payout ledger.
- `ar08p_payout_account`: payout account.

![](stage8_1_previews/ar08_earnings.png)
![](stage8_1_previews/ar08p_payout_account.png)

### Profile, verification, business, portfolio
- `ar09_profile`: an **artisan-only** profile ("how customers see you").
- `ar09v_verification`: verification status.
- `ar09b_business_profile`: business profile and service area.
- `ar10_portfolio`: portfolio; `ar10e_portfolio_project`: project editor.

![](stage8_1_previews/ar09_profile.png)
![](stage8_1_previews/ar09v_verification.png)
![](stage8_1_previews/ar09b_business_profile.png)
![](stage8_1_previews/ar10_portfolio.png)
![](stage8_1_previews/ar10e_portfolio_project.png)

### Notifications and messaging
- `ar11_notifications`: artisan notifications.
- `ar12_messages`: messages with the job stage per conversation.
- `ar12c_chat`: chat with the work-order strip.

![](stage8_1_previews/ar11_notifications.png)
![](stage8_1_previews/ar12_messages.png)
![](stage8_1_previews/ar12c_chat.png)

### Loading and error states
- `ar13_loading`: skeleton.
- `ar13e_error`: error with retry.

The empty state is in `ar01n`, and the success state in `ar02s`.

![](stage8_1_previews/ar13_loading.png)
![](stage8_1_previews/ar13e_error.png)

## 4. Every value maps to existing data (nothing invented)

| UI element | Source (existing) |
|---|---|
| Availability ring, "Ready to work" | `ArtisanModel.isAvailable` (toggle write moves into a service) |
| Matching radius | `platformConfig.defaultServiceRadiusKm` / artisan service area |
| Booking-request countdown | `JobModel.bookingRequestedAt` + `platformConfig.bookingConfirmationHours` (the server reopens expired requests) |
| Agreement status, changes requested | `agreementStatus`, `agreementChangesRequestedReason`, `agreementConfirmedByCustomer` / `ByArtisan`, `agreementScope`, agreed price |
| Schedule | `appointmentSlots`, `confirmedAppointment`, `schedulingStatus` (up to 3 slots) |
| Progress meter | `progressStage` (`JobProgressStage`: 8 values), `updateProgress` |
| Work-order stepper stage | `JobStatus` + booking/agreement/scheduling fields |
| Submit work checklist | `beforePhotoUrls`, `completionImageUrls`, `artisanNotes` |
| Review countdown, release date | `submittedAt`, `autoReleaseAt` (14-day window, server `REVIEW_WINDOW_MS`) |
| Rework | `reworkReason`, `reworkRequestedAt`, `reworkCount` (one request, policy D4), `respondToRework(response)` |
| Dispute | `DisputeModel` reason and evidence; `respondToDispute(responseText, evidenceImageUrls)` |
| Earnings: released by month, in escrow, awaiting release | `artisanPaymentsProvider` (`PaymentModel.amount`, `status`, `releasedAt`) grouped client-side |
| Ledger payout status | `JobModel.payoutStatus` (`processing`, `paid`, `delayed`, `on_hold`) |
| Payout account | `artisanPayoutReadyProvider` (bank details present: yes/no) |
| Trust score + breakdown | `TrustScoreService` components (Completed Jobs, Customer Rating, Verification, Response Time, Dispute History) |
| Profile stats, skills, area | `ArtisanModel` (rating, totalRatings, completed jobs, trust score, skills, service area); portfolio views from `portfolio_analytics` |
| Verification steps | `verificationStatusProvider` (`pending` / `pending_later` / approved / rejected) |
| Notifications filters | `NotificationCategories` (All / Jobs / Escrow & Pay / Account) |
| Messages job stage | job status of each conversation's job |

### Limit to approve: "My quotes"

The backend has **no cross-job query** for an artisan's own quotes: it would need a collection-group query plus a rules change, which isn't proposed.

So **My quotes lists your quotes on jobs that are still in your open matches**, read per job with the existing `artisanQuoteForJobProvider`. Accepted quotes appear as bookings in My Jobs.

A quote on a job that is no longer open (expired or closed) isn't listed there; you're notified through the existing notifications instead.

## 5. Old artisan files to delete

Each is deleted only after its replacement passes its tests.

| File | What it is today | Replaced by |
|---|---|---|
| `lib/screens/artisan/artisan_dashboard_screen.dart` | `ArtisanHomeTabContent`, `ArtisanDashboardScreen` (unused wrapper) | `artisan_home_screen` |
| `lib/screens/artisan/open_jobs_feed_screen.dart` | Feed + `_SubmitQuoteSheet` (+ direct availability write) | `find_work_screen`, `my_quotes_view`, `quote_composer_screen`, `quote_sent_screen` |
| `lib/screens/artisan/business_profile_screen.dart` | Business profile (direct write) | `business_profile_screen` (Pro) |
| `lib/screens/artisan/bank_details_screen.dart` | Bank details (direct write) | `payout_account_screen` |
| `lib/screens/artisan/portfolio_manager_screen.dart` | Portfolio manager | `portfolio_screen` |
| `lib/screens/artisan/portfolio_project_screen.dart` | Project editor | `portfolio_project_screen` (Pro) |
| `lib/screens/home/all_jobs_screen.dart` | Artisan jobs (+ the obsolete customer branch, **F-11**) | `my_jobs_screen` |
| `lib/screens/home/home_screen.dart` | `_ArtisanHome` via `MainShellScreen` (+ the customer branch) | `artisan_shell` + the existing `CustomerShell` |
| `lib/screens/wallet/wallet_screen.dart` | `_ArtisanEarningsView` (+ obsolete `_CustomerWalletView`) | `earnings_screen` |
| `lib/screens/job/job_completion_screen.dart` | Work submission | `submit_work_screen` |
| `lib/screens/job/job_detail_screen.dart` | Shared job detail (artisan half) | `work_order_screen` (+ tabs), `booking_request_screen`, `rework_screen`, `dispute_response_screen`; the customer half goes to the customer job detail |
| `lib/screens/auth/artisan_registration_screen.dart` | Artisan onboarding (direct writes) | `artisan_registration_screen` (new) |

**Old widgets used by the artisan screens**, deleted with them (some are also used by other old screens, which are replaced in the same phase):
- `premium_scaffold` (`MainShellScreen`), `trust_score_card`, `earnings_summary_card`, `balance_card`, `transaction_card`;
- `shimmer_loaders`, `notification_bell`, `pill_tab_selector`, `job_booking_card`;
- `workflow_timeline`, `workflow_status_card`;
- `portfolio_viewer`, `service_area_card`, `web_content_wrapper`, `user_avatar`, `error_snackbar`.

**Artisan-specific theme components:** there are none separate today. Artisan screens use the old `AppTheme` / `context.colors`, which is removed when the last old screen goes (`lib/theme/*`).

**Stage 8 code with artisan branches** (modify, not delete):

| File | Change |
|---|---|
| `lib/ui/screens/profile_screen.dart` | Becomes customer-only; artisans get the new Pro profile |
| `lib/ui/screens/verification_screen.dart` | The upload flow is reused by the artisan verification hub; 24–48-hour promise removed |
| `lib/ui/screens/chat_screen.dart` | Artisan viewers see the work-order strip |
| `lib/ui/screens/notifications_screen.dart` | Artisan variant styling and filters |

## 6. New files to create

```
lib/ui/artisan/
  components/
    pro_nav_bar.dart        pro_header.dart        pro_back_header.dart
    pro_action_card.dart    pro_pipeline.dart      pro_ticket.dart
    pro_work_stepper.dart   pro_progress_meter.dart pro_countdown_ring.dart
    pro_stat.dart           pro_month_bars.dart    pro_ledger_row.dart
    pro_segments.dart       pro_tabs.dart          pro_action_bar.dart
  artisan_shell.dart                      # docked 5-tab shell (D-2), header actions
  home/artisan_home_screen.dart           # today, action queue, pipeline, appointment, month, trust
  find_work/find_work_screen.dart         # board + status filter + search
  find_work/my_quotes_view.dart
  find_work/quote_composer_screen.dart    # submit / edit quote
  find_work/quote_sent_screen.dart
  jobs/my_jobs_screen.dart                # stage-grouped tickets; tablet board
  jobs/booking_request_screen.dart        # accept / decline (reasons) within the window
  work_order/work_order_screen.dart       # header, stepper, tabs, sticky action bar
  work_order/tabs/{overview,agreement,schedule,photos,activity}_tab.dart
  work_order/submit_work_screen.dart
  work_order/rework_screen.dart
  work_order/dispute_response_screen.dart
  earnings/earnings_screen.dart           # released bars, tiles, ledger
  earnings/payout_account_screen.dart
  profile/artisan_profile_screen.dart     # how customers see you, business, account, role switch
  profile/artisan_verification_screen.dart
  profile/business_profile_screen.dart
  profile/portfolio_screen.dart
  profile/portfolio_project_screen.dart
  messages/artisan_messages_screen.dart
  notifications/artisan_notifications_screen.dart
  registration/artisan_registration_screen.dart
lib/core/services/
  artisan_work_logic.dart        # stage grouping, action queue, countdowns, next action; activeRole (F-11)
  artisan_earnings_summary.dart  # released by month, in escrow, awaiting release (pure)
  artisan_profile_service.dart   # availability, business profile, bank details, registration writes,
                                 # moved from widgets with identical payloads (D-5)
lib/providers/
  artisan_work_providers.dart    # derived streams for the shell, home and jobs
test/
  artisan_work_logic_test.dart  artisan_earnings_summary_test.dart  artisan_profile_service_test.dart
  artisan_ui_test.dart           # widget tests for every artisan screen and state
  artisan_router_test.dart       # D-6 redirects, dual-role switching, deep links
test_visual/
  artisan_visual_test.dart       # goldens light/dark, responsive 320/360/430 + 1024 board
```

**Router:**
- `/home` (artisan) → `ArtisanShell`.
- `/open-jobs`, `/jobs` (artisan), `/wallet` (artisan), `/job/:id` (artisan viewer), `/job/:id/submit`, `/bank-details`, `/business-profile`, `/portfolio`, `/portfolio-project`, `/register/artisan` → the new screens.
- Route paths, guards and notification deep links are unchanged; the artisan redirect (D-6) is UI-only.

**Unchanged:** Firestore collections and documents, Cloud Functions, security rules, Firebase Auth and roles, Paystack, the job lifecycle and payout logic, the 5% fee and the 14-day review.

## 7. Verification plan (after implementation)

| Requirement | How |
|---|---|
| Compare against the approved references | Golden renders of every new artisan screen vs these approved previews (pixel-diff report, as in Stage 8) |
| Old artisan presentation actually replaced | Source guard tests: none of the deleted files exist; no imports of `screens/artisan`, `MainShellScreen`, `AppTheme` or `context.colors` from artisan code; the router builds only `lib/ui/artisan/` for artisan routes |
| Every artisan workflow | Widget and logic tests: availability, search/filter, quote submit/edit/withdraw, booking accept/decline (reason), agreement send/revise, slots, start work, progress, submit (photos required), rework response + resubmit, dispute response (text + evidence), withdraw, earnings and ledger, payout account, business profile, portfolio CRUD, verification, notifications, messages |
| Dual-role users | Switch Customer ↔ Artisan; My Jobs shows only artisan jobs in Artisan Mode (F-11); customer Bookings unaffected |
| Navigation and deep links | Router tests: artisan routes, D-6 redirect, notification allow-list routes landing in the artisan shell, `/portfolio-project` without `extra` |
| Light and dark | Goldens for both themes |
| Tests and analyzer | `flutter test`, `flutter analyze` (0 errors / 0 warnings; no new infos) |
| Backend and rules stay green | Functions 266, rules 139, Storage 9, e2e 16 (Node 22 emulators), plus rules tests proving the moved writes keep identical payloads |

## 8. Preview verification (this step)

| Command | Result |
|---|---|
| `flutter analyze test_visual/previews` | No issues found |
| `flutter test test_visual/previews --update-goldens`, then a plain re-run | **170 passed** (85 previews × 2 themes) |
| `flutter test test_visual` | **258 passed** (Stage 8 suite + all previews) |

**Nothing else changed:**
- `lib/`, `functions/`, rules, indexes and `firebase.json` are unchanged.
- Nothing is committed, pushed or deployed.

**STOP. Waiting for your visual approval of these revised artisan previews before any destructive implementation.**
