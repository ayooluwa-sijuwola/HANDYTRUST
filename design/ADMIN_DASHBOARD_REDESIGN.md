# Admin Dashboard Redesign

Scope: a visual/information-architecture redesign, not a functional rewrite. Per instruction, the existing Admin functionality is the source of truth — every feature, backend connection, and action below was inventoried before any code changed, and re-verified live (real signed-in admin account, real Firestore data) after.

## Existing functionality inventory

The dashboard has 12 sections, all under one `ShellRoute` (`/admin/*`, `AdminSection` enum → URL, `router.dart`), guarded by `isAdminProvider` (an `/admins/{uid}` doc existence check) both at the router-redirect level and inside the shell. None of this — routes, guard, or the underlying Firestore/provider wiring — was touched.

| Section | Backend source | Key actions | Preserved |
|---|---|---|---|
| Dashboard | `_allUsersProvider`, `_allArtisansProvider`, `_allJobsProvider`, `_allPaymentsProvider`, `pendingVerificationsProvider`, `_adminAlertsProvider`, `_recentAuditLogsProvider` (all live `StreamProvider`s) | Tap-through navigation to every other section; per-alert "Resolve" write | Yes — same providers, same computations, only layout order changed |
| Users | `_allUsersProvider` | Search/filter/sort; Suspend/Reactivate; Delete (Cloud Function `adminDeleteUser`); Beta Tester toggle; Profile/Activity drill-in | Yes — table row rendering changed, `onRowTap`/action handlers untouched |
| Artisans (Pending + All) | `_pendingArtisansProvider`, `_allArtisansProvider` | Approve/Reject; search/filter/sort; Beta Tester toggle | Yes |
| Jobs | `_allJobsProvider` (read-only by design) | Search/filter; Delete Job Request; detail sheet (quotes/dispute/appointment/photos) | Yes |
| Verifications | `pendingVerificationsProvider` | Approve; Reject (with reason) | Yes, untouched |
| Disputes | `openDisputesProvider` (`DisputeService`) | Dismiss/Resolve (writes job-level audit trail, not `admin_audit_logs` — this pre-existing asymmetry was left exactly as-is, not "fixed," since it wasn't in scope) | Yes, untouched |
| Reviews | `allReviewsProvider` | Search/sort; Delete (recomputes artisan rating) | Yes |
| Support Tickets | `allTicketsProvider` | Search/filter; Respond & Resolve | Yes |
| Deletion Requests | `_deletionRequestsProvider` | Mark Resolved (clears the request flag only — does not itself delete the account) | Yes, untouched |
| Audit Logs | `AdminAuditService.watchAll()` | Read-only viewer | Yes — visual language rebuilt, same stream, same 200-entry cap, same rows |
| Analytics | Aggregates of the above providers | Read-only; drill-in links to Jobs/Artisans | Yes, untouched |
| Settings | `FirebaseAuth.currentUser`, `themeProvider` | Theme toggle, Sign Out | Yes, untouched |

Cross-cutting, all untouched: global Ctrl/Cmd+K search, notification bell, "Back to App", the Beta Tester toggle (shared between Users and Artisans), sign-out (sidebar + Settings), the `AdminDataTable`/`AdminMasterDetail` pagination and side-panel/bottom-sheet pattern.

## What changed, and why

**1. Three hardcoded light-only colors → semantic tokens.** The "Pending" approval badge and the artisan-list rejected/pending status fallback (`_ArtisanApplicationCard`, `_ArtisanListTile`) used fixed hex literals (`0xFFFFF3CD`/`0xFF856404`, `0xFFE6A817`) that never adapted for dark mode. Migrated to `context.colors.warning`/`warningSurface` — the same dark-mode-audited tokens these widgets' other colors already used.

**2. Audit Logs rebuilt.** This was the one section that bypassed `AdminPalette` entirely (raw `Theme.of(context).colorScheme`, default `ListTile` styling, raw `Colors.green/red/orange/blue/grey` for action icons) — it visually read as a different app from the rest of admin. Rebuilt with the same card/list language every other section uses (`AdminPalette`, bordered card container, `AdminPalette.green/red/amber/blue` for action colors, `palette.textTertiary` in place of `Colors.grey`). Same live stream, same data, same read-only behavior — purely visual.

**3. Responsive card-mode for `AdminDataTable`.** Previously every browse table (Users, Artisans, Jobs, Reviews, Support Tickets) was a fixed flex-column `Row` layout with no mobile adaptation — on a phone-width screen this either clips or forces the same cramped desktop columns into a narrow space. Added a `narrowRowBuilder` slot to `AdminDataTable` (below 640px, if supplied, rows render as stacked cards instead of the column layout) and implemented one for all 5 tables, each reusing the exact same computed values (name, status, category, etc.) the wide layout already had — just reflowed into a card: primary identifier + status badge on top, secondary metadata wrapped below. Pagination, row-tap-to-detail, and selection highlighting are shared between both layouts via one `_pager` helper, so behavior didn't fork.

**4. Dashboard Home reordered.** Previously: stat-card grid → charts → Recent Activity / Pending Actions / Platform Health → Operational Alerts (last). Reordered so **Pending Actions and Operational Alerts are now the first thing on the page**, side-by-side on wide layouts — matching the brief's "first screen should immediately communicate... pending verification, disputes requiring attention... important alerts." The KPI stat grid, charts, Recent Activity, and Platform Health all kept their existing content and computation, just resequenced. No card's internal logic, data source, or action changed — this was a pure reordering of existing widgets.

## What was deliberately left unchanged

- The 12 `AdminSection` routes/URLs and the `ShellRoute` structure — changing these would break deep-linking and existing bookmarks/links for zero visual benefit.
- Every Firestore query, provider, and write path.
- The pre-existing audit-logging gaps (dispute resolution, review deletion, ticket resolution, and deletion-request resolution don't write to `admin_audit_logs`) — this is a functional/data-completeness question, not a visual one, and expanding it wasn't requested.
- `AdminMasterDetail`'s side-panel (wide web) / bottom-sheet (everything else) pattern, and every section's detail-panel content (`_UserListTile`, `_ArtisanListTile`, `_JobDetailSheet`, etc.) — these already used `context.colors`/`AdminPalette` correctly.
- Charts (`admin_charts.dart`), the sidebar, the top bar, the command palette, the notification bell — already dark-mode-aware and visually consistent; touching them wasn't warranted by anything found in the audit.

## Responsive behavior

- **Desktop (`kIsWeb && width ≥ 1100`)**: persistent left sidebar, unchanged.
- **Mobile/tablet (below that)**: `Drawer`-based sidebar, unchanged.
- **New**: the Dashboard's "Needs Attention" row and stat-card grid both reflow (1 column narrow → up to 6 on wide desktop, gated so non-web/narrow-web never gets more than 1–2 columns); the five browse tables switch from column-table to stacked cards below 640px content width, verified live at a 390px mobile viewport — no clipped/cramped columns, full data still visible.

## Dark-mode behavior

Verified live in both themes: Dashboard Home (new "Needs Attention" row, stat grid, charts), Audit Logs (rebuilt), Users table (both wide-table and narrow-card forms). All use `AdminPalette`'s existing bg0/bg1/bg2/card elevation ladder and border/text tiers — no new ad hoc colors were introduced; the only palette-adjacent additions were reusing `context.colors.warning`/`warningSurface` (already part of the app-wide Dark Mode audit) for the two fixed badges.

## Tests performed

- `flutter analyze` — 12 pre-existing issues (unrelated: one unused import, deprecated API usage, `use_build_context_synchronously` info-hints in `settings_screen.dart`/`bank_details_screen.dart`/`service_request_screen.dart`), zero new issues from this change.
- `flutter test` — all 85 tests pass, unchanged.
- `flutter build web --release` — builds cleanly.
- Live, real-account Playwright verification: Dashboard Home reorder (desktop light, desktop dark, mobile light) with real counts (25 users, 6 artisans, 1 pending artisan approval); Audit Logs new styling in light and dark, real entries (Artisan Approved, Beta Tester Changed, Job Deleted) with correct icons/colors/timestamps; Users table wide-desktop-dark (unmodified layout still correct) and narrow-mobile-card (new layout, all data present, Beta badge and pagination intact); Jobs table narrow-mobile-card (category, job ID, customer→artisan, status badge, date all present); tapping a user card on mobile correctly opens the same bottom-sheet detail panel with all actions (Profile/Activity/Suspend/Delete/Beta Tester toggle) present and reachable.
- **Not exercised**: actually triggering a destructive/mutating action (Suspend, Delete, Approve/Reject, resolve a dispute/ticket) against the live account, since none of those code paths were touched by this redesign — verified by reading the code (`onPressed`/`onTap` handlers are byte-identical to before) rather than by risking a real write to production-shaped data.

## Remaining issues / out of scope

- The pre-existing audit-log completeness gap (alert resolution, review deletion, ticket resolution, and deletion-request resolution aren't captured in the Audit Logs section) is unchanged. Flagged during the audit as a real, if minor, inconsistency — but it's a data/functionality question, not a visual-redesign one, so it wasn't addressed here.
- `_ArtisanApplicationCard`, `_VerificationReviewCard`, `_DisputeReviewCard`, and the other detail/review cards still use the app-wide `context.colors` token system rather than `AdminPalette` — this is a legitimate second theming system within admin, not a bug (both respond to dark mode correctly, independently), but a future pass could unify them onto one system for easier maintenance. Not attempted here since none of them showed an actual visual defect.
- The "Super Administrator" label (sidebar footer, Settings) is hardcoded text, not derived from any role field — there is no distinct admin-tier system in the codebase today. Noted during the audit; out of scope for a visual redesign.
