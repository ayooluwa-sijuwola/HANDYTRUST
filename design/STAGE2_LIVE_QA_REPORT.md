# Stage 2 Live QA Report — Non-Storage Functionality

Continuation of `COMPLETE_VISUAL_QA_REPORT.md` and `STORAGE_UPLOAD_ROOT_CAUSE.md`. Storage is confirmed deferred (project decision — not provisioned, not being worked around). Every screen below was captured from the real running app (`flutter build web`, served locally, driven with Playwright against a real signed-in admin+customer+artisan account), not inferred from code.

## Storage-dependent flows — blocked, deferred, not tested as passing

Per instruction, these are **not** claimed to work. Each requires an actual file upload, which requires the Storage bucket that doesn't exist yet:
- Job photo upload (blocks job creation entirely — the form requires ≥1 photo)
- Profile photo change (Settings screen has a working camera-icon affordance for this, confirmed reachable, upload itself untested)
- Artisan verification (ID + selfie upload) — Settings' "Verification: Upload ID & selfie" row confirmed reachable, upload itself untested
- Portfolio photo management — Settings' "Portfolio: Manage work photos" row confirmed reachable, upload itself untested
- Business Profile, if it includes a logo/cover image field — not verified either way, deferred out of caution

Downstream of these: **creating a new job** (blocked by the required-photo gate), and therefore anything only reachable from a freshly-created job (a new Payment/Escrow flow, a new Chat thread). Testing continued using **already-existing** real jobs/chats/data from earlier sessions instead, which is why Chat and Job Detail below *are* covered — those specific records predate the Storage gap being hit today.

## What was genuinely tested live and works

**Job Detail** (existing cancelled job, reached via a real chat thread's "View Job Details") — full `WorkflowTimeline` in detailed mode renders correctly: Job Posted → Artisan Matched → Negotiating (all completed, blue checkmarks), remaining steps correctly grayed out, then a red "Job Cancelled" terminal step with reason "Found another artisan". Service Category, Description, Agreed Amount, and the `_CancellationInfoBox` at the bottom all render correctly. One observation, not confirmed as a bug: the counterparty card shows the same name as the signed-in customer ("DI RAIZEL") — plausibly this account's own dual customer/artisan role being both sides of old test data, not necessarily a real defect; flagged rather than silently ignored.

**Admin Dashboard** — home screen renders live stats (Total Users: 25, Total Artisans: 6, Active Jobs: 0) with correct percent-change indicators, no console errors. Drawer navigation lists all 12 sections (Dashboard/Users/Artisans/Jobs/Verifications/Disputes/Reviews/Support Tickets/Deletion Requests/Audit Logs/Analytics/Settings) correctly, with the "Super Administrator" role label at the bottom.

**Admin → Artisans**: "Pending Approval" tab shows a genuine, correctly-styled empty state (no pending applications). "All Artisans" shows a real 6-row data table (Name/Category/Status/Rating columns) — **the Beta badge renders correctly** next to the one beta-flagged artisan in the list. Opening that artisan's detail panel confirms the full feature end-to-end with live data: Approval status badge, trust score/rating/job-count stats, "Verification: unverified", **"Eligible to Quote: YES"** (proving the beta bypass logic actually computes correctly for a real unverified-but-beta-flagged account), and the Beta Tester switch itself showing **ON**. The switch was not toggled during this pass — verifying its live *display* state was sufficient; flipping it would be a real write to live data beyond what verification required.

**Artisan Dashboard ("Find Jobs" home)** — avatar, "Available for new jobs" toggle (on), a "Verification Deferred / Verify anytime to unlock quoting / Verify Now" banner, stats row (Rating/Completed/Trust Score, all real zero/new values), quick-action buttons (Browse Open Jobs / My Chats / Payout Details / Portfolio / Business Profile), and a real "Active Jobs (3)" list with a genuine job card (category, description, date, phase badge, status chip). Bottom nav correctly shows the artisan-specific label set (Find Jobs/My Jobs/Inbox/Profile).

**Open Jobs Feed** — search bar, "Ready to work!" toggle, All Matched/Recent/Urgent filter pills, and real job cards with budget/location/urgency chips and Chat/I'm Interested buttons. Some card text contains obvious junk test data ("Ibadanmnnnnnnnnnnnnnnnnn") from earlier manual testing — that's bad *data*, not a rendering defect.

**Bank Details (Payout Details)** — real, populated form (bank name, account number, account name), no Storage dependency, renders and would plausibly save correctly (not submitted, to avoid altering real payout data unnecessarily).

**Settings** — comprehensive and correctly organized: Account (Username/Display Name/Email/Change Password), Role & Status (Active Mode, Verification entry point), Appearance (**Dark Mode toggle correctly showing Off** — confirms the theme-default fix from the earlier visual QA pass is holding), Notifications (toggle On), Artisan-only section (Payout Details/Business Profile/Portfolio), Support (Help & Support). No console errors on any of these views.

**Notifications feed** — real, populated, multiple notification types (Customer Confirmed the Agreement, Quote Accepted, New Quote Received) with correct icons, timestamps, unread state/highlight, and "Mark all read" / "View job" actions all present and correctly styled. Confirms the notification-system work from earlier in this project is functioning end-to-end against real Firestore data.

**Profile (both roles)** — customer variant and artisan variant both verified live; the artisan variant correctly shows the additional "My Reviews" row that the customer variant doesn't, confirming the `isArtisanMode` conditional works as built.

No console/page errors were captured on any of the screens above.

## Side effect from testing, worth knowing about

Earlier live-testing (this session) tapped the customer/artisan role-switch icon on Home, which is a real, working feature — it wrote `activeRole: 'artisan'` to this account's Firestore user document. That change **persists**: the test account will keep landing on the Artisan Dashboard on login until someone switches it back (via the same icon, from either mode). Not a bug — just a real side effect of exercising a real feature, flagged so it isn't mistaken for one.

## Updated production-readiness blocker list

1. **Firebase Storage not provisioned** (`design/STORAGE_UPLOAD_ROOT_CAUSE.md`) — intentionally deferred. Blocks: job photo upload (and therefore new job creation), profile photo change, verification document upload, portfolio image upload, and anything downstream of a freshly-created job.
2. Everything else tested in this pass — Admin (dashboard, artisan management, Beta Tester feature), Artisan Dashboard, Open Jobs Feed, Job Detail, Chat, Notifications, Settings, Bank Details, Profile (both roles) — **works correctly against real data**, no defects found.
