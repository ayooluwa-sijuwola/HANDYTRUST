# Stage 8.1 — Artisan visual QA report

**Date:** 5 November 2026
**Scope:** the rebuilt artisan screens compared against the approved artisan previews (`test_visual/previews/goldens/ar*`, `au06*`).
**Companion:** `design/STAGE8_1_IMPLEMENTATION_REPORT.md`

## 1. Method

- **What is rendered:** the real artisan widgets (not the preview mock-ups), via `test_visual/artisan_visual_test.dart`. Fixture data is modelled on the approved previews. It is test-only and supplied through provider overrides.
- **Frame:** the same as the approved previews: 390 pt wide at 1.5×, light and dark. The My Jobs board is rendered at 1024 × 740.
- **Fonts:** the real app fonts are loaded from the font manifest, not Flutter's square test glyphs.
- **Fixed clock:** every capture runs at 5 Nov 2026, 10:14, via `withClock`. Countdowns, "20m ago" labels and dates are therefore identical on every run, so the 54 captures are real regression baselines. Without it, a "20m ago" → "21m ago" tick broke 12 captures between two runs.
- **Responsive sweep:** each screen, in both themes, at 320 × 568, 360 × 780 and 430 × 932 (2×). A test fails on any overflow or layout exception.
- **Side-by-side review:** `design/stage8_1_artisan_vs_approved/<screen>_<theme>.png` shows the approved preview on the left and the implementation on the right. I reviewed them by eye and fixed the defects in §4.

Goldens: `test_visual/goldens/artisan/` (54 files). Re-run with `flutter test test_visual/artisan_visual_test.dart`.

## 2. Results

| Suite | Result |
|---|---|
| Responsive sweep: 26 screens × 2 themes × 3 sizes | **156 / 156**, no overflow or exception |
| Captures at the approved frame (26 × 2) plus tablet board (× 2) | **54 / 54** match their baselines |
| Stage 8 customer goldens (unchanged) | **88 / 88** |
| Approved preview goldens (unchanged) | **170 / 170** |

## 3. Screen-by-screen comparison

| Screen | Approved preview | Match | Notes |
|---|---|---|---|
| Home (working artisan) | `ar01_home` | Layout, header, availability, action queue, pipeline, next appointment, this month, trust card | Queue holds 5 real actions from the fixture (preview 3); "In escrow" includes jobs in review |
| Home (new artisan) | `ar01n_home_new_artisan` | Setup steps, payout reminder | Real zero pipeline and ₦0 totals instead of the "No jobs yet" card (deviation 7) |
| Find Work | `ar02_find_work` | Segments, search, filters, job rows, Quote buttons | Chat icon per job (existing pre-booking chat); distance shown only when the artisan has set a service area |
| Quote composer | `ar02b_quote_composer` | Labour, materials, duration stepper, fee line | Fee % from server config |
| My quotes | `ar02q_my_quotes` | Quote rows with status | Limited to open matched jobs (deviation 5) |
| My Jobs (phone) | `ar03_my_jobs` | Chips with counts, grouped tickets, Chat + next action | Groups follow real stages |
| My Jobs (tablet board) | `ar03t_my_jobs_tablet` | Pipeline board | Real columns + Disputed when present (deviation 4) |
| Booking request | `ar03r_booking_request` | Countdown ring, job card, banner, Decline / Accept | No customer name (deviation 3); window from server config |
| Work order | `ar04_work_order` | Header card, stepper, tabs, progress meter, bottom bar | Stepper "Funded" (deviation 1); an Activity tab instead of a separate Schedule tab on ASAP jobs |
| Agreement | `ar04a_agreement` | Banner, scope, price, both parties' status | The artisan reviews and accepts the customer's draft (deviation 2) |
| Submit work | `ar05_submit_work` | Checklist, photos, notes, 14-day banner, privacy note | Separate before and after photo sections (both required by `submitCompletion`) |
| In review | `ar05r_in_review` | Countdown ring "11 d", release date | Plus the "Now" explanation from the workflow gate |
| Rework | `ar06_rework` | Customer's reason, response box | Shown inside the work order with "Resubmit work" as the primary action. The response is optional: the rules treat resubmission as the normal `inProgress → submitted` step (`firestore.rules:406-420`) |
| Dispute | `ar07_dispute` | Status, claim, response, evidence | Evidence thumbnails appear when the dispute has them |
| Earnings | `ar08_earnings` | Released total, month bars, escrow / awaiting tiles, payout card, ledger | Ledger shows "Job #HT-…" when the job title isn't loadable |
| Payout account | `ar08p_payout_account` | Bank, account number, name | NUBAN validation |
| Profile | `ar09_profile` | Public card, stats, skills, business, account | Adds Messages and About rows; "Joined" date |
| Business profile | `ar09b_business_profile` | Account type, service area, radius chips | Radius capped at the server maximum |
| Verification | `ar09v_verification` | Status hub | Uploads use the Stage 8 flow (deviation 10) |
| Portfolio | `ar10_portfolio` | Projects / Photos | Empty-state fixture |
| Portfolio project | `ar10e_portfolio_project` | Editor | Category dropdown (deviation 6) |
| Notifications | `ar11_notifications` | Category chips, Today / Earlier, unread dots | "Mark all read" and a Notification settings link |
| Messages | `ar12_messages` | Conversation list with unread counts | — |
| Chat (artisan) | `ar12c_chat` | Work strip with six-step stepper | Header says "Customer" (deviation 3) |
| Loading / error | `ar13_loading`, `ar13e_error` | Skeleton and retry states | — |
| Artisan registration | `au06_artisan_registration` | Header, intro, sections, submit bar | **Deviation:** a category dropdown and free-text skills instead of the preview's chips. The backend stores `skills` as one text field and the validators are unchanged (skills ≥ 10 chars, bio ≥ 20, area required) |

## 4. Visual defects found and fixed

| Defect | Where | Fix |
|---|---|---|
| Heading overflowed by 20 px at 320 pt | Rework card | `Expanded` heading |
| "Not funded yet" on a funded job | Work order header | Derived from job status / `escrowLockedAt` |
| Disputed job missing | Tablet board | Disputed column |
| Budget cut off ("₦20,000 – …") | Find Work rows | Budget takes all free space |
| "HOW CUSTOMERS S…" truncated | Section headers with a trailing link | Label takes the free space |
| Stage pills truncated ("Booking …") | Board tickets | Two-line pills |

All six were re-captured and checked again by eye after the fix.

## 5. Light and dark

Every screen is captured and swept in both themes. Colours come only from the HandyTrust palette (`context.ht`) and the Pro accent helpers. The chart palette is the validated one: light `#6E7D31` / `#2A78D6` / `#D55181`, dark `#8E9F45` / `#3987E5` / `#D55181`.

## 6. Limits

- Widget-test rendering, not a device. Real-device checks (keyboard insets, platform pickers, camera) remain for a manual pass on hardware.
- Screens that show photos use empty or placeholder fixtures; network images aren't fetched in tests.
