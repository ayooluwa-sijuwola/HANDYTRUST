# HandyTrust — Complete Navigation Map

Date: 2026-11-04 · Source: `lib/routes/router.dart` (GoRouter), the shells (`CustomerShell`, `MainShellScreen`, `AdminShell`), every `context.push` / `go` / `pushReplacement` call, overlays, and the push and email deep links.

Screen IDs refer to `STAGE8_COMPLETE_SCREEN_INVENTORY.md`.

**Proposed changes are marked ◆.** Everything else is existing navigation, which stays the same in Phase C.

## 1. Route table (50 paths)

| Path | Screen (ID) | Access | Notes |
|---|---|---|---|
| `/` | Splash (SY-03) | public | Redirect hub |
| `/onboarding` | Onboarding (ON-01) | public | Shown once (prefs) |
| `/login` | Sign In (AU-01) | public | |
| `/register` | Sign Up (AU-02) | public | |
| `/register/artisan` | Artisan registration (AU-06) | signed in | |
| `/verify-email` | Verify email (AU-04) | signed in, unverified | |
| `/forgot-password` | Password recovery (AU-03) | public | |
| `/suspended` | Suspended (AU-07) | suspended | |
| `/role-select` | Role selection (AU-05) | dual role | |
| `/home` | Customer shell (CU-01) / artisan shell (AR-00) | signed in | `HomeScreen` chooses by `activeRole` |
| `/browse-artisans` | Discovery (CU-02) | signed in | |
| `/favorites` | Saved artisans (CU-12) | signed in | |
| `/artisans/:jobId` | Choose an artisan (CU-05) | signed in | `extra`: category, lat, lng |
| `/artisan/:uid` | Artisan public profile (CU-03) | signed in | `extra`: jobId (direct hire) |
| `/secure-booking/:artisanId` | Secure booking (CU-06) | signed in | |
| `/request` | Post a Job (CU-04) | signed in | `?category=` |
| `/jobs` | Bookings (CU-07) / My Jobs (AR-03) | signed in | `_RoleAware` |
| `/job/:jobId` | Job detail (SH-01) | participants | |
| `/job/:jobId/submit` | Work submission (AR-04) | artisan | |
| `/chat/:jobId` | Chat (SH-02) | participants | |
| `/my-chats` | Chat list (SH-03) | signed in | |
| `/payment/:jobId` | Confirm & Pay (CU-08) | customer | |
| `/payment/:jobId/webview` | Paystack checkout + result (CU-09, CU-10) | customer | |
| `/wallet` | Payments (CU-11) / Earnings (AR-05) | signed in | `_RoleAware` |
| `/review/:jobId` | Review (CU-14) | customer | |
| `/dispute/:jobId` | Dispute (CU-13) | participants | |
| `/notifications` | Notifications (SH-04) | signed in | |
| `/profile` | Profile (SH-05) | signed in | |
| `/settings` | Settings (SH-06) | signed in | |
| `/support` | Help & Support (SH-07) | signed in (also allowed while suspended) | |
| `/about` | About (SH-08) | public | |
| `/verification` | Identity verification (SH-09) | signed in | |
| `/open-jobs` | Find Work (AR-02) | artisan ◆ guard (D-6) | |
| `/bank-details` | Payout details (AR-07) | artisan ◆ guard | |
| `/business-profile` | Business profile (AR-06) | artisan ◆ guard | |
| `/portfolio` | Portfolio manager (AR-08) | artisan ◆ guard | |
| `/portfolio-project` | Project editor (AR-09) | artisan ◆ guard | Requires `extra`; otherwise SY-05 |
| `/admin` | → `/admin/dashboard` | admin | |
| `/admin/dashboard` … `/admin/settings` (12) | AD-01 … AD-12 | admin (`isAdminProvider`) | `ShellRoute` keeps `AdminShell` |
| ◆ `/admin/finance` | Finance (AD-13) | admin | Approved D-3 |
| *(any unknown path)* | GoRouter default error page | — | ◆ styled not-found (SY-04) via `errorBuilder` |

## 2. Global redirect logic (unchanged)

```
request ─► signed out?
            ├─ onboarding flag unknown ─► stay on /
            ├─ not seen ─────────────────► /onboarding
            └─ seen ─────────────────────► /login        (public paths allowed)
          signed in:
            ├─ on /onboarding ─────────────► /home
            ├─ email not verified ─────────► /verify-email
            ├─ suspended ──────────────────► /suspended, except /jobs /job/ /dispute/ /notifications /support
            │                                (+ /chat/ /payment/ for administrative/verification suspensions)
            ├─ /admin* and not admin ──────► /home
            ├─ dual role, no active role ──► /role-select
            ◆ artisan-only route and not in Artisan Mode ─► /home   (UI convenience; rules enforce access)
            └─ otherwise ──────────────────► requested path
```

## 3. Authentication flows

```
/ Splash ──startup failure──► Startup error (SY-02) ──Retry──► /
/onboarding ── Get Started ─► /register        ── Skip ─► /login
/login ── success ─► / (router decides) ── Forgot Password? ─► /forgot-password ── Sign Up ─► /register
/register ── success (verification email sent) ─► /verify-email ── Sign In ─► /login
/verify-email ── Resend · Use a different account (sign out ─► /login) · auto-advance when verified
/forgot-password ── Send Reset Link ─► "Check your inbox" ── Back to Login ─► /login
   email link ─► Firebase-hosted reset page (external) ─► user returns to /login
/role-select ── Continue as Customer | Artisan ─► /home
/register/artisan ── Submit for review ─► /home
/suspended ── View My Existing Jobs ─► /jobs · ◆ Contact support ─► /support · Sign Out ─► /login
```

## 4. Customer

```
Bottom nav (CustomerShell): Discovery · Bookings · Payments · Profile      Header: bell ─► /notifications
Discovery ─► /artisan/:uid ─► Book ─► /secure-booking/:id ─► job ─► /job/:id
          ─► (with job) Book ─► confirm sheet ─► acceptArtisan ─► /chat/:jobId
Post a Job (/request) ─► /artisans/:jobId ─► Select ─► /job/:id
Bookings ─► card ─► /job/:id · chat ─► /chat/:id · Pay into Escrow ─► /payment/:id
         ─► Approve & Release ─► confirm sheet ─► confirmComplete · Post Job ─► /request
/payment/:id ─► /payment/:id/webview (Paystack) ─► result ─► View Job ─► /job/:id | Try Again
Payments ─► Inspect Job / transaction ─► /job/:id      ◆ optional transaction detail sheet (needs approval)
Job detail (customer) ─► quotes (Accept/Decline/Chat) · confirm agreement · request changes (dialog)
                      ─► confirm slot · cancel (reason dialog) · paid cancellation · rework (dialog)
                      ─► /dispute/:id · /review/:id · /chat/:id
Profile ─► /jobs · /my-chats · /settings · /support · /about · /favorites · /artisan/:uid (artisans)
        ─► Artisan Mode switch (dual role) · Admin Dashboard ─► /admin (admins) · Log out (confirm sheet)
```

## 5. Artisan

```
Bottom nav ◆ (D-2): Home · Find Work · My Jobs · Earnings · Profile     Header ◆: Messages ─► /my-chats · bell ─► /notifications
  (today: Home · Jobs · Chats · Profile)
Home ─► verification card ─► /verification · trust score ─► breakdown sheet
     ─► quick actions ─► /open-jobs · /business-profile · /portfolio · /bank-details · recent job ─► /job/:id
Find Work (/open-jobs) ─► Ready to work toggle · status filter · quote sheet (submit/edit/withdraw) · Chat ─► /chat/:id
My Jobs (/jobs) ─► /job/:id ─► confirm/decline booking · agreement (propose/accept/request changes)
                ─► propose slots (date/time pickers) · start work · update progress
                ─► /job/:id/submit · respond to rework · dispute reply · withdraw (reason dialog)
Earnings (/wallet) ─► transaction ─► /job/:id · payout readiness ─► /bank-details
Portfolio (/portfolio) ─► Add/Edit ─► /portfolio-project (extra) · photo ─► portfolio viewer · delete (confirm)
Profile (S8) ─► My Reviews · Earnings & Payouts · Identity Verification · settings · Customer Mode (dual role)
```

## 6. Admin

```
/admin/* (ShellRoute AdminShell; rail ≥1024 px, drawer below)
Top bar: global search (sheet: Go to section · People · Jobs) · notifications (dialog ─► section) · theme · Back to app ─► /home
Sidebar ◆ grouping:
  OVERVIEW    Dashboard ─► alert actions (settlement dialog · reason dialog · ◆ View in Finance) · pending actions ─► sections
              Analytics (chart period menu)
  PEOPLE      Users ─► detail (suspension type ─► confirm · delete confirm · beta tester confirm · contact · activity)
              Artisans ─► approve/reject confirm
              Verifications ─► image zoom · approve · reject (reason)
  OPERATIONS  Jobs ─► detail (◆ gated delete confirm) · Disputes ─► evidence zoom · settlement dialog
              Support ─► Respond & Resolve · Reviews ─► delete confirm · Deletion requests ─► Mark Resolved
  FINANCE ◆   Finance ─► chargebacks · platform losses · refunds · settlements (read-only) · ◆ payout freeze dialog
  COMPLIANCE  Audit logs
  Settings    account · appearance · sign out
```

## 7. Deep links and external pages

| Source | Handling | Lands on |
|---|---|---|
| Push notification tap (cold start / background) | `getInitialMessage` / `onMessageOpenedApp` → `safeNotificationRoute` | Allow-list only: `/job/`, `/chat/`, `/dispute/`, `/notifications`, `/jobs`, `/wallet`, `/home`; anything else → `/notifications` |
| In-app notification tap | Mark read, then `safeNotificationRoute(route)` | Same allow-list |
| Email verification link | Firebase-hosted action page | App re-checks on resume; router leaves `/verify-email` |
| Password reset link | Firebase-hosted reset page | User returns and signs in |
| Paystack checkout | In-app webview (`/payment/:id/webview`) | Result view after server `verifyPayment` |
| Direct URL to `/portfolio-project` without `extra` | `CannotOpenDirectlyScreen` | Go back → `/portfolio` |
| Unknown URL | GoRouter default page | ◆ SY-04 styled not-found → `/home` |
| Web refresh / bookmark of any `/admin/*` | `ShellRoute` + guard | Same section, after the admin check |

## 8. Owner decisions applied (2026-11-04)

- **Approved:**
  - `errorBuilder` → styled not-found (SY-04), with "Go to home" → `/home`;
  - Suspended → Contact support → `/support` (already allowed while suspended; ticket create permitted);
  - artisan Home payout reminder → `/bank-details`, shown only when `artisanPayoutReadyProvider` is false.
- **Q-7:** Payments → transaction row → **transaction details sheet** → View job → `/job/:id`.
- **Q-8:** notification tap continues to open its allow-listed destination; no details screen.
- **Q-4:** Finance has no chargeback actions; it's read-only navigation only.
- **Pending (U-2):** "View in Finance" alert links → `/admin/finance` (navigation only).
