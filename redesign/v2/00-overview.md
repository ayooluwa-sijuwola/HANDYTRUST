# HandyTrust V2 — Design Reset

Supersedes the visual-design portions of the original 11-phase program (`redesign/00-overview.md`) per your instruction to reset the redesign against the actual visual reference material rather than the codebase's existing theme. **Not a supersession of the product/architecture findings** — `01-ux-audit.md`'s backend findings (escrow payout, Trust Score ranking, security gaps), `04`'s Firestore/Storage architecture, `05`'s Trust Score formula, `06`'s escrow/milestone model, `07`'s GPS flow, and `08`'s messaging/notification design are all still the plan. This folder only resets *how things look and are visually organized*, not what they do.

## What's in this folder

| File | Status |
|---|---|
| `00-overview.md` | This file |
| `../02-design-system-v2.md` | Done — extracted from 2 reference images, all open questions resolved, gaps inferred |
| `01-home-explore.md` | Done — full 15-point spec; 3 fixes applied (fake-progress card, badge contrast, video-feature scope decided against) |
| `02-artisan-profile.md` | Done — full 15-point spec; found and fixed a real dead-end CTA bug (general-discovery profile had no primary action at all in the current code) |
| `03-wallet.md` | Done — visual/nav delta only (functional spec unchanged from `06-escrow-wallet.md` §6); generalized the badge-contrast fix into a standing rule in `02-design-system-v2.md` §11 |
| `04-my-tasks.md` | Done — added a real "Disputed" filter (previously flattened into "Completed") |
| `05-job-detail.md` | Done — the hub screen; consolidated 3 overlapping timeline widgets into 1, added the "Report an issue" entry point, integrated the Live ETA card and milestone payment section |
| `06-profile-settings.md` | Done — found 4 real navigation bugs (2 mis-wired menu items, 1 dead button, 1 stub pointing at the wrong existing screen instead of the right nonexistent one) |
| Auth flows (code, not a spec doc) | Done — `AuthCard` retrofitted to the borderless card language; `forgot_password_screen.dart`/`verify_email_screen.dart` rebuilt to match login/signup |
| `07-artisan-screens.md` | Done — Dashboard, Open Jobs Feed, Portfolio, Verification; found 1 new gap (no rejected-application banner) |
| `08-admin.md` | Done — resolved `AdminColorsExtension` with a verified byte-exact color mapping; applied v2 visual language to Admin Web + Mobile, citing `10-admin-redesign.md`'s function unchanged |
| `09-synthesis-and-roadmap.md` | Done — closing synthesis: build order, a consolidated checklist of every real bug found across this pass, and the open product decisions still waiting on you |

**Pacing plan complete.** Every screen originally listed now has a v2 treatment. See `09-synthesis-and-roadmap.md` for what to actually build first.

## Sourcing, restated plainly

Two static images exist as reference material (`02-design-system-v2.md` §0). No video. Every screen spec in this folder is graded the same way that doc was: **directly evidenced** (matches Image A/B), **extrapolated** (a consistent, reasoned extension of the extracted design language to a screen the reference doesn't show), or **inferred** (per your instruction, filling genuine gaps rather than blocking on them). I'll keep marking these distinctly rather than presenting extrapolation as if it were photographed fact — that distinction is what makes this whole exercise trustworthy rather than just confident-sounding.

## Pacing plan for the remaining screens

The brief's Phase 2 ask — full 15-point spec (Purpose, User Journey, Layout, Component hierarchy, Interactions, Animations, 4 states, Accessibility, Responsive, Firestore, Cloud Function, Notification triggers, Security) for **every** screen across Customer, Artisan, Admin Web, and Admin Mobile — is roughly 40+ screens at this depth. That's genuinely a multi-turn undertaking, the same shape as the original 11-phase program, not something to compress into fewer, shallower passes just to appear to cover everything at once.

Proposed order (evidence-first, then extrapolating outward by product proximity):
1. **Home/Explore** (customer) — done, direct evidence.
2. **Artisan Profile / Nearby Expert detail** — the natural next screen a tap on Image A's list cards leads to; still close to direct evidence (extrapolating one level from a fully-evidenced list-card component).
3. **Wallet** — now a primary nav tab per the resolved nav decision; high product priority (this is the escrow-trust surface).
4. **My Tasks (Jobs)**, **Job Detail** — the hub screen, most complex.
5. **Profile, Settings** — lower complexity, faster to spec.
6. **Auth flows** — already implemented in code (login/signup) against Image B; extend the same treatment to forgot-password/verify-email for consistency.
7. **Artisan-side screens** (dashboard, open jobs feed, portfolio, verification) — extrapolating the customer-side language to the other role.
8. **Admin Web**, then **Admin Mobile** — last, per the original program's own reasoning (`10-admin-redesign.md`'s sequencing note still applies: don't spec a mobile view of sections still changing underneath it).

Each screen ships as its own file in this folder as it's done, same working pattern as the original program — reviewable independently, not one giant deliverable at the end.
