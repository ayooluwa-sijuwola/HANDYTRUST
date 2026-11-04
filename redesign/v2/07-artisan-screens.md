# V2 — Artisan-Side Screens

Eighth phase: Dashboard, Open Jobs Feed, Portfolio Manager, Verification Upload. Grouped in one file — the v2 visual language (borderless gray-fill cards, contrast-safe status chips, flat pill-active nav) is fully established by this point and doesn't need re-deriving four times; this doc focuses on what's actually different per screen: content, workflow, and any real findings.

**Evidence key**: 🟡 Extrapolated · 🔵 Inferred · 🟢 reused from already-evidenced components · 🟠 real finding from reading the code.

---

## 1. Artisan Dashboard (`ArtisanHomeTabContent`)

This is the artisan role's equivalent of `v2/01-home-explore.md`'s Explore tab — same nav slot, different content, per that doc's own decision log ("artisan's equivalent tab leads with Open Jobs Feed instead" — refined here: it leads with the artisan's *own* dashboard, with Open Jobs Feed one tap away via Quick Actions, not literally replacing Home's content 1:1).

**What's already right, read directly** — conditional sections matching artisan state precisely: pending-approval banner (`approvalStatus == 'pending'`), availability toggle (only once approved — correctly prevents toggling availability before approval even makes sense), a verification/trust card, stats row, quick actions, jobs section. Also: if no artisan doc exists yet, auto-redirects to `/register/artisan` — confirms the artisan step-2 onboarding path this program has referenced since `03-ia-navigation-journeys.md` §1 actually fires from here, not left dangling.

**v2 treatment**: every section restyled to borderless gray-fill cards; verification/trust card reuses the Trust Score tier badge component from `v2/02-artisan-profile.md` (same component, artisan viewing their own standing instead of a customer viewing someone else's — one component, two contexts, not two builds); job list rows reuse `v2/04-my-tasks.md`'s `JobListRow` styling (including the new Disputed filter, since an artisan needs to see their disputed jobs distinctly too, not just customers).

**🟠 One real gap worth fixing while here**: the pending-approval banner and availability toggle are mutually exclusive (`if pending` vs `if approved`) — reasonable — but there's no visible state for a *rejected* artisan application. Per `01-ux-audit.md`'s verification journey (§3.4 in `03-ia-navigation-journeys.md`), rejection routes back to resubmission via `/verification`, but the dashboard itself has no banner telling a rejected artisan why they're stuck or what to do — they'd only find out by trying to submit a quote and hitting a rules rejection, the exact same silent-failure pattern already fixed for "Verify Later" elsewhere in this program. **Fix**: add a third conditional banner state (`approvalStatus == 'rejected'`) with the rejection reason and a direct link to resubmit, mirroring the pending banner's treatment.

---

## 2. Open Jobs Feed

Already deeply analyzed in the original program — `01-ux-audit.md` §2.8 and `09-screens-customer-artisan.md` §2.7 both found and fixed the same real gap: an unverified/"Verify Later" artisan can browse this feed with no proactive messaging about why quoting is blocked, only discovering it via a silent rules rejection. That fix is logical/content-level and already decided — this v2 pass makes it visual:

- **Persistent gate banner** (unverified artisans only): amber/warning-toned per `v2/05-job-detail.md`'s color-scoping decision (warning tones reserved for exactly this kind of "you can look but not act yet" state, distinct from navy's escrow-trust meaning and green's success/verified meaning) — not a modal, not a one-time dismissible toast, since the constraint is persistent for as long as verification is pending.
- **Job cards**: borderless gray-fill, restyled from the current implementation's already-decent loading/error/empty states (confirmed reading the file in the original program's pass — `_FeedLoadingSkeleton`, a real empty state, a real error state already exist, just due for the v2 skin).
- **Quote-status indicator** (has this artisan already quoted this job?): contrast-safe chip, same rule as everywhere else in this pass.

## 3. Portfolio Manager

Read directly: two tabs (Photos / Projects — matches the `portfolio_projects` vs. `artisans.portfolioImageUrls` split documented back in `01-ux-audit.md` §0's recon), add/remove/reorder for photos, compression at an 800KB threshold before upload. Sound, working logic — no bugs found here.

- **v2 treatment**: photo grid becomes borderless gray-fill cells (from the current bordered grid); the tab bar itself restyled to match the app's tab-selection convention (reuse the same filled-pill selected-state pattern already established for the bottom nav and filter chips in `v2/04-my-tasks.md`, so "selected" reads consistently across every tab/chip/nav control in the app, not as three different visual languages for the same concept).
- **Reaffirming the Decision Log from `v2/01-home-explore.md`**: no video portfolio items — this program decided against building artisan video as a feature this pass; Portfolio stays photos + projects, unchanged in scope.

## 4. Verification Upload

Read directly: checks for an existing verification submission on load (handles resubmission correctly), selfie (front camera) + government ID capture, compression, and a "Verify Later" deferral path (`_deferring` state). **Worth crediting explicitly**: the code already contains a fix for a real prior bug — a comment documents that both image pickers previously had no error handling and called `setState()` without a `mounted` check, causing an uncaught crash when the camera activity backgrounded mid-capture (a genuinely tricky Android lifecycle bug, already fixed). Not a new finding — flagging it so it's clear this file has real engineering care already, not something to casually rewrite.

- **v2 treatment**: restyle to the same card language as everywhere else; the selfie/ID capture tiles become bordered-to-borderless per the standard swap.
- **Applies the decision from `09-screens-customer-artisan.md` §2.8 visually**: at the "Verify Later" decision point itself, show the actual consequence in plain language ("You can browse jobs, but you won't be able to submit quotes until you verify") right next to the deferral button — not just fixing the downstream Open Jobs Feed banner (§2 above), but making the *upstream* decision an informed one too, so an artisan choosing to defer knows what they're trading off at the moment they choose it.

---

## Cross-cutting notes for all four screens
- **Firestore/Security**: unchanged from each screen's existing, already-correct implementation — this whole file is a visual and small-workflow pass, not a data-model change, except the one new rejected-status banner (§1) which reads a field (`approvalStatus`) already present on the artisan doc — no new query.
- **Accessibility**: the standing rule from `02-design-system-v2.md` §11 (color as icon/fill, never small text) applies to every status/gate banner introduced or restyled across all four screens.
- **Notification triggers**: none new from these screens directly — verification approval/rejection notifications already exist per `01-ux-audit.md` §0's recon (`verification_approved`/`verification_rejected` in the whitelist); this pass doesn't add to that.

---

**Next**: per the pacing plan, Admin Web is last, then Admin Mobile. That's a large, distinct surface (`10-admin-redesign.md`'s territory) — worth confirming you want the same full-fidelity treatment there, or a different pace, before diving in.
