# Complete Visual QA Report

Method: `flutter build web`, served locally, driven headlessly with Playwright against a real signed-in account (credentials provided by the user; not stored anywhere in this repo or report). Every screenshot below is a genuine rendered capture, not a code-level inference — except where explicitly marked otherwise.

## Scope note, stated plainly

Two things blocked full data population, both environment limitations, not app bugs:

1. **Email verification loop** — a fresh signup requires clicking a real email link; automation has no inbox access. Worked around by switching to an existing verified account (also confirmed admin-enabled) mid-session, per your instruction.
2. **Firebase Storage CORS** — job posting requires a photo, and the upload call from `localhost:8642` (the local test server) is rejected by Storage's CORS policy (`Access-Control-Allow-Origin` doesn't include arbitrary local ports — only the app's real hosting origin is likely whitelisted). Confirmed via browser console: `net::ERR_FAILED` / CORS preflight rejection on `firebasestorage.googleapis.com`. This blocked creating a **new** job, which blocked everything downstream of one (Payment/Escrow, a job-specific Chat thread from scratch). I did **not** attempt to change Storage's CORS configuration to work around this — that's a real infrastructure change with security implications, out of scope for a QA pass.

Where a real, already-existing chat thread let me route around the blocker (My Chats had two real threads from earlier testing), I used it — that's how the actual Chat screen below got a genuine screenshot instead of a code-level guess.

---

## Screen: Customer Home
**Reference:** "Find trusted experts for your home" — search bar, category chips (Electrician/Plumber/Carpenter example set), Featured Experts cards with photo/rating/Verified Pro/price.
**Current:** Rendered correctly — headline, search bar, and header (avatar, wordmark, bell with live unread badge) all match structurally. Category chips render as Plumbing/Electrical/Cleaning (the app's real category list, not the reference's 3 example categories — expected, not a bug: the reference names were illustrative, not literal). Featured Experts shows a genuine, correctly-styled empty state ("No verified experts yet" + Browse Artisans button) since no artisan in this Firebase project is `id_verified`/`trusted` yet.
**Difference:** An extra dual-role-switch icon (⇄) appears in the header, absent from the reference — this account has both customer and artisan roles enabled, and the icon is real, working functionality for switching between them.
**Severity:** P2 (data-driven, not a defect) for the empty state; not a mismatch for the extra icon (real feature, correctly kept per your "do not remove functionality" instruction).
**Fix required:** None. Empty state is marked *empty-state validation only* — cannot be resolved without a verified artisan existing in the project.

---

## Screen: My Bookings
**Reference:** Active/Completed/Drafts tabs (with counts), job cards with status pill/artisan avatar/price, FAB.
**Current:** Header, tab pills (black-selected/gray-unselected, exact style match), and FAB all render correctly. Shows genuine empty state ("No active jobs" + Post a Job button) — could not populate with a real job due to the CORS blocker above.
**Difference:** None structural — this is a real, correctly-styled empty state, not a broken layout.
**Severity:** N/A — **empty state validation only**.
**Fix required:** None from the UI side. Populating this for a true populated-card comparison requires either fixing Storage CORS for local testing (an infra task, not a code fix) or testing from the app's real deployed origin.

---

## Screen: Wallet
**Reference:** Green summary card ("Total Funds in Escrow"), Active Escrow Tasks, Recent Transactions.
**Current:** Genuine empty state ("No transactions yet" + subtitle). Confirmed the summary card is intentionally never shown at zero payments (`wallet_screen.dart`'s existing `if (payments.isEmpty)` branch) — correct, honest design, not a bug (no point showing a "₦0" card).
**Difference:** Summary card styling (color, layout, tabular-number formatting) could not be visually verified — no payment exists in this account.
**Severity:** N/A — **empty state validation only**.
**Fix required:** None identified from what's reachable.

---

## Screen: Profile / Settings
**Reference:** Centered avatar+name+location, single grouped card of plain-icon rows, App Mode toggle, separate red Logout card.
**Current:** Strong, verified match. Real data rendered correctly: avatar (green initial fallback, no photo set — correct fallback behavior), name "DI RAIZEL", location "ibadan", then My Jobs / My Chats / Account Information / Payment Methods / Security & Password / App Mode (working toggle) / Notification Settings (live unread badge) / Support Center / About HandyTrust / Admin Dashboard (this account is admin-enabled) — all plain-icon rows in one card, exactly matching the restyle done in the previous pass. Scrolled further to confirm the separate red Logout card — also renders correctly (centered, red icon+text).
**Difference:** None found. This screen's earlier restyle holds up under real rendering.
**Severity:** N/A.
**Fix required:** None.

---

## Screen: Post a New Job
**Reference:** Pill category chips, description box, photo grid, location/budget fields, urgency toggle.
**Current:** Verified end-to-end up to submission. Category chips render and select correctly (light-gray fill on select, matching the reference's selected-pill treatment exactly). Description field, "Analyze with AI" button, photo attach flow (real file picker, thumbnail preview with remove button, "1/5" counter), location field, budget fields, and the "As Soon As Possible" / "Specific Date" urgency toggle all render correctly and match the reference's structure.
**Difference:** None visual. Submission itself could not complete (CORS blocker above) — the loading state on the submit button was confirmed rendering correctly (spinner, disabled gray state) before the network call failed silently in the background.
**Severity:** N/A for the form UI itself (no mismatch found).
**Fix required:** None from the UI. Full-submission verification needs testing from a CORS-whitelisted origin.

---

## Screen: Messages / My Chats
**Reference:** Search bar, conversation cards with avatar+online dot, name, timestamp, status chip, message preview.
**Current:** Real, populated data (two existing threads). Header, search bar copy ("Search artisans or jobs...", exact match), card style (white rounded card, avatar with green online-dot), name, timestamp ("5d", "~1mo"), status chip ("Closed"), and message preview all render correctly and match the reference's structure.
**Difference:** Cards additionally show a live unread-count badge (green circle, "1"/"3") that the reference doesn't depict — real, working functionality, correctly kept per your instruction not to remove features to match a screenshot.
**Severity:** Not a mismatch (functional addition, not a defect).
**Fix required:** None.

---

## Screen: Chat (thread)
**Reference:** Avatar+name+verified checkmark+"Verified Pro" subtitle header, job summary card (title/price/status pill/"View Job Details"), message bubbles.
**Current:** Real thread rendered. Header shows avatar + "Artisan" (generic fallback name — this app has no by-id lookup for a customer/artisan display name in every code path, a pre-existing, documented limitation, not something this pass introduced) with no checkmark/subtitle since this specific artisan isn't verified — correct, honest behavior matching the header logic built in the previous pass. Job summary card renders correctly: category ("Welding"), price ("₦10000"), status pill ("Closed"), "View Job Details" expandable row. Message bubble (black, right-aligned, "hello") matches the reference's self-message styling.
**Difference:** The status pill is the same green/primary color for every phase — including this terminal "Closed" state — because `_JobSummaryBar`'s `AppBadge` always passes a fixed `color: context.colors.primary` regardless of what phase it's displaying. The reference only ever shows one in-progress state ("Awaiting Schedule"), so this isn't a direct mismatch against it, but it's a real, observable inconsistency: a "Closed"/terminal job reads visually identical to an actionable one.
**Severity:** P2 (polish, not a defect — the badge is legible and functional, just not tone-differentiated the way `JobBookingCard`'s `JobBookingTone` already is elsewhere in the app).
**Fix required:** Optional — `_JobSummaryBar` (`chat_screen.dart`) could derive its badge color from job status/tone the same way `JobBookingCard` does, instead of a fixed primary color. Not fixed in this pass since it's not a mismatch against any reference image, per "only fix visual inconsistencies where the rendered result differs from the reference."

---

## Screens not reachable this pass (code-level review only, not re-verified against a live render)

| Screen | Why blocked | Prior-pass status |
|---|---|---|
| Payment / Secure Booking | Requires an active job past agreement + scheduling — blocked by the CORS job-creation issue | Pixel-matched in an earlier pass; not re-verified live |
| Artisan Profile (customer-facing detail) | Attempted; the click-through from Browse Artisans didn't land reliably in the time available for this pass | Pixel-matched in an earlier pass (dark TrustScore card variant); not re-verified live |
| Find Jobs (artisan-side feed) | Requires a second account with `activeRole: artisan` and admin approval — out of scope for this pass given the account/CORS constraints already hit | Pixel-matched in an earlier pass; not re-verified live |
| Recent Activity | No equivalent screen exists anywhere in the app — flagged as a real product gap back in the original Stitch audit, unrelated to this QA pass | Documented gap, not built |

---

## Fixed this pass
None — every difference found against a reachable, real render was either data-driven (empty states, expected) or an intentional functional addition beyond the reference (unread badges, role-switch icon), not a genuine visual defect. The one real polish item found (Chat status-badge color) is left as an optional, disclosed follow-up rather than fixed, since it isn't a mismatch against any reference image.

## Remaining known differences
1. Chat's job-summary status badge doesn't vary color by phase/tone (P2, optional).
2. Four screens (Payment, Artisan Profile, Find Jobs, and by extension anything requiring a populated job) remain verified only at the code level from the previous pass, not against a live render, due to the CORS/account constraints documented above.
3. Category chip icons throughout the app are Material Icons approximating the reference's icon glyphs, not literal asset matches — a standing, previously-disclosed limitation.
