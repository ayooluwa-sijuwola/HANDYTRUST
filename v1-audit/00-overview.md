# HandyTrust V1 — Complete Technical Documentation & Archive

Purpose: a standalone, neutral technical record of HandyTrust V1 as it exists in this repository today, complete enough that V2 could be rebuilt from this documentation alone, and V1 archived. This is **not** a redesign document — no code was modified to produce it, and no recommendations are offered outside the explicitly-requested Parts 18–22.

**Provenance note**: this repository already contains an extensive prior body of verified technical analysis in `redesign/` (an 11-phase product/backend audit, a visual-reset design-system pass, and two feature-implementation reports for Agreement Confirmation and Escrow Payout Automation — the latter two are the newest code in the app and are documented here as first-class V1 features, not omitted). Where this audit's findings overlap with `redesign/`, they are cross-referenced rather than silently re-derived from scratch — but every fact stated here was independently confirmed against the actual source files during this pass, consistent with the "never guess" rule, not copied on trust from the earlier documents.

**Method**: every part below is built from direct inspection of the files that implement it — models, services, providers, screens, `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `functions/index.js`, and `router.dart`. Where something could not be confirmed from the repository, that is stated explicitly rather than inferred.

**Severity/status marking used throughout**: ✅ fully implemented and reachable · ⚠️ implemented but partial/has a known gap · ❌ not implemented · 🔒 exists in code but unreachable from the UI (dead code).

---

## Parts index

| # | Part | Status |
|---|---|---|
| 1 | Project Overview | Done |
| 2 | Authentication | Done — includes a verified finding that "Guest mode" doesn't exist despite older root-level docs describing it |
| 3 | Customer Features | Done |
| 4 | Artisan Features | Done |
| 5 | Admin Features | Done (scope note: the 5,000-line admin dashboard file was spot-verified, not read line-by-line in full — stated in the doc) |
| 6 | Job Workflow (full lifecycle) | Done — includes a self-caught-and-corrected error (see file's note) |
| 7 | Quote Workflow | Done |
| 8 | Escrow Workflow | Done |
| 9 | Chat System | Done |
| 10 | Notification System | Done |
| 11 | Firestore — complete schema | Done — found `admin_alerts` is written by 3 Cloud Functions but has zero rules coverage, unreadable by any client |
| 12 | Security Rules | Done |
| 13 | Providers | Done — 60+ providers across 20 files, grepped directly |
| 14 | Services | Done — 21 services; 3 of them (EscrowService, DemoEscrowService, PaymentService) are historical duplicates of the real payment path |
| 15 | Screens inventory | Done — 43 screens, 41 reachable, 2 dead |
| 16 | Navigation Map | Done |
| 17 | External Services | Done |
| 18 | Feature Matrix | Done |
| 19 | Dead Code | Done |
| 20 | Technical Debt | Done |
| 21 | Reusable Components | Done |
| 22 | Rebuild Recommendation | Done |

**Audit complete — all 22 parts done.** See Part 22 for the closing synthesis and the one-paragraph summary of what to keep, fix, rebuild, and remove.

This index is updated as each part is completed. Given the scope (every screen, service, provider, collection, and rule in the application), this is produced across multiple passes rather than compressed into one shallow document — the same working pattern already established in `redesign/`.
