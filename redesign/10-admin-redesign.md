# 10 — Admin Web + Mobile Redesign

Closes every deferred admin surface from prior phases: the `AdminPalette` refactor (`02-design-system.md` §7), Escrow Monitoring (`06-escrow-wallet.md` §4/§6), Trust Score Management and the anomaly queue (`05-trust-score.md` §4), Reports triage (`08-messaging-notifications.md` §3.6), and Role Management (`04-firestore-architecture.md` §5's `grantAdmin` flow). Also resolves — and sharpens — the pagination question `01-ux-audit.md` §3.6 left open.

---

## 1. What exists today, precisely

12 sections (`admin_sidebar.dart`, read directly): Dashboard, Users, Artisans, Jobs, Verifications, Disputes, Reviews, Support Tickets, Deletion Requests, Audit Logs, Analytics, Settings — a 248px fixed sidebar, desktop-oriented, inside a `ShellRoute` (`03-ia-navigation-journeys.md` §1.1 already praised this shell pattern; it's not being replaced).

**Finding upgraded from "unconfirmed" to "confirmed"**: `01-ux-audit.md` §3.6 flagged admin table pagination as unverified. Reading `admin_data_table.dart` directly for this doc: `AdminDataTable` paginates a `List<T> rows` parameter **already fully materialized in memory** — `start = _page * pageSize` is index math over a list that's already there, not a Firestore cursor (`startAfter`) driving the actual query. So the *UI* shows 10 rows at a time, but the *read* already pulled the full collection into memory first. This means the audit's "at scale this becomes a real cost/latency problem" was correct, and understated — it's not a risk to watch for, it's already true today, just currently invisible at low data volume. Fixed in §5.

---

## 2. Brief's admin feature list vs. what exists

| Brief section | Status |
|---|---|
| Dashboard | ✅ exists |
| Analytics | ✅ exists |
| Verification Queue | ✅ exists (`Verifications`) |
| Dispute Center | ✅ exists (`Disputes`) |
| Reports | ❌ no section — and until `08-messaging-notifications.md` §3.6, no underlying `reports` collection existed to have a section for |
| User Management | ✅ exists (`Users`) |
| Job Monitoring | ✅ exists (`Jobs`) |
| **Escrow Monitoring** | ❌ absent — directly compounds Critical Finding 1.1; there's no admin visibility into `escrow_releases` state at all today |
| Support Tickets | ✅ exists |
| **Trust Score Management** | ⚠️ partial — trust score is visible per-artisan in the `Artisans` directory, but no dedicated management/override/anomaly view exists |
| Notifications | ❌ no admin-facing notification management (broadcast, template review) |
| Content Moderation | ⚠️ partial — job deletion exists (`Jobs` section, per `README.md`'s feature list) and review deletion exists (`Reviews`), but there's no unified moderation queue across job descriptions/portfolio content/chat reports |
| **Security Logs** | ❌ absent, and distinct from what exists — `admin_audit_logs` tracks *admin actions* (who approved what), not *security events* (failed logins, suspicious access patterns, anomalous admin-claim usage) |
| Audit Trail | ✅ exists (`Audit Logs`) |
| **Role Management** | ❌ absent as a section — granting admin today is a manual, three-step, partly-CLI process (`README.md`'s own install instructions, formalized as a gap in `04-firestore-architecture.md` §5) |

Five real gaps, not cosmetic ones: Reports, Escrow Monitoring, Trust Score Management, Security Logs, Role Management.

---

## 3. `AdminPalette` → `AdminColorsExtension` (executing `02-design-system.md` §7's decision)

That doc settled the *principle* (keep the deliberate dark-SaaS "Ops" feel, stop hand-rolling it independently of the brand tokens) — here's the concrete refactor:

```dart
class AdminColorsExtension extends ThemeExtension<AdminColorsExtension> {
  // Derived from brand tokens — NOT re-declared:
  final Color success;   // = AppColors.primary (was AdminPalette.green, a re-typed #22C55E)
  final Color danger;    // = AppColors.error
  final Color warn;      // = AppColors.warning
  final Color info;      // = AppColors.accent

  // Genuinely admin-exclusive — no consumer-app equivalent exists, stay as new tokens:
  final Color purple;    // chart categorical color
  final Color indigo;
  final Color pink;
  final Color cyan;

  // Structural (bg0/bg1/bg2/card/border/text*) — these stay admin-specific by
  // design (the dark-SaaS density the doc's §7 explicitly kept), but the
  // *file* moves from a hand-rolled standalone class into a proper
  // ThemeExtension, consistent with how AppColorsExtension already works,
  // so it participates in the same lerp()/context-getter pattern instead
  // of its own bespoke `.of(ThemeMode)` factory.
}
```
The practical effect: a future brand color change (rebrand, contrast fix) updates in one place and both the consumer app and admin dashboard's shared semantics move together, while admin keeps its distinct structural/density identity. This is a mechanical refactor, not a visual redesign — admin should look the same after this change, just be built on a foundation that can't silently drift again.

---

## 4. Server-side pagination fix (executing the confirmed §1 finding)

`AdminDataTable`'s pagination UI stays — it's a reasonable component. What changes is what feeds it: replace the full-collection `.get()`/stream (implied by a fully-materialized `rows` list) with cursor-based queries (`startAfter(lastDocument).limit(pageSize)`), re-fetching a page from Firestore on next/previous rather than slicing an in-memory list. This needs each admin list screen (`Users`, `Artisans`, `Jobs`, etc.) to hold a cursor stack, not just a page index — a real but contained change, scoped to the data-fetching layer, not the table UI itself. **Sequence this before any new admin section is added** (§5-§9 below) so new sections are built against the corrected pattern from the start rather than replicating the same mistake five more times.

---

## 5. New section: Escrow Monitoring

Full spec — this is the direct admin-facing counterpart to Critical Finding 1.1's fix (`06-escrow-wallet.md` §4).
- **Purpose**: give admin visibility into every payout in flight, and a queue for the ones that need human intervention.
- **User goal** (admin): "is money moving correctly, and which artisans are stuck waiting to be paid?"
- **Layout**: a stat row (total in escrow, pending payouts, failed/blocked count — reusing `AdminStatCard`) above a cursor-paginated table (§4) of `escrow_releases`, filterable by status.
- **Components**: `AdminDataTable<EscrowRelease>` with a status column using the corrected escrow color tokens (`02-design-system.md` §2.2 Gap 1's dark-mode-complete `escrowLocked`/`Pending`/`Released`/`Failed` set).
- **Interactions**: a blocked release row expands to show `failureReason` and a manual "retry payout" action (re-triggers the Cloud Function from `06` §4) — admin should never need to hand-edit `escrow_releases.status` directly, per that doc's rules note that client `update` should be structurally impossible post-creation.
- **Firestore**: reads `escrow_releases` via the new `status ASC, createdAt ASC` index (`04-firestore-architecture.md` §2) — already flagged as needed there, this section is its consumer.
- **Security**: admin-read already correct per existing rules; the retry action should be a Cloud Functions callable (admin-gated), not a direct Firestore write, consistent with §keeping this collection Function-owned post-creation.

## 6. New section: Trust Score Management

Full spec — closes `05-trust-score.md` §4's anomaly queue and gives the "management" half of the brief's ask (today's per-artisan visibility is read-only).
- **Purpose**: surface trust-and-safety anomalies for human review, and give admin a documented override path when needed.
- **User goal**: "which artisans need a manual trust/safety look, and why?"
- **Layout**: two tabs — **Anomalies** (the flagged customer↔artisan repeat-pairing and review-velocity signals from `05` §4, queue-style, each with a dismiss/escalate action) and **Score History** (searchable by artisan, rendering the new `scoreHistory` subcollection from `04-firestore-architecture.md` §8).
- **Interactions**: an anomaly entry links directly to the involved jobs/reviews for context; "escalate" creates a `disputes`-adjacent admin note rather than unilaterally changing a score — **a human decides, the system only surfaces**, exactly as `05` §4 specified.
- **Firestore**: reads the anomaly signals (computed by a scheduled function, per `05`'s design) and `artisans/{uid}/scoreHistory`.
- **Security**: admin-only, read-heavy; any manual score adjustment (rare, exceptional) should itself write a `scoreHistory` entry with an admin-attributed reason — the override path shouldn't be exempt from the audit trail it's meant to consult.

## 7. New section: Reports (Content Moderation)

- **Purpose**: triage queue for the `reports` collection (`08-messaging-notifications.md` §3.6).
- **Layout/interactions**: category-filterable queue, each report showing its evidence and a resolve/escalate-to-dispute action — escalation should create a real `disputes` doc referencing the report, not duplicate the report as a second parallel record.
- Folds in job/portfolio content moderation as additional filters within the same queue rather than a separate section — one moderation surface, multiple content types, consistent with keeping the admin IA from sprawling into a section per content type.

## 8. New section: Role Management

- **Purpose**: replace the manual three-step admin-grant process with the single-flow `grantAdmin` callable already designed in `04-firestore-architecture.md` §5.
- **Layout**: a simple searchable user list with a "Grant Admin" / "Revoke Admin" action, each requiring a confirmation step (this is one of the highest-blast-radius actions in the entire app — granting admin — and deserves explicit friction, not a one-tap toggle).
- **Security**: the callable itself already checks the caller's own admin status (`04` §5); this section is purely the UI for a function that already exists in spec — no new security design needed, just surfacing it instead of leaving it CLI-only.

## 9. Security Logs — scoped honestly

Distinct from `Audit Logs` (admin actions) — this would track authentication anomalies (repeated failed logins, sign-ins from new devices/locations, admin-claim usage patterns). **This is the one brief-requested section this program can't fully spec without new infrastructure** (Firebase Auth doesn't natively expose a queryable login-event log to Firestore without additional instrumentation — e.g., a Cloud Function on Auth trigger writing security events, or exporting Firebase Auth logs to BigQuery). Flagged honestly as a larger infra addition for `11-production-roadmap.md` to size, rather than hand-waved as a simple UI section like the others above.

---

## 10. Mobile admin — a real redesign, not a responsive shrink

The brief asks for a distinct mobile admin experience, and the honest UX case for that isn't "the desktop sidebar doesn't fit a phone screen" — it's that **the mobile admin use case is genuinely different**. Desktop admin is where deep work happens (working through the verification queue, analyzing dashboards, reconciling escrow). Mobile admin is realistically used for on-the-go triage: approving a straightforward verification, resolving a support ticket, checking whether an alert needs urgent attention — quick, bounded actions, not deep sessions.

**Design principle**: don't make `AdminDataTable` responsive down to phone width (a dense data table is a poor mobile pattern regardless of how well it reflows) — build a **card-based, action-first mobile admin view** for the small set of sections that genuinely benefit from on-the-go access:
- **Priority for mobile**: Verification Queue, Disputes, Support Tickets, Escrow Monitoring's failed/blocked queue, and a push-notification-driven alert feed (new — admin should be *pushed* to when something urgent needs attention, not expected to poll a dashboard) — these are the bounded, quick-decision sections.
- **Explicitly not mobile-optimized**: Analytics, Audit Logs, full Jobs/Users tables — these are deep-work surfaces that stay desktop-primary; the mobile app should still let an admin *reach* them (read-only, scrollable, not reformatted into cards) rather than omit them, but shouldn't be designed around making them comfortable on a phone.
- **Navigation**: bottom nav (4-5 slots: Alerts, Verification, Disputes/Reports, Escrow, More) replacing the sidebar — same shell-persistence principle as the existing `AdminShell`/`ShellRoute` pattern (`03-ia-navigation-journeys.md` §1.1), just a mobile-appropriate chrome, not a different architecture.
- **Same Flutter codebase, not a separate app** — the existing app already targets six platforms (`README.md`'s Technology Stack); this is a responsive layout branch within the existing admin routes, gated on screen width/platform, not a new project.

---

## 11. Rollout sequencing

1. §4 (server-side pagination) first — every new section below should be built against the corrected data-fetching pattern, not the confirmed-broken one.
2. §5 (Escrow Monitoring) next, timed with `06-escrow-wallet.md`'s payout automation shipping — an admin queue for a system that doesn't exist yet has nothing to show.
3. §6 (Trust Score Management) and §7 (Reports) can ship in parallel once `05`'s ranking fix and `08`'s reports collection exist respectively.
4. §8 (Role Management) is independent and cheap — can ship anytime, no reason to wait.
5. §9 (Security Logs) is the one genuinely open-ended item — scope it properly in `11-production-roadmap.md` rather than rushing a shallow version.
6. §10 (mobile admin) last — it's a presentation-layer addition over sections that need to exist and be stable first; building a mobile view of an admin section that's still changing underneath it is wasted effort.

---

**Next**: `11-production-roadmap.md` — the closing synthesis, now genuinely informed by nine prior docs' concrete findings rather than a guess made before any of this was known.
