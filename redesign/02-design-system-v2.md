# 02-v2 — Design System (Extracted from Reference Images)

**Supersedes `02-design-system.md`.** That document formalized the app's *existing* code-based theme. This one is extracted from actual visual reference material instead, per your instruction to treat the reference as source-of-truth over the current implementation.

## Sourcing — read this before trusting anything below

Exactly **two static images** have been provided in this conversation, ever:
1. A phone-screenshot of a Google Stitch AI-generated mobile UI preview — "Nearby Experts" list + an escrow-protection card + bottom nav (referred to below as **Image A**).
2. The login-screen mockup used earlier in this session (referred to below as **Image B**, already implemented in `login_screen.dart`/`register_screen.dart`).

No video exists. Every claim below is graded:
- **Extracted** — directly visible in Image A or B, high confidence.
- **Inferred** — a reasonable, low-risk extension of an extracted pattern (e.g., a dark-mode variant of an extracted light color), clearly derived, not invented from nothing.
- **Unknown — needs source** — genuinely not determinable from two static frames (all motion/animation, hover/pressed states, illustration style, empty/loading states). Flagged, not guessed.

Two images can't fully specify a design system this large. If you share the full Stitch link or more screens, everything marked "Unknown" becomes answerable — until then, this doc is honest about its evidence base rather than padding it out with invented specifics dressed up as extracted ones.

---

## 1. Overall Feel — Extracted

Image A reads as: clean, airy, confident, fintech-adjacent — closer to Moniepoint/Revolut's restrained trust-through-simplicity than a busy marketplace app. Generous whitespace, minimal borders, color used sparingly and deliberately (green appears in exactly three places: the active nav pill, the "VERIFIED" mark, and the escrow progress bar/label — never as decoration). The escrow card's near-black navy panel against an otherwise all-white/light-gray screen is the single boldest visual move in the reference — it reads as "this is the serious, trust-critical part," which is a genuinely good instinct for this product's core promise.

Image B reads as a more generic, template-like auth pattern (card-on-background, centered logo, social buttons) — less distinctive than Image A, already implemented faithfully in the prior turn.

---

## 2. Colors — Extracted

| Token | Approx. hex | Where seen | Confidence |
|---|---|---|---|
| Primary Green | `#22A559`–`#2BA84A` range (medium, slightly muted green — **not** the current app's brighter `#22C55E`, this reads a shade darker/more muted) | Active nav pill fill, "VERIFIED" checkmark+text, distance badges ("0.8 km away"), escrow progress bar + "Payment Held Securely" label | Extracted |
| Ink / Text Primary | Near-black, `#111827`–`#1A1A1A` | "HandyTrust" wordmark, artisan names, "Nearby Experts" heading | Extracted |
| Text Secondary | Mid-gray, `#6B7280`-ish | Specialty lines ("HVAC Specialist • AC Repair"), review counts, "Lagos, NG" location text | Extracted |
| Surface / Card Fill | Very light gray, `#F3F4F6`-ish (**not white** — distinctly off-white/gray, flatter than the current app's white `#FFFFFF` cards) | Artisan list card backgrounds | Extracted |
| Page Background | White or near-white, `#FFFFFF`/`#FAFAFA` | Screen background behind the cards | Extracted |
| Escrow Card / Deep Navy | Near-black navy, `#0E1526`–`#111827` range | The "HandyTrust Escrow Protection" card fill | Extracted — **notable**: this is very close to the current app's existing `AppColors.darkBackground` (`#0F172A`), so this isn't a foreign color, it's a color the codebase already has, just not currently used this way in a light-mode screen |
| Escrow Card Body Text | Muted white/gray, `#9CA3AF`-ish on navy | Escrow card's explanatory sentence | Extracted |
| Progress Track (on navy) | Darker navy/gray, `#2A3344`-ish | The unfilled portion of the escrow progress bar | Extracted |
| Border (implied) | Little to none visible — cards read borderless, separated by whitespace/subtle fill contrast rather than strokes | Extracted |
| Warning / Error / Info | Not visible anywhere in either image | **Unknown — needs source** |

**What this changes vs. the current codebase's `#22C55E`**: the reference's green reads slightly more muted/desaturated than the app's current bright green. I'm flagging this rather than silently swapping the brand primary — see §9's open question.

---

## 3. Gradients — Unknown, mostly

Neither image shows a clear, unambiguous gradient — every surface reads as a flat fill (cards, buttons, the escrow panel). The only thing close to a gradient is a very subtle vignette/shadow at the edges of the escrow card that could be a soft dark-to-darker gradient, but it's equally explainable as a plain shadow — **not confident enough to specify as a gradient system**. Given the current `02-design-system.md` already has a defined gradient set (`primaryGradient`, `serviceHeroGradient`, etc.) and nothing in the reference contradicts flat fills being the dominant pattern, recommend: **keep gradients minimal/reserved for hero moments only** (consistent with what little signal exists), don't manufacture a gradient system the reference doesn't actually show.

---

## 4. Typography — Extracted (partial)

- Headings ("HandyTrust" wordmark, "Nearby Experts", "Welcome Back" in Image B): bold, tight letter-spacing, sans-serif — consistent with the current app's Inter typeface at high weight (w700/w800). Nothing in either image suggests a different font family than what's already bundled.
- Body/secondary text: regular weight, smaller size, gray — consistent with the app's existing type scale.
- **Unknown — needs source**: exact point sizes can't be measured reliably from a phone screenshot at this resolution; full heading/body/caption hierarchy beyond "bold headline, regular body, small caption" isn't determinable from two frames.

**Recommendation**: keep the current app's Inter-based type scale (`02-design-system.md` §3, already thorough and not contradicted by anything visible here) rather than inventing new sizes with no real evidence behind them.

---

## 5. Card Design — Extracted

- **Corner radius**: generous, ~16-20px — rounder than a standard Material card, consistent with the current app's `AppRadius.xl` (20).
- **Padding**: generous internal padding, content never touches the card edge — consistent with `AppSpacing.cardPadding` (16) or slightly more.
- **Elevation/shadow**: minimal to none on the light-gray artisan cards (they separate from the white background by fill-color contrast, not shadow) — the escrow card reads as having more visual weight (implied depth via its dark color, not necessarily a heavy shadow). This actually validates the current design system's existing "restraint" principle (`02-design-system.md` §4: shadow reserved for floating/emphasized elements, not routine cards) — the reference independently arrived at the same instinct.
- **Border**: none visible — cards are borderless, unlike the current app's hairline-border card pattern (`cardTheme`'s `BorderSide(color: AppColors.borderLight)`). **This is a real, specific difference worth flagging** (§9).
- **Glass/transparency effects**: none visible in either image — no blur, no translucency. The current app's floating nav bar uses a frosted-glass `BackdropFilter` effect; nothing in the reference confirms or contradicts this since the reference's nav bar (§7) is a flat, opaque bar, not floating/blurred.

---

## 6. Buttons — Extracted (partial)

- **Primary/CTA** ("BOOK NOW" in Image A, "Login to Account" in Image B): full-width, rounded-pill-to-rounded-rect (closer to a large radius rect than a full pill), bold white label. Image A's is green; Image B's was black (already resolved in the prior turn — keeping green per your decision, consistent with Image A's own green CTA, which is reassuring corroboration that green-primary is correct, not just my earlier assumption).
- **Badge/chip-style "buttons"** (VERIFIED mark, distance badge): no visible container/fill — just colored icon+text, no pill background. This is a lighter-weight pattern than the current app's `AppBadge` (which always has a filled pill background per `02-design-system.md`'s existing component). **Worth considering a second, backgroundless badge variant** for cases like this rather than forcing everything into the filled-pill pattern.
- **Nav "button"** (active Explore tab): a filled solid-green rounded-pill *behind* an icon+label pair — this is a distinct, specific pattern (§7).
- **Unknown — needs source**: secondary/outlined button treatment, icon-only buttons, disabled/pressed states — none visible in a static screenshot of an idle screen.

---

## 7. Navigation — Extracted

This is the single clearest, most specific new pattern in the reference, and it's a **real departure from the current app's nav**:

- Current app (`premium_scaffold.dart`): a floating, frosted-glass, rounded nav bar with a center circular gradient FAB for "post a job," per `01-ux-audit.md`/`02-design-system.md`'s existing documentation.
- Reference (Image A): a flat, opaque, inline bottom bar (not floating/elevated off the bottom edge), **no center FAB at all**. Active tab is indicated by a filled green rounded-pill background wrapping the icon+label; inactive tabs are plain gray icon+label with no container.
- Reference's four tabs: **Explore, My Tasks, Wallet, Profile** — notably different labels/set than the current app's Home/Jobs/Chats/Profile-plus-FAB, and notably **Wallet is already a primary nav slot in the reference**, which directly contradicts this program's earlier decision (`06-escrow-wallet.md` §6) to put Wallet inside Profile rather than the bottom nav. **This is a real conflict to resolve, flagged in §9, not silently overridden either direction.**

---

## 8. Layout & Spacing — Extracted

Generous vertical rhythm between sections (list → escrow card → nav has clear breathing room, not cramped). Section headers ("Nearby Experts") sit with clear separation from both the content above and the cards below. List cards have consistent, moderate gaps between them (not touching, not excessively spaced) — consistent with the current app's `AppSpacing` scale (12-16px between elements), not contradicted, no change needed here.

---

## 9. Resolved decisions

1. **Primary green**: keep the current `#22C55E` — the reference's shift is treated as screenshot/compression drift, not intent. No rework needed on the already-shipped login/signup screens.
2. **Card style**: **adopt the reference** — borderless cards, light gray fill (~`#F3F4F6`) against a white page, replacing the current white-card-with-hairline-border system. Applies to every card in the app going forward; existing screens using `appCardDecoration()`/`cardTheme` need this token updated centrally (one theme change, not a per-screen edit) — flagged for whoever implements this to update `AppColors.surfaceVariant`-as-card-fill and drop the `borderLight` stroke from `cardTheme`.
3. **Nav bar**: **adopt the reference** — flat, opaque bar, filled-green-pill active state, no center FAB. **Real consequence**: the current app's primary "post a job" entry point (the center FAB in `premium_scaffold.dart`) has nowhere to live in this pattern. Needs a new placement — most likely a prominent CTA within the Home/Explore tab itself (e.g., a "Post a Job" button in the hero area, matching Image A's cropped-but-visible green "BOOK NOW" button sitting *above* the nav, in-content rather than in the nav chrome). This also happens to directly fix `01-ux-audit.md` 2.1 (the FAB's role-unaware bug) for free — there's no shared FAB left to be role-unaware, since posting a job becomes an in-content action per role instead of one global button.
4. **Wallet placement**: **moves into the bottom nav**, matching the reference's 4-tab set (Explore, My Tasks, Wallet, Profile). This overrides `06-escrow-wallet.md` §6's earlier reasoning — noted there directly rather than left standing uncorrected.

**Resulting nav set** (customer): Explore, My Tasks (Jobs), Wallet, Profile — matching Image A exactly. Artisan-side equivalent needs its own pass (Open Jobs Feed likely replaces "Explore" for artisans, consistent with `09-screens-customer-artisan.md`'s existing role-aware home-tab distinction) — flagged for the nav rebuild, not decided here.

---

## 10. Inferred (per your instruction to infer rather than block)

Each grounded in the extracted evidence (§1's "Overall Feel," the actual colors/patterns in §§2-8) rather than invented freely. Marked **Inferred**, not **Extracted** — if more source material surfaces later, these are the first things to re-check.

- **Motion**: restrained, fast, non-bouncy — nothing in the reference contradicts the current codebase's existing `AppAnimations` tokens (fast=150ms/normal=250ms/slow=400ms, `easeOutCubic` default, `elasticOut` reserved for rare celebratory moments). The reference's fintech-adjacent, minimal-decoration feel (§1) is inconsistent with playful/bouncy motion as a default — **keep the existing motion system as the v2 standard**, don't invent a new one with no evidence behind it.
- **Hover/pressed/disabled states**: the reference communicates state through **fill and color, not elevation** (the nav's active pill is a solid fill vs. plain icon+text, not a shadow change; nothing in either image shows elevation-based emphasis). Inferred pattern: pressed = slight opacity dip (~0.9) on the pressed element, no scale/shadow change; disabled = ~38% opacity + muted color (Material's standard convention, already proposed in `02-design-system.md` §2.2 Gap 2 — nothing here contradicts adopting it).
- **Illustration/empty/error/loading states**: neither image shows an illustration — both are fully populated, data-rich screens. Given the fintech-restrained tone (Moniepoint/Revolut lean geometric-minimal, not whimsical, unlike e.g. Duolingo from your comparison list), inferred direction: **simple line-icon-based empty states** (one large outlined icon + short text), not custom illustrations. This is the least-grounded inference in this section — nothing illustrative appears in either source image, so treat this as a placeholder direction to confirm, not a settled call, if a real illustration style matters to you.
- **Dark mode**: genuinely has partial real evidence, not pure invention — the escrow card's near-black navy (§2) already demonstrates a dark surface *within* a light screen, and it already matches the current codebase's `AppColors.darkBackground` (`#0F172A`) closely. Inferred: extend that navy as the v2 dark-mode base, with card fills becoming a lighter slate (~`#1A2235`) rather than the light-mode's `#F3F4F6` gray. See §11 for a real contrast check confirming this works, not just reads plausibly.
- **Type scale**: keep the current codebase's existing Inter-based scale (`02-design-system.md` §3) — the reference's bold-black-headline/regular-gray-body pattern is fully consistent with it, nothing suggests a different scale.
- **Responsive/tablet**: no signal from a phone screenshot either way — keep the app's existing responsive conventions; this was never actually reference-driven.

---

## 11. Real accessibility check (not inferred — computed from the resolved §9 colors)

Now that colors are settled, these are actual WCAG relative-luminance contrast-ratio calculations, not estimates:

| Pair | Ratio | AA normal text (4.5:1) |
|---|---|---|
| `#22C55E` green text on `#0F172A` navy (escrow card's "Payment Held Securely") | **7.83:1** | ✅ passes AA *and* AAA |
| White text on `#0F172A` navy (escrow card heading) | **17.85:1** | ✅ comfortably |
| Muted gray `#9CA3AF` on `#0F172A` navy (escrow card body copy) | **7.03:1** | ✅ passes AA |
| `#22C55E` green as a *text* color on white/light-gray surface (e.g. "VERIFIED" label) | **~2.28:1** | ❌ fails — confirms the same finding already on record in `02-design-system.md` §2.3; green must stay an icon/fill color here, never body text |
| `#F3F4F6` card fill vs. `#FFFFFF` page background | **~1.10:1** | N/A (not a text-contrast case) — but worth flagging as a UX note: this is a *very* subtle tonal difference, meaning card boundaries in the reference lean on spacing/margin more than color contrast to read as distinct. **Recommendation**: keep generous gaps between cards (the reference already does this) so the subtle fill difference isn't the only boundary cue — don't tighten card spacing later without re-checking this. |

The escrow card's own color choices hold up well under real scrutiny — worth noting, since it means the single most trust-critical surface in the reference is also its most accessible one, which is a good sign about the source material's underlying design judgment even though it's AI-generated.

**General rule, generalized from fixing this twice already** (`v2/01-home-explore.md`'s VERIFIED/distance badges, `v2/02-artisan-profile.md`'s identity block): this isn't just a reference-specific bug. The current codebase's own `AppBadge` widget (`02-design-system.md` §6.1) already pairs saturated icon+text colors on a *light-tint* surface (e.g. `primarySurface #DCFCE7`, close enough to white that it doesn't meaningfully change the ~2.3-2.5:1 ratio computed above) — meaning every status/badge chip built on that pattern anywhere in the app is presumptively in the same failing range, not just the two spots patched so far. **Standing rule for every screen in this v2 program from here on**: a saturated brand color (green, amber, red, blue) may be a chip's *fill* (if paired with white/high-contrast text) or its *icon*, but never its own *text* color on a light/white/light-tint background. Apply this proactively in every new screen spec, not reactively per screen.

---

## 12. Status

All of §9's open questions are resolved (your answers) and §10's gaps are now inferred rather than blocking. This document is ready to build against. Next: rebuilding actual screens against it, starting with Home/Explore — the one screen with direct visual evidence (Image A) rather than inference.
