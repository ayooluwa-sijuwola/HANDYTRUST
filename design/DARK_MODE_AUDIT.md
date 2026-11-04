# Dark Mode Visual Quality Audit

Scope: audit and fix Dark Mode only. Light Mode is the already-approved,
screenshot-matched baseline (`design/COMPLETE_VISUAL_QA_REPORT.md`) and was
**not** redesigned — every fix below either reads a value that's identical
to the pre-existing light-mode literal (verified byte-for-byte, e.g.
`Colors.white` → `context.colors.surface`, where `AppColorsExtension.light.
surface == Colors.white` exactly) or is branched so it only ever executes
in dark mode. A final light-mode regression screenshot (Home) was diffed
against the pre-fix baseline and is visually identical.

Method: read every dark-mode token and every widget that references them
(`lib/theme/app_colors.dart`, `app_theme.dart`, `app_design_system.dart`,
then every `context.colors.*`/`Colors.white`/`Colors.black` hit across
`lib/screens` and `lib/widgets`), then rendered the real app — `flutter
build web`, served locally, driven with Playwright against a real signed-in
account — in Dark Mode across Home, Find Jobs (hub + Open Jobs feed), My
Bookings, Wallet, Post a Job, Messages, Chat, Job Detail, Verification,
Artisan Profile, Settings/Profile, and Admin Dashboard, before and after
each fix.

## Problems found

### 1. `border`/`borderLight` were identical to the surfaces they're drawn on
`AppColorsExtension.dark.border` (`0xFF334155`) was byte-identical to
`surfaceVariant` (`0xFF334155`), and `borderLight` (`0xFF1E293B`) was
byte-identical to `surface` (`0xFF1E293B`). Any `Border.all(color: context.
colors.border)` drawn around a `surfaceVariant`-filled element, or
`borderLight` against a `surface`-filled one, had exactly zero contrast —
an invisible border. This is a token-definition bug, not a per-widget one:
every one of the ~35 files that reference these tokens inherited it.

### 2. Fixed "commitment" tones (`ink`, `navy`) collided with the dark page
`AppColors.ink` (`0xFF111827`) and `AppColors.navy` (`0xFF0F172A`) are
deliberately theme-**independent** — a bold near-black/navy accent meant to
pop against a light page for `CommitButton` (Post Job, Lock Funds, Hire
This Artisan) and `TrustScoreCard`/`PillTabSelector`'s selected pill. In
dark mode, `AppColors.navy` is **exactly** `AppColors.darkBackground`
(`0xFF0F172A` = `0xFF0F172A`), and `ink` measures ~1.03:1 contrast against
it — both are effectively invisible against the dark scaffold. Worse,
`TrustScoreCard` didn't even go through the theme extension — it hardcoded
`color: AppColors.darkBackground` directly, so it was byte-identical to the
page background in dark mode regardless of theme wiring. The same pattern
was found duplicated ad hoc in `JobBookingCard`'s "View Details" button and
the My Bookings floating action button.

### 3. `PillTabSelector`'s selected state inverted the visual hierarchy
Because the selected pill used the same colliding `navy` value, the
*selected* "Active (0)" tab on My Bookings rendered as a near-invisible gap
while the *unselected* "Completed"/"Drafts" tabs (a lighter `surfaceVariant`
fill) were clearly more visible — selected read as less prominent than
unselected, backwards from what a tab selector should communicate.

### 4. Hardcoded `Colors.white`/`Colors.black`, confined to Home screen
Six spots in `home_screen.dart` (`_ActiveBookingMiniCard`, `_QuickActionRow`,
`_EmptyFeaturedCard`, `_FeaturedExpertCard`, the "No active bookings" empty
card, and the category-chip fill) hardcoded `Colors.white`/`Colors.black`
instead of a theme token. In dark mode this produced literal white card
islands floating on the dark page — and worse, the text drawn on top of
them (`context.colors.textPrimary`, which is near-white in dark mode) was
*also* rendered on that same white background, making it nearly illegible
("washed out"). This was the single most visible defect — Home is the
first screen most users see. A repo-wide grep confirmed this pattern did
**not** recur elsewhere; every other screen already themed its card fills
correctly.

### 5. No elevation tier above `surface` — dialogs/sheets/elevated cards were flat
The dark palette had exactly three tiers (`background` → `surface` →
`surfaceVariant`), with nothing between "a card" and "an inset fill." There
was no way for a dialog or bottom sheet to visually "pop" above the card
that triggered it — the default Material dialog/sheet would have inherited
`colorScheme.surface` (`darkSurface`), the *same* tone as an ordinary card
behind it.

### 6. Shadows are invisible in dark mode by construction
`AppShadows.cardDark`/`floatingNavDark` are black, semi-transparent
shadows. On a page background that's already near-black (`0xFF0F172A`), a
black shadow has no perceptible effect — dark-mode "elevation" was
carrying zero actual visual weight, contributing to the "flat" complaint.

### 7. `textTertiary` (and everything reusing its literal) failed contrast
`0xFF64748B`, used for tertiary text, input hints, unselected bottom-nav
items, and `labelSmall`, measured **~3:1** against `darkBackground` and
**~3.67:1** against `darkSurface` — below the WCAG AA 4.5:1 threshold for
normal text on all four uses.

## Root cause

Two distinct root causes, not one:

- **Token-definition bugs** — `border`/`borderLight` were assigned values
  equal to sibling tokens instead of genuinely distinct ones (items 1, 7).
- **Theme-independent literals used where a theme-aware token was needed**
  — `ink`/`navy` are *intentionally* fixed across themes for their original
  purpose (popping against a light page), but nothing gave dark mode its
  own version of that idea, and one widget (`TrustScoreCard`) bypassed the
  theme extension entirely and hardcoded the literal that happens to equal
  the dark scaffold background (items 2, 3, 4's chip-selected state).

Item 4 (Home's hardcoded white cards) is a separate, simpler bug: those six
spots were never wired to the theme system at all, on either theme — they
happened to look correct in light mode purely because `Colors.white`
coincides with light mode's `surface` token, and broke the instant dark
mode was selected.

## Tokens changed

All changes are additive or dark-mode-scoped; every light-mode value is
byte-for-byte unchanged.

| Token | Before (dark) | After (dark) | Why |
|---|---|---|---|
| `border` | `0xFF334155` (= surfaceVariant) | `0xFF44536D` | Now visible against both `surface` and `surfaceVariant` |
| `borderLight` | `0xFF1E293B` (= surface) | `0xFF29374C` | Now visible against `surface` |
| `surfaceElevated` (**new**) | — | `0xFF25324A` | Dialogs/sheets/explicitly-elevated cards get their own rung above `surface` |
| `textTertiary` | `0xFF64748B` (~3:1 vs background) | `0xFF8A97AE` (~6.1:1 vs background, ~5.0:1 vs surface) | Passes WCAG AA for normal text |
| `disabled` (**new**) | — | `0xFF64748B` (the old textTertiary value) | Genuinely disabled/decorative UI is allowed sub-AA contrast per WCAG; repurposed rather than discarded |
| `ink` (dark only) | `0xFF111827` (shared with light, ~1.03:1 vs darkBackground) | `0xFF26344C` + hairline light border on the widgets that use it | `CommitButton`, `JobBookingCard`'s dark button, and the My Bookings FAB now read as raised buttons, not gaps |
| `navy` (dark only) | `0xFF0F172A` (**identical** to darkBackground) | `0xFF1C2942` + hairline light border where used | `TrustScoreCard` and `PillTabSelector`'s selected pill no longer disappear |
| `navySurface` (dark only) | `0xFF1E293B` | `0xFF16223A` | Kept distinct from the new `navy` value |

`AppColorsExtension` gained two new fields (`surfaceElevated`, `disabled`)
across the class definition, constructor, `light`/`dark` instances, and
`lerp()` — light mode's values (`surfaceElevated: AppColors.surface`,
`disabled: AppColors.textTertiary`) are explicit no-ops matching what light
mode already did implicitly.

`ThemeData.dark` gained explicit `dialogTheme`/`bottomSheetTheme` using
`surfaceElevated`; `ThemeData.light` gained the same, explicitly pinned to
`AppColors.surface` (white) so it matches Material3's prior default
exactly — added only so dark mode had something to override.

## Screens/widgets affected

| File | Change |
|---|---|
| `lib/theme/app_colors.dart` | New/fixed dark constants: `darkSurfaceElevated`, `darkBorder`, `darkBorderLight`, `darkTextTertiary`, `darkDisabled`, `darkInk`, `darkNavy`, `darkNavySurface` |
| `lib/theme/app_theme.dart` | `AppColorsExtension` gains `surfaceElevated`/`disabled`; dark instance wired to the new constants; dark `hintStyle`/`unselectedItemColor`/`labelSmall` migrated off the old low-contrast literal; explicit `dialogTheme`/`bottomSheetTheme` for both themes |
| `lib/theme/app_design_system.dart` | `appCardDecoration(elevated: true)` uses `surfaceElevated` in dark mode; `CommitButton` gets a dark-mode-only hairline border |
| `lib/widgets/pill_tab_selector.dart` | Selected pill gets a dark-mode-only hairline border |
| `lib/widgets/trust_score_card.dart` | Fixed the `AppColors.darkBackground` hardcode → `context.colors.navy`; added dark-mode hairline border |
| `lib/widgets/job_booking_card.dart` | `primaryDark` button now uses `context.colors.ink`/`onInk` instead of the fixed `AppColors.darkBackground` literal, plus a dark-mode border |
| `lib/screens/home/home_screen.dart` | 6 hardcoded `Colors.white`/`Colors.black` spots (empty-bookings card, active-booking mini card, quick-action rows, empty-featured card, featured-expert card, category chips) now theme-aware |
| `lib/screens/home/all_jobs_screen.dart` | My Bookings FAB uses `context.colors.ink`/`onInk` instead of `AppColors.darkBackground` |

Screens rendered and confirmed correct (several needed no change — see
Before/after below): Home, Find Jobs hub, Open Jobs feed, My Bookings,
Wallet, Post a Job, Messages, Chat (thread + job summary), Job Detail,
Verification, Artisan Profile, Settings/Profile, Admin Dashboard.

## Before/after assessment

- **Home (Discovery)** — Before: "Featured Experts" empty-state card and
  category chips rendered as stark white islands on the dark page, with
  near-white body text nearly illegible against that white fill. After:
  every card/chip uses the dark surface tone; text is fully legible; chip
  selection uses the new raised `ink` tone with a visible edge.
- **My Bookings** — Before: the selected "Active (0)" tab pill was nearly
  invisible (same color as the page), while unselected tabs looked more
  prominent. The FAB blended into the page. After: the selected pill and
  FAB both read clearly as raised elements via the new `ink`/`navy` tones
  plus hairline borders.
- **Artisan Profile** — Before (predicted from the `AppColors.darkBackground`
  hardcode, confirmed by fix verification): the dark navy stats bar
  (Rating/Jobs done/Response) would have been indistinguishable from the
  page. After: renders as a clearly bounded card.
- **Wallet, Post a Job, Messages, Chat, Job Detail, Verification, Settings/
  Profile, Admin Dashboard** — Already correct before this pass; confirmed
  via live render, no changes made. Admin Dashboard in particular already
  had its own well-built, dark-aware elevation system (`AdminPalette`, a
  separate palette scoped to `/admin/*` with its own background/card/text
  ladder and alpha-based borders that are visible against any fill) — it
  was not touched.
- **Light mode** — Confirmed pixel-identical via a direct before/after
  screenshot comparison of Home (the most heavily edited file).

## Accessibility

- Fixed: `textTertiary` now clears WCAG AA (4.5:1) for normal text against
  both `background` and `surface` — was ~3:1–3.67:1 before, affecting
  timestamps, hint text, unselected bottom-nav labels, and `labelSmall`
  text everywhere those are used.
- Deliberately not fixed uniformly: the old low-contrast value was kept as
  a new `disabled` token rather than discarded, for genuinely disabled/
  inactive UI where WCAG explicitly does not require text-level contrast.
  This avoids "solving contrast by making everything white."
- Not chased further: `statusRequested`/`statusResolved` (`0xFF64748B`,
  used as small status-chip text/icon color, typically on a tinted
  same-color translucent background rather than directly on the page) were
  left unchanged — no live rendering showed a legibility problem on any
  status chip, and changing them wasn't backed by a concrete observed
  defect the way `textTertiary` was.
- Buttons/cards that rely on a "raised dark" fill (`ink`, `navy`) get a
  hairline `Colors.white.withValues(alpha: 0.10)` border specifically
  because pure luminance contrast between two dark tones is inherently
  low (a professionally-designed dark card on a dark page will never hit
  4.5:1 against the page by fill color alone) — the border, not the fill
  alone, is what makes the edge unambiguous. This mirrors the technique
  `AdminPalette` (untouched, pre-existing) already used successfully.

## Remaining limitations

- `AppShadows.cardDark`/`floatingNavDark` were not redesigned — a black
  shadow on a near-black page contributes little regardless of alpha
  tuning. Dark-mode elevation now leans primarily on the `surfaceElevated`
  fill tier (a real, visible tone change) rather than shadow; the existing
  shadow is kept as a secondary, minor cue rather than removed, since
  doing so wasn't necessary to fix the concrete defects found.
- `TrustScoreCard`'s populated state (score >0, real component chips) was
  verified structurally and via the fixed `navy` token, but no artisan in
  the current Firestore project has completed jobs/ratings to trigger it —
  same limitation already disclosed in `design/COMPLETE_VISUAL_QA_REPORT.md`.
  The *empty*-eligible stats bar on Artisan Profile (which does render
  unconditionally) was confirmed live.
- `CommitButton`'s other call sites (Post Job submit, Lock Funds in
  Escrow) remain blocked from a live dark-mode render by the same
  pre-existing, deliberately deferred Firebase Storage gap documented in
  `design/STORAGE_UPLOAD_ROOT_CAUSE.md` — the fix was verified via the
  `ink` token's live-rendered use elsewhere (Home's chips, My Bookings'
  FAB, JobBookingCard, Artisan Profile) rather than on those two specific
  screens.
- Status colors (`statusRequested` through `statusResolved`) and escrow
  colors were audited but left unchanged — no defect was found in any
  live render, and the task's own instruction was to fix confirmed
  problems, not repaint tokens without cause.

## Validation performed

- `flutter analyze` — 12 pre-existing issues (unrelated unused import,
  deprecated API usage, `use_build_context_synchronously` info-level
  hints), zero new issues introduced by this change.
- `flutter test` — all 85 tests pass.
- `flutter build web --release` — builds cleanly.
- Live-rendered, real-account Playwright verification in both themes:
  Home, Find Jobs hub, Open Jobs feed, My Bookings, Artisan Profile,
  Settings/Profile, Admin Dashboard — before and after the fix, plus a
  final light-mode-unchanged regression screenshot.
