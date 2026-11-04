# V2 — Artisan Profile Detail

Second screen in the pacing plan — extrapolated one level from `v2/01-home-explore.md`'s fully-evidenced `NearbyExpertCard` (tapping a card lands here). Supersedes `09-screens-customer-artisan.md` §2.3's artisan-profile treatment.

**Evidence key**: 🟢 Directly evidenced · 🟡 Extrapolated · 🔵 Inferred · 🟠 **Real gap found reading the current code** (new to this doc — not visual, a workflow fix).

---

## Real finding before the spec: today's screen has a dead end

Read `artisan_profile_screen.dart` directly: the primary action button (`_actionButton`, opens the "Confirm Selection" hire dialog) only renders `if (jobId != null)` — i.e., only when this screen is reached *from a specific already-posted job's matching flow*. When reached via general discovery (no `jobId` — precisely the `v2/01-home-explore.md` "Nearby Experts" case, and `BrowseArtisansScreen`), **there is no primary CTA at all today**, just a favorite-heart icon. A customer browsing nearby experts and tapping into a profile currently has no next action beyond backing out and separately posting a job. This is a genuine workflow gap, not a visual one — 🟠 fixed below, not just restyled.

---

## Purpose
Let a customer evaluate one specific artisan in depth and take a real next step toward hiring them — whichever context they arrived from.

## User goal
"Is this person right for my job, can I trust them, and how do I actually move forward with them?"

## Layout (top to bottom)

1. **Collapsing header** 🟡 — large photo (the current implementation already uses a `SliverAppBar` with a 220px expanded photo header; kept, restyled to the v2 language: no border, generous whitespace), favorite-heart action (🟢 existing feature, kept per "do not remove important features"), back button.
2. **Identity block** 🟡 — name, specialty line, verified mark (checkmark-icon-green + `textPrimary`-text, per the contrast fix from `v2/01`), rating + review count, distance — same field set and same contrast-safe treatment as the list card, just larger.
3. **Trust Score tier badge + explainer entry point** 🟢/🟡 — this is exactly the surface `05-trust-score.md` §6 named as an entry point for the Trust Score Explainer bottom sheet ("artisan card, artisan profile, quote list") — tapping it opens that already-specced sheet, unchanged by this visual reset.
4. **About/bio** 🟡 — short artisan-written description (existing field, `ArtisanModel`).
5. **Portfolio grid** 🟢 existing feature (`portfolio_viewer.dart`, `_ProjectsSection`) — kept, restyled: borderless gray-fill grid cells per the v2 card language, no video content (per the Decision Log in `v2/01` — this program isn't building artisan video this pass).
6. **Reviews section** 🟢 existing feature (`review_tile.dart`) — kept, restyled; shows a capped preview (e.g. 3) with a "See all N reviews" expansion rather than the full list inline, keeping the screen scannable.
7. **Primary CTA — 🟠 fixed, not just restyled**: two distinct contexts, both need a real action now:
   - **Job-linked context** (`jobId` present — customer arrived via an already-posted job's matching flow): "Select [Name] for this job" → existing `Confirm Selection` dialog flow, kept, restyled to the v2 button language (solid green, full-width, rounded).
   - **General discovery context** (`jobId` null — the Home/Explore case): **new CTA, "Request a Quote"** → starts the job-posting flow (`/request`) pre-filled with this artisan's category and a soft "invite" of this specific artisan once the job is posted (exact mechanism — direct invite vs. just pre-filtering the open-jobs-feed visibility — is a product decision for whoever implements this; the point fixed here is that *some* real action must exist, not which exact mechanism). This directly closes the dead-end gap found above.

## Component hierarchy

- `ArtisanProfileScreen`
  - `ProfileHeaderSliver` (photo, favorite action, back) — 🟡 restyled from existing `SliverAppBar` pattern
  - `IdentityBlock` (name, specialty, verified mark, rating, distance) — 🟡 reuses the fixed-contrast pattern from `NearbyExpertCard`
  - `TrustScoreBadgeRow` (tier badge + "ⓘ" → Explainer sheet) — 🟢 from `05-trust-score.md` §6, unchanged
  - `AboutSection` — 🟡
  - `PortfolioGrid` — 🟢 existing feature, restyled
  - `ReviewsPreviewSection` (capped list + "See all") — 🟡 restyled from existing `_reviewsSection`
  - `PrimaryActionButton` — 🟠 now renders in **both** contexts (fixed), not just the job-linked one

## Interactions
- Tap portfolio image → existing lightbox (`portfolio_viewer.dart`), restyled with the new `scrim` token from `02-design-system.md` §2.2 Gap 3 (unaffected by the visual reset, still valid).
- Tap "See all reviews" → expands inline or pushes a dedicated reviews list — 🟡 either is reasonable, recommend inline expansion to avoid an extra navigation hop for a supporting-detail action.
- Tap favorite heart → existing `toggleFavorite`, unchanged.
- Tap Trust Score badge → Explainer sheet (`05-trust-score.md` §6).
- Tap primary CTA → context-dependent per the fix above.

## Animations
🔵 Inferred, consistent with `v2/01`: header photo has a subtle parallax/collapse on scroll (already implicit in `SliverAppBar` behavior, kept); section content fades in on load (`AppAnimations.normal`); CTA button uses the same restrained press-opacity state as every other v2 button, no bounce.

## Loading state
Skeleton for the header + identity block while `artisanProfileProvider` resolves; portfolio/reviews sections show their own shimmer once the artisan doc resolves but before their respective queries do (they're separate providers, per the code — `artisanReviewsProvider`, portfolio provider — so they can resolve independently and shouldn't block each other).

## Empty state
- No portfolio images: 🟡 a simple "No portfolio yet" placeholder rather than an empty grid — distinct from an error, since a new artisan legitimately has nothing here yet.
- No reviews: `artisan.totalRatings > 0` already gates the reviews section entirely in the current code (confirmed) — for v2, replace the section's complete absence with a lightweight "No reviews yet" note instead of hiding the section outright, since an artisan with zero reviews isn't necessarily untrustworthy (ties to `05-trust-score.md` §2.2's Bayesian-shrinkage point — a new artisan shouldn't read as suspicious for having no reviews yet, the UI shouldn't reinforce that by hiding the section like something's missing).

## Error state
Artisan doc fails to load or doesn't exist: distinct copy ("This artisan's profile isn't available" vs. a generic network error) — the current code already distinguishes `artisan == null` from a stream error (`error: (e, _) => ...` vs. the null check), a good existing pattern to keep, just restyle to the shared `ErrorStateView`/`EmptyStateView` components flagged as needed since `02-design-system.md` §6.4.

## Success state
Favoriting/unfavoriting gives instant icon-state feedback (already true in the current implementation) — no additional confirmation needed for a lightweight action. The CTA's success state (quote requested / selection confirmed) is a snackbar + navigation forward, not a state that persists on this screen.

## Accessibility
Same contrast fix as `v2/01` applies identically here (green icon-only, never green body text) — this screen reuses the same identity-block fields, so the fix propagates rather than needing to be re-derived. Favorite icon needs an accessible label distinguishing "Save artisan" vs. "Remove from favorites" (already present as a `tooltip` in the current code — good, carry it forward as a real accessibility label, not just a tooltip, since tooltips alone aren't reliably exposed to all screen readers).

## Responsive behaviour
🔵 Inferred: portfolio grid goes from 2 columns (phone) to 3-4 (tablet/wide); header photo height caps rather than growing unboundedly on large viewports.

## Firestore implications
No new reads beyond what the current screen already does (`artisanProfileProvider`, `artisanReviewsProvider`, portfolio provider, `favoriteIdsProvider`) — this is a visual and one workflow fix, not a data-model change. The 🟠 general-discovery CTA fix, depending on the "direct invite" mechanism chosen by whoever implements it, may need a small addition (e.g., a `preferredArtisanId` field on the job doc at creation) — flagged as an implementation detail, not specified here since the exact mechanism wasn't decided above.

## Cloud Function implications
None new, unless the invite mechanism above needs one (e.g., notifying the specific invited artisan) — same flag as above.

## Notification triggers
If the invite mechanism sends a direct notification to the invited artisan ("A customer wants you for their job"), that's a new notification type — would extend `08-messaging-notifications.md` §4.1's whitelist the same way every other new type in that doc did. Not designed in full here since the underlying mechanism itself isn't chosen yet.

## Security considerations
No new security surface for the read side (existing rules already correctly scope artisan profile reads to public+approved+verified). If a direct-invite write is added, it needs the same ownership pattern already established (customer can only invite on their own job) — mechanical, not a new pattern.

---

## Decision log
- **Dead-end CTA gap (🟠)**: fixed in principle (a real CTA now exists in both contexts) — the exact "how a specific artisan gets pulled into a newly-posted job" mechanism (direct invite vs. pre-filtered visibility vs. something else) is flagged as an implementation decision, not resolved here, since it's a data-model/matching-algorithm question closer to `05-trust-score.md`/`MatchingService` territory than a screen-layout one.
