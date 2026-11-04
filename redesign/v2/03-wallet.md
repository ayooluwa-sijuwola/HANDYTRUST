# V2 — Wallet

Third screen in the pacing plan. The *functional* design (milestone-aware ledger, escrow states, payout-failure UX) was already fully specified in `06-escrow-wallet.md` §6 and is unchanged by this visual reset — cited, not re-derived. This doc covers only what the reset actually changes: visual treatment and navigation placement.

> **Implementation note (post-build correction):** `wallet_screen.dart` as actually built queries the *existing* `PaymentModel`/`payments` collection directly (`customerPaymentsProvider`/`artisanPaymentsProvider`, new — needed two new composite indexes added to `firestore.indexes.json` that still require an actual `firebase deploy --only firestore:indexes` to take effect), not the `jobs/{jobId}/milestones` subcollection this doc and `06-escrow-wallet.md` §2 describe. This is intentional and matches `06` §8's own sequencing ("ship the Wallet screen against the single-milestone model... doesn't need multi-milestone support to exist") — but concretely, today's summary card sums `PaymentStatus.escrowHeld`/`.released` amounts, not milestone aggregates, and the ledger has no milestone-label field. Upgrade to the milestone-aware version once that subcollection ships.



**Evidence key**: 🟢 Directly evidenced · 🟡 Extrapolated · 🔵 Inferred · unchanged items cite `06-escrow-wallet.md` directly.

---

## What changed vs. `06-escrow-wallet.md` §6

1. **Navigation**: Wallet is now a primary bottom-nav tab (`02-design-system-v2.md` §9.4), not a row inside Profile. Already corrected in `06` and `03-ia-navigation-journeys.md` — this doc just builds the screen that decision points to.
2. **Visual language**: borderless gray-fill ledger rows (not white-bordered cards), and — 🟢 the one piece with real direct evidence — the summary card reuses the *exact* navy/green escrow-card treatment from Image A, since a wallet balance summary is functionally the same kind of "this is the serious, trust-critical part" moment the reference already showed a real design for.
3. **Badge/chip contrast**: the general rule just added to `02-design-system-v2.md` §11 applies to every status chip on this screen (`escrowLocked`/`Pending`/`Released`/`Failed`) — colored icon or colored fill-with-white-text, never colored text on a light background.

Everything else — the data model, the ledger's Firestore query shape, loading/empty/error state *content* (not just their visual skin), and the security scoping — is `06-escrow-wallet.md` §6 unchanged.

---

## Layout

1. **Page header** 🟡 — decided: a plain bold "Wallet" title, distinct from Home's full branded header (avatar+wordmark+trust icon). Reasoning: Home is the one tab that needs full brand identity on every open; the other three primary tabs (My Tasks, Wallet, Profile) are utility destinations that benefit more from getting straight to content than repeating the brand header — a common, low-risk convention, not evidenced either way by the reference (which only shows the Home tab).
2. **`WalletSummaryCard`** 🟢-adjacent — navy panel, reusing Image A's escrow-card visual language directly: bold white heading ("Your Wallet"), key stat(s) in large type (customer: "In Escrow" / "Total Spent"; artisan: "In Escrow" / "Available to Withdraw" / "Paid Out"), green accent used only where it was already evidenced as accessible (§11's 7.83:1 green-on-navy pairing) — never as small chip text elsewhere on this screen.
3. **`PayoutBlockedBanner`** 🟡 — artisan-only, conditional, amber/warning-toned (not navy — reserving navy for the summary card keeps it meaning one specific thing: "this is the trust-critical summary," not a general dark-card style used everywhere). Per `06-escrow-wallet.md` §4 point 4 — tappable, routes to `/bank-details`.
4. **Ledger list** — `LedgerRow` × N, borderless gray-fill (`02-design-system-v2.md` §9.2's card style), status chip using the general contrast rule, currency in `AppTextStyles.currency` tabular figures (`02-design-system.md` §3, unaffected by the reset).
5. **Filter bar** 🟡 — minimal, date-range + status filter, sitting between the summary card and the list rather than as a separate screen/sheet.
6. **`V2BottomNav`** — Wallet tab active (filled green pill, per the resolved nav pattern).

## Component hierarchy
- `WalletScreen`
  - `PageHeader` ("Wallet")
  - `WalletSummaryCard` — 🟢-adjacent, navy/green, reuses the evidenced escrow-card language
  - `PayoutBlockedBanner` (conditional) — 🟡
  - `FilterBar` — 🟡
  - `LedgerRow` × N — 🟡 restyled from `06-escrow-wallet.md` §6's original `LedgerRow` spec, borderless gray fill, contrast-safe status chip
  - `V2BottomNav`

## Interactions, Loading/Empty/Error/Success states, Firestore/Cloud Function implications, Notification triggers, Security considerations
**Unchanged from `06-escrow-wallet.md` §6** — that spec's content-level decisions (tap-row-for-detail, artisan blocked-banner deep-links to bank details, per-role empty-state copy, shimmer loading, milestones collection-group query, party-scoped security) are all still correct and not affected by a visual reset. Re-stating them here would just be copying text; read `06` §6 for the substance, this doc only supplies the skin.

## Animations
🔵 Inferred, consistent with `v2/01`/`v2/02`: ledger rows fade in on load; a milestone transitioning to `released` while the screen is open animates the row per `06`'s original note (`AppAnimations.normal`) — unchanged in substance, restyled to match the v2 motion tokens (same tokens, no change needed — `02-design-system.md` §4's motion system was never contradicted by the reference).

## Accessibility
Applies the general rule added to `02-design-system-v2.md` §11 directly: every escrow-state chip (`escrowLocked`/`Pending`/`Released`/`Failed`) uses its color as an icon or a filled background with white text — never as small colored text on the gray card fill. This is the first screen where that general rule gets applied proactively rather than found-and-fixed reactively, which is the point of having generalized it.

## Responsive behaviour
🔵 Inferred, same pattern as prior screens: ledger list stays single-column even on wide viewports (a transaction list doesn't benefit from a grid), summary card caps its max-width rather than stretching full-bleed.

---

## Decision log
- **Navy reserved for the summary card only**, not reused as a general "important card" style elsewhere on this screen (the blocked-payout banner uses amber, not navy) — keeps the navy treatment meaning one specific thing (the core trust/escrow summary) rather than diluting it into generic dark-card decoration, consistent with §1's "Trust Green is the brand, not a UI accent" principle extended to "navy is the escrow-trust color, not a UI accent" either.
