# 01 — UX, Product & Security Audit

Grounded entirely in the current codebase (`c:\PROJECTS\handy_trust`, main branch) — every finding below cites the file it comes from. Findings are graded by impact on trust, safety, and revenue, since those are what a marketplace actually sells.

> **Errata (post-publication correction):** an independent critical review (`01.5-critical-review-and-hardening-sprint.md`) re-verified every 🔴/🟠 finding directly against source instead of trusting this document's own citations. Two findings below were wrong or overstated and have been corrected in place: **1.4** (the composite index this finding claimed was missing actually exists — the original claim came from a stale line in `README.md` that was never independently checked against `firestore.indexes.json`) and **1.2** (the vulnerable client code path was already removed before this audit was written — the current exposure is a much smaller residual rules-hardening gap, not a live secret leak). **2.3** is also narrowed — `EscrowService` is wired only to the demo payment path, not production. Read `01.5` alongside this file; it is the more reliable prioritization.

**Severity key**: 🔴 Critical (breaks the core value proposition or exposes money/PII) · 🟠 High (real user harm or fraud path, not yet exploited-looking but live) · 🟡 Medium (confusing/incomplete but contained) · 🟢 Low (polish).

---

## 0. What already works (do not re-litigate)

Before the findings, it's worth being explicit about what's already solid, because a redesign that "fixes" working infrastructure wastes effort that should go to real gaps:

- `JobService` (`lib/core/services/job_service.dart`, 775 ln) — a correct, transactional job state machine with an atomic audit log on every mutation. This is the right architecture; keep it as the single write-authority for `/jobs`.
- Firestore rules (`firestore.rules`, 511 ln) mirror the same state machine server-side (`_isValidJobTransition`), field-diff partial updates, and correctly scope the multi-artisan pre-match chat so artisans can't see each other's messages. This is genuinely careful rules engineering.
- Trust Score is real and server-authoritative (`functions/index.js` `_computeTrustScore`), not a placeholder.
- Paystack is wired through a webhook (HMAC-verified) as the authoritative payment-confirmation path, with a client callable path as a secondary confirm — the right shape, modulo one specific bug below.
- Riverpod + GoRouter is the correct architecture for this app's complexity. **Not being replaced.**

---

## 1. 🔴 Critical Findings

### 1.1 Escrow release does not pay anyone
`escrow_releases/{id}` documents are created (`status: 'pending'`) when a customer confirms completion, but no Cloud Function in `functions/index.js` consumes that collection to call Paystack's Transfer API. Artisan bank details are collected (`BankDetailsScreen` → `artisan_private/{uid}`) but nothing ever pays out to them.

**Impact**: this breaks the platform's entire pitch — "payment routed through escrow, held until confirmed." Today, "release" is a Firestore status flip, not a movement of money. If this shipped as-is, every artisan who completes a job and gets "released" escrow would see a status change and no deposit. This is the single highest-priority build item in the whole program.

**Fix direction**: a Cloud Function triggered on `escrow_releases` creation (or a scheduled sweeper) that calls Paystack Transfer, updates the doc to `processing → completed/failed`, and notifies both parties. Needs its own reconciliation/retry story (see `06-escrow-wallet.md`).

### 1.2 ~~Paystack secret key is exposed~~ — CORRECTED: already fixed, residual gap is Medium (moved, see 3.7)
Original claim overstated. `lib/core/services/paystack_service.dart` (read directly) is already a pure Cloud Functions facade — its own doc comment states the client-side-secret-key design was **previously** used and has been replaced. `firestore.rules` blocks all client writes to `/config/**` (`allow write: if false`), so no client can plant a secret there either. There is no live exploit path today. The residual risk — `/config` still allows broad `read: if isSignedIn()`, so *if* an operator ever manually adds a secret field via console/Admin SDK, it would be client-readable — is real but much smaller, and is tracked as **3.7** in the Medium section, not here.

### 1.3 Trust Score does not drive search ranking, despite three separate scoring formulas existing
The brief is explicit: ranking = **Distance → Trust Score → Rating → Experience**. What's actually implemented (`lib/core/services/matching_service.dart:66-76`, `lib/models/artisan_model.dart:76-81`):

- Ranking uses `ArtisanModel.matchScore` — a **third, independent** formula (`rating×0.40 + completionRate×0.30 + responseTime×0.20`) — plus a distance proximity bonus (max +0.10 within 50km).
- The actual Trust Score (`functions/index.js` `_computeTrustScore`, 5 weighted factors including verification and disputes) is **never read by the matching service**.
- "Experience" (job count) only enters via a binary rising/experienced split (`<10 jobs` vs. not), not as a ranking factor within the experienced bucket.

So there are three overlapping-but-different scoring systems in the codebase — `trustScore` (badges/tiers), `matchScore` (ranking), and an implied fourth (the brief's requested formula) — computing similar things differently, none of which match the brief's specified priority order.

**Impact**: this directly contradicts the product's core trust claim. A highly-verified, dispute-free, high-trust-score artisan can rank below a barely-verified one with a slightly better raw rating, because verification/disputes never enter ranking at all.

**Fix direction**: covered in `05-trust-score.md`. In short — collapse to one formula, make it the ranking input, and make Distance the primary sort key with Trust Score as the dominant tiebreaker per the brief's ordering.

### 1.4 ~~Auto-release escrow function is deployed-but-broken~~ — RETRACTED
False. `firestore.indexes.json` contains exactly the composite index this query needs (`jobs`: `status ASC, autoReleaseAt ASC`) — read directly, lines 37-44. `functions/index.js`'s `autoReleaseEscrow` query (`status == 'submitted'`, `autoReleaseAt <= now`) matches it exactly. This finding was copied from a stale line in `README.md` without checking the actual index file, which is exactly the kind of unverified claim this program should not be shipping. Retracted from the Critical section entirely.

What *does* still deserve a (much smaller) mention: there's no confirmation the declared index has actually been deployed/built against the live Firestore project (declaring an index in the repo and having it built in production are different steps), and no monitoring/alerting exists on scheduled-function failures generally. Tracked as **3.8** in the Medium section — an operational-visibility gap, not a broken feature.

---

## 2. 🟠 High-Severity Findings

### 2.1 Primary "+" action is not role-aware — MOOT as of `02-design-system-v2.md` §9.3
The floating action button in the shared bottom nav (`lib/widgets/premium_scaffold.dart:35-40`) always routes to `/request` — the customer's post-a-job form — regardless of whether the signed-in user is currently in artisan mode. An artisan in artisan mode tapping the app's single most prominent action button lands on a form meant for the other role.

**Original fix direction** (superseded): make the FAB role-conditional. **Actual resolution**: the nav bar redesign (visual-reference-driven, `02-design-system-v2.md`) removes the center FAB entirely — "post a job" becomes an in-content hero action on the customer's Explore tab instead. No FAB left to be role-unaware.

### 2.2 Two parallel, un-gated payment paths reachable from the same UI
`PaymentScreen`/`PaymentWebviewScreen` (real Paystack) and `DemoEscrowScreen` (`DemoEscrowService`, simulated) are both reachable in the shipped app with no build-time or role-based gate separating them (self-documented in README). A real customer should never be able to reach a fake payment screen, even accidentally.

**Fix direction**: gate the demo path behind a debug/staging build flag; it should not exist as a reachable route in a release build at all.

### 2.3 Two independent job/escrow state-machine implementations — NARROWED after verifying call sites
`EscrowService` (`lib/core/services/escrow_service.dart`, 148 ln) duplicates transition methods already owned by `JobService`. Verified call sites (`grep` for `EscrowService(` / `EscrowService.`): it is wired **only** to `demo_payment_provider.dart` — the demo path, not production payment. So this is not "a customer could get either auto-release window" (production only ever goes through `JobService`, which is already internally consistent at 48h — its own code comment notes it was previously 7 days and documents the earlier inconsistency being resolved). What remains true: `EscrowService` still hardcodes the old 7-day value, so the *demo* flow's business logic has quietly drifted from production's. On its own that's low stakes (it's a demo). It only becomes a real issue in combination with **2.2** — since the demo path is reachable from production UI with no gate, a real user could end up exercising `EscrowService`'s stale logic instead of `JobService`'s corrected logic.

**Fix direction**: unchanged in spirit, smaller in urgency — delete `EscrowService` once `DemoEscrowService`/demo payment path is either gated out of release builds (2.2) or rebuilt on top of `JobService` directly. Sequence this after 2.2, not as its own independent priority.

### 2.4 Trust Score's rating component defaults unrated artisans to a neutral mid-score
`TrustScoreService`/`_computeTrustScore`: an artisan with zero reviews gets rating-component `50` (of 100) — i.e., 12.5 of 25 points — rather than being excluded or dampened. Combined with the volume-weighted completed-jobs factor (which rewards raw count, not ratio), a new account can reach a deceptively high score before any real quality signal exists.

**Impact**: this is a gameable seam — a bad-faith actor could push a new account's score up via low-cost activity (fast responses, self-verification) before genuine rating signal has a chance to pull it down, undermining exactly the trust guarantee the score exists to provide.

**Fix direction**: use a Bayesian/confidence-weighted rating average (shrink toward the platform-wide mean until `totalRatings` crosses a threshold) instead of a flat neutral default; keep the "New" tier visually distinct and filtered separately from "Trusted" in search unless the customer opts in.

### 2.5 Escrow payout consumer aside, response-time (15% of Trust Score) appears uninstrumented
No write path for `responseTimeMinutes` was found anywhere in the reviewed services. If nothing updates it, every artisan may be scored against a stale default, silently distorting 15% of every artisan's trust score and (once fixed per 1.3) their ranking.

**Fix direction**: instrument response time explicitly — first-quote-after-job-post timestamp delta, or first-chat-reply timestamp delta — as a Cloud Function side effect, same pattern already used for `onJobCompleted`.

### 2.6 Reputation-farming path via manufactured job completion
Reviews require the job to be `completed` and restrict creation to the job's customer — a reasonable baseline — but nothing prevents two colluding accounts from repeatedly posting trivial jobs, "completing" them, and leaving 5-star reviews to inflate an artisan's score. At scale this is a known marketplace attack (see Upwork/Fiverr fake-review rings).

**Fix direction**: add anomaly signals surfaced to a Trust & Safety admin view (same customer↔artisan repeat pairing frequency, job value vs. review frequency, account age vs. review velocity) — detailed in `05-trust-score.md`.

### 2.7 No abuse/rate-limiting layer
Firestore rules validate shape and ownership but cannot cheaply rate-limit. No App Check, no Cloud Function-side counters were found guarding job posting, quote submission, chat sends, or review creation. A single compromised or malicious account can currently spam any of these without friction.

**Fix direction**: enable Firebase App Check across client SDKs (blocks non-app traffic cheaply), and add Cloud Function-enforced per-user rate limits on the highest-abuse-value actions (job posting, chat send, quote send) — detailed in `04-firestore-architecture.md`.

### 2.8 "Verify Later" artisans can build a full profile and appear to function normally, then silently fail to quote
An artisan who defers verification (`pending_later`) can browse the open jobs feed and toggle availability, but Firestore rules block them from actually submitting a quote until `id_verified`/`trusted`. Recon did not find UI messaging that proactively surfaces this gap before the artisan attempts to quote and hits a rules rejection.

**Fix direction**: surface unverified status persistently (not just as a rejected write) — a banner on the feed, a disabled-with-explanation quote button, and a nudge back to verification.

---

## 3. 🟡 Medium-Severity Findings

### 3.1 Hidden admin-access gesture on the customer home screen
`home_screen.dart:52-82` — a long-press on the greeting text checks `/admins/{uid}` and prompts a PIN dialog. This is security-through-obscurity sitting on a production customer-facing surface: it's an odd, undiscoverable UX for legitimate admins and a strange thing for an ordinary user to stumble into by accident.

**Fix direction**: real admins should sign in through a dedicated, rate-limited admin entry point (a distinct login surface or a role-aware redirect post-login for accounts with the admin claim) — not a gesture buried in customer chrome.

### 3.2 Dual near-duplicate admin audit-log services
`admin_audit_log_service.dart` and `admin_audit_service.dart` (`lib/core/services/`) have near-identical `log()` signatures; `VerificationService` uses one of them. Two write paths to the same audit collection risk inconsistent records (e.g., one missing `logInBatch()`'s atomicity) depending on which a future feature happens to import.

**Fix direction**: consolidate to one canonical service; delete the other.

### 3.3 Admin dashboard uses a completely separate color system
`AdminPalette` (`lib/screens/admin/admin_palette.dart`, purple/indigo-toned) is independent of `AppColors`/`AppColorsExtension` (green-toned) used everywhere else. This directly works against the brief's "consistent design system" goal — admin will visually read as a different product. Addressed in `02-design-system.md`.

### 3.4 `PhoneLoginScreen` exists but isn't routed
`lib/screens/auth/phone_login_screen.dart` has no corresponding `GoRoute` in `router.dart`. Either it's dead code that should be removed, or phone login is an intended entry point that's currently unreachable — needs a product decision either way (see `03-ia-navigation-journeys.md`).

### 3.5 No map UI despite location data existing
`geolocator`/`geocoding` are used for a one-time address capture at job-posting time, and artisan lat/lng feed the matching distance bonus — but no `google_maps_flutter` (or any map package) exists in `pubspec.yaml`. Customers can't see where a job/artisan actually is on a map; the brief's GPS/ETA flow (`07-gps-flow.md`) will need this dependency added.

### 3.6 Admin data tables — CONFIRMED (upgraded from "unconfirmed" in `10-admin-redesign.md` §1)
`AdminDataTable<T>`, read directly: it paginates an already-fully-materialized in-memory `List<T>` by index math (`start = _page * pageSize`), not a Firestore cursor (`startAfter`) driving the query. So the concern this entry originally hedged on is real today, not just a risk at future scale — the full collection is already being read before the UI ever shows "page 1 of N." Fix (server-side cursor pagination) specified in `10-admin-redesign.md` §4.

### 3.7 `/config` allows broad read access with no structural guard against future secret exposure (downgraded from 1.2)
`firestore.rules:399-402` — `/config/{doc}` is `read: if isSignedIn()` (any authenticated user) with `write: if false`. No client can write a secret there today, and the app no longer reads one from there — but the rule itself doesn't distinguish "safe public config" (Paystack *public* key, feature flags) from anything sensitive. This is a defense-in-depth gap, not a live leak: it relies on operational discipline (nobody ever manually adds a secret-bearing field via console/Admin SDK) rather than the rules themselves making it impossible.

**Fix direction**: split `/config` into an explicitly public-only document (safe to read broadly) and, if any server-managed sensitive config is ever needed client-side, use Cloud Functions to mediate it rather than a broadly-readable document. Cheap to fix; worth doing before launch as a hardening item, not urgent as a live-incident item.

### 3.8 No monitoring/alerting on scheduled Cloud Functions (downgraded from 1.4)
The composite index `autoReleaseEscrow` needs does exist (see corrected 1.4 above), but there's no confirmation it's actually built in the live Firebase project, and no alerting was found for scheduled-function failures in general. A silently-failing scheduled function (wrong index, quota exhaustion, an unrelated regression) would currently go unnoticed until a user complains.

**Fix direction**: confirm the index is built (`firebase deploy --only firestore:indexes` + Firebase console check), and add Cloud Monitoring alert policies on Cloud Functions error rate/execution count for every scheduled function, especially anything touching money (`autoReleaseEscrow`, and the escrow payout consumer once 1.1 is built).

---

## 4. 🟢 Low-Severity / Hygiene Findings

- `google_fonts` is a declared dependency but unused — the theme hardcodes the bundled `Inter` font family string. Harmless, but either remove the dependency or use it intentionally (e.g., if Inter is ever swapped).
- Two parallel auth/Firestore access layers appear to coexist: `lib/core/services/auth_service.dart` (actively used) vs. `lib/firebase/auth/*` + `lib/firebase/firestore/*` (repository-style, looks like earlier/legacy scaffolding). Worth confirming zero usage and deleting rather than carrying two mental models forward.
- No automated tests, no CI (`README.md` self-documents this). For a payments-and-trust marketplace, this is a standing production-readiness risk addressed head-on in `11-production-roadmap.md`.

---

## 5. Missing Features vs. the Brief

Cross-referencing the brief's explicit requirements against what recon found implemented:

| Brief requirement | Status |
|---|---|
| Milestone payments (multiple partial releases) | ❌ Not implemented — escrow is a single lock/release per job |
| Material payments (separate from labor) | ❌ Not implemented |
| Refund workflow | ❌ Not found as a distinct flow (only admin-side dispute resolution) |
| Automatic escrow reminders | ❌ No reminder notification types found |
| "I'm On My Way" → live location → ETA → auto-stop | ❌ `onTheWay` is a manual self-reported status; no GPS streaming, no ETA, no map |
| Voice notes in chat | ❌ Not implemented (brief marks this "future-ready," consistent with current state) |
| Read receipts / typing indicators | ⚠️ Partial — `isRead` exists per-message; no typing indicator found |
| Chat archive / search | ❌ Not found |
| Complaint reporting from chat | ❌ Not found — disputes are filed from job detail, not inline from a chat thread |
| Notification preferences | ❌ No preferences screen found |
| Appointment/verification/review reminder notifications | ❌ Only a fixed enum of transactional notification types exists (`quote_received`, `job_status_update`, etc.) — no reminder-class notifications |
| Radius-based matching (customer-controlled) | ❌ Matching returns a fixed top-5; no radius control surfaced to the customer |
| Admin: dedicated Trust Score management UI | ⚠️ Partial — trust score is visible per-artisan in the directory, but no dedicated override/audit UI beyond the general artisan record |
| Distinct mobile admin app | ❌ Current admin is a responsive-ish web-style dashboard (248px fixed sidebar) inside the same Flutter codebase, not a mobile-first redesign |
| Wallet / payment history screen | ❌ No dedicated wallet UI found; payments exist only as raw Firestore records |

This table is the seed for `11-production-roadmap.md`'s prioritized backlog.

---

## 6. Scalability Notes (brief detail in `04-firestore-architecture.md`)

- Matching queries the full `artisans` collection per category (`limit(100)`) and ranks client/function-side via haversine — fine at low density, will need geohash-bucketed queries or a dedicated geo-index as artisan counts per category grow past low hundreds in a single metro area.
- Escrow auto-release's missing index (1.4) is the sharpest example of a broader risk: several dashboard/admin queries were not confirmed to have matching composite indexes for their actual filter+sort combinations — recommend an index audit pass before launch, not just for the one known-broken query.

---

## 7. Priority Stack Rank — superseded

This section's ordering has been superseded by the independently re-verified prioritization in `01.5-critical-review-and-hardening-sprint.md` §2, which corrects for the 1.2/1.4/2.3 errata above. Use that document's stack rank, not this one.

---

**Next**: `02-design-system.md` — formalizing the existing Trust Green design language into a complete, consistent system (colors, type, spacing, components), explicitly flagging where I need your visual confirmation since no reference recording was available.
