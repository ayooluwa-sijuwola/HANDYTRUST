# 09 — Screen-by-Screen Redesign: Customer & Artisan

All of `03`/`05`/`06`/`07`/`08` are settled — this is where their decisions land on actual screens. Covers the 43 screens confirmed in the Phase 1 recon, minus the two dead ones (`03-ia-navigation-journeys.md` §1.3) and the demo payment screen (gated out per `01.5` Track C, not redesigned).

## Scoping call, stated plainly

The brief's 12-point checklist (purpose, user goal, layout, components, interactions, navigation, loading/empty/error/success states, accessibility, animations, Firestore implications, security) applied literally and separately to all ~40 remaining screens would mean repeating the same boilerplate dozens of times — "uses `AppShadows.card`, `easeOutCubic`, owner-scoped Firestore read" doesn't need restating per screen when `02-design-system.md` and `04-firestore-architecture.md` already govern it universally. Real design-system practice documents cross-cutting behavior once, at the system level, and screen specs only call out what's *different* about that screen.

So: **§1 states the cross-cutting rules once** (they apply to every screen below by default). **§2 gives full 12-point specs to the 9 screens that are genuinely complex, high-stakes, or most changed by this program.** **§3 gives every other screen a concise "what changes and why" pass** — still complete, just not repeating what §1 already covers. **§4** is the dead-code/removal list.

---

## 1. Cross-cutting rules (apply to every screen unless a screen explicitly overrides one)

- **Loading**: skeleton states via `shimmer_loaders.dart` for lists/cards; a shared `ErrorStateView`/`EmptyStateView` (flagged as missing in `02-design-system.md` §6.4 — build these two components first, before touching individual screens, since nearly every screen below depends on them existing).
- **Error**: retry-affordance, never a dead end; network errors distinguished from "this data genuinely doesn't exist" (404-equivalent) with different copy.
- **Empty**: role- and context-specific copy, never a generic "Nothing here" — `06-escrow-wallet.md` §6 and `07-gps-flow.md` §5 already modeled this (distinct customer/artisan empty-state copy).
- **Accessibility**: no color-only status signaling (icon+color pairing always) — `02-design-system.md` §2.3's finding that `textTertiary`/`ratingGold` fail as text colors applies wherever those appear; audit each screen's actual usage during implementation, not assumed fixed by this doc.
- **Animations**: `AppAnimations.fast` for state toggles, `normal` for in-screen transitions, `page` for navigation, `slow`/`bounceCurve` reserved for genuine milestones (job completed, escrow released, arrival) — never routine UI.
- **Firestore/security**: every list/detail screen reads only what the signed-in user is a party to, per `04-firestore-architecture.md` §1's ownership convention — flagged individually below only where a screen's access pattern is non-obvious or the redesign changes it.
- **Currency**: every amount uses `AppTextStyles.currency` (tabular figures, `02-design-system.md` §3) — mechanical but easy to miss if unstated.

---

## 2. Full specs — the 9 screens this program changes most

### 2.1 Home (`home_screen.dart` — both `_CustomerHomeTab` and `ArtisanHomeTabContent`)
- **Purpose**: role-appropriate daily entry point — different jobs-to-be-done per role, sharing one shell.
- **User goal**: customer — "what's the state of my active jobs, and can I quickly start a new one?" Artisan — "what's waiting for my attention (jobs, verification, availability)?"
- **Layout**: unchanged structurally (greeting header, search/hero, active-jobs section, quick actions) — the redesign here is behavioral, not visual.
- **Key changes**:
  - **Remove the hidden long-press admin-PIN gesture** (`01-ux-audit.md` §3.1, `03-ia-navigation-journeys.md` §4.2) — replaced by a conditional "Admin Dashboard" entry in the Profile menu.
  - ~~**Fix the FAB's role-awareness**~~ — superseded by the nav rebuild (`02-design-system-v2.md` §9.3): no more center FAB. Customer's Explore tab gets an in-content "Post a Job" hero CTA; artisan's equivalent tab leads with Open Jobs Feed instead — resolved by removing the shared component, not by branching it.
  - Add a Wallet-summary teaser card for both roles (links to `/wallet`, `06-escrow-wallet.md` §6) — surfaces "money in motion" without requiring a nav trip.
  - Artisan home surfaces the "Verify Later" gate proactively (`01-ux-audit.md` §2.8) if applicable — a persistent banner, not just a blocked write.
- **Firestore**: unchanged read pattern (own jobs, own profile) — no new queries.
- **Security**: unchanged.

### 2.2 Service Request / Job Posting (`service_request_screen.dart`)
- **Purpose**: capture a job request completely enough to get good quotes.
- **User goal**: "describe what I need done, quickly, without missing something that delays quoting."
- **Key changes**: the one-time `Geolocator.getCurrentPosition()` capture (`01-ux-audit.md` §3.5) stays as-is — this is correctly scoped (job-site address, not live tracking) and shouldn't be touched by `07-gps-flow.md`'s live-tracking work, which is a different concern entirely. Add the milestone-breakdown *opt-in* toggle from `06-escrow-wallet.md` §2.3 as an advanced/optional step — default path stays single-payment, unchanged for the common case.
- **Loading/empty/error**: standard form validation states — nothing unusual found here.
- **Firestore**: creates one `jobs` doc, `status: requested` — unchanged.
- **Security**: unchanged — create restricted to the authenticated customer, per existing rules.

### 2.3 Artisan Discovery — List + Profile (`artisan_list_screen.dart`, `artisan_profile_screen.dart`, `browse_artisans_screen.dart`)
- **Purpose**: let a customer evaluate and choose an artisan with real information, not just a name and a star rating.
- **User goal**: "which of these artisans should I trust with this job?"
- **Key changes**: results now ranked by the corrected `05-trust-score.md` §3.1 algorithm (distance bucket → trustScore → rating → experience) — replacing today's `matchScore`-driven order. Every artisan card and profile gets the Trust Score Explainer entry point (`05` §6's bottom sheet) and the "Verify Later"/unverified badge made persistent on the card itself, not just profile detail (`01-ux-audit.md` §2.8's fix, now placed concretely).
- **Loading**: shimmer artisan-card skeletons (confirm this variant exists per `02-design-system.md` §6.2's coverage note).
- **Empty**: "No artisans found nearby yet" — distinct from a zero-result *search* (browse) vs. zero-*match* (job-linked list), since the causes and right next action differ (browse: widen category; job-linked: no fix action, this is a supply gap the customer can't solve).
- **Firestore**: `MatchingService.findMatches` query shape changes per `05-trust-score.md` §3.3 (likely geohash-prefix range instead of pure category+availability filter) — new composite index required, already flagged there.
- **Security**: unchanged — public read already correctly gated to approved+verified artisans.

### 2.4 Job Detail (`job_detail_screen.dart`) — the hub screen
Read directly for this doc: currently composes `JobProgressTracker` + `JobTimelineWidget` + `JobProgressTimeline` **all three simultaneously** on one screen — direct, concrete confirmation of `02-design-system.md` §6.2's flagged widget-naming/scope overlap ("three timeline-named widgets is a sign of organic growth without a single owner"). Also renders a quote inbox section, dispute countdown banner, and dispute thread section inline.
- **Purpose**: single source of truth for a job's entire lifecycle, for whichever party is viewing it.
- **User goal**: "what's the current state of this job, and what do I need to do next?"
- **Key changes**:
  - **Consolidate the three timeline widgets into one** — this screen is the concrete evidence the consolidation `02-design-system.md` flagged is overdue, not hypothetical.
  - Insert the `LiveEtaCard` (`07-gps-flow.md` §5) during the `onTheWay` window — inline in the progress section, not a new route.
  - Milestone-aware payment section (`06-escrow-wallet.md` §2) replacing the single `agreedAmount` display — show each milestone's status individually once multi-milestone jobs exist, single-row for the default single-milestone case (no visual change for the common path).
  - Add "Report an issue" action from this screen too, not only from Chat (`03-ia-navigation-journeys.md` §4.4's fix applies wherever a job is in view) — links to the richer report flow (`08-messaging-notifications.md` §3.6).
- **Loading/error**: already reasonable (`CircularProgressIndicator`/error text) — bring in line with the shared `ErrorStateView` from §1 rather than the current ad-hoc `Center(child: Text('Error: $e'))`.
- **Firestore**: unchanged core read (`jobStreamProvider`); adds a `liveLocation` single-doc listener (§2.4 above) and a `milestones` subcollection read once that ships.
- **Security**: unchanged party-scoped access; the new `liveLocation` read follows the same party-scoping already established.

### 2.5 Chat (`chat_screen.dart`)
- **Purpose**: negotiate and coordinate on a specific job.
- **User goal**: "talk to this artisan/customer about this job, and act on what we agree (price, appointment)."
- **Key changes**: typing indicator (`08` §3.1), `readAt` timestamp (§3.2), "Report an issue" app-bar action (§3.6, already an interim fix per `03` §4 — this is where the richer categorized version lands), voice-note enum/field reserved but not built (§3.5).
- **Loading/empty**: unchanged (message stream already handles this reasonably).
- **Firestore**: adds the `typing/{uid}` subdoc write (throttled/debounced per `08` §3.1) — new but cheap.
- **Security**: typing-indicator writes scoped to job-party + self, mirroring the `liveLocation` pattern.

### 2.6 My Chats (`my_chats_screen.dart`)
- **Key changes**: Archived filter tab (`08` §3.3), client-side thread-preview search (`08` §3.4's MVP scope — explicitly not full-text history search).
- **Firestore**: adds a per-user `archivedChats` read to filter the existing list — no change to the underlying `messages` query.

### 2.7 Open Jobs Feed (`open_jobs_feed_screen.dart`)
Read directly for this doc: currently has no visible messaging distinguishing a `pending_later`/unverified artisan's blocked-quoting state from a fully eligible one within the feed itself — confirms `01-ux-audit.md` §2.8 concretely on this specific screen, not just as a general claim.
- **Key changes**: persistent banner/disabled-quote-button state for unverified artisans (`03-ia-navigation-journeys.md` §3.4's journey gap, now placed on the exact screen it belongs on) — replacing silent rules-rejection as the only signal.
- **Firestore/security**: unchanged query and access pattern — this is a client-side messaging fix, not a rules change (the rules are already correctly restrictive; the gap was UI communication, not access control).

### 2.8 Verification Upload (`verification_upload_screen.dart`)
- **Key changes**: clearer distinction between the full-verification and "Verify Later" paths' *consequences* — today's screen presumably presents them as a binary choice without making the open-jobs-feed quoting gate explicit at the decision point itself; add that context inline so the artisan makes an informed choice (ties directly into fixing 2.7's gap at the source rather than only downstream).

### 2.9 Wallet (new — fully spec'd in `06-escrow-wallet.md` §6, cross-referenced here, not re-specified)

---

## 3. Concise pass — every other screen

Grouped by module. "No change" means the redesign program found nothing requiring it — stated explicitly rather than silently omitted, so it's clear these were considered, not skipped.

**Auth/Onboarding**: `splash_screen.dart`, `login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart`, `verify_email_screen.dart`, `role_selection_screen.dart`, `suspended_screen.dart` — no functional changes; visual polish only follows `02-design-system.md`'s token system, already largely in place per that doc's §2.1. `artisan_registration_screen.dart` gets one addition: surface the verification-path decision context from §2.8 above during registration, not just later at `/verification`. `phone_login_screen.dart` and `customer_registration_screen.dart` — see §4, not redesigned, decision pending.

**Jobs**: `all_jobs_screen.dart` — no structural change; ranking/filtering unaffected by this program's changes. `job_completion_screen.dart` — add milestone-selector if multi-milestone (`06` §2), otherwise unchanged.

**Payment**: `payment_screen.dart`/`payment_webview_screen.dart` — becomes milestone-aware per `06` §2 (pay a specific milestone, not always "the" job payment) once multi-milestone ships; unchanged for the default single-milestone case. `demo_escrow_screen.dart` — see §4.

**Review/Dispute/Support**: `review_screen.dart` — no change. `dispute_screen.dart` — gains the category step from `08` §3.6 when reached via the new "Report an issue" entry points; unchanged when reached directly. `contact_support_screen.dart` — no structural change; benefits from the new `support_reply` notification (`08` §4.3) closing a silent-resolution gap, which is a backend change, not a screen change.

**Artisan profile-building**: `portfolio_manager_screen.dart`, `portfolio_project_screen.dart`, `business_profile_screen.dart`, `bank_details_screen.dart`, `favorites_screen.dart` — no structural changes found necessary; `bank_details_screen.dart` gains one addition — a visible link/prompt from here when a payout is blocked for missing bank details (`06-escrow-wallet.md` §4 point 4's notification should deep-link straight here).

**Notifications/Settings/Profile**: `notifications_screen.dart` — extend to render the new reminder-class types (`08` §4) with visually distinct treatment from transactional ones (e.g., a "Reminder" tag) so they don't read as identically urgent. `settings_screen.dart` — gains the `/settings/notifications` entry point (`08` §5). `profile_screen.dart` — gains the Wallet row (`06` §6) and the conditional Admin entry (§2.1 above).

---

## 4. Dead code — not redesigned, flagged for a decision/removal instead

- `phone_login_screen.dart`, `customer_registration_screen.dart` — confirmed unreferenced anywhere (`03-ia-navigation-journeys.md` §1.3). Not touched by this redesign pending your call on whether phone auth is a real entry point.
- `demo_escrow_screen.dart` — stays functional in debug builds only, per `01.5` Track C's gating fix; not part of the production screen set this doc redesigns.

---

## 5. Sequencing note

None of §2's screen changes should start implementation before the hardening sprint's Track A/B (`01.5`) actually ship — several of these specs (milestone-aware payment display, trust-score-ranked discovery, live ETA card) render nonsensically against a backend that doesn't yet do what they assume. This mirrors the same dependency logic `03-ia-navigation-journeys.md` stated for itself at the start of this program.

---

**Next**: `10-admin-redesign.md` (web + mobile admin, including the `AdminPalette` refactor from `02-design-system.md` §7 and the Escrow Monitoring / Trust Score Management / Reports triage surfaces this and prior docs deferred to it), then the closing `11-production-roadmap.md`.
