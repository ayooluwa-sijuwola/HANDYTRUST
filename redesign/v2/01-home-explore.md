# V2 — Home / Explore (Customer)

First screen rebuilt against the visual reference. Directly evidenced by Image A (the Stitch "Nearby Experts" screenshot) — the most-grounded screen in this entire program, since it's the one screen actually shown. Supersedes `09-screens-customer-artisan.md` §2.1's customer-side treatment.

**Evidence key**: 🟢 Directly evidenced (visible in Image A) · 🟡 Extrapolated (reasoned extension of evidenced patterns to something the image doesn't show) · 🔵 Inferred (per `02-design-system-v2.md` §10's inference set).

---

## Purpose
The customer's primary landing surface — discover nearby verified artisans, start a new job request, and see the platform's core trust promise (escrow protection) reinforced without having to go looking for it.

## User goal
"Show me trustworthy people near me who can do the job, and reassure me my money is safe if I hire one."

## Layout (top to bottom, 🟢 directly from Image A except where marked)

1. **Header row** 🟢 — circular user avatar (left), "HandyTrust" wordmark (bold, black), a shield-check verification/trust icon (right). Reads as identity + trust signal in one glance, not decorative branding.
2. **Hero CTA area** 🟡 — Image A crops this to just the top edge of a green "BOOK NOW" button. Extrapolated and decided: this is a hero section above the fold containing a service-category prompt ("What do you need done today?") with the CTA leading into job posting — this is where "post a job" lives now that the nav FAB is gone (`02-design-system-v2.md` §9.3's resolution). Content: a simple category grid (reusing the app's existing `service_categories.dart` constant list) plus the CTA — closest fit to what little of the hero is actually visible.
3. **"Nearby Experts" section** 🟢 — bold section header, right-aligned location pill ("📍 Lagos, NG").
4. **Artisan list cards** 🟢 (see Component Hierarchy below).
5. **HandyTrust Escrow Protection card** 🟢 — dark navy panel, always visible on Home (not conditional on having an active job) — reinforces trust proactively, not just reactively during a transaction.
6. **Bottom nav** 🟢 — flat bar, 4 tabs (Explore/My Tasks/Wallet/Profile), filled-pill active state, per the resolved nav decision.

## Component hierarchy

- `HomeExploreScreen`
  - `AppHeaderBar` (avatar, wordmark, trust badge) — 🟢 new shared component, not in the current widget inventory; replaces the current `home_screen.dart`'s ad-hoc greeting header
  - `HeroCtaSection` — 🟡 category grid + "Post a Job" CTA
  - `SectionHeader` (label + trailing location pill) — 🟢 reusable, will recur on other list screens (Open Jobs Feed, Browse Artisans)
  - `NearbyExpertCard` × N — 🟢 replaces the current `artisan_card.dart`; **fields, decided**: circular photo thumbnail (plain — see Decision Log for the dropped video-overlay idea), name (bold), specialty line ("Category • Subcategory" bullet-separated), a borderless "✓ VERIFIED" mark with the **checkmark icon in green, the "VERIFIED" label text in `textPrimary`** (contrast fix applied — see Accessibility), star rating + review count, a distance badge top-right pairing a small green location-pin icon with the distance number in `textPrimary` (same fix pattern — green stays the icon, never the text color), trailing chevron.
  - `EscrowPromoCard` — 🟢 new component: navy panel, heading, body copy, **conditional progress display (fix applied)**: if the customer has no active escrowed job, the card shows reassurance copy only ("Every payment is protected — held securely until you confirm the work") with no numeric progress bar at all; if they have a real active job, it shows that job's actual escrow/completion progress. Never a fixed/fake percentage — avoids the "wait, why does this say 70%" trust problem flagged in the original spec.
  - `V2BottomNav` (4 tabs, pill active-state) — 🟢, replaces `premium_scaffold.dart`'s floating/FAB nav

## Interactions
- Tap a `NearbyExpertCard` → artisan profile detail (next screen in the pacing plan, §2 of `v2/00-overview.md`).
- Tap location pill → 🟡 extrapolated: opens a location/radius picker (ties to `05-trust-score.md` §3's distance-bucketed ranking — this is the natural place to surface radius control, which that doc noted was missing entirely from the current app).
- Tap the escrow promo card → 🟡 extrapolated: opens the Trust Score/Escrow explainer content (`05-trust-score.md` §6's Explainer sheet is artisan-trust-specific; this would be the escrow-specific counterpart — worth deciding whether these merge into one "How HandyTrust protects you" surface or stay separate; flagging rather than deciding unilaterally).
- Tap "BOOK NOW"/hero CTA → job posting flow (`/request`, unchanged destination, new entry point).

## Animations
🔵 Inferred per `02-design-system-v2.md` §10: list cards fade/slide in on load (`AppAnimations.normal`, `easeOutCubic`); the escrow card's progress bar (when showing real data) animates fill changes rather than jumping; nav tab switches use a quick fill-in of the pill background (`AppAnimations.fast`), not a bouncy transition, consistent with the reference's restrained tone.

## Loading state
Skeleton cards for the artisan list (shimmer, matching the card's actual shape — photo circle + 3 text lines) while `MatchingService`/discovery query resolves; header and nav render immediately (they don't depend on the query).

## Empty state
No nearby verified artisans in range: 🟡 extrapolated, distinct copy from a zero-*search*-result case elsewhere in the app — "No experts nearby yet" with a widen-radius action (ties to the location-pill radius control above), not a dead end.

## Error state
Discovery query fails (network, Firestore error): retry affordance, per the shared `ErrorStateView` component this program has flagged as needed since `02-design-system.md` §6.4 — still needed here, unchanged by the visual reset.

## Success state
N/A as a persistent state for a landing screen — the "success" moment is really the escrow card's reassurance messaging being present at all, not a transactional confirmation.

## Accessibility
- **Fix applied**: `02-design-system-v2.md` §11 computed green-as-text at ~2.28:1 against white/light-gray — fails AA, and it's literally the reference's own contrast bug (its VERIFIED label and distance badges use green text directly). Both components now use green only for the icon (checkmark / location pin), with the label text itself in `textPrimary` — a deliberate, evidence-based deviation from the literal reference, since accessibility compliance wins over pixel-matching an AI-generated mockup that has its own contrast problem.
- Icon + text pairing (not color alone) for both marks — already correct in the reference's own pattern, matches this program's existing rule against color-only status signaling, unaffected by the color fix above.
- Escrow card's green-on-navy text: already verified accessible (7.83:1+, `02-design-system-v2.md` §11) — no change needed there.

## Responsive behaviour
🔵 Inferred — no tablet/desktop signal in the source image (a phone screenshot). Standard reflow: artisan list becomes a 2-column grid above a tablet breakpoint, hero/escrow cards remain single-column max-width-constrained rather than stretching full-bleed on wide viewports.

## Firestore implications
- Artisan list query: unchanged data source (`MatchingService`), now also carrying the corrected ranking from `05-trust-score.md` §3.1 (distance bucket → trustScore → rating → experience) once that ships.
- Escrow promo card: when showing real progress (per the applied fix above), reads the customer's most recent active job's escrow state — same data `job_detail_screen.dart` already uses, no new query. No new field/collection needed anywhere on this screen.

## Cloud Function implications
None — this is a read/display surface over existing data, no new writes or triggers.

## Notification triggers
None originate from this screen — it's a landing surface, not a state-transition point.

## Security considerations
No new security surface — artisan discovery read access is unchanged from the existing, already-correct rules (public read gated to approved+verified).

---

## Decision log

- **Video-preview overlay** (visible on one card in Image A) — **decided: not building it.** Treated as a generic Stitch-generated affordance rather than a real, confirmed feature request — it would have been the single largest scope addition in this screen (new Storage upload path, moderation/transcoding pipeline, a data-model field with no precedent anywhere in this program), and nothing beyond one icon in one AI-generated mockup indicates it's actually wanted. `NearbyExpertCard`'s photo thumbnail is plain. Revisit as a real feature request later if you want it — it's a clean addition on top of this spec, not a redesign.
