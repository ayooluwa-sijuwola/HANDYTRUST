# Part 16 — Navigation Map

Built directly from `router.dart` (a single flat `GoRoute` list plus one `ShellRoute` for admin) and `premium_scaffold.dart` (the bottom-nav shell, rebuilt in the most recent work on this codebase).

## Gate sequence (the router's single `redirect:` callback, evaluated on every navigation)
```
Firebase auth state loading? ──yes──▶ stay on splash ("/")
        │ no
        ▼
Signed out (or anonymous — anonymous is treated as signed-out) ──▶ /login
        │ (except /login, /register, /register/artisan, /forgot-password — public)
        ▼
Email unverified ──▶ /verify-email
        │
        ▼
Verified user on an auth screen (/login, /, /verify-email, /register) ──▶ /home
        │
        ▼
Account suspended ──▶ /suspended (locked everywhere else)
        │
        ▼
/admin/* requested but not an admin ──▶ /home
        │
        ▼
Dual-role account, first /home visit, no activeRole set ──▶ /role-select
        │
        ▼
        (through — normal navigation proceeds)
```

## Bottom-nav shell (both roles, same 4 slots, different content per tab — rebuilt in the most recent work; no center FAB, unlike an earlier version of this shell)
```
/home
 ├─ Explore tab   — customer: home feed + "post a job" CTA · artisan: dashboard
 ├─ My Tasks tab  — /jobs content, role-branched internally (AllJobsScreen)
 ├─ Wallet tab    — /wallet content (WalletScreen)
 └─ Profile tab   — /profile content (ProfileTabContent)
```
Chat is reached via a header icon (not a nav tab) or contextually from a job/quote — confirmed, no bottom-nav Chat slot exists in the current shell.

## Full route tree

```
/                          splash
/login                     ─┬─▶ /forgot-password
/register                   ├─▶ /register/artisan
/verify-email                │
/role-select                  │
/suspended                     │
/home  ◀──────────────────────┘ (post-auth landing)
 ├─ /request                 (post a job)
 ├─ /jobs                    (My Tasks)
 ├─ /wallet
 ├─ /profile
 │    ├─ /settings
 │    ├─ /support
 │    ├─ /about
 │    ├─ /verification
 │    ├─ /bank-details        (artisan)
 │    ├─ /business-profile    (artisan)
 │    └─ /portfolio           (artisan) ──▶ /portfolio-project
 ├─ /notifications
 ├─ /browse-artisans ──▶ /artisan/:uid
 ├─ /favorites ──▶ /artisan/:uid
 ├─ /open-jobs                (artisan — quote an open job)
 └─ /admin/*                  (ShellRoute — only if admin-claim resolves true)
      ├─ dashboard · users · artisans · jobs · verifications
      └─ disputes · reviews · support · deletions · audit-logs · analytics · settings

Job-scoped subtree (reached from /jobs, /request→/artisans/:jobId, notifications, quotes):
/artisans/:jobId ──▶ /artisan/:uid (jobId carried via `extra`, enables "Confirm Selection")
/job/:jobId
 ├─ /chat/:jobId ──▶ /payment/:jobId  (un-gated "Pay Now" button — Part 6/9/15)
 ├─ /payment/:jobId ──▶ /payment/:jobId/webview
 ├─ /demo-payment/:jobId              (still reachable, no gate)
 ├─ /job/:jobId/submit                (artisan completion)
 ├─ /review/:jobId
 └─ /dispute/:jobId

/my-chats ──▶ /chat/:jobId
```

## Dead ends / unreachable nodes
`/phone-login` and any customer-specific-registration route **do not exist in this tree at all** — the two screens behind them are unroutable dead code (Part 15/19). No other confirmed unreachable node was found; every other screen has at least one confirmed navigation path onto it.

## Cross-cutting navigation notes
- **Deep linking**: FCM push taps resolve via `routeFromMessage` (Part 10) into either `/job/:jobId` or `/chat/:jobId`.
- **The admin `ShellRoute`** is the only place in the app where chrome (a sidebar) persists across route changes rather than the whole screen remounting — every other navigation is a full route replacement/push.
- **Two payment entry points into the same job** (`/job/:jobId`'s action button and `/chat/:jobId`'s app-bar button) exist without a single shared gating point — the gating (agreement confirmation, Part 6) lives in `JobService`/rules, which both paths eventually hit, but the *screens* don't share a pre-check.
