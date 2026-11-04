# HandyTrust Redesign — Program Overview

## How to read this folder

This is a phased redesign program, not a single document. Each file is a standalone deliverable that can be reviewed, revised, and approved independently before the next phase starts.

| # | File | Status |
|---|---|---|
| 00 | `00-overview.md` | This file |
| 01 | `01-ux-audit.md` | Done — 2 findings corrected post-review, see errata |
| 01.5 | `01.5-critical-review-and-hardening-sprint.md` | Done — independent review + launch-gating sprint plan |
| 02 | `02-design-system.md` | Superseded — see `02-design-system-v2.md` |
| 02v2 | `02-design-system-v2.md` | Draft — extracted from 2 reference images; 4 open conflicts with v1 need your call before Phase 9's screens are rebuilt |
| 03 | `03-ia-navigation-journeys.md` | Done (partial) — settled sections buildable now; Wallet/GPS/notification-pref nav sections provisional pending 06/07/08 |
| 04 | `04-firestore-architecture.md` | Done — Storage rules reviewed for the first time, 2 new privacy gaps found |
| 05 | `05-trust-score.md` | Done — two verified formula bugs found, ranking integration + explainer screen spec'd |
| 06 | `06-escrow-wallet.md` | Done — milestone-payment architecture, payout automation, Wallet screen spec'd |
| 07 | `07-gps-flow.md` | Done — live-location model, map vendor decision, Punctuality tie-in to Trust Score |
| 08 | `08-messaging-notifications.md` | Done — typing/archive/search/reports designed, notification taxonomy expanded, preferences screen spec'd |
| 09 | `09-screens-customer-artisan.md` | Done — full specs for 9 high-stakes screens, concise pass for the rest, 2 dead screens flagged |
| 10 | `10-admin-redesign.md` | Done — pagination gap confirmed (not just risked), 5 new sections spec'd, mobile admin scoped by actual use case |
| 11 | `11-production-roadmap.md` | Done — full readiness checklist, consolidated backlog, competitiveness recommendations |

**Program complete** as originally scoped (11 phases + 1.5). **Visual design has since been reset**: real reference images were provided, and the visual-design portions of this program (primarily `02`, `03`'s nav sections, `09`'s screen specs) are being rebuilt against them in `redesign/v2/` — see `redesign/v2/00-overview.md` for that in-progress work and `02-design-system-v2.md` for the extracted design language. The backend/architecture findings (`01`, `04`, `05`, `06`, `07`, `08`, `10`, `11`) are unaffected and still the plan — only *how things look and are visually organized* is being redone.

**Sequencing note**: the original straight 1→11 order has been revised. `01.5` found that two of the audit's four "critical" findings didn't survive direct source verification (see its §1), and reordered the remaining work so screen-by-screen design (09, 10) isn't spec'd against a backend that doesn't yet do what the product claims. Full reasoning and dependency graph in `01.5` §6.

## Framing correction (important)

The original brief treats this as if HandyTrust is an early-stage product needing a first real design pass. **It isn't.** Codebase reconnaissance (see `01-ux-audit.md` §0) found:

- A working, transactional job state-machine (`JobService`, 775 lines) with an immutable per-job audit log.
- A real, server-authoritative Trust Score formula, already weighted across 5 factors and live in Cloud Functions.
- A functioning Paystack escrow integration (webhook-verified, auto-release scheduler) — with one specific, already-self-diagnosed security bug (secret key reachable from a client-readable Firestore doc).
- A complete 8-tab admin web dashboard, GoRouter admin shell, and Firestore rules with a genuinely sophisticated access-control model (field-diffed partial updates, state-machine-validated transitions mirrored between rules and service layer).
- A Riverpod + GoRouter architecture that is already the right choice for this app — this redesign will not recommend replacing it.

This changes the job: **this is an evolution of a real product, not a greenfield build.** Every deliverable in this program is written against the actual code, not a generic marketplace template. Recommendations that would mean discarding working, correct infrastructure (the job state machine, the rules architecture, Riverpod/GoRouter) are explicitly out of scope unless a specific defect requires it — the brief's "do not change HandyTrust's core concept" instruction is being read as applying to this working core, not only to product vision.

**No meeting recording was available as a visual reference for this pass.** Per your direction, the existing in-app design system (`lib/theme/app_colors.dart`, `app_theme.dart`, `app_design_system.dart`) is being treated as the current, agreed design language and evolved from — Trust Green (`#22C55E`) primary, Inter typeface, Material 3 base, already-defined spacing/radius/shadow/animation tokens. `02-design-system.md` will flag every place this needs your visual confirmation rather than silently inventing a new direction.

## Working agreement

- Each phase ships as a markdown file in this folder, reviewed before the next starts.
- Findings are graded **Critical / High / Medium / Low** by trust, safety, and revenue impact — a marketplace's currency is trust, so issues that let one side defraud or endanger the other are weighted above cosmetic ones.
- Every recommendation states what exists today, what changes, and why — no unexplained rewrites.
