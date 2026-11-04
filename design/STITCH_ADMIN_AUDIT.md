# Stitch Admin Audit — Group 10

Ops/admin redesign — no `JobService`/`WorkflowGateService`/payment/escrow/Paystack/Trust Score logic touched. Everything below was verified by reading the actual 6,810-line `admin_dashboard_screen.dart` plus its four supporting files (`admin_widgets.dart`, `admin_data_table.dart`, `admin_sidebar.dart`, `admin_charts.dart`, `admin_palette.dart`), not assumed from the task description.

**Headline finding, stated up front**: this is not a bare admin surface needing to be built. It's an already mature, production-quality operations dashboard — real search/filter/sort, real approve/reject/resolve/suspend actions, real audit logging on every mutation, real per-tab error/empty states. The actual gaps found were narrow and specific, not structural.

---

## Current admin capabilities — verified from source

### Dashboard home
Already had 6 real stat cards (Total Users, Total Artisans, Active Jobs, Completed Jobs, Pending Verifications, Average Rating — all computed from live data with week-over-week trend indicators, all tap-to-navigate), a Jobs Overview chart, a Users donut, a Top Categories card, a Recent Activity feed (sourced from the real admin audit log), a Pending Actions card (artisan approvals/verifications/support tickets/open disputes, each a real live count), and a Platform Health card (completion rate, verification rate, response time, dispute rate, each with a 7-day sparkline). Genuinely comprehensive.

**Gap (Task 2)**: **Escrow Volume** was the one overview figure Task 2 named that didn't exist. **Fixed** — added as a 7th stat card, computed from `PaymentModel.status == escrowHeld` summed across a new admin-wide `_allPaymentsProvider` (real data; `isAdmin()` already grants full `/payments` read per `firestore.rules`, no rule change needed for this part).

### Artisan verification (Task 3)
`_VerificationCenterTab`/`_VerificationReviewCard`: real pending-list, full artisan info + submitted documents + current verification/trust state displayed, real `approve()`/`reject()` calls through `verificationServiceProvider`, a reason-required rejection dialog, and an `AdminAuditService` log entry written on every action. **No gap found** — already complete, not touched.

### Dispute management (Task 4)
`_DisputesTab`/`_DisputeReviewCard`: real open-disputes list, job/customer/artisan context shown, resolve-with-resolution-text and dismiss actions both wired to `disputeServiceProvider.resolveDispute`, real error handling. **No gap found** — already complete, not touched.

### User management (Task 5)
`_UsersTab`/`_UserListTile`: search by name/email (already supported, confirmed working), filter by role/suspended status, sortable table (name/role/status/joined), master-detail view, and a real suspend/reactivate action with a confirmation dialog and audit logging. **No gap found** — already complete, not touched.

### Design system usage (Task 7)
`admin_palette.dart` already does exactly what this task asked for, not something introduced here: its own doc comment states the 4 semantic accents (green/red/amber/blue) are derived directly from `AppColors` ("single source of truth... rather than re-typing the same hex values, so a future brand-color change can't silently fail to propagate here") — only 4 genuinely admin-exclusive accents (purple/indigo/pink/cyan, used for chart variety) have no consumer-app equivalent and stay separate. This already satisfies "share the design foundation, don't create a separate theme" — verified, not re-litigated.

---

## Task 6 — admin_alerts, verified precisely as asked

Grepped the entire codebase for `admin_alerts`. Found it written in exactly two places in `functions/index.js` (`reconcileStuckEscrowReleases`, a daily cron catching stuck escrow releases; `_alertAdminDispute`, fired whenever a job enters `disputed`) — both via the Admin SDK, which bypasses Firestore rules entirely, so the writes always worked. **Confirmed: zero references to `admin_alerts` anywhere in `firestore.rules`** — no `match` block at all. Firestore is default-deny: with no matching rule, the collection was **completely unreadable from the app**, for anyone, including admins. Also confirmed: no provider, no screen section anywhere referenced this collection — there was no attempt to read it that was merely broken; nothing tried at all.

**Fixed**: added a `match /admin_alerts/{alertId}` rule (`allow read: if isAdmin()`, `allow update` scoped to exactly `resolved`/`resolvedAt`/`resolvedBy` — the one field both writers already set to `false`, so this exposes flipping it, not a new business rule — `allow create/delete: if false`, Cloud-Functions-only, matching the existing `auditLogs` collection's pattern in the same file). Added a new "Operational Alerts" card to the dashboard home tab — the first and only surface that reads this collection — showing each alert's type-specific description and a "Resolve" action.

---

## Backend gaps discovered

- Escrow Volume and admin_alerts (above) — both closed within this pass, using only real, already-existing data and an additive rules change.
- No other missing backend support was found for Tasks 3–5; every action they asked to expose already existed and already worked.
