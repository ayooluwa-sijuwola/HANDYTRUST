# Screen Mapping — Preparation for Google Stitch Redesign

**Status: preparation only.** No Stitch designs have been implemented. The "Future Stitch Screen" column is intentionally left as a placeholder on every entry below — per the explicit instruction not to implement or map real Stitch screens until the design reference is reviewed and confirmed. A Stitch project URL was attached to the task that produced this document, but it was not opened or used to fill this column, consistent with "do not implement the Stitch designs yet."

This covers the primary marketplace-lifecycle screens most relevant to the workflow fixed in this pass. The full 43-screen inventory (route, purpose, completion %, known issues) already exists in `v1-audit/15-screens-inventory.md` — not duplicated here in a second format; this document adds the redesign-specific columns (current components, required data, required actions) that the audit didn't need.

---

## Job Details Screen

**Current:** `lib/screens/job/job_detail_screen.dart`

**Purpose:** Single source of truth for a job's entire lifecycle — status, agreement, appointment, photos, disputes, and the primary next action, for whichever party is viewing it.

**Current components:** `JobProgressTracker`, `JobTimelineWidget`, `JobProgressTimeline` (three separate, overlapping timeline widgets — flagged as technical debt, not something to carry into the redesign as three components), `_AgreementSection`, `_AppointmentSection`, `_QuoteInboxSection`, `_DisputeCountdownBanner`, `_DisputeThreadSection`, photo galleries, `_actionButtons` (now driven by the new `WorkflowStatusCard` component for most states).

**Future Stitch:** *(to be filled after the design reference is reviewed)*

**Required data:** job status, `agreementStatus` + agreement fields, `confirmedAppointment`/`appointmentSlots`, photo URLs (job/before/completion), dispute record if any, the other party's basic profile info.

**Required actions:** Accept quote (from the inbox), Continue Negotiation (opens chat), Confirm/Accept/Request-Changes on the agreement, propose/confirm an appointment slot, Pay Into Escrow, Start Job, Submit Completion, Confirm & Release Payment, Raise Dispute, Cancel Job, Leave a Review.

---

## Open Jobs Feed

**Current:** `lib/screens/artisan/open_jobs_feed_screen.dart`

**Purpose:** Let an artisan browse jobs open for quoting in their category and submit a quote.

**Current components:** `_OpenJobCard` (job summary, quote-status banner, **now** an eligibility banner when the artisan can't yet quote, Chat/Quote button row), `_SubmitQuoteSheet` (a modal bottom sheet with labor/materials/duration/notes fields).

**Future Stitch:** *(to be filled after the design reference is reviewed)*

**Required data:** open job list (category-filtered), the artisan's own quote (if any) per job, the artisan's own `approvalStatus`/`verificationStatus` (now live-watched for the eligibility gate).

**Required actions:** Chat with the customer pre-match, submit/edit/withdraw a quote.

---

## Chat Screen

**Current:** `lib/screens/chat/chat_screen.dart`

**Purpose:** Per-job messaging between customer and artisan, including price negotiation.

**Current components:** Message list (`_MessageBubble`, text/image/negotiation/system types), negotiation bar, input bar with image-attach, an app-bar "Pay Now" shortcut.

**Future Stitch:** *(to be filled after the design reference is reviewed)*

**Required data:** message stream, job status (for the app-bar subtitle and the "Pay Now" shortcut's visibility).

**Required actions:** send text/image, propose a price, jump to payment. **Known gap for the redesign to address**: the "Pay Now" shortcut isn't aware of `agreementStatus` — flagged in `WORKFLOW_AUDIT.md`, not fixed in this pass since it's a chat-screen change outside this pass's stated scope.

---

## Artisan Dashboard

**Current:** `lib/screens/artisan/artisan_dashboard_screen.dart` (`ArtisanHomeTabContent`)

**Purpose:** Artisan's daily entry point — approval/verification state, availability, stats, active jobs.

**Current components:** pending-approval banner, availability toggle, verification/trust card, stats row, quick actions, jobs section.

**Future Stitch:** *(to be filled after the design reference is reviewed)*

**Required data:** `artisans/{uid}` profile (approval/verification/availability/trust score), the artisan's active jobs.

**Required actions:** toggle availability, navigate to verification/portfolio/open jobs/job list.

---

## Wallet Screen

**Current:** `lib/screens/wallet/wallet_screen.dart`

**Purpose:** Payment history — escrow held, total spent/paid out.

**Current components:** summary card, ledger list (per-job, single-payment — no milestone breakdown, since none exists in the data model).

**Future Stitch:** *(to be filled after the design reference is reviewed)*

**Required data:** `payments` collection, filtered by customer/artisan ID.

**Required actions:** view a payment's detail (currently read-only, no actions).

---

## Notes for whoever picks this up when the Stitch URL is reviewed
- Fill the "Future Stitch Screen" column per screen only after the actual designs are reviewed against the real data/actions listed above — several screens here (Job Details especially) carry real functional complexity that a visual mockup won't show; match designs to the *actual* required data/actions, not the other way around.
- The three-timeline-widget situation on Job Details and the un-gated "Pay Now" button in Chat are both real, known items worth resolving *as part of* the redesign pass, not before it — noted here so they aren't lost.
