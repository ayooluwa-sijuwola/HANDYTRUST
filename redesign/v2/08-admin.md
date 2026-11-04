# V2 — Admin Web & Admin Mobile

Final phase of the v2 pacing plan. `10-admin-redesign.md` already did the full functional design for admin (Escrow Monitoring, Trust Score Management, Reports, Role Management, the confirmed-broken pagination fix, the mobile-scope decision) — none of that is re-derived here. This doc resolves the one concrete implementation question that document deferred (`02-design-system-v2.md` §7's `AdminColorsExtension` refactor) and applies the v2 visual language to the admin surface.

**Evidence key**: neither reference image shows an admin screen — everything here is 🟡 extrapolated from the consumer-side v2 language, or cites `10-admin-redesign.md`'s already-decided function directly.

---

## 1. `AdminColorsExtension` — resolved, code-ready mapping

`02-design-system-v2.md` §7 settled the *principle* (keep the distinct dark-SaaS "Ops" density, stop hand-rolling it independently of brand tokens). Verified directly against `app_colors.dart` for this doc: `AdminPalette`'s four semantic accents already have **byte-identical hex values** to the app's real tokens —

| `AdminPalette` constant | Value | `AppColors` equivalent |
|---|---|---|
| `green` | `#22C55E` | `primary` — exact match |
| `red` | `#EF4444` | `error` — exact match |
| `amber` | `#F59E0B` | `warning` — exact match |
| `blue` | `#3B82F6` | `accent` — exact match |

This confirms the fix is **purely structural, zero visual change**: replace the four re-typed constants with direct references to `AppColors.primary`/`.error`/`.warning`/`.accent`. Nothing on screen moves; only the drift risk (a future brand-color change silently not propagating to admin) goes away. `purple` (`#8B5CF6`), `indigo` (`#6366F1`), `pink` (`#EC4899`), `cyan` (`#06B6D4`) have no consumer-app equivalent — they stay as genuinely admin-exclusive tokens on the new `AdminColorsExtension`, per `02-design-system-v2.md` §7's original reasoning.

**Recommended additional call** (extending the same consistency principle this whole v2 pass has applied everywhere else): `AdminPalette.cardDecoration()` currently includes `border: Border.all(color: border)` — a bordered card, the same pattern the consumer app dropped in favor of borderless gray-fill (`02-design-system-v2.md` §9.2). Recommend dropping the border here too, keeping only the existing shadow-based separation — this is a separate axis from the color-source unification above (it's about card *shape*, not color *source*), but the same "one card language, no matter which part of the app" reasoning applies. The Ops-specific density/darkness stays exactly as designed; only the border goes, matching every other card in the app now.

---

## 2. Admin Web

### Shell / navigation
Keep the persistent sidebar + `ShellRoute` pattern (`03-ia-navigation-journeys.md` §1.1 already praised this architecture, unaffected by the visual reset) — admin is a desktop-density tool, and nothing in the consumer-side reference argues for replacing a sidebar with the consumer app's bottom-tab pattern. Visual delta only: sidebar background/text pull from the resolved `AdminColorsExtension` above.

### Cards, tables, chips
- Every `AdminSectionCard`/`AdminStatCard` drops its border per §1's recommendation, keeping only the dark-mode shadow / light-mode subtle-shadow already defined in `cardDecoration()`.
- `AdminDataTable` itself is unchanged visually by this pass — its real problem was never visual, it was the confirmed-broken client-side-only pagination found in `10-admin-redesign.md` §1/§4 (already fully specified there, cited not repeated).
- **Status chips across every admin section** (job status, dispute status, escrow-release status, verification status) follow the same standing rule from `02-design-system-v2.md` §11: color as icon or filled-background-with-white-text, never as small colored text on a light/dark-tint surface. This matters more in admin than anywhere else in the app — a data-table-dense screen has far more simultaneous status chips on screen at once than any single consumer screen, so a systemic contrast bug here would be systemic at a larger scale.

### New sections (Escrow Monitoring, Trust Score Management, Reports, Role Management)
Functionally fully specified in `10-admin-redesign.md` §5-§8 — this pass adds nothing to their logic, only notes the visual delta: all four render inside the same restyled shell/card/chip language as the rest of admin, no bespoke treatment needed. Escrow Monitoring's status chips (`escrowLocked`/`Pending`/`Released`/`Failed`) reuse the exact same tokens as the consumer Wallet screen (`v2/03-wallet.md`) — same underlying states, same colors, admin just sees them in a denser table instead of a card ledger.

### Security Logs
Still the one section `10-admin-redesign.md` §9 correctly declined to fully spec (needs new Auth-event infrastructure, not just a UI) — unchanged by this pass; nothing to visually design yet for a section whose data source doesn't exist.

---

## 3. Admin Mobile

`10-admin-redesign.md` §10 already made the key scoping call: not a responsive shrink of the data tables, a purpose-built subset for on-the-go triage — **Verification Queue, Disputes, Support Tickets, Escrow Monitoring's failed/blocked queue, and a push-driven alert feed**, explicitly *not* Analytics/Audit Logs/full Jobs-Users tables (reachable read-only, not redesigned for touch).

**v2 visual treatment for that already-scoped subset**:
- Card-based, not table-based, per `10`'s own principle — each of the five in-scope sections renders as a scrollable list of borderless gray-fill cards (same card language as every consumer screen in this pass, not a bespoke admin-mobile style), each card summarizing one actionable item (one verification submission, one dispute, one ticket, one blocked payout) with a clear primary action, not a dense multi-column row.
- **Bottom nav**: 4-5 slots (Alerts, Verification, Disputes/Reports, Escrow, More) per `10`'s spec, restyled to the same flat-bar/filled-pill-active-state pattern as the consumer app's nav (`02-design-system-v2.md` §9.3) — one nav visual language across the entire app, admin included, rather than a third distinct nav style.
- Status chips: same standing contrast rule as everywhere else.

---

## What this doc deliberately doesn't do
Re-derive any function `10-admin-redesign.md` already specified — every section's data model, security scoping, rollout sequencing, and the pagination fix are unchanged and cited, not repeated. This is the same discipline `v2/03-wallet.md` and `v2/07-artisan-screens.md` already applied: screens with real prior functional specs get a visual-delta pass, screens without one get full 15-point treatment.

---

**This completes the v2 pacing plan** from `redesign/v2/00-overview.md`. Every screen in the original plan — Home/Explore, Artisan Profile, Wallet, My Tasks, Job Detail, Profile/Settings, all four auth screens, the four artisan-side screens, and Admin Web + Mobile — now has a v2 treatment, either full-fidelity (where no prior spec existed) or a resolved visual/nav delta (where `06`-`10`'s functional work already stood). Let me know if you want a closing synthesis doc (mirroring the original program's `11-production-roadmap.md`) tying the visual reset back into that roadmap's sequencing, or want to move to implementing any specific screen in code next.
