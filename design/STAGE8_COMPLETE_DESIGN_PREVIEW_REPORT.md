# HandyTrust — Complete Design Preview Report

Date: 2026-11-04 · Status: **previews for approval. Nothing has been implemented in the app, and no screen has been deleted.**

## What these previews are

**How they were rendered:**
- Each image is a real Flutter render: the Stage 8 design-system components (`lib/ui/`) plus the proposed additions in `test_visual/previews/preview_kit.dart`.
- Fonts are the bundled Plus Jakarta Sans and Inter.
- Each image shows **light (left) and dark (right)**.

**Size and scale:**
- Phones: 390 pt wide at 1.5×.
- Admin desktop: 1,440 px wide.

**Sample data:**
- Every frame carries a **"PREVIEW · SAMPLE DATA"** tag.
- Names, amounts and counts are illustrative, not real records.
- Photos are placeholders; the app shows real user images.

**What each caption separates:**
- **Existing**: functionality the app already has, restyled.
- **Visual**: the presentation change.
- **Proposed**: anything that needs your approval beyond restyling.

**Totals:**
- **85 previews, 170 renders** (after the artisan revision).
- Every render passes the overflow and layout-exception check.
- A plain re-run matches the stored goldens.

**Reproduce with:**
```
flutter test test_visual/previews --update-goldens   # render → test_visual/previews/goldens/
flutter test test_visual/previews                    # verify against stored goldens (140 passed)
flutter test test_visual                             # Stage 8 suite + previews (230 passed)
```

**Screen IDs:** see `STAGE8_COMPLETE_SCREEN_INVENTORY.md`. Design rules: `STAGE8_1_DESIGN_SPECIFICATION.md`.

---

## 1. System and authentication

### Splash and startup error (SY-03, SY-01, SY-02)
![](stage8_1_previews/au00_splash.png)
![](stage8_1_previews/au00b_startup_error.png)
- **Existing:** logo + progress; startup failure with "Retry" (same copy).
- **Visual:** design-system background and icon tile.

### Sign In: default, error, loading (AU-01)
![](stage8_1_previews/au01_login.png)
![](stage8_1_previews/au01b_login_error.png)
![](stage8_1_previews/au01c_login_loading.png)
- **Existing:** email/password, Forgot Password?, Sign Up. The error text comes from `AuthService.friendlyError`, and loading locks the form.
- **Visual:** brand pill, two-tone headline, error banner in the danger tone.
- **No new sign-in methods.**

### Sign Up: default and validation (AU-02)
![](stage8_1_previews/au02_register.png)
![](stage8_1_previews/au02b_register_errors.png)
- **Existing:** role choice (I need services / I offer services), name, email, city (optional), password and confirm; the existing validators and server errors.
- **Visual:** selectable role cards, inline field errors.

### Password recovery and link sent (AU-03)
![](stage8_1_previews/au03_forgot_password.png)
![](stage8_1_previews/au03b_reset_link_sent.png)
- **Existing:** send reset link, "Check your inbox", Back to Login.
- **Proposed copy:** a note that the link opens Firebase's secure page, which is accurate.
- The password is still reset on Firebase's hosted page (Q-2).

### Verify email, role selection, artisan registration, suspended (AU-04 – AU-07)
![](stage8_1_previews/au04_verify_email.png)
![](stage8_1_previews/au05_role_select.png)
![](stage8_1_previews/au06_artisan_registration.png)
![](stage8_1_previews/au07_suspended.png)
- **Existing:**
  - verify email: resend, use a different account;
  - role selection: continue as Customer or Artisan;
  - artisan registration: category, skills, about, service area;
  - suspended: View My Existing Jobs, Sign Out.
- **Proposed:** a "Contact support" button on Suspended. `/support` is already allowed while suspended.

### Not found and cannot open directly (SY-04, SY-05)
![](stage8_1_previews/sy01_not_found.png)
![](stage8_1_previews/sy02_cannot_open_directly.png)
- **Existing:** the cannot-open screen, with the same copy and "Go back".
- **Proposed:** a styled not-found page replacing GoRouter's unstyled default. This adds an `errorBuilder` and new copy.

## 2. Customer screens not designed in Stitch

### Settings and dialogs (SH-06)
![](stage8_1_previews/cu01_settings.png)
![](stage8_1_previews/dl01_edit_name.png)
![](stage8_1_previews/dl02_change_email.png)
![](stage8_1_previews/dl03_change_password.png)
![](stage8_1_previews/dl04_request_deletion.png)
![](stage8_1_previews/dl05_switch_mode.png)
- **Existing:**
  - username, display name;
  - change email and change password, both re-authenticating with the current password;
  - active mode, dark mode, push notifications on/off;
  - help, contact, account deletion (optional reason) and its cancellation, sign out.
- **Visual:** grouped cards (Account, Preferences, Help, Account actions); dialog cards.
- **Copy fix F-8:** the FAQ's escrow period becomes 14 days.

### Help & Support, About (SH-07, SH-08)
![](stage8_1_previews/cu02_support.png)
![](stage8_1_previews/cu09_about.png)
- **Existing:** submit a ticket (subject, message); your tickets (Open/Resolved); version, Terms, Privacy Policy.

### Dispute, Review (CU-13, CU-14)
![](stage8_1_previews/cu03_dispute.png)
![](stage8_1_previews/cu04_review.png)
- **Existing:**
  - dispute: reason chips, details, evidence photos (optional, up to 5);
  - review: stars with rating words, comment, skip.
- The "within 48 hours" promise is kept out of the preview pending Q-6.

### Secure booking, matched artisans, saved artisans (CU-06, CU-05, CU-12)
![](stage8_1_previews/cu05_secure_booking.png)
![](stage8_1_previews/cu06_matched_artisans.png)
![](stage8_1_previews/cu07_favorites.png)
- **Existing:**
  - secure booking: task, schedule (ASAP / date), proposed budget, "Platform fee (5%)", total once accepted, nothing charged yet;
  - matched artisans: Top and Rising Professionals, Select;
  - saved artisans: remove, Hire.

### Payment: checkout, results, transaction sheet (CU-09, CU-10)
![](stage8_1_previews/cu10_payment_checkout.png)
![](stage8_1_previews/cu08_payment_result.png)
![](stage8_1_previews/cu08b_payment_not_completed.png)
![](stage8_1_previews/cu08c_payment_verifying.png)
![](stage8_1_previews/cu11_transaction_detail.png)
- **Existing:**
  - webview frame: the Paystack page itself is third-party and not restyled;
  - Verifying / Payment Successful / Payment Not Completed, with the existing copy;
  - Try Again, View Job.
- **Proposed (needs approval):** a transaction detail sheet. It shows only existing `PaymentModel` fields: amount, platform fee, total, reference, dates.

### Job detail, customer view, plus dialogs (SH-01)
![](stage8_1_previews/cu12_job_detail_customer_quotes.png)
![](stage8_1_previews/dl06_cancel_job.png)
![](stage8_1_previews/dl07_request_changes.png)
- **Existing:**
  - quotes inbox: sort by Price/Trust; Accept, Decline, Chat;
  - cancel with a reason (Found another artisan, No longer needed, Too expensive, Other);
  - request agreement changes.
- **Visual:** sectioned cards.

## 3. Artisan: superseded by the revised "HandyTrust Pro" design

The first-round artisan previews reused customer layouts and have been **removed**.

The revised, purpose-built artisan design is documented in **`STAGE8_ARTISAN_REDESIGN_PREVIEW.md`**:
- 29 artisan screens, overlays and states (58 renders);
- comparisons against the customer screens and the superseded first round;
- data mapping;
- the exact file deletion and creation lists.

It is awaiting your visual approval.

## 4. Admin

### Dashboard: desktop and mobile (AD-01)
![](stage8_1_previews/ad01_dashboard_desktop.png)
![](stage8_1_previews/ad01_dashboard_mobile.png)
- **Existing:**
  - the same seven KPIs and formulas;
  - operational alerts with their existing actions;
  - pending actions, jobs overview, top categories, platform health.
- **Fix F-2:** every alert shows a readable label, severity and the **original type id**.
- **Visual:** a validated chart palette; "View as table"; metrics without a trend state their definition.

### Users and delete dialog (AD-02)
![](stage8_1_previews/ad02_users.png)
![](stage8_1_previews/ad16_delete_user_dialog.png)
- **Existing:**
  - search, role filters, suspended filter;
  - suspension type, unsuspend, beta tester;
  - delete user, with the existing copy; `adminDeleteUser` writes the audit entry.
- **Visual:** table + side panel.

### Artisans, verifications (AD-03, AD-05)
![](stage8_1_previews/ad03_artisans_pending.png)
![](stage8_1_previews/ad04_verifications.png)
- **Existing:** application review (about, skills, Approve/Reject); ID + selfie review with a rejection reason.

### Jobs with gated delete (AD-04)
![](stage8_1_previews/ad05_jobs.png)
- **Existing:** job table and detail.
- **Fix F-1:** delete is offered only for unpaid jobs, the check runs first, and chat, photos and financial history are kept for paid or disputed jobs.

### Disputes and settlement (AD-06)
![](stage8_1_previews/ad06_disputes_settlement.png)
- **Existing:** release / full refund / split, with amounts and a required reason (`adminResolveDispute`, server-validated).

### Reviews, support, deletion requests (AD-07 – AD-09)
![](stage8_1_previews/ad07_reviews.png)
![](stage8_1_previews/ad08_support.png)
![](stage8_1_previews/ad09_deletions.png)
- **Existing:** delete review; Respond & Resolve; Mark Resolved (+ open the user).

### Audit logs, analytics, settings (AD-10 – AD-12)
![](stage8_1_previews/ad10_audit_logs.png)
![](stage8_1_previews/ad11_analytics.png)
![](stage8_1_previews/ad12_settings.png)
- **Existing:**
  - read-only audit log, with reasons only where the action records one;
  - growth, rating distribution and funnel counts;
  - account, appearance, sign out.
- **Fix F-3:** "Administrator" replaces "Super Administrator".

### Finance and payout freeze (AD-13: approved new exposure)
![](stage8_1_previews/ad13_finance.png)
![](stage8_1_previews/ad13b_payout_freeze.png)
- **Approved D-3:**
  - read-only chargebacks / platform losses / refunds / settlements, using the real status values;
  - payout freeze with a consequence statement, a required reason (at least 10 characters, server-enforced), confirmation and an audit note.
- **Pending decisions:**
  - freeze state display needs Q-5;
  - the chargeback close / investigate actions are not exposed (Q-4).

### Global search, admin notifications (AD-00)
![](stage8_1_previews/ad14_search.png)
![](stage8_1_previews/ad15_notifications.png)
- **Existing:** search or jump to a section, people, jobs; the four admin notification types.

---

## 5. Corrections made during this preview round

While rendering, I checked each preview against the code and removed anything not backed by it. A preview with invented detail would misrepresent the app.

| # | Initially shown | Removed or corrected because |
|---|---|---|
| 1 | Category and distance filters on Find Work, plus a filter sheet | The feed only has a status filter (All Matched / Recent / Urgent) |
| 2 | Reason field and typed-name confirmation on Delete user | `adminDeleteUser` takes only the uid; the existing dialog has neither |
| 3 | Suspension "reason" in the user panel and audit sample | There's no suspension-reason field (only `suspensionType`) |
| 4 | "18 messages" on the admin job panel | The app only knows whether a chat exists |
| 5 | "Load more" pagination on admin tables | The admin lists are full streams; no pagination exists |
| 6 | Bank name and digits on the Earnings banner | The payout-ready provider exposes only a yes/no |
| 7 | Payment-result copy | Replaced with the exact existing strings |
| 8 | "Median response time" | The existing metric is "Response Time" |
| 9 | Notifications row subtitle; missing Username row in Settings | Matched to the real On/Off state and rows |
| 10 | Artisan "Reject…" (implying a reason prompt) | Artisan rejection has a confirmation only |
| 11 | "Within 48 hours" dispute review promise | Held pending Q-6 |
