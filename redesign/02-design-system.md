> **Superseded by `02-design-system-v2.md`.** This document formalized the app's existing code-based theme in the absence of visual reference material. Reference images have since been provided; `02-design-system-v2.md` extracts from those instead and takes priority wherever the two disagree (see v2 §9 for the specific open conflicts — card borders, nav architecture, Wallet's nav placement, primary green shade). Kept here for its still-valid analysis (accessibility contrast findings, the `AdminPalette` refactor reasoning, motion/spacing tokens not contradicted by the new reference).

# 02 — Design System & Component Library

Formalizes the existing in-app design language (`lib/theme/app_colors.dart`, `app_design_system.dart`, `app_theme.dart`) into a complete, governed system, closes the gaps found reading that code directly, and resolves the admin color-system question flagged in `01-ux-audit.md` §3.3.

**No reference recording was available for this pass** (per `00-overview.md`). Everything below extends decisions already live in the codebase rather than inventing a new direction. Every place I'm making a genuinely new call — not just formalizing what exists — is marked **[NEW]** so it's easy to find and push back on.

---

## 1. Design principles

Four rules the system should be checked against, derived from the brief (trust, transparency, premium, distinctly Nigerian) and what the codebase already does well:

1. **Trust Green is the brand, not a UI accent.** `#22C55E` already carries escrow-locked, success, primary CTA, and completed-status meaning simultaneously in the current code. That's correct for a marketplace whose pitch *is* trust — keep green load-bearing, don't dilute it by introducing competing "bright" colors for routine UI.
2. **Status must be legible before it's styled.** Job/escrow/verification states are the product's nervous system (nine `statusX` colors already exist for exactly this reason). Every new component that shows state must use the existing status token set, never a one-off color.
3. **Premium reads as restraint, not decoration.** The existing theme already made good calls here — 0-elevation cards with hairline borders instead of drop-shadow soup, no elevation on AppBars, a single floating shadow reserved for the nav bar. Keep extending that restraint rather than adding visual noise.
4. **Every dark-mode pair is a first-class deliverable, not an afterthought.** `AppColorsExtension.dark` already exists and is thorough — the system's job going forward is making sure every *new* token gets a dark pair at the same time it's authored, not retrofitted later (see Gap 1 below for where this already slipped).

---

## 2. Color system

### 2.1 What's already correct — keep as-is
- Primary Trust Green scale (`primary #22C55E` / `primaryLight #4ADE80` / `primaryDark #16A34A` / `primarySurface #DCFCE7`) and its dark-mode remapping (`primarySurface` → `#14532D`, a real dark-surface color rather than the light tint at reduced opacity — this is the right technique, not a shortcut).
- The `AppColorsExtension` + `context.colors` pattern (`app_theme.dart:218-221`) — a `ThemeExtension` accessed via a context getter is the correct Flutter-idiomatic way to ship a themed, dark-aware palette, and it already covers `lerp()` for animated theme-switch transitions. No architectural change needed here.
- Status-chip palette (9 job-lifecycle colors) — matches Firestore's actual state machine 1:1, including having `statusResolved` reuse the neutral gray rather than inventing a tenth color. Good discipline.
- Semantic pairing convention (`color` + `colorSurface` for every semantic — error/errorSurface, warning/warningSurface) — this is a solid, extensible pattern; every new semantic color must follow it.

### 2.2 Gaps found reading the code directly

**Gap 1 — Escrow-specific colors have no dark-mode pair. [Fix, not new direction]**
`escrowLocked` / `escrowPending` / `escrowReleased` (`app_colors.dart:16-18`) exist only as raw `AppColors` constants — unlike every other semantic color, they were never added to `AppColorsExtension`, so no `context.colors.escrowX` exists and no dark-mode remapping exists for them. Any escrow-status UI written today either hardcodes the raw light-mode value (wrong in dark mode — `escrowPending`'s `#F59E0B` on a dark background has materially different contrast than intended) or reuses `statusEscrowLocked`/`statusInProgress`/`statusSubmitted` as an approximation. Given escrow is the single highest-trust-stakes surface in the app (per `01-ux-audit.md` 1.1), this needs to be exact, not approximate.

**Fix**: add `escrowLocked`, `escrowPending`, `escrowReleased` (+ a needed fourth, `escrowFailed`, for the payout-failure path being built in the Phase 1.5 hardening sprint) to `AppColorsExtension`, with dark-mode values following the same brightening technique already used elsewhere (e.g., `warning #F59E0B` → `#FBBF24` in dark). This is groundwork the Phase 1.5 Track A payout UI will need directly.

**Gap 2 — No disabled/pressed/focus state tokens.**
The theme defines default component states thoroughly but no explicit disabled-state color, pressed-state overlay, or focus-ring color. Material 3's default state-layer opacity mechanics partially cover this automatically via `ColorScheme`, but nothing was found explicitly tuning it for this palette (e.g., what a disabled green primary button should look like — is it just `primary` at reduced opacity, or a distinct muted tone?). **[NEW]** — define `textDisabled` (`#CBD5E1` light / `#475569` dark) and standardize on Material's built-in 38%-opacity disabled convention rather than inventing a bespoke one, since it's already accessible and predictable.

**Gap 3 — No overlay/scrim token beyond `cardGradient`.**
Modal sheets, image lightboxes (portfolio viewer), and dialogs need a consistent backdrop scrim. Only `AppGradients.cardOverlay` (a black-to-transparent gradient for image captions) exists — there's no flat scrim color for bottom sheets/dialogs. **[NEW]** — add `AppColors.scrim = Color(0x99000000)` (60% black), same value in both themes (scrims don't need a dark-mode remap — they sit over content, not as content).

**Gap 4 — Rising/Trust badge colors don't fully reconcile with the corrected Trust Score work in the hardening sprint.**
`risingBadge` (purple `#8B5CF6`) and `trustElite`/`trustTrusted` (amber/green) are visually distinct systems answering two different questions ("is this artisan new" vs. "how trusted is this artisan"), which is conceptually correct — but once `01.5`'s Track B makes `trustScore` the actual ranking input, the tier boundaries these colors represent (`tierLabel`: 90+ Excellent, 75-89 Trusted, 60-74 Good, 40-59 Fair, <40 New) need a 1:1 badge color per tier, and today only two of five tiers (`trustElite`, `trustTrusted`) have dedicated colors. **Fix**: extend to five tier colors — this is detailed in `05-trust-score.md`, flagged here so the color tokens are ready when that phase lands rather than retrofitted.

### 2.3 Accessibility check on existing pairs
Spot-checked the highest-traffic text/background pairs against WCAG AA (4.5:1 for body text, 3:1 for large text/UI components):

| Pair | Approx. ratio | AA body text (4.5:1) | Note |
|---|---|---|---|
| `textPrimary #0F172A` on `surface #FFFFFF` | ~17.9:1 | ✅ | |
| `textSecondary #475569` on `surface #FFFFFF` | ~7.5:1 | ✅ | |
| `textTertiary #94A3B8` on `surface #FFFFFF` | ~2.6:1 | ❌ fails body text | Only safe for large text (18pt+/14pt+bold) or non-text UI (icons, dividers) — confirm every current usage is a label/caption context, not paragraph body copy |
| `ratingGold #F59E0B` on `surface #FFFFFF` | ~2.2:1 | ❌ fails as text color | Fine as a fill (star icon), unsafe if ever used as text color directly — e.g., a "4.8" rating number rendered in gold-on-white needs `textPrimary` instead, with gold reserved for the star glyph |
| `primary #22C55E` (white text on it, buttons) | white on `#22C55E` ≈ 2.5:1 | ⚠️ borderline | Passes AA for large/bold text (18pt+) which is what button labels typically are (16px/w600 per `elevatedButtonTheme`), but is close to the line — recommend keeping button label weight at 600+ and never dropping button text below 15px, or shift to `primaryDark #16A34A` as the button fill for a safer margin |

**Action for Phase 2 build-out**: audit every live usage of `textTertiary` and `ratingGold` as a text color (not fill) and correct any body-text usage found. This is a cheap, mechanical pass — flag it as a Phase 1.5-adjacent quick win, not a new phase.

---

## 3. Typography

**Keep**: single-family Inter, bundled as a local variable-font asset (`assets/fonts/Inter/Inter-VariableFont_opsz,wght.ttf`). This is the right call for a Nigerian marketplace where network conditions can't be assumed — a bundled font has zero runtime dependency on a CDN fetch, unlike `GoogleFonts.inter()`.

**Fix**: the `google_fonts` package is a declared dependency (`pubspec.yaml`) but never used — the theme hardcodes the literal string `'Inter'` everywhere instead. **Remove the `google_fonts` dependency.** Keeping an unused package that *could* silently start making network calls to fetch fonts if someone mistakenly reaches for `GoogleFonts.inter()` instead of the bundled asset is a foot-gun, not a convenience — someone six months from now who doesn't know the bundled-asset decision was deliberate could "helpfully" switch to it and reintroduce a network dependency and a font flash. Delete the dependency; the intent (bundled, offline-safe Inter) then can't accidentally regress.

**Type scale**: the existing scale (displayLarge 32/w800 → labelSmall 11/w500, full ladder in `app_theme.dart:409-493`) is complete and consistent — negative letter-spacing on larger sizes (display/headline), neutral on body, is a correct premium-reads-as-restraint technique already in place. No changes recommended to the scale itself.

**[NEW] — one addition**: no `monospace`/tabular-figure treatment is defined anywhere for currency amounts (₦ values in escrow/wallet/quote screens). Numbers that change (job budgets, quote amounts, wallet balances) should use `FontFeature.tabularFigures()` so digits don't shift width as they update — cheap to add as a named `AppTextStyles.currency` extension of `bodyLarge`/`headlineMedium`, worth defining now since `06-escrow-wallet.md` will need it immediately for wallet/ledger rows.

---

## 4. Spacing, radius, shadow, motion — formalized as-is

These are already well-designed and complete; this section exists to make the *rules*, not just the values, explicit and citable for anyone building new screens.

- **Spacing** (`AppSpacing`, 4/8/12/16/20/24/32/48): an 8pt-ish scale with 4 and 12 as half-steps — use `screenPadding` (20h/16v) and `cardPadding` (16 all) as the only two padding presets for their respective contexts; don't hand-roll `EdgeInsets` for standard screens/cards.
- **Radius** (`AppRadius`, 6/10/14/18/20/24/full): note the existing convention — buttons/inputs at `md=14`, cards at `xl=20`, chips at `full`. **Rule**: radius should increase with a component's visual "weight" (chips smallest conceptually but pill-shaped=full, buttons/inputs mid, cards largest rectangular radius) — this is already followed, just make it an explicit rule so new components don't invent a fifth radius value.
- **Shadow** (`AppShadows`): deliberately sparse — only `card` (used *optionally*, via `appCardDecoration(elevated: true)`), `floatingNav`, `button`, `snackbar` have real elevation; default cards are flat with a hairline border instead. **Rule**: shadow is reserved for things that float above content (nav bar, snackbar) or are being interactively emphasized (an elevated/pressed card state) — never for static resting content. This is what makes the current app read as premium rather than skeuomorphic; don't add elevation to more components without a specific interaction reason.
- **Motion** (`AppAnimations`: fast=150ms/normal=250ms/slow=400ms/page=300ms, `easeOutCubic` default): correctly tiered (micro-interactions fast, page transitions slower). **Rule for new components**: state changes (toggle, chip select, badge appear) use `fast`; content transitions (tab switch, expand/collapse) use `normal`; full-screen navigation uses `page`. `slow`/`bounceCurve` (`elasticOut`) should stay reserved for rare celebratory moments (e.g., "job completed" confirmation, escrow released) — using a bounce curve on routine UI would cheapen it.

---

## 5. Iconography

Existing usage (`home_screen.dart`, `premium_scaffold.dart`) consistently uses Material's **`_rounded` icon suffix** (`home_rounded`, `work_rounded`, `chat_bubble_rounded`, `person_rounded`, `add_rounded`). **[NEW, formalizing an implicit convention]**: make this an explicit rule — **always use the `_rounded` variant of a Material icon, never the sharp/outlined default**, for consistency across every future screen. Rounded icons read as friendlier/more approachable, which fits "premium, trustworthy, distinctly Nigerian" better than the sharper Material default. Icon sizing: standardize on 20px (inline/label icons), 24px (nav/action icons), 28-32px (feature/empty-state icons) as the three allowed sizes — avoid arbitrary in-between sizes.

---

## 6. Component library

Cataloging what exists in `lib/widgets/` today, plus theme-driven Material components, as the canonical component inventory. This is a specification of target state and usage rules, not a re-audit of each implementation — a widget-by-widget correctness pass belongs in Phase 9 once screen specs exist to test each component against.

### 6.1 Themed Material primitives (via `AppTheme`, no custom widget needed)
Buttons (elevated/outlined/text — all 52px min height, 14px radius), inputs (filled, 14px radius, no border light / bordered dark), chips, cards (0 elevation + hairline border), bottom nav bar theme, snackbar (floating, 14px radius), dividers. **Rule**: never override these inline in a screen (`ElevatedButton(style: ...)` with ad-hoc values) — if a screen needs a variant, add it to the theme, don't fork it locally, or the "consistency" goal erodes one screen at a time.

**[NEW] gap**: no destructive-action button variant exists (e.g., "Delete job," "Cancel job," "Reject verification" in the admin dashboard). Add a `destructiveButtonTheme`-equivalent — same shape/height as the primary button, `error` color fill, used only for irreversible destructive actions, never for routine negative actions like "Decline quote" (which should stay neutral/outlined, not red — reserve red for genuinely destructive, hard-to-reverse actions per the elevation-of-shadow restraint principle above).

### 6.2 Custom widget inventory (`lib/widgets/`)

| Widget | Role | Design-system notes |
|---|---|---|
| `premium_scaffold.dart` (`MainShellScreen`) | Shared bottom-nav shell, `IndexedStack` + floating frosted nav bar | Correctly uses `floatingNav` shadow + blur; **carries the role-unaware FAB bug from `01-ux-audit.md` 2.1** — a design-system fix alone won't resolve that, it needs the role-conditional logic fix from the hardening sprint's adjacent cleanup, not a new visual treatment |
| `job_status_badge.dart` | Renders the 9-state status chip | Must consume `context.colors.statusX`, never a raw `AppColors.statusX` — verify in Phase 9 |
| `trust_score_card.dart` | Artisan-facing trust score breakdown | Will need updating alongside `05-trust-score.md`'s tier-color expansion (§2.2 Gap 4) |
| `job_progress_timeline.dart` / `job_progress_tracker.dart` | Renders the manual `JobProgressStage` steps | Currently a step-list, not a map — will need a companion map-based component once `07-gps-flow.md` lands; these two don't merge into one, they represent different information (discrete milestones vs. live position) |
| `job_timeline_widget.dart` | Appears to overlap with the two above — **needs a naming/scope reconciliation pass**, three timeline-named widgets is a sign of organic growth without a single owner | Flag for consolidation when Phase 9 touches job detail |
| `artisan_card.dart` | Artisan list/grid card | Primary surface for Trust Score legibility — must show verification state prominently per `01-ux-audit.md` 2.8 (surface "Verify Later"/unverified state on the card itself, not just profile detail) |
| `star_rating.dart` | Rating display/input | Confirm gold fill vs. text-color accessibility rule (§2.3) is followed here specifically, since this is its primary use case |
| `review_tile.dart` | Single review display | — |
| `user_avatar.dart` | Avatar w/ fallback | Standardize fallback (initials vs. generic icon) as one pattern app-wide |
| `notification_bell.dart` | Bell icon + unread badge | Badge color should be `error`, count should cap at a display maximum (e.g., "9+") rather than rendering arbitrary large numbers |
| `app_snackbars.dart` / `error_snackbar.dart` | Two snackbar helpers — **overlapping responsibility**, similar to the timeline-widget triplication above | Consolidate into one snackbar helper with a `type` parameter (success/error/info) rather than two separate files |
| `shimmer_loaders.dart` | Loading skeletons | Uses `shimmerBase`/`shimmerHighlight` tokens correctly per the palette; ensure a shimmer variant exists for every major list/card type used app-wide (jobs, artisans, chats) — Phase 9 to verify coverage |
| `loading_indicator.dart` | Generic spinner | — |
| `cancellation_reason_dialog.dart` | Reason-capture dialog | Pattern (reason-required destructive action) should be reused for the dispute/rejection flows, not reinvented per screen |
| `portfolio_viewer.dart` | Image lightbox | Should use the new `scrim` token (§2.2 Gap 3) |

### 6.3 Admin-specific components (`lib/screens/admin/`)
`admin_charts.dart` (fl_chart wrappers), `admin_data_table.dart` (`AdminDataTable<T>`), `admin_widgets.dart` (`AdminStatCard`/`AdminSectionCard`/`AdminCountBadge`), all currently styled from `AdminPalette`, addressed in §7 below.

### 6.4 Missing components the brief will require (build in later phases, tokens ready now)
Not building these yet — listed so the token foundation above (escrow colors, scrim, currency type style, destructive button) is sized correctly for what's coming:
- Milestone/payment-stepper component (`06-escrow-wallet.md`)
- Wallet ledger row / transaction list item (`06-escrow-wallet.md`)
- Live ETA/map card (`07-gps-flow.md`)
- Notification preference toggle row (`08-messaging-notifications.md`)
- Chat typing-indicator, read-receipt, and archive-list item (`08-messaging-notifications.md`)
- Standardized empty-state, error-state, and offline-state components — currently each screen appears to build its own (no shared `EmptyStateView`/`ErrorStateView` found in the widget inventory). **[NEW]** — this is worth building early since every single screen spec in Phase 9 will call for one; recommend pulling this forward as a small, low-risk addition alongside the Phase 1.5 hardening sprint rather than waiting for Phase 9.

---

## 7. Resolving the admin color-system question (`01-ux-audit.md` 3.3)

Reading `admin_palette.dart` directly changes the framing from the original audit: this wasn't accidental drift. Its doc comment states the intent plainly — a "dark-premium SaaS palette scoped to the admin dashboard only," deliberately distinct from the consumer green/blue theme, with light mode built to make the theme toggle meaningful there too.

**Is a distinct admin visual language defensible?** Partially, yes — separating an internal operations tool from the consumer-facing brand is a legitimate, common pattern (Stripe, Shopify, and most marketplaces skin their admin/ops surfaces differently from their storefront). The brief's "consistent design system" goal is about the *product* a customer/artisan touches, and arguably shouldn't be read as forcing an ops dashboard into the same skin.

**But the current execution has a real problem**: `AdminPalette` is a fully independent, hand-rolled color set with no structural connection to `AppColors`/`AppColorsExtension` — it doesn't extend, reference, or derive from the brand tokens at all (it's a from-scratch purple/indigo/pink/cyan accent set). That means updating the brand palette (a rebrand, a contrast fix, a new semantic color) requires remembering to also update this entirely separate file — the two will drift by construction, not by mistake.

**Recommendation [NEW]**: keep the *concept* (a denser, darker, information-rich "Ops" visual mode for admin is genuinely appropriate for a data-heavy internal tool) but rebuild it as a **second `ThemeExtension`** (`AdminColorsExtension`, parallel to `AppColorsExtension`) that pulls its accent colors from the *same* semantic source where they overlap — `AdminPalette.green` should literally be `AppColors.primary`, not a re-typed `#22C55E`; `AdminPalette.red`/`amber`/`blue` should be `AppColors.error`/`warning`/`accent`, not re-declared. Only the admin-exclusive additions (purple, indigo, pink, cyan — used for chart categorical color and section accents that don't exist in the consumer app) stay as genuinely new tokens, clearly scoped as admin-only extensions rather than a full palette fork. This keeps the deliberate "admin feels like an ops console" decision while eliminating the drift risk — one is proposed to `10-admin-redesign.md` as the concrete refactor, this section just settles the *principle*.

---

## 8. Governance — how this system stays a system

- **No inline style overrides.** Any `TextStyle`/`BoxDecoration`/color literal written directly in a screen file instead of pulled from `context.colors`/`AppTheme`/`AppSpacing`/etc. is a design-system violation, not a style preference — flag these in code review the same way a lint rule would.
- **New tokens get both light and dark values in the same PR.** Gap 1 above (escrow colors missing a dark pair) is exactly what happens when this isn't enforced — don't let it happen again.
- **One canonical widget per concept.** §6.2 already found three timeline-named widgets and two snackbar helpers — this is the predictable result of not having a single point of ownership for "does this component already exist." Before adding a new widget, grep the existing 17 first.
- **This document is the source of truth for tokens; the code is the source of truth for exact values.** If they ever disagree, trust the code and update this doc — don't let a stale spec win, which is exactly the mistake `01-ux-audit.md`'s retracted findings made by trusting a stale `README.md` line over the actual index file.

---

**Next**: proceeding per the `01.5` roadmap — `05-trust-score.md` (sequenced right after the Phase 1.5 hardening sprint's Track B ships) and `06-escrow-wallet.md` (after Track A) are next in dependency order, with `07-gps-flow.md` and `08-messaging-notifications.md` available to pull forward in parallel since they have no hardening-sprint dependency. Let me know which to take next.
