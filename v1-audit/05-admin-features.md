# Part 5 — Admin Features

**Scope note, stated honestly**: `admin_dashboard_screen.dart` is roughly 5,000 lines — the largest single file in the codebase by a wide margin. This part is built from the section list (`admin_sidebar.dart`'s `AdminSection` enum), confirmed action-handler function signatures (grepped directly, not read line-by-line for every section), and the specific findings already verified in earlier work on this codebase (pagination behavior, the color-system refactor). Where a capability's exact behavior wasn't read in full, that's stated rather than assumed.

## Access and shell
Reachable at `/admin/*`, wrapped in a persistent `ShellRoute` (`AdminShell`) so the sidebar/chrome stays mounted across section switches rather than remounting on every click — confirmed in `router.dart`. Gated by the router's redirect on the resolved admin custom-claim state, independently of the Firestore-doc-based `isAdmin()` check the rules layer uses (two separate admin-authorization mechanisms exist — see Part 12 and Part 20). Discoverable in the UI via a conditional "Admin Dashboard" row in the Profile menu (see Part 2's note on the removed hidden-gesture predecessor of this).

## The 12 sections (`AdminSection` enum, confirmed directly)

| Section | Confirmed real actions | Notes |
|---|---|---|
| **Dashboard** | — | Stat cards + charts (`admin_charts.dart`, uses `fl_chart`) |
| **Users** | `_deleteUser()` (confirmed, line 3623) | Also implies suspend/reactivate per the collection's `accountStatus` field, though the exact handler wasn't individually grepped |
| **Artisans** | — | Searchable/filterable directory; trust score, rating, verification status visible per row |
| **Jobs** | `_deleteJob()` (confirmed, line 5166) | Full job list with status and an explicit "accepted by" indicator |
| **Verifications** | `_approve()`, `_reject()` (confirmed, lines 2851/2872) | Reviews pending selfie/ID submissions |
| **Disputes** | `_resolve({required bool dismiss})` (confirmed, line 3140) | The `dismiss` parameter confirms two distinct resolution outcomes exist, not just one |
| **Reviews** | `_delete()` (confirmed, line 4772) | Deleting a review presumably triggers the rating-changed Cloud Function trigger to recompute the artisan's trust score, since that trigger fires on any `rating`/`totalRatings` change to the artisans doc — not independently re-verified for this specific delete path |
| **Support** | — | Ticket list, presumed resolve action (ticket model confirmed to have a `resolveTicket`-style method in `SupportTicketService`, per Part 14) |
| **Deletion Requests** | — | Account-deletion request queue |
| **Audit Logs** | — | Reads `admin_audit_logs` |
| **Analytics** | — | Aggregate stats/charts |
| **Settings** | — | Admin-specific settings |

## Verified cross-cutting findings

- **Pagination is client-side only.** `AdminDataTable<T>`'s pagination (confirmed by direct reading of `admin_data_table.dart`) slices an already-fully-materialized `List<T> rows` by index math — the underlying Firestore read has already pulled the entire collection into memory before the UI shows "page 1." This is real today, at whatever data volume currently exists, not a future risk.
- **Color system**: `AdminPalette` previously hand-typed 4 accent colors (`green`/`red`/`amber`/`blue`) as raw hex literals independent of the consumer app's `AppColors`. As of the most recent work on this codebase, those 4 accessors derive directly from `AppColors.primary`/`error`/`warning`/`accent` instead — verified byte-identical values, zero visual change, eliminates a future-drift risk. The 4 genuinely admin-exclusive accents (purple/indigo/pink/cyan, used for chart categorical coloring) remain independent hex constants, since no consumer-app equivalent exists for them.
- **Admin-only Cloud Functions**: `adminDeleteUser` (disables the Firebase Auth account — the client SDK cannot do this even with Firestore delete rights) and `onAdminGranted`/`onAdminRevoked` (sync the `/admins/{uid}` Firestore doc to the Auth custom claim automatically on create/delete of that doc).

## Not found / not confirmed
- No dedicated "Escrow Monitoring" section — the `escrow_releases` collection (Part 8) has no admin UI reading it; the most recent Cloud Functions work added a reconciliation sweep that writes to `admin_alerts` on a stuck release, but nothing in the admin screens was found consuming that alert type specifically.
- No dedicated "Trust Score Management"/anomaly-review section — trust score is visible per-artisan in the Artisans directory row, not as its own management surface.
- No "Reports" section distinct from Disputes/Reviews — no `reports` collection was found anywhere in `firestore.rules` or any service.
- No "Ban" as a distinct action from suspend/delete — `accountStatus`-based suspension and outright user deletion are the two account-restriction mechanisms found; no separate "ban" concept.
- A dedicated mobile-optimized admin experience does not exist — the admin section is the same desktop-oriented (248px fixed sidebar) layout regardless of screen size, confirmed by the shell's structure in `router.dart`/`admin_sidebar.dart`.
