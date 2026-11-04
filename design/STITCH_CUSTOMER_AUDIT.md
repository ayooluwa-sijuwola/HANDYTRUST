# Stitch Customer Audit — Group 3

Same standing note as the prior two audits: Stitch mockups exist for Home, My Bookings, Job Creation ("Post a New Job"), Chat, Payment/Escrow, Artisan Profile, and Wallet (all covered in `STITCH_IMPLEMENTATION_AUDIT.md` with variant decisions already locked in). **No mockup exists for Job Details or Reviews.** Job Details restyles with Group 1 tokens against its already-correct workflow logic (per the earlier decision that it "restyles once Group 1 lands" if no mockup ever arrives); Reviews wasn't in either screenshot batch and gets the same treatment.

---

### Home / Dashboard
**Current file**: `lib/screens/home/home_screen.dart` (`_CustomerHomeTab`)
**Purpose**: daily entry point — greeting, search, category browse, active-jobs summary, quick actions
**Current workflow actions**: post a job, browse artisans, open a job, switch to artisan mode (dual-role users)
**Existing components**: hand-rolled header/search/hero/category-grid/job-tile/quick-action-grid — none of Group 1's new shared components used yet
**Stitch replacement**: "Find your expert helper" variant (locked in `STITCH_IMPLEMENTATION_AUDIT.md`) — search bar, category chips, `ArtisanCard`-style featured-pro cards
**Missing states**: **no completed-jobs visibility at all** — `_ActiveJobsList` filters to `!status.isTerminal` and nothing on Home ever shows what's finished; Task 2 explicitly asks for active + pending + completed to all be visible. Also: `_PremiumJobTile`'s badge reads raw `job.status` via `JobStatusBadge`, not `WorkflowGateService` — same class of issue Group 2 audits kept finding, real here too.

### Create Job
**Current file**: `lib/screens/home/service_request_screen.dart`
**Purpose**: post a new job request
**Current workflow actions**: category/description/photos/location/budget/urgency → `jobRequestNotifierProvider.submitRequest` → navigates to artisan selection
**Existing components**: none shared — bespoke `_SectionLabel`, `_UrgencyTile`, inline `TextFormField`s with duplicated `InputDecoration` (border/fillColor repeated 6 times)
**Stitch replacement**: "Post a New Job" (locked in) — category chips, title/description, photos, schedule, budget. Note (already documented): the photo-unlock paywall is **not** built — no backend exists for it.
**Missing states**: form has good field-level validation and `showErrorSnackbar(..., onRetry: ...)` on submit failure (real retry, not swallowed) — actually well handled already. What's missing is **progress/section clarity**: seven sections in one long scroll with no visual indication of how far along the user is or which sections are done — Task 4's actual ask.

### Job Details
**Current file**: `lib/screens/job/job_detail_screen.dart`
**Purpose**: full lifecycle view — status, timeline, quotes, agreement, scheduling, payment, completion, dispute
**Current workflow actions**: everything `WorkflowGateService.describeStep` returns, plus quote accept/reject, agreement confirm/accept/request-changes, appointment propose/confirm, dispute raise/respond, review
**Existing components**: **already uses `WorkflowTimeline`, `WorkflowStatusCard`, `WorkflowGateService` in full** — this screen was built during the earlier workflow-stabilization phase specifically to satisfy exactly what Task 5 is asking for. Nothing architectural is missing.
**Stitch replacement**: none supplied — restyle only (spacing/token pass), no logic change, no layout invention.
**Missing states**: quotes section already has a real empty state ("Waiting for artisans to submit quotes for this job."); the one genuine gap is the quotes-provider `error` branch, which is just `Text('$e')` with no retry — the only visibly weak error state in this screen.

### My Bookings
**Current file**: `lib/screens/home/all_jobs_screen.dart` (`AllJobsScreen`)
**Purpose**: filterable job list, both customer and artisan
**Current workflow actions**: filter by All/Active/Completed/Disputed, open a job
**Existing components**: bespoke `_JobCard`, `_FilterBar`/`_Chip` — **exactly the two components Group 1 built `JobBookingCard`/`PillTabSelector` to replace**
**Stitch replacement**: "My Bookings" (locked in) — dark-pill tabs, dual-button cards
**Missing states**: empty states already exist and are well-written per filter (including the deliberately-reassuring "No disputes" copy) — genuinely good prior work, not a gap. The real gap is structural: **no Drafts concept exists** (confirmed in the original implementation audit) — the new Drafts tab must show a real, honest empty state, not fabricated entries. **Status badge is raw `job.status.label`, not `WorkflowGateService`** — this is the literal violation Task 3's rule calls out by name.

### Quotes
**Current file**: not a standalone screen — `_QuoteInboxSection`/`_QuoteCard` inside `job_detail_screen.dart`
**Purpose**: shows pending quotes for a `requested`/`matched` job, sortable by price/trust
**Current workflow actions**: accept, reject
**Existing components**: `_QuoteCard` (private to job_detail_screen.dart)
**Stitch replacement**: none supplied as a standalone screen — it's embedded in Job Details, which itself has no mockup
**Missing states**: covered above (empty state good, error state weak)

### Chat entry points
**Current files**: `lib/screens/chat/chat_screen.dart`, `lib/screens/chat/my_chats_screen.dart` — **both already redesigned in Group 2's scope? No** — actually neither was touched in Group 1 or 2; they were wired to `WorkflowGateService` in the pre-Stitch workflow-stabilization pass, but not yet visually redesigned. Out of scope for Group 3 per the task's explicit 9-screen list (Chat itself is Group 6 in the build order) — **entry points from customer screens** (Home's chat icon, a job's "Continue Negotiation" action) are what's actually in scope here, and both already work correctly and aren't touched by this pass.

### Escrow / Payment
**Current files**: `lib/screens/payment/payment_screen.dart`, `payment_webview_screen.dart`
**Purpose**: Paystack checkout once `WorkflowGateService.isReadyForPayment`
**Stitch replacement**: locked in as Group 7 in the build order (depends on Job Details being finalized) — **not touched in this pass**, per the build order's own sequencing. Mentioned here only for completeness of the 9-screen inventory the task named.

### Reviews
**Current file**: `lib/screens/review/review_screen.dart`
**Purpose**: rate a completed job
**Stitch replacement**: none supplied in any batch
**Missing states**: not yet audited in detail — out of this pass's critical path (Tasks 2-5 don't name it), left for a later group unless it blocks Job Details' "completion state" requirement (it doesn't — completion state is the `completed`/review-prompt branch inside Job Details itself, which already exists).

### Profile
**Current file**: `lib/screens/profile/profile_screen.dart` (+ `settings_screen.dart`, `contact_support_screen.dart`)
**Stitch replacement**: locked in as its own consolidation (three screens → one list) per the original build order, sequenced later — not touched in this pass.

---

## What Group 3 actually builds, given the above

Tasks 2, 3, and 4 are real redesign work (Home, My Bookings, Create Job). Task 5 (Job Details) is confirmed already architecturally complete — this pass gives it a token/spacing polish only, explicitly not a rebuild, since rebuilding a screen that already correctly does everything the task asks for would be pure risk with no benefit. Reviews, Chat, Payment, and Profile are confirmed out of this pass's critical path and untouched.
