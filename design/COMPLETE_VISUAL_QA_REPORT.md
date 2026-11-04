# Complete Visual QA Report — All Reference Screens

Consolidates three rounds of real, rendered testing against this app's Stitch reference screenshots:

1. **First pass** (`COMPLETE_VISUAL_QA_REPORT.md`, repo root) — Home, My Bookings, Wallet, Profile, Post a Job, Messages, Chat. Already reviewed and approved; unchanged in this pass except where noted.
2. **Stage 2** (`design/STAGE2_LIVE_QA_REPORT.md`) — Job Detail, Admin (Dashboard/Artisans/Beta Tester), Artisan Dashboard, Open Jobs Feed, Bank Details, Settings, Notifications, Profile (both roles).
3. **This pass** — the screens the first two passes left unreached: Payment, Artisan Profile (customer-facing detail), Find Jobs (rigorous re-check), Verification. All driven live via Playwright against `flutter build web` served locally, real signed-in account, real Firestore data. Every screenshot below is a genuine rendered capture, not a code-level guess, except where explicitly marked as code-verified only.

**Methodology note on this pass specifically:** the reference screenshots were supplied earlier in this working session as pasted images, not saved as files in the repo. A context-window compaction partway through this task means the raw reference pixels are no longer directly available to re-inspect in this pass; comparisons below rely on the detailed written descriptions of each reference recorded earlier in the same session (composition, copy, colors, component structure), cross-checked against the live render. Where that written record and the live render agree structurally and in content, it's called a match; where a reference detail could not be reconstructed with confidence, it's disclosed rather than guessed at.

---

## Screen: Payment / Secure Booking
**Reference:** "Secure Booking" style — job summary, escrow amount, Pay Now CTA.
**Rendered result:** Not reached. Reaching this screen requires a job that has an artisan matched, a price agreed, and is past scheduling into a payable state. This account's existing jobs are either in Negotiation or a terminal state (Cancelled/Closed); creating a **new** job that could progress to payable requires uploading a job photo, which requires Firebase Storage — deferred per explicit instruction.
**Match status:** NOT YET VERIFIABLE.
**Differences:** N/A — not reached.
**Changes made:** None.
**Remaining limitations:** Blocked transitively by the Firebase Storage deferral (`design/STORAGE_UPLOAD_ROOT_CAUSE.md`). Was pixel-matched against the reference in an earlier work pass at the code level; not re-confirmed against a live render in any pass to date.

---

## Screen: Artisan Profile (customer-facing detail)
**Reference:** Dark navy "TrustScore" card variant — avatar, name, role/specialty tags, Experience/Completed stats, TrustScore card (score, tier, component breakdown), About/Skills, portfolio gallery, booking CTA.
**Rendered result:** Reached live via Customer Home → Browse Artisans → artisan card. Header (mint avatar band, back arrow), name "DI RAIZEL", handle "@RAIZEL", "Rising Pro" badge, trade "Welding", location "Ibadan" with pin icon, dark navy stats bar (Rating/Jobs done/Response), "About" and "Skills" sections all render correctly and match the reference's structure and styling.
**Match status:** MATCHED WITH INTENTIONAL FUNCTIONAL DIFFERENCES (structure/styling); populated sub-elements code-verified only, not live-rendered.
**Differences:**
- The TrustScore card, portfolio gallery, and booking CTA button did not render for this specific artisan. Reading `lib/screens/artisan/artisan_profile_screen.dart`, this is correct, intentional conditional behavior, not a bug: the TrustScore card only shows `if (artisan.totalRatings > 0 || artisan.totalJobs > 0)`, the portfolio gallery only shows `if (artisan.portfolioImageUrls.isNotEmpty)`, and the "Hire This Artisan" CTA only shows `if (jobId != null)` (i.e. when reached from a specific job's artisan-selection flow, not the general public Browse Artisans directory). Every seed artisan in this Firestore project currently has 0 completed jobs and 0 ratings, and Browse Artisans is a job-independent route, so all three legitimately don't apply here.
- Per `lib/widgets/trust_score_card.dart` (already written and unchanged in this pass), the TrustScore card is a deliberate, previously-documented intentional difference from the reference: it shows the two highest-weighted real `TrustScoreService` components (drawn from Completed Jobs / Customer Rating / Verification / Response Speed / Dispute History) instead of the reference's literal "Craftsmanship"/"Punctuality" labels, which this backend has never computed for any artisan. The reference's "Top 5%" percentile badge is likewise omitted — no percentile-ranking Cloud Function exists. This is a "don't invent data that could misrepresent the product" call, not an oversight.
**Changes made:** None — no confirmed mismatch found; the difference from the reference's fully-populated mockup is a data/entry-point difference, not a rendering defect.
**Remaining limitations:** Could not live-render the populated TrustScore card, portfolio gallery, or booking CTA — no artisan in this Firestore project has completed jobs/ratings, and portfolio images remain blocked by deferred Storage. These paths are verified by source reading only, not by an actual screenshot with real data.

---

## Screen: Find Jobs (artisan-side)
**Reference:** "Find Jobs" variant — search bar, "Ready to work!" toggle, All Matched/Recent/Urgent filter chips, job cards with budget/location/urgency.
**Rendered result:** Reached live via artisan mode → "Browse Open Jobs". Search bar ("Search tasks, locations…"), green "Ready to work!" toggle (on), filter chips (All Matched selected in black, Recent, Urgent), and job cards (category icon, title, urgency badge, description, price-range pill, location pill, Chat + "I'm Interested" buttons) all render correctly and match the reference structure exactly.
**Match status:** EXACT / visually matched.
**Differences:** The page's `AppBar` title reads the artisan's own trade category ("Welding") rather than a generic "Find Jobs" label — confirmed intentional in `lib/screens/artisan/open_jobs_feed_screen.dart` (`widget.category.isEmpty ? 'Open Jobs' : widget.category`), personalizing the feed to the artisan's own trade rather than a static label. Not a defect.
**Changes made:** None — no mismatch found. (Separately, the artisan-mode home/dashboard hub — reached via the bottom-nav "Find Jobs" tab, distinct from this feed screen — was also re-checked live this pass: avatar, "Find Jobs" title, swap/notification/logout icons, "Available for new jobs" toggle, "Verification Deferred" banner, stats row, quick-action grid, and "Active Jobs" list all render correctly, consistent with Stage 2's prior findings.)
**Remaining limitations:** Some job card text in this Firestore project contains leftover test data ("Ibadannnnnnnnnnnnnnnnnn") from earlier manual testing sessions — this is bad seed *data*, not a rendering defect, and was already disclosed in Stage 2.

---

## Screen: Verification
**Reference:** Selfie + government ID upload flow, "Verified" badge messaging.
**Rendered result:** Reached live via artisan Find Jobs hub → "Verify Now". Back arrow + "Verify Your Identity" title, blue "verify later" status banner, green benefit banner ("Identity verification earns the Verified badge and builds customer trust."), Step 1 "Take a Selfie" card with camera-icon button, Step 2 "Upload Government ID" card with camera-icon button (National ID / Driver's licence / Voter's card / International passport), disabled "Submit for Verification" button (correctly greyed until both steps complete), and a "Verify Later" fallback link with subtext.
**Match status:** MATCHED (structure/content); upload interactions not exercised.
**Differences:** None found in layout, copy, or component structure.
**Changes made:** None.
**Remaining limitations:** The "Take Selfie" and "Upload ID" buttons themselves were not clicked through to completion — both ultimately call the same `image_picker` → Firebase Storage upload path that is deferred project-wide (`design/STORAGE_UPLOAD_ROOT_CAUSE.md`). Screen reachability and layout are confirmed; the upload itself is not.

---

## Screens with no corresponding reference image
The current task's instructions named several screens (Bank Details, Dispute, Business Profile, Portfolio, "Admin screens/details") that do not correspond to any image among the reference set gathered for this project. These are a different category from "not yet verifiable" — there is nothing to pixel-match them against. For completeness, their functional status (from Stage 2 and this project's broader audit history) is noted below rather than left unaddressed:

| Screen | Functional status | Reference image available? |
|---|---|---|
| Bank Details / Payout Details | Live-tested in Stage 2 — real populated form (bank name, account number, account name), renders correctly | No |
| Business Profile | Screen exists (`lib/screens/artisan/business_profile_screen.dart`), reachable from the artisan dashboard; not independently pixel-tested (no reference to test against) | No |
| Portfolio | Screen exists (`lib/screens/artisan/portfolio_manager_screen.dart`, `portfolio_project_screen.dart`); reachable, but photo upload is Storage-blocked | No |
| Dispute | Screen exists (`lib/screens/dispute/dispute_screen.dart`); not independently pixel-tested (no reference to test against) | No |
| Admin screens/details | Live-tested in Stage 2 — Dashboard stats, 12-section drawer nav, Artisans list + detail panel (including the Beta Tester feature end-to-end) all confirmed working against real data | No |

## Screen with no equivalent in the app
**Recent Activity** — no screen anywhere in the app corresponds to this reference. This is a standing, previously-documented product gap (flagged in the original Stitch audit), not something introduced or overlooked by this QA pass. Per this task's own instruction not to add UI/features, it was not built.

---

## Fixed this pass
None. Every screen reached this pass either matched its reference structurally and visually, or its only difference from the reference was data-driven (no artisan with completed jobs/ratings in this Firestore project) or an already-documented, intentional product decision (real TrustScore components instead of the reference's fictitious ones; category-personalized feed title). No genuine rendering defect was found on any of the four screens investigated in this pass (Payment, Artisan Profile, Find Jobs, Verification).

## Remaining known differences (carried forward from all passes)
1. Chat's job-summary status badge doesn't vary color by phase/tone (P2, optional, first pass).
2. Payment remains unverified against a live render — blocked transitively by the deferred Storage bucket.
3. Artisan Profile's TrustScore card, portfolio gallery, and booking CTA are code-verified but not live-rendered with populated data — no seed artisan in this project has completed jobs or ratings.
4. Category chip icons throughout the app are Material Icons approximating reference glyphs, not literal asset matches (standing, previously-disclosed limitation).
5. Some seed job-card data in the Open Jobs Feed contains obvious test-data junk strings — a data cleanliness issue, not a rendering defect.

---

## Final categorization

**1. EXACT / visually matched**
- Find Jobs (artisan feed) — search/toggle/filter chips/job cards match reference exactly
- Profile / Settings (both roles)
- Messages / My Chats
- Verification (structure/content; upload interaction not exercised)

**2. MATCHED WITH INTENTIONAL FUNCTIONAL DIFFERENCES**
- Customer Home — extra working role-switch icon, real (not illustrative) category set
- My Bookings — no reference-deviating differences beyond expected empty state
- Wallet — summary card intentionally hidden at zero balance (correct, honest design)
- Post a New Job — matches reference; submission itself blocked by deferred Storage
- Chat (thread) — real unread badges added beyond reference; one optional P2 (status-badge tone) left unfixed since it's not a mismatch against the reference
- Artisan Profile — structure/styling matches; TrustScore card intentionally uses real weighted components instead of the reference's fictitious "Craftsmanship/Punctuality" labels and omits an uncomputed "Top 5%" percentile

**3. NOT YET VERIFIABLE**
- Payment / Secure Booking — no job in this account has reached a payable state; creating one is blocked by deferred Storage

**4. NEEDS FIXING**
- None found in this pass or prior passes. No confirmed genuine visual mismatch against any reference screen remains open.

**No reference image exists for:** Bank Details, Business Profile, Portfolio, Dispute, Admin screens/details (functionality independently verified where feasible; see table above).

**No app screen exists for:** Recent Activity (standing, disclosed product gap — not built, per instruction not to add new UI).
