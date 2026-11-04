# Stitch Build Order

Sequencing for the redesign, built on the decisions recorded in `design/STITCH_IMPLEMENTATION_AUDIT.md`. Nothing here has been implemented yet — this is Phase 2, planning only. Two screens (Job Details, Artisan Dashboard) are excluded from this order until their Stitch mockups arrive; every other group can proceed.

Ground rule carried through every group below, not repeated per-item: **screens read workflow state from `WorkflowGateService`, execute actions through the existing services/providers, and never re-derive `agreementStatus`/`jobStatus`/payment conditions locally.** Where a group's screens don't touch workflow at all (auth, wallet, notifications), this rule is inapplicable and isn't mentioned again.

---

## 1. Design system

**Why first**: every other group instantiates this. Building screen-by-screen before this exists means redoing visual work twice.

- **Colors**: extract a token set from the winning variants — Trust Green stays the primary accent (it's already the existing brand color and every Stitch variant kept a green accent somewhere), dark navy becomes a new secondary/surface color for the cards that want it (TrustScore card, dark Wallet variant reference — even though that exact Wallet variant lost, the navy token is still needed for the TrustScore card that won). Update `lib/theme/app_design_system.dart` tokens; do not introduce ad-hoc hex values in screen files.
- **Typography**: Stitch's headlines are heavier/larger than the current app's (`My Bookings`, `Find your expert helper` — bold, tight tracking, ~28-32px). Extend the existing type scale with a heavier display weight rather than replacing body/caption styles, which look compatible with what's already there.
- **Buttons**: two new shapes recur across every screen — a solid black/near-black pill-shaped primary button (distinct from the current Trust Green primary) and a bordered secondary button. Decide whether black-pill becomes a second primary variant or is reserved for specific high-commitment actions (Lock Funds in Escrow, Post Job, Book Now) — recommend the latter, so Trust Green stays the everyday primary and black marks "this is a commitment" actions, matching how Stitch actually used it (never on routine navigation).
- **Cards**: the Stitch card silhouette (photo hero + floating rating badge, or white card with hairline divider between header and body) is a new pattern on top of the existing `appCardDecoration()` — extend, don't replace, so `WorkflowStatusCard` and other existing card consumers keep working.
- **Spacing**: Stitch screens run slightly more generous vertical rhythm than the current app. Capture as an additive spacing token, not a global multiplier.
- **Reusable components to build here, once, for every later group to consume**:
  - `ArtisanCard` (photo hero, floating rating badge, verified pill, rate, arrow button) — replaces ad-hoc artisan tiles in Home, Browse Artisans, Artisan List, Open Jobs Feed
  - `JobBookingCard` (status badge, date, artisan avatar, price, dual action buttons) — for My Bookings
  - `TrustScoreCard` (percentile + sub-score breakdown) — new component, blocked on the backend work in Group 4 below for real data, but the UI shell can be built now against placeholder-shaped (not placeholder-value) data
  - Pill-tab selector (Active/Completed/Drafts style) — generic enough to reuse wherever segmented filters appear

**Blocking**: nothing. Do this first.

---

## 2. Authentication

**Why here**: low workflow risk (no `WorkflowGateService` interaction at all — auth screens sit entirely outside job lifecycle), and it's the first thing every user sees, so it's a good place to prove the new design system actually holds up before committing to it everywhere else.

- Login, Signup, Forgot Password, Verify Email, Role Selection, Artisan Registration
- No Stitch mockups were supplied for auth screens in this batch — flag if more are coming, otherwise these get restyled with Group 1's tokens directly (colors/type/buttons/cards) with no layout invention, since "no visual design changes beyond what Stitch specifies" is still the standing rule from the workflow-stabilization phase.
- Resolve the two known-dead screens (`phone_login_screen.dart`, `customer_registration_screen.dart`) before or during this group — carrying dead code into a redesign pass compounds confusion later. Flag to the user rather than silently deleting.

**Blocking**: Group 1.

---

## 3. Customer experience

- **Home / Explore** — "Find your expert helper" variant (per audit decision), consumes `ArtisanCard` from Group 1
- **Browse Artisans**, **Artisan List (job-linked)** — same `ArtisanCard`, no Stitch-specific mockup supplied but visually identical component reuse means minimal new work
- **My Bookings** — `JobBookingCard`, dark-pill tab treatment, tab label becomes "My Tasks" per the audit decision; **status badges on each card must come from `WorkflowGateService.describeStep(...).phase`**, not be hand-written per card — this is the one place in this screen where the "don't manually check job status" rule bites, since the Stitch mockup shows static-looking badge text ("In Progress," "Awaiting Artisan") that needs to actually be computed
- **Favorites** — no dedicated mockup, restyle with Group 1 tokens
- **Recent Activity** — new screen (per audit, no current equivalent). Sequenced last within this group since it needs the view-history backend work from Group 4/Phase 5 territory to show real "Recently Viewed" data; build the UI shell first, wire real data once that lands

**Blocking**: Group 1. My Bookings additionally blocked on nothing new — `WorkflowGateService.describeStep` already exists and is exactly the right source for its badges.

---

## 4. Artisan experience

- **Dashboard** — no Stitch mockup exists for this screen (confirmed after a follow-up screenshot turned out to be a duplicate of "Jobs matched for you"). Restyle the existing layout with Group 1's tokens directly — no layout invention, same treatment as auth/Portfolio/Notifications below.
- **Open Jobs Feed** — "Find Jobs" variant (per audit decision); the eligibility-gating logic (approval/verification live-check, disabled quote button with reason) stays wired to `artisanProfileProvider` exactly as it is today — this is real business logic, not styling, and doesn't move into the widget tree
- **Quote Submission** (`_SubmitQuoteSheet`) — no distinct mockup, restyle in place as a modal sheet
- **Portfolio**, **Business Profile / Bank Details / Verification** — no mockups supplied, lower priority, restyle with Group 1 tokens whenever convenient
- **TrustScoreCard backend**: the percentile rank and Craftsmanship/Punctuality sub-scores that the winning Artisan Profile variant needs don't exist in `trust_score_service.dart` yet. This is real computation work (aggregating existing review/completion data into two sub-scores plus a percentile against other artisans), sequenced here because Artisan Profile (Group 5, since customers view it) depends on it. Document the required fields even if this group only gets to the UI shell.

**Blocking**: Group 1.

---

## 5. Job workflow screens

- **Job Details** — held, pending Stitch mockup. This is the app's most workflow-dense screen (`WorkflowGateService`, `WorkflowStatusCard`, `WorkflowTimeline`, `_AgreementSection`, `_AppointmentSection` all converge here) — deliberately not attempted from a guess.
- **Artisan Profile (customer-facing)** — TrustScore variant (per audit decision); real Craftsmanship/Punctuality/percentile data depends on Group 4's backend work landing first, so this group can build the visual shell and wire everything except those three fields immediately, then complete the wiring once Group 4 finishes.
- **Post a New Job** — restyle directly (category chips, title, description, schedule, budget map 1:1 to `jobRequestNotifierProvider` fields already). The photo-unlock paywall is explicitly **not** built here — no backend exists for it (see audit) — the photo picker ships without the paywall UI, and the paywall is logged as a Phase 5 backlog item requiring product sign-off on pricing before any UI is worth building.

**Blocking**: Group 1, partially Group 4 (Artisan Profile's score fields). Job Details additionally blocked on its missing mockup.

---

## 6. Chat

- Sticky job-summary header (title, `WorkflowGateService`-sourced status chip, price, expandable "View Job Details") and the "Proposed Schedule" inline message card are the two new components; both are presentation-only wrappers around data the chat screen already has (`job`, appointment-proposal messages) — no new providers needed
- Payment gate stays exactly as it is today: `!WorkflowGateService.isAgreementRequired(job)`, unchanged from the workflow-stabilization pass
- **My Chats / Messages list** — light variant only (per audit decision), status chips per conversation sourced the same way as My Bookings' badges

**Blocking**: Group 1. Sequenced after Job workflow screens since the sticky header's "View Job Details" link target is that screen.

---

## 7. Escrow/payment

- **Payment screen** (existing lump-sum escrow flow) — restyle the Cost Breakdown / "Lock Funds in Escrow" step directly, this maps cleanly to the winning wizard's step 3
- **New: direct-booking wizard** ("Secure Booking" 3-step flow) — built as an **additive entry point** per the audit decision, not a lifecycle replacement. Needs a decision on where it's entered from (an artisan profile's "Start Secure Booking" button, most likely) and what it actually creates on submit — recommend it still creates a normal `JobModel` through the existing `JobService`/Firestore-rules-enforced transitions (skipping straight to a pre-negotiated state isn't safe to invent unilaterally; flag for the user's confirmation before this specific sub-item starts). Do not build a second parallel job-lifecycle state machine for this — it should terminate in the same `JobStatus` states everything else does, just via a shorter UI path.

**Blocking**: Group 1, Group 5 (payment screen's "isReadyForPayment" gate is the same one Job Details renders from). The direct-booking wizard is additionally blocked on the entry-point/data-model confirmation above.

---

## 8. Wallet/Earnings

- **Wallet** — green-gradient variant (per audit decision), built against the real single-payment `PaymentModel` data; milestone progress bars, "Milestone 2 of 3" labels, and partial-release amounts are **not built**, per the audit decision that this stays UI-structure-only and doesn't simulate a backend that doesn't exist. The screen shows real total-in-escrow and real transaction history instead.
- **Artisan Earnings** — genuinely new screen (flagged in the original `STITCH_IMPLEMENTATION_PLAN.md` as a gap, reinforced here). No Stitch-specific earnings-analytics mockup was in this screenshot batch — the artisan Wallet variant ("Available for Payout," "Pending Clearances") is the closest reference. Build the UI structure (total earnings, pending payments, completed payments, withdrawal history) against real `payments` data filtered to the artisan; if "Pending Clearances" implies a payout-clearance concept that doesn't exist in the current Paystack integration, document that gap rather than fabricate a number.

**Blocking**: Group 1. Independent of everything else — can be pulled earlier in the order if desired.

---

## 9. Notifications

- **Notifications screen** — no mockup supplied in this batch, restyle with Group 1 tokens against the existing 12-type whitelist
- **Notification Preferences** — new screen (per the original task's Phase 5 request and `STITCH_IMPLEMENTATION_PLAN.md`'s flagged gap). Today there's a single global toggle, nothing per-category. Build the UI with per-category rows (push/job updates/payment updates/messages) but wire only the categories that can actually be independently controlled today — if the backend only supports one global flag, the screen should either say so honestly or this is the point where per-category backend support gets scoped as its own small task before the screen ships as fully functional.

**Blocking**: Group 1. Independent of everything else.

---

## 10. Admin

- No Stitch mockups were supplied for any admin screen. Out of scope for this pass entirely — the admin surface has its own `ShellRoute` and color system already, and nothing in the 22 screenshots touched it. Not sequenced; revisit only if Stitch mockups for admin arrive later.

---

## Cross-group dependency summary

```
1. Design system
   └─▶ 2. Auth
   └─▶ 3. Customer experience
   └─▶ 4. Artisan experience ──────────────┐
   └─▶ 5. Job workflow screens ◀───────────┘ (TrustScore fields)
         └─▶ 6. Chat (View Job Details link target)
               └─▶ 7. Escrow/payment (isReadyForPayment gate)
   └─▶ 8. Wallet/Earnings (independent)
   └─▶ 9. Notifications (independent)
   10. Admin — not sequenced, no mockups
```

Held pending a mockup: **Job Details** (Artisan Dashboard no longer held — confirmed no dedicated Stitch mockup exists, restyles with Group 1 tokens directly).
Held pending product sign-off before building: **photo-unlock paywall** (no pricing/backend decision made), **direct-booking wizard's data model** (needs entry-point confirmation).

Recommend starting with Group 1, then Group 2 (auth) as a low-risk proving ground for the new tokens, per the order above — ready to proceed on your go-ahead.
