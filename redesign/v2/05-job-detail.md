# V2 — Job Detail (Hub Screen)

Fifth screen, the most complex remaining. Read `job_detail_screen.dart` in full for this doc (both the portion covered in `09-screens-customer-artisan.md` §2.4 and the rest) — this screen already does a lot, and does most of it reasonably well; the v2 pass consolidates rather than reinvents.

**Evidence key**: 🟡 Extrapolated · 🔵 Inferred · 🟢 reused from already-evidenced components elsewhere in this v2 program · 🟠 real fix (not just visual).

---

## What the current screen already gets right (keep, just restyle)
- Conditional sections that only render when relevant (appointment scheduling only during `inChat`, dispute countdown only during `submitted`, quote inbox only for a customer viewing a `requested` job) — correct, information-dense-only-when-needed pattern, not a "show everything always" screen. Keep this discipline in v2.
- Three separate photo galleries — job photos (customer's original), **"Arrival Photos (Before Work)"** and completion photos — this is a real existing feature worth noting explicitly: there's already a photo-based arrival-proof concept, distinct from and complementary to the live GPS tracking in `07-gps-flow.md`. Keep both — a photo is evidence, live tracking is real-time reassurance; they serve different moments.
- "Hire Again" CTA on completed jobs (customer-only) — small, real feature, easy to lose in a reskin if not called out explicitly. Keep.
- Artisan mini-card (tap-through to profile) embedded in the job detail — keep, restyle to the borderless card language.

## 🟠 Real fix, confirmed by reading the file: consolidate three timeline widgets into one
`_JobDetailBody` renders `JobProgressTracker`, `JobTimelineWidget`, **and** `JobProgressTimeline` simultaneously, in sequence, on the same screen (confirmed directly in code, not inferred — `09-screens-customer-artisan.md` §2.4 flagged this as the concrete evidence for `02-design-system.md` §6.2's "organic growth, no single owner" finding). Three components rendering overlapping "what state is this job in" information back-to-back is confusing regardless of visual skin. **v2 fix**: one consolidated `JobLifecycleTimeline` component covering both the coarse job-status steps (requested → matched → escrowLocked → inProgress → completed) and the fine-grained `progressStage` sub-steps (accepted → onTheWay → workStarted → ... → completed) as a single continuous stepper, not three separate renderings of similar information.

---

## Layout (top to bottom)

1. **Page header** 🟡 — job category as the title (e.g. "AC Repair"), back button, `textPrimary`.
2. **`JobLifecycleTimeline`** — 🟠 consolidated (see above), restyled to the v2 borderless-card language.
3. **`LiveEtaCard`** — 🟢 reused unchanged from `07-gps-flow.md` §5, renders only during the `onTheWay` window, inline here exactly as that doc specified.
4. **Milestone-aware payment section** — 🟢 reused from `06-escrow-wallet.md` §2/§8: single-row "Agreed Amount" display for the default single-milestone case (visually unchanged from today), expanding to per-milestone status rows once multi-milestone jobs ship. Uses the same navy/green escrow-card language as the Wallet summary card (`v2/03-wallet.md`) when showing locked/pending escrow state — reinforces that this is the same trust surface, not a visually disconnected one.
5. **Quote inbox** (customer, `requested` status only) — 🟡 restyled list of quotes, borderless cards, contrast-safe status chips.
6. **Appointment section** (`inChat`) / **Confirmed appointment detail** — 🟡 restyled, unchanged logic.
7. **Photo galleries** (job / arrival / completion) — 🟡 restyled horizontal-scroll image strips, kept as three distinct sections per the "keep" note above.
8. **Artisan mini-card** — 🟡 restyled borderless card, tap-through to `v2/02-artisan-profile.md`.
9. **Dispute countdown banner** (`submitted`) / **Dispute thread** (`disputed`/`resolved`) — 🟡 restyled; dispute-related surfaces use `error`/warning tones, never navy (navy stays reserved for escrow-trust per `v2/03`'s decision log) or green (green stays reserved for success/verified/trust signals) — a dispute is neither.
10. **Action buttons** (context-dependent: confirm completion, raise dispute, submit completion, etc.) + **"Report an issue"** — 🟠 the report action is a real addition, not previously on this screen: `03-ia-navigation-journeys.md` §4.4 flagged that job detail (not just chat) should have a "Report an issue" entry point linking to the richer categorized report flow (`08-messaging-notifications.md` §3.6). Added here as a secondary action alongside the primary status-appropriate button.
11. **"Hire Again"** (completed, customer-only) — 🟡 restyled, kept.

## Component hierarchy
- `JobDetailScreen`
  - `PageHeader`
  - `JobLifecycleTimeline` — 🟠 new consolidated component, replaces 3
  - `LiveEtaCard` — 🟢 from `07-gps-flow.md` §5
  - `MilestonePaymentSection` — 🟢 from `06-escrow-wallet.md` §2
  - `QuoteInboxSection` — 🟡 restyled
  - `AppointmentSection` — 🟡 restyled
  - `PhotoGallerySection` × 3 — 🟡 restyled
  - `ArtisanMiniCard` — 🟡 restyled
  - `DisputeBanner` / `DisputeThreadSection` — 🟡 restyled
  - `ActionButtonRow` (primary action + "Report an issue") — 🟠 report action added
  - `HireAgainButton` — 🟡 restyled, kept

## Interactions
Unchanged from the current implementation's logic (accept quote, propose/confirm appointment, view photo full-screen, tap artisan card, confirm completion, raise dispute) — this is a visual/consolidation pass, not a workflow rewrite, except for the one addition: tap "Report an issue" → the categorized report flow (`08-messaging-notifications.md` §3.6), same entry point the chat screen already got.

## Animations
🔵 Inferred: the consolidated timeline animates step transitions (a step filling in when status advances) rather than the screen just re-rendering — this is a genuine upgrade over having three separate static-looking widgets, and a natural place for a small celebratory motion (`AppAnimations.slow`/`bounceCurve`) when a step completes, consistent with `02-design-system.md` §4's reservation of that motion tier for real milestones.

## Loading state
Skeleton for the timeline + header while `jobStreamProvider` resolves — matches the current implementation's existing `CircularProgressIndicator`, upgraded to a shaped skeleton per this program's shimmer convention.

## Empty state
N/A — this screen only renders for a specific, existing job; there's no "empty" version of a single-item detail screen.

## Error state
Job not found / stream error: the current code already distinguishes these (`job == null` vs. stream error) — keep that distinction, restyle to the shared `ErrorStateView`.

## Success state
Status-advancing actions (confirm completion, escrow release) show the same celebratory micro-animation on the timeline noted above, plus a snackbar confirming the action — not a separate full-screen success state, since the user stays on this screen to see the result reflected in the timeline itself.

## Accessibility
Every status/dispute chip on this screen follows the standing rule from `02-design-system-v2.md` §11 (color as icon/fill, never as small text). The consolidated timeline needs each step to have an accessible label describing its state (completed/current/upcoming), not rely on color/position alone — this matters more here than almost anywhere else in the app, since the timeline *is* the primary way a user understands "where is my job right now."

## Responsive behaviour
🔵 Inferred: photo galleries' horizontal scroll becomes a wrapping grid on wide viewports rather than staying a fixed-height horizontal strip; everything else stays single-column, consistent with every other screen in this pass (a detail screen doesn't benefit from multi-column layout at any width this app targets).

## Firestore implications
Unchanged core read (`jobStreamProvider`) plus the two additions already specified elsewhere and just being placed on this screen: the `liveLocation` single-doc listener (`07-gps-flow.md` §3) and the `milestones` subcollection read (`06-escrow-wallet.md` §2) once each ships. No new reads introduced by this doc itself.

## Cloud Function implications
None new from this screen directly — it's a composition of already-specified data sources.

## Notification triggers
None originate here — this is where notifications about a job *land* (tapping a job-status notification opens this screen), not where they're generated.

## Security considerations
Unchanged — party-scoped job access, already correctly implemented; the new "Report an issue" action writes to the `reports` collection under the same ownership pattern already specified in `08-messaging-notifications.md` §3.6.

---

## Decision log
- **Consolidating three timeline widgets into one** is the single largest structural change on this screen — flagged clearly rather than folded quietly into "restyled," since it's a real component-architecture decision (one new `JobLifecycleTimeline` replacing `JobProgressTracker`, `JobTimelineWidget`, and `JobProgressTimeline`), not just new colors on the existing three.
- **Navy reserved for escrow-trust, never used for disputes** — disputes get `error`/warning tones instead, keeping the "navy = this is the serious, trust-protecting part" meaning from `v2/03-wallet.md`'s decision log consistent; a dispute is serious but isn't reassuring, so it shouldn't borrow the same visual register as "your money is protected."
