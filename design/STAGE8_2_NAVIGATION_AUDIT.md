# Stage 8.2 — navigation audit

## 1. Settings destinations (D)

| Entry point | Option | Before | After (verified by test) |
|---|---|---|---|
| Customer Profile | Account Information | `/settings` (hub) | `/settings/personal` |
| Customer Profile | Security & Password | `/settings` | `/settings/security` |
| Customer Profile | Notification Settings | `/settings` | `/settings/notifications` |
| Customer Profile | Support Center / About | `/support`, `/about` (old screens) | New screens, same paths |
| Customer Notifications | Manage Notification Settings | `/settings` | `/settings/notifications` |
| Artisan Notifications | Notification settings | `/settings` | `/settings/notifications` |
| Artisan Profile | Settings | `/settings` | Hub; each row opens its own page |
| Settings hub | Personal information · Security and password · Notification preferences · Support Centre · About HandyTrust | — | Own destination each; **Back returns to the hub** (5 tests) |

A source guard (`test/stage8_2_ui_test.dart`) fails if those Profile rows point at the hub again.

## 2. Routes added or changed

| Path | Screen | Notes |
|---|---|---|
| `/settings` (+ `/personal`, `/notifications`, `/security`) | `SettingsScreen` and pages | Nested GoRoutes; deep-linkable; Back pops, or goes to `/profile` when opened directly |
| `/support` | `SupportCentreScreen` | Still on the suspended-user allow-list (ticket creation is allowed by the rules) |
| `/about` | `AboutHandyTrustScreen` | — |
| `/my-chats` | Customer: `CustomerMessagesScreen`; artisan mode: `ArtisanMessagesScreen` | Role-aware (`_RoleAware`); conversations separated by role |
| `/chat/:jobId?with=uid` | `ChatScreen` | `?with=` selects one conversation without route extras (deep links) |
| `/admin/*` (13 sections incl. **`/admin/finance`**) | `AdminShell` + sections | ShellRoute; `?focus=` preselects a user or job (search results) |

**Obsolete routes:** none removed. Every path still exists and now renders a rebuilt screen. No route points at a deleted file (analyzer: 0 errors).

## 3. Back behaviour

- **Settings pages:** header Back uses `pop` when possible, otherwise `go('/profile')`.
- **Admin:** sidebar/rail/drawer use `go` (section URLs, no stack growth); detail panels close in place on wide screens and use a pushed page on phones (system Back closes it); **Back to app** → `/home`.
- **My Chats:** Back pops, or goes to `/home`. Chat → Back returns to the list.

## 4. Deep links and redirects (real app router, tested)

- `/settings`, `/settings/personal`, `/settings/notifications`, `/settings/security`, `/support`, `/about`, `/my-chats` each open their screen.
- Every admin section URL opens its section for an admin.
- **Non-admins** requesting `/admin/finance` are sent to `/home`. This is a UI gate only: the rules and admin callables enforce access independently.
- **Not yet tested:** suspended-user access to `/support` (this redirect logic was unchanged).
- **Android app links:** none are declared (`AndroidManifest.xml` has no URL intent filters). "Deep links" here means in-app routes and notification taps.

## 5. Role switching

- **Settings → Active mode** (dual-role users only): `setActiveRole` then `go('/home')`. `/home` shows the shell for the new role (tested).
- **Messages:** `/my-chats` and the artisan header badge use role-specific conversation sets, so a dual-role user never sees the other role's threads mixed in.
- **Notification taps:** routes are role-neutral (`/job/:id`, `/chat/:id`). The screen resolves the user's side of the job.
