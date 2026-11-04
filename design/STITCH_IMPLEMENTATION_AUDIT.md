# Stitch Implementation Audit

Source: 22 screenshots supplied directly in chat (Stitch does not render for unauthenticated/automated fetches, so this audit is built from the exported images, not the live project). Phase 1 only — no code changes in this document.

**Read this first — two things block a clean Phase 2 until resolved, flagged in detail at the bottom:**
1. Several screen types were exported as **2–3 competing variants** with different nav labels, color systems, and layouts (e.g. two different Home screens, three different Wallet screens). These need to be picked down to one before a design system can be extracted.
2. The booking/payment screens ("Initiate Task" / "Secure Booking") bundle **job details + scheduling + payment into a single linear wizard**, which doesn't match the current multi-stage lifecycle (post → quote → negotiate in chat → schedule in chat → pay). This is a workflow question, not a visual one.

---

## Screen-by-screen comparison

### 1. Customer Home / Explore
**Current screen** — `lib/screens/home/home_screen.dart` (`_CustomerHomeTab`)
- Purpose: daily entry point — active jobs + category browse
- Actions: post a job, browse artisans, view a job
- Data: `customerJobsProvider`, category list

**Stitch screen** — two variants supplied:
- (A) "Find your expert helper" — dark search bar, black "Ready to work!" pill, Featured Pros cards with star-rating badge overlaying the photo, bottom nav *Explore / My Tasks / Wallet / Profile*
- (B) "Find trusted experts for your home" — lighter header, "Featured Experts" with "See all" link, cards show rating + Verified Pro + job count inline instead of overlaid, bottom nav *Discovery / Bookings / Wallet / Profile*
- New components: category filter chips, artisan card with photo hero + floating rating badge
- Missing data vs. current: none — same data shape (`ArtisanModel` fields), just richer card treatment
- Required backend support: none

**Category**: Direct replacement candidate (pending variant choice, see open questions).

---

### 2. My Bookings / Job List
**Current screen** — `lib/screens/home/all_jobs_screen.dart`
- Purpose: filterable list of customer's jobs
- Actions: filter (All/Active/Completed/Disputed), open a job
- Data: `customerJobsProvider`

**Stitch screen** — two near-identical variants ("My Bookings," dark-pill tabs vs. light-pill tabs; one has a chat icon in the header, one a hamburger menu)
- Tabs: Active (2) / Completed (14) / Drafts (1) — **"Drafts" has no current equivalent** (see gap below)
- Card shows: status badge (In Progress / Awaiting Artisan), date, artisan avatar+name+verified badge, agreed price, Message + View Details buttons — or for unmatched jobs: "Searching…", proposals count, budget, Edit Booking button
- New components: dual-button job card (secondary "Message" + primary "View Details"), promo card ("Need a Hand? Explore Services"), FAB
- Missing data: **"Drafts" status doesn't exist in `JobStatus`** — no current job can be in a draft state (jobs are created fully-formed via `service_request_screen.dart`, not saved incomplete)
- Required backend support: a draft-saving mechanism, if this tab is kept

**Category**: Mostly a direct replacement, but the status badges shown ("In Progress," "Awaiting Artisan") need to route through `WorkflowGateService.describeStep(...).phase`, not be re-derived — and "Drafts" is a **new-functionality** item.

---

### 3. Job Details (full page)
**Current screen** — `lib/screens/job/job_detail_screen.dart`
- Purpose: single source of truth for a job's entire lifecycle — status card, timeline, agreement section, appointment section, action buttons
- Actions: everything `WorkflowGateService.describeStep` can return, plus agreement confirm/accept/request-changes, appointment propose/confirm, dispute, review

**Stitch screen** — **not present in the supplied screenshots.** The closest artifacts are the collapsible "View Job Details" summary bar inside the Chat screen, and the job-preview blocks inside Wallet/Bookings. No dedicated full job-detail page was exported.

**Category**: **Gap in the supplied designs** — this is the single most complex existing screen (agreement/scheduling/timeline/dispute logic all live here) and needs its own Stitch screen before Phase 3 can touch it. Flagged as a blocking gap, not something to guess at.

---

### 4. Post a New Job
**Current screen** — `lib/screens/home/service_request_screen.dart`
- Purpose: create a job request
- Actions: submit, optional AI description assist
- Data: none in, `jobRequestNotifierProvider` out

**Stitch screen** — "Post a New Job"
- Category chips (Welding/Plumbing/Carpentry — sample data, not the full current category list), title, description, **photo upload with a paywall** ("Max 3 free" / "Unlock more images ₦500"), schedule dropdown ("As soon as possible"), budget field, Post Job button
- Missing data / new functionality: **a pay-to-unlock-more-photos paywall does not exist anywhere in the current app** — no `payments` document type, no Cloud Function, no pricing config for this
- Required backend support: if kept, needs a new payment product (separate from escrow), a Cloud Function to gate photo count server-side (client-side gating alone isn't enforceable), and a Firestore field to track purchased slots

**Category**: Mostly visual/replacement, **except the photo paywall, which is new functionality requiring real backend work** — flagged for Phase 5-style treatment (document, don't fake).

---

### 5. Chat
**Current screen** — `lib/screens/chat/chat_screen.dart`
- Purpose: per-job messaging + negotiation
- Actions: send text/image, propose price, view agreement (if required via `WorkflowGateService.isAgreementRequired`), pay into escrow (if ready)
- Data: `chatNotifierProvider`, `job.status`/`agreementStatus`

**Stitch screen** — "Marcus Thorne / Verified Pro" (two identical exports)
- Sticky job-summary bar at top: title, status chip ("Awaiting Schedule"), price, expandable "View Job Details"
- Message bubbles (customer light-gray left, artisan black right — note: reversed from typical convention, worth confirming who's "self" in the final IA)
- **"Proposed Schedule" inline card** rendered as a message — this maps directly to the existing appointment-proposal flow (`confirmAppointmentSlot`, `SchedulingStatus`) and is good evidence Stitch's designer *did* intend to keep scheduling-in-chat, which is reassuring against the payment-wizard conflation noted above
- Data needed: same as current, plus the sticky summary bar wants `WorkflowGateService.describeStep(...).phase` for its status chip

**Category**: Direct replacement, straightforward. The sticky "View Job Details" header and "Proposed Schedule" message card are the two genuinely new components.

---

### 6. My Chats / Messages list
**Current screen** — `lib/screens/chat/my_chats_screen.dart`
- Purpose: conversation list
- Actions: open a thread
- Data: chat previews, unread counts

**Stitch screen** — two variants: a light "Messages" list (search bar, avatar+name+time+preview+status chip) and an unexplained **black-background variant** of the same list under the "Bookings" bottom-nav tab
- The status chips shown ("Booking Confirmed," "Agreed Price: $120," "Awaiting Schedule") are exactly `WorkflowGateService`-shaped data — good sign
- The black-background one may be a dark-mode capture or a stray variant; flagged in open questions rather than assumed to be intentional

**Category**: Direct replacement (pending which variant/theme is canonical).

---

### 7. Payment / Escrow initiation
**Current screen** — `lib/screens/payment/payment_screen.dart` + `payment_webview_screen.dart`
- Purpose: Paystack checkout for a job that's already `isReadyForPayment`
- Actions: pay
- Data: `PaymentModel`, Paystack checkout URL

**Stitch screen** — two variants, "Initiate Task" and "Secure Booking" — both a 3-step wizard: **Details → Schedule → Payment**, all in one flow, ending in "Lock Funds in Escrow"
- Step 1 collects task title/description/budget (this is `service_request_screen.dart`'s job, not `payment_screen.dart`'s)
- Step 2 (in the "Secure Booking" variant) collects Preferred Date/Time directly in the wizard — this is currently a **chat-mediated, two-party negotiation** (`confirmAppointmentSlot`), not a single-party form field
- Step 3 shows Cost Breakdown + "Lock Funds in Escrow," which does map to the current payment screen
- **This is the workflow-conflation issue flagged at the top** — see open questions

**Category**: **Requires a product decision before categorizing.** If this is a *new, separate* "book this specific artisan directly, skip the open marketplace" flow, it's new functionality layered alongside the existing lifecycle. If it's meant to *replace* post→quote→negotiate→schedule→pay, that's a lifecycle change the task's own rules forbid guessing at ("Do not remove existing workflow protections," "Do not bypass WorkflowGateService").

---

### 8. Artisan Profile (customer-facing)
**Current screen** — `lib/screens/artisan/artisan_profile_screen.dart`
- Purpose: evaluate one artisan
- Actions: chat, hire (if job-linked), favorite
- Data: `ArtisanModel`, reviews, portfolio

**Stitch screen** — two variants: a "TrustScore" card (dark navy, 98/100, Top 5%, Craftsmanship/Punctuality breakdown, "Escrow Guarantee" note, "Start Secure Booking" button) and a "HandyTrust Score" card (lighter, Jobs Completed/On-Time Arrival stats, Verified Expertise tags, Reviews list, "Book Now" button)
- New components: trust-score visualization card, expertise tag list, standalone reviews section
- Missing data: **"Top 5%" percentile ranking and a Craftsmanship/Punctuality sub-score breakdown don't exist in `ArtisanModel` today** — only an aggregate trust score exists per `trust_score_service.dart`
- Required backend support: if the sub-score breakdown is kept, `TrustScoreService` needs new computed fields (craftsmanship, punctuality) — currently it produces one number, not a breakdown

**Category**: Direct replacement for the base layout; the percentile/sub-score breakdown is new functionality requiring backend work in `trust_score_service.dart`.

---

### 9. Wallet
**Current screen** — `lib/screens/wallet/wallet_screen.dart`
- Purpose: payment history (not milestone-aware — no milestone model exists)
- Data: `payments` collection via `customerPaymentsProvider`

**Stitch screen** — three variants, all showing **milestone-based escrow** ("Milestone 2 of 3," progress bars, "66% Locked," per-milestone amounts):
- Customer variant: "Total Funds in Escrow," Add Funds/Withdraw, Active Escrow Tasks with milestone progress, Recent Transactions
- Artisan variant: "Available for Payout," Withdraw Funds/View Statements, "Pending Clearances" figure, Active Jobs & Milestones
- Third variant: dark-navy card restyle of the customer one, same content
- Missing data: **milestone-based escrow doesn't exist in the current data model at all.** Today a job has one lump escrow payment (`PaymentModel`, locked → released on completion confirmation) — there's no `milestones` subcollection, no partial-release logic in `JobService` or the Cloud Functions webhook handler, and Firestore rules have no milestone-scoped write rules
- Required backend support: this is the single largest backend gap in the whole audit — a real milestone system needs a new subcollection, new `JobService` methods, new Firestore rules, and new Cloud Functions logic for partial Paystack releases. Not a UI change.

**Category**: **Requires new functionality**, not a visual reskin — flagged for Phase 5 treatment (build the UI structure against the *current* single-payment model, document the milestone gap rather than fabricate a working milestone UI against fake data).

---

### 10. Open Jobs Feed (artisan)
**Current screen** — `lib/screens/artisan/open_jobs_feed_screen.dart`
- Purpose: browse + quote open jobs, with live eligibility checking
- Actions: chat, submit/edit/withdraw quote (disabled with reason if ineligible)
- Data: `openJobsFeedProvider`, `artisanQuoteForJobProvider`, `artisanProfileProvider`

**Stitch screen** — two variants: "Find Jobs" (bottom nav *Find Jobs / My Jobs / Inbox / Profile*) and "Jobs matched for you" (bottom nav *Find Jobs / My Tasks / Wallet / Account*)
- "Ready to Work!" toggle, filter chips (All Matched/Recent/Urgent), job cards with "Perfect Match"/"Urgent"/category badges, "Interested" button
- Missing data: **"Perfect Match" scoring and an explicit "Urgent" flag don't exist today** — job matching/ranking exists (`MatchingService`, used for `artisan_list_screen.dart`) but isn't surfaced as a badge, and there's no urgency-flagging separate from the existing `urgency` field (`asap`/`scheduled`)
- Required backend support: none strictly required — "Perfect Match" can likely be derived client-side from existing `MatchingService` output; "Urgent" could map to `urgency == 'asap'` if that's what's intended, but that's a naming/semantics decision, not a data gap

**Category**: Direct replacement candidate, with the "eligibility gating" behavior (the one real piece of business logic on this screen) needing to stay wired to the same providers, not reimplemented.

---

### 11. Artisan Dashboard
**Current screen** — `lib/screens/artisan/artisan_dashboard_screen.dart`
- Purpose: approval/verification state, availability toggle, active jobs summary
- Data: `ArtisanModel` (approvalStatus, verificationStatus, isAvailable)

**Stitch screen** — **not present in the supplied screenshots.** The "Find Jobs"/"Jobs matched for you" screens cover job discovery but not the approval/verification-gate landing screen artisans see before they're allowed to work.

**Category**: **Gap** — flagged, same as Job Details. This screen carries real gating logic (`approvalStatus`/`verificationStatus`) that a redesign can't silently drop.

---

### 12. Profile / Settings
**Current screens** — `lib/screens/profile/profile_screen.dart`, `lib/screens/settings/settings_screen.dart`, `lib/screens/support/contact_support_screen.dart` (three separate files today)
- Purpose: account management, split across three screens

**Stitch screen** — single consolidated "Profile" screen: Account Information / Payment Methods / Security & Password / App Mode (dark-mode toggle) / Notification Settings / Support Center / Logout, all as one navigable list
- Missing data: **App Mode (dark mode) doesn't exist in the current app** — there's no `ThemeMode` toggle or persisted preference today
- Required backend support: none for the list itself; dark mode is a client-side theming task (out of scope per this task's own "do not modify themes" rule, but the *toggle UI* is a legitimate Stitch-driven addition to build once a real dark theme exists)

**Category**: Structural consolidation — three current files collapse toward one navigable list, each row still pointing at its own existing screen/provider. Dark mode toggle is new functionality (UI only, no working theme yet).

---

### 13. Recent Activity
**Current screen** — **none.** No screen in the current app shows a "Recently Viewed" list or a chronological cross-entity activity feed (applied/messaged/saved, mixed).

**Stitch screen** — "Recent Activity": Recently Viewed job cards, then an Activity Feed timeline (Applied / Message / Saved, each with a timestamp)
- Missing data: **no current provider tracks "recently viewed jobs"** (would need client-side or Firestore-backed view-history tracking), and there's no unified activity-log collection — today's data is scattered across `jobs`, `chats`, and a `favorites`-style save action with no single feed
- Required backend support: a `recentActivity` or `viewHistory` collection/subcollection, plus write-triggers wherever "view/save/apply" actions already happen

**Category**: **New screen entirely** — no current equivalent, real backend work required. Squarely a Phase 5 candidate.

---

## Summary — the four requested buckets

**1. Screens that can directly replace existing screens** (visual/structural work, data already available)
- Customer Home / Explore
- My Bookings / Job List (minus the Drafts tab)
- Chat
- My Chats / Messages
- Open Jobs Feed (minus "Perfect Match"/"Urgent" badges, which are cheap to derive)
- Artisan Profile base layout (minus the sub-score breakdown)

**2. Screens requiring new functionality** (real backend/data work, not just UI)
- Wallet — milestone-based escrow doesn't exist server-side (largest gap in this audit)
- Post a New Job — photo-unlock paywall has no backend
- Artisan Profile — Craftsmanship/Punctuality sub-scores and percentile ranking aren't computed anywhere
- My Bookings — "Drafts" tab has no draft-job concept in `JobStatus`

**3. Screens requiring only visual changes**
- Chat's sticky job-summary bar and "Proposed Schedule" message card (real functionality already exists — `WorkflowGateService`, `confirmAppointmentSlot` — just needs new presentation)
- Profile/Settings consolidation (three existing screens into one list — navigation restructuring, not new logic)

**4. Screens missing from the current app** (net-new, per Phase 5 or later)
- Job Details full page — **not exported by Stitch either; this is a gap on both sides and blocks Phase 3 for the app's most complex screen until a design exists**
- Artisan Dashboard — same, not exported by Stitch
- Recent Activity — exported by Stitch, doesn't exist in the app, real backend work needed
- Artisan Earnings (from the original task's own Phase 5 list) — partially covered by the artisan Wallet variant ("Available for Payout") but not a dedicated analytics/earnings screen
- Notification Preferences (from the original task's own Phase 5 list) — not present in any supplied screenshot at all

---

## Decisions (resolved with the user after this audit was drafted)

1. **Customer nav/IA**: `Explore / My Tasks / Wallet / Profile`. This selects the "Find your expert helper" Home variant and the green-gradient Wallet variant as canonical. My Bookings' two variants both shipped under a `Discovery/Bookings` label in the source export — since that label lost, the My Bookings screen's tab label becomes "My Tasks" going forward even though neither exported variant showed that exact pairing; its visual treatment (dark-pill tabs, chat icon in header — the screenshot-1 version) is kept since it's the more finished of the two and the difference between the two was cosmetic only (header icon, pill shade).
2. **Artisan nav/IA**: `Find Jobs / My Jobs / Inbox / Profile`. Selects the "Find Jobs" Open Jobs Feed variant (search + "Ready to Work!" toggle + All Matched/Recent/Urgent chips) as canonical over "Jobs matched for you." The artisan Wallet screenshot's nav didn't cleanly match either exported set — it now follows this same artisan label set for consistency.
3. **Artisan trust-score card**: the dark-navy "TrustScore" variant (percentile rank + Craftsmanship/Punctuality breakdown) wins over the lighter "HandyTrust Score" variant. This is flagged as **new functionality**, not a straight restyle — `trust_score_service.dart` only produces one aggregate number today; percentile rank and the two sub-scores need real computation before the UI can show real data (see Phase 5 in the build order).
4. **Dark-background Messages variant**: confirmed a stray export, discarded. Messages/My Chats builds from the light variant only.
5. **Booking wizard ("Initiate Task"/"Secure Booking")**: confirmed to be a **new, parallel "direct hire" flow**, not a replacement for the existing post→quote→negotiate→schedule→pay lifecycle. It must not touch `JobService`'s state machine or bypass `WorkflowGateService` — it's scoped as an additive entry point (see Phase 5 in the build order).
6. **Milestone-based Wallet**: confirmed **UI structure only** — no real milestone backend exists or is currently planned. The Wallet redesign will be built against the actual single-payment `PaymentModel` data, visually adapted to the new design system, without simulating fake milestone progress.
7. **Job Details**: no Stitch screen supplied yet — user is still checking for one. Implementation held until it arrives; everything else in the build order can proceed without it.
8. **Artisan Dashboard**: a follow-up screenshot turned out to be a duplicate of the already-audited "Jobs matched for you" screen (job search/matching), not the approval-status/verification/availability-toggle landing screen this refers to. Confirmed: no dedicated Stitch mockup exists for it. It's no longer held — restyle the existing `artisan_dashboard_screen.dart` with Group 1's design-system tokens directly, same treatment as the other no-mockup screens (auth, Portfolio, Notifications).

No implementation has started. Proceeding to Phase 2 (build order) next.
