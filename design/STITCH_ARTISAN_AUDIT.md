# Stitch Artisan Audit — Group 4

Per `STITCH_IMPLEMENTATION_AUDIT.md`'s decisions: the "Find Jobs" variant won for Open Jobs Feed (over "Jobs matched for you"), artisan nav is `Find Jobs / My Jobs / Inbox / Profile`, and the dark-navy TrustScore card won for the artisan-profile-as-viewed-by-customer screen (that screen is Job Details territory, Group 5/3, not here). **No Stitch mockup exists for the Dashboard** — confirmed twice now: the original screenshot batch didn't include it, and a follow-up screenshot the user sent turned out to be a duplicate of "Jobs matched for you," not a distinct Dashboard design. Quote Submission, Portfolio, Business Profile, Bank Details, and Verification have no mockups either.

---

### Dashboard
**Current file**: `lib/screens/artisan/artisan_dashboard_screen.dart` (`ArtisanHomeTabContent`)
**Purpose**: approval/verification gating, availability toggle, stats, quick actions, active/recent jobs
**Existing components**: already fully token-driven (`context.colors`, `AppRadius`, `AppShadows` throughout), already uses `WorkflowTimeline` (compact) and the real `TrustScoreCard`/`showTrustScoreSheet` for the artisan's own trust breakdown
**Stitch replacement**: none — restyled with Group 1 tokens only, no layout invention
**Missing states**: the one real gap — `_ArtisanJobTile`'s badge read raw `job.status.label` via `JobStatusBadge`, not `WorkflowGateService`, same class of issue found and fixed on Home and My Bookings. **Fixed**: now reads `WorkflowGateService.describeStep(job, viewerIsCustomer: false).phase`.

### Open Jobs Feed
**Current file**: `lib/screens/artisan/open_jobs_feed_screen.dart`
**Purpose**: browse open jobs in-category, submit/edit/withdraw quotes, live eligibility gating
**Existing functionality (untouched)**: `_OpenJobCard`'s eligibility computation (`notApproved`/`notVerified`/`ineligibleReason`, live off `artisanProfileProvider`), `_SubmitQuoteSheet`'s validation and `quoteServiceProvider` calls, `_friendlySubmitError`'s permission-denied handling — all byte-identical to before.
**Stitch replacement**: "Find Jobs" variant (locked in) — search bar, "Ready to Work!" toggle, All Matched/Recent/Urgent filter chips. All three were missing from the existing screen and are now added as **client-side, additive filters over the already-fetched job list** — no new Firestore queries, no change to `openJobsFeedProvider`.
**Missing states**: added a distinct "no jobs match your filters" state (with a clear-filters action) separate from the pre-existing "no open jobs at all" empty state — previously conflated (searching to zero results looked identical to a genuinely empty category).

### Quote Submission
**Current file**: `_SubmitQuoteSheet` (same file, modal bottom sheet)
**Purpose**: labor/materials/duration/notes form, submit or withdraw
**Stitch replacement**: none — already token-consistent (`context.colors`, `AppRadius` throughout); left untouched rather than making cosmetic-only edits for their own sake.

### Portfolio / Business Profile / Bank Details / Verification
**Current files**: `portfolio_manager_screen.dart`, `portfolio_project_screen.dart`, `business_profile_screen.dart`, `bank_details_screen.dart`, `verification_upload_screen.dart`
**Stitch replacement**: none supplied, lowest priority per the build order ("restyle whenever convenient")
**Audit result**: grepped all five for raw `Colors.*`/hex-literal usage outside legitimate cases (white text/spinners on colored buttons, a photo-overlay scrim) — none found. Already consistent with the design system. No changes made.

---

## Summary

Real redesign work this pass: Open Jobs Feed (search/toggle/filter additions, both empty states) and the Dashboard/Feed job-tile badge fix (routing through `WorkflowGateService` instead of raw `job.status`). Everything else in this group was already in good shape from prior work and didn't need touching — confirmed by inspection, not assumed.
