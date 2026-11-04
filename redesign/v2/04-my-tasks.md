# V2 — My Tasks (Jobs List)

Fourth screen. Rebuilds `all_jobs_screen.dart` (currently titled "My Jobs") as the second primary nav tab, renamed **My Tasks** to match the reference's own label (Explore/My Tasks/Wallet/Profile). Functionally light-touch — the existing filter/query logic is sound; this is mostly a visual-language pass plus a couple of real gaps worth fixing while here.

**Evidence key**: 🟡 Extrapolated (no direct image evidence of this screen) · 🔵 Inferred · 🟠 real gap found reading the current code.

---

## What the current code already gets right (keep)
Read `all_jobs_screen.dart` directly: role-aware query source (`artisanJobsProvider` vs `customerJobsProvider`), a simple all/active/completed filter, and an already-decent empty state with role-specific copy ("Post a job to get matched with artisans" for customers, generic for artisans). None of this needs re-deriving — it's sound logic, just due for the v2 visual skin.

## 🟠 Real gap found: the active/completed split loses information the brief cares about
`isTerminal` splits jobs into exactly two buckets. That means `disputed` and `resolved` jobs land in "completed" alongside genuinely successful ones — a customer or artisan can't filter to just see disputes, and a resolved-but-contentious job reads identically to a clean 5-star completion in this list. Given how much of this program's backend work (`01-ux-audit.md`, `05-trust-score.md` §4's anomaly detection) treats disputes as a distinct, important category, the jobs list shouldn't flatten them into "completed." **Fix**: add a third filter chip, "Disputed," pulling `status in [disputed, resolved]` separately — cheap, and it directly serves a real user need ("let me see the job I'm having a problem with") that the current two-bucket split can't.

---

## Layout
1. **Page header** 🟡 — "My Tasks" title (same convention as Wallet — no full brand header on non-Home tabs).
2. **Filter chips** — All / Active / Completed / **Disputed** (🟠 new) — pill-style chips, consistent with the v2 borderless language (light gray fill, green fill only on the selected chip — reusing the exact active-state pattern already established for the bottom nav's pill, so "selected" reads consistently everywhere in the app, not as a one-off chip style).
3. **Job list** — `JobListRow` × N, borderless gray-fill cards: category/title, other party's name (artisan name for a customer, customer name for an artisan), status chip (contrast-safe, per `02-design-system-v2.md` §11's standing rule), date, amount (tabular figures) if agreed.
4. **Bottom nav** — My Tasks tab active.

## Component hierarchy
- `MyTasksScreen`
  - `PageHeader` ("My Tasks")
  - `FilterChipRow` (All/Active/Completed/Disputed) — 🟠 extended
  - `JobListRow` × N — 🟡 restyled from the current implementation's list item, reusing `job_status_badge.dart`'s underlying status logic but with the contrast-safe visual treatment
  - `V2BottomNav`

## Interactions
Tap a row → Job Detail (`v2/05-job-detail.md`, next in the pacing plan). Tap a filter chip → re-filters the existing query client-side (unchanged from current behavior — the dataset per user is small enough that this doesn't need to become a server-side filtered query).

## Animations
🔵 Inferred, consistent with prior screens: list rows fade in on load; filter chip selection uses a quick fill transition (`AppAnimations.fast`), matching the nav pill's own transition for consistency.

## Loading state
Shimmer list rows (`shimmer_loaders.dart`, already flagged in `02-design-system.md` §6.2 as needing coverage for every major list — this is one).

## Empty state
Kept from the current implementation's role-aware copy, restyled: "No jobs yet" / "No active jobs" / "No completed jobs" / 🟠 new: "No disputes — that's a good thing" for the new Disputed filter (deliberately reassuring copy for an empty disputes list, since unlike other empty states, "empty" here is the *good* outcome, not a call to action).

## Error state
Standard retry via the shared `ErrorStateView` (`02-design-system.md` §6.4).

## Success state
N/A — a list screen, not a transactional one.

## Accessibility
Filter chips need accessible selected-state announcement (not just a visual fill change) — standard for any chip/tab-like control. Status chips follow the same icon/fill-not-text-color rule as every other screen in this v2 pass.

## Responsive behaviour
🔵 Inferred: list stays single-column on all widths (a task list doesn't benefit from a grid, same reasoning as Wallet's ledger); filter chips wrap rather than scroll horizontally if space is tight, since there are only 4 now.

## Firestore implications
Unchanged data source (`artisanJobsProvider`/`customerJobsProvider`) — the new Disputed filter is a client-side filter over the same already-fetched list, per the existing `isTerminal`-based filtering pattern, not a new query.

## Cloud Function implications
None.

## Notification triggers
None originate here.

## Security considerations
Unchanged — same party-scoped job list queries already in place.

---

**Next**: Job Detail — the hub screen, and the most complex one remaining. That one gets its own full pass given `09-screens-customer-artisan.md` §2.4 already found it composing three overlapping timeline widgets simultaneously, plus needing to absorb the milestone-aware payment display, the live ETA card, and the dispute/quote sections — real complexity, not just a skin.
