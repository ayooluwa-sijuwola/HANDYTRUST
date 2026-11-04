# 05 — Trust Score Algorithm & Ranking Integration

Sequenced here per `01.5-critical-review-and-hardening-sprint.md` §6 — this is the direct sequel to the hardening sprint's Track B (make `trustScore` the actual ranking input). Everything below is read directly from `functions/index.js` and `trust_score_service.dart`, not inferred.

---

## 1. Current state, precisely verified

### 1.1 The formula that exists (`functions/index.js:224-241`, mirrored display-only in `trust_score_service.dart`)

```
trustScore = 0.30 × min(completedJobs, 50)/50 × 100        // volume, not ratio
           + 0.25 × (totalRatings > 0 ? rating/5×100 : 50)  // neutral default if unrated
           + 0.20 × verificationPoints[verificationStatus]  // unverified=0, id_submitted=50, id_verified/trusted=100
           + 0.15 × responseTimePoints(responseTimeMinutes) // <=15min=100 ... >120min=20
           + 0.10 × max(0, 100 - openDisputeCount×25)       // floors at 0 after 4 open disputes
```

Server-authoritative, recomputed transactionally on job completion/cancellation (`_recordJobOutcome`), dispute open/resolve (`_adjustDisputeCount`), rating change (`onArtisanRatingChanged`), and verification change (`onArtisanVerificationChanged`). Firestore rules correctly block all client writes to `artisans.trustScore`. This architecture is sound — nothing here needs to change.

### 1.2 Two precise, previously-unverified bugs found reading the code directly

**Bug A — `responseTimeMinutes` is a frozen constant, not a measurement.** Grepped every write site: it's set to a hardcoded `30.0` exactly once, at artisan registration (`artisan_registration_screen.dart:58`), and is **never updated anywhere else in the codebase** — not on quote submission, not on chat reply, nowhere. `_trustResponseTimePoints(30)` always evaluates to `80` (the `<=30min` bracket). This means **every artisan on the platform, forever, receives exactly 12.0 of the 15 available response-time points** — not "uninstrumented and therefore probably wrong" as the original audit hedged, but a verified, universal constant. Practically this means the response-time component currently contributes zero discriminating signal between artisans (everyone gets the same value), while still inflating every score by the same fixed amount. It's read back out for an admin analytics average (`admin_dashboard_screen.dart:1677`) — that average is therefore always exactly 30 too, which is itself a tell that this was never wired up.

**Bug B — cancellation data is tracked but never fed into the score.** `_recordJobOutcome` computes and stores both `cancelledJobsCount` and `cancellationRatePercent` on every job outcome — but `_computeTrustScore`'s input list (`stats.rating`, `.totalRatings`, `.completedJobs`, `.verificationStatus`, `.responseTimeMinutes`, `.openDisputeCount`) never reads either field. The brief explicitly lists "Cancelled jobs" and "Completion rate" as required Trust Score inputs (`## Trust Score` section) — the data pipeline for this already exists end-to-end, it's simply not connected to the formula. This is a smaller lift than Bug A to fix, since no new instrumentation is needed, only a formula change.

### 1.3 Brief's 10 required signals vs. what's implemented

| Brief signal | Status |
|---|---|
| Completed jobs | ✅ implemented (as raw volume, capped at 50 — see §3.1 on why this needs to change to a ratio) |
| Cancelled jobs | ❌ tracked, not scored (Bug B) |
| Response speed | ⚠️ scored, but the input is a frozen constant (Bug A) — currently non-functional in practice |
| Punctuality | ❌ not implemented — no data source exists yet; depends on `07-gps-flow.md` (arrival-vs-appointment-time delta) |
| Customer ratings | ✅ implemented |
| Verification status | ✅ implemented |
| Disputes | ⚠️ partially — only *open* dispute count is scored; total disputes ever raised (even if resolved in the artisan's favor) isn't distinguished from disputes raised against a genuinely bad actor vs. a vexatious customer (see §4.2) |
| Reports | ❌ no separate "report" concept exists distinct from disputes/reviews — brief lists it separately, implying e.g. a customer flagging unsafe/inappropriate behavior outside the dispute flow; not built |
| Completion rate | ❌ tracked as `cancellationRatePercent` but not scored (Bug B, inverse framing) |
| Reliability | Not a single field — best read as the composite the other 9 signals should already produce once complete, not a distinct 11th input |

Net: **4 of 10 brief-required signals are genuinely live; 1 is present but numerically inert; 3 are tracked-but-unused or partial; 2 don't exist yet** (Punctuality depends on GPS, Reports needs a new concept). This is a more precise, harsher-but-fairer read than the original audit's single line on this topic.

---

## 2. Redesigned formula

Two goals drove every change here: (1) close Bugs A/B and the brief-signal gaps above without a wholesale rewrite of a formula that's mostly sound, and (2) close the gaming vectors flagged in `01-ux-audit.md` 2.4/2.6 (neutral-default rating inflation, review-farming) now that this score is about to actually drive ranking (`01.5` Track B) — hardening a score nothing reads is wasted precision, but this score is about to matter, so it needs to hold up.

### 2.1 Completed jobs → switch from volume to a Bayesian-shrunk completion *rate*

Current: `min(completedJobs,50)/50` — rewards raw count, structurally indifferent to reliability. An artisan with 40 completed / 45 total (89% completion) scores lower than one with 50/50, correctly — but one with 50/200 (25% completion, mostly cancelled or abandoned) scores identically to the 50/50 artisan, which is wrong; volume alone can't distinguish those.

**New**: `completedRate = completedJobs / max(totalJobs, 1)`, shrunk toward a platform-wide prior mean to avoid punishing brand-new artisans with a tiny sample (a single early cancellation shouldn't be catastrophic) — same Bayesian-averaging technique proposed for ratings below:
```
shrunkCompletionRate = (completedJobs + k × platformMeanCompletionRate) / (totalJobs + k)
```
with `k` (a "confidence" constant, suggest `k=5`, i.e. treat the prior as worth 5 jobs of evidence) tuned once real platform data exists. Combine with a smaller residual volume bonus (artisans with a longer track record at the *same* completion rate should still edge out newer ones) — recommend `0.24 × shrunkCompletionRate×100 + 0.06 × min(completedJobs,50)/50×100`, keeping the total weight at 30% but splitting it between rate (dominant) and volume (tiebreaker), which directly closes the "50/200 scores like 50/50" gap while still rewarding genuine experience.

### 2.2 Customer rating → Bayesian shrinkage instead of a flat neutral default (closes `01-ux-audit.md` 2.4)

Current: `totalRatings>0 ? rating/5×100 : 50` — a hard cliff. Zero reviews = automatic 50 (12.5 of 25 points); one review = fully trusts that single data point, however extreme.

**New**: same shrinkage technique as above, applied smoothly instead of as a step function:
```
shrunkRating = (rating × totalRatings + k × platformMeanRating) / (totalRatings + k)
```
with `k≈5` again (tunable). A brand-new artisan (`totalRatings=0`) naturally lands exactly at the platform mean — same practical starting point as today's flat 50 default if the platform mean is ~2.5/5, but now it moves smoothly and proportionally as reviews arrive instead of snapping discontinuously, and a single 5-star review from a colluding account can no longer swing the score anywhere near as hard (it's diluted against `k` prior-weight instead of taken at face value). This is the direct fix for 2.4.

### 2.3 Verification, dispute history — keep the formula, widen the input

Verification: unchanged, already correctly implemented and appropriately weighted.

Dispute history: keep `openDisputeCount` as the dominant term (an *active* dispute should hurt more than a long-closed one), but add a smaller secondary term for lifetime dispute rate (`totalDisputesEverRaised / totalJobs`) so an artisan who accumulates and resolves many disputes over time — even if each is individually closed — still reads as higher-risk than one with a clean history, which the current formula (open-count only) can't distinguish. Suggest re-splitting the existing 10% as `0.07 × openDisputePenalty + 0.03 × lifetimeDisputeRatePenalty`.

### 2.4 Response time → fix Bug A before touching the weight at all

No formula change needed — the bracket thresholds (`<=15min=100`...`>120min=20`) are reasonable. What's needed is real instrumentation, which this doc treats as the actual deliverable here, not a footnote:

- **Definition**: time from a job entering the open-jobs feed (`status: 'requested'`, artisan-visible) to that artisan's first quote submission on it, OR time from a chat opening (`inChat`) to the artisan's first message — whichever the artisan does first for a given job. Use the smaller of the two per job, then maintain a rolling average (e.g., trailing 20 jobs) rather than a single lifetime average, so a currently-slow-to-respond artisan can't coast forever on old fast responses (or the reverse — one early slow month shouldn't be permanent).
- **Where to write it**: a new Cloud Function trigger, same pattern as `_recordJobOutcome` — on `quotes` document creation (`onDocumentCreated('jobs/{jobId}/quotes/{quoteId}')`), compute the delta between the job's `createdAt` and the quote's `createdAt`, update a rolling-average field on the artisan doc in the same transaction pattern already used elsewhere, then recompute `trustScore`. This is a small, self-contained addition to `functions/index.js` that doesn't touch any existing trigger.
- **Backfill**: existing artisans all have the frozen `30.0` — leave it as the honest "no data yet" default for anyone with zero measured responses post-launch of this fix, rather than fabricating history; it'll correct itself within their first few real quotes.

### 2.5 New: Reports (closes the "Reports" brief gap)

Out of scope to fully design here (it's a new product surface, not just a scoring change) — but the score needs a slot reserved for it once it exists, so flagging the decision now rather than retrofitting weights later: propose folding "Reports" in as a modifier on the dispute-history term rather than a fully separate weighted category (a report is, functionally, a lighter-weight precursor to a dispute — same trust-and-safety concern, different formality). Concrete design deferred to `08-messaging-notifications.md` (the natural place a "report from chat" feature — already flagged missing in `01-ux-audit.md` §5 — would be specified) and looped back into this formula once that exists.

### 2.6 Punctuality — explicitly deferred, not forgotten

Requires `07-gps-flow.md`'s appointment/arrival data to exist before it can be measured at all (scheduled-arrival-time vs. actual-arrival-time delta). Reserve a weight slot for it now so the eventual rebalancing is additive rather than another full re-weighting: propose that once Punctuality lands, it takes 10% out of the existing Response Time allocation (both are "artisan promptness" signals, arguably overlapping) rather than diluting every other category — i.e., Response Time 15%→10%, new Punctuality 10%, everything else unchanged. Flagged as a decision for whoever builds `07` to confirm against real data once it exists, not locked in now.

### 2.7 Resulting formula (near-term, buildable immediately — Punctuality/Reports deferred per above)

```
trustScore = 0.24 × shrunkCompletionRate×100 + 0.06 × min(completedJobs,50)/50×100   // was 30% volume-only
           + 0.25 × shrunkRating×100 (Bayesian, replaces flat neutral default)         // was 25% flat-default
           + 0.20 × verificationPoints[verificationStatus]                             // unchanged
           + 0.15 × responseTimePoints(actualRollingResponseTimeMinutes)               // unchanged formula, real input
           + 0.07 × openDisputePenalty + 0.03 × lifetimeDisputeRatePenalty            // was 10% open-only
```
Weights still sum to 100. This is a formula *refinement*, not a rewrite — every existing bracket/threshold is preserved where it was already sound (verification, response-time buckets, dispute penalty shape); only the two genuinely broken inputs (Bugs A/B) and the one gaming vector (2.2) change.

---

## 3. Ranking integration (executing `01.5` Track B)

### 3.1 Sort key
Per the brief's explicit order (Distance → Trust Score → Rating → Experience) and `01.5` B2's direction — distance as a coarse **bucket**, not a continuous tiebreaker-only bonus (today's `matching_service.dart` treats it as a minor +0.10 max adjustment, which is why it currently under-weights distance relative to the brief's stated priority):

```
1. Distance bucket   (e.g. ≤5km / ≤15km / ≤50km / >50km — artisans in a closer bucket always outrank a farther one)
2. trustScore         (the redesigned §2.7 formula, descending)
3. rating              (shrunkRating, descending, as the tiebreaker within equal-ish trust scores)
4. completedJobs      (experience, descending, final tiebreaker)
```

`ArtisanModel.matchScore` (the third, currently-competing formula in `artisan_model.dart:76-81`) is retired as a ranking input per `01.5` B1 — it can remain as a *display* concept only if a genuine product need for it surfaces later (none is apparent today; recommend deleting it outright rather than leaving unused code that could confuse a future maintainer into wiring it back in).

### 3.2 The "Rising Professional" fairness layer stays, reframed
The existing `<10 jobs` rising-artisan slice (2 of 5 results reserved) is a legitimate, deliberate fairness mechanism — new artisans need a path to their first jobs, or the marketplace never grows supply. Keep it, but sort the rising bucket by `trustScore` too (currently sorted by `createdAt` — newest first, which has no relationship to quality at all) rather than pure recency, so "rising" doesn't mean "purely random by signup date" once a rising artisan actually has *some* data.

### 3.3 Firestore implications
- `artisans` composite index `category + approvalStatus + trustScore DESC` already exists (`firestore.indexes.json`, confirmed in `01-ux-audit.md` §0). Confirm it still covers the distance-bucketed query once built — if distance bucketing is implemented as a `where` range on a geohash prefix field (recommended over a raw lat/lng range query, which Firestore can't do natively) rather than post-fetch filtering, a new composite index (`category + approvalStatus + geohashPrefix + trustScore`) will likely be needed. Flagged for `04-firestore-architecture.md` to formalize.
- New artisan fields needed: `totalDisputesEverRaised` (currently only `openDisputeCount` exists), a rolling response-time array or pre-aggregated rolling average field, `geohash`/`geohashPrefix` for bucketed queries (currently only raw `latitude`/`longitude`).
- **Migration**: changing the formula means every existing artisan's stored `trustScore` is stale the moment this ships. Needs a one-time backfill Cloud Function (recompute every artisan doc against the new formula) run once at deploy time — not a live concern for a pre-launch product per `01.5`'s framing, but worth stating explicitly so it isn't missed.

---

## 4. Trust & Safety additions (closes `01-ux-audit.md` 2.6 — review farming)

Bayesian shrinkage (§2.2) blunts the *impact* of a small number of fabricated reviews but doesn't detect the pattern. Recommend a lightweight, admin-facing anomaly surface — not a new automated enforcement action (false positives against genuine repeat-customer relationships, e.g. a landlord repeatedly hiring the same trusted electrician, are a real risk of over-automating this):

- Flag any customer↔artisan pair with ≥3 completed jobs within a short rolling window (e.g. 30 days) for admin review — genuine repeat business is common and fine, but combined with a second signal it's worth a human look.
- Flag review velocity that's statistically high relative to an artisan's job cadence (e.g. 5-star reviews arriving faster than jobs plausibly complete).
- Surface both as a queue in the admin dashboard (ties into `10-admin-redesign.md`'s Trust Score Management section) — a human decides, the system only surfaces.

---

## 5. Tier system & badges (extends `02-design-system.md` §2.2 Gap 4)

Existing 5 tiers (`tierLabel`: 90-100 Excellent, 75-89 Trusted, 60-74 Good, 40-59 Fair, <40 New) are reasonable and don't need to change numerically — but only 2 of 5 have dedicated colors today (`trustElite`, `trustTrusted`). Proposed full mapping, following the existing semantic-pair convention (`color`/`colorSurface`):

| Tier | Score | Color | Surface |
|---|---|---|---|
| Excellent | 90-100 | `trustElite` (existing, amber `#F59E0B`) | `trustEliteSurface` |
| Trusted | 75-89 | `trustTrusted` (existing, green `#22C55E`) | `trustTrustedSurface` |
| Good | 60-74 | **[NEW]** `trustGood` — accent blue `#3B82F6` (reuse existing `accent`, don't invent a new hue) | `accentSurface` |
| Fair | 40-59 | **[NEW]** `trustFair` — neutral `textTertiary #94A3B8` (deliberately unexciting — a "Fair" artisan shouldn't get a badge that reads as an achievement) | `surfaceVariant` |
| New | <40 | **[NEW]** `trustNew` — same neutral treatment as Fair, but labeled distinctly so a customer can tell "genuinely new, no track record yet" apart from "has a track record and it's mediocre" — these mean very different things and shouldn't look identical | `surfaceVariant` |

Reusing existing hues (`accent`, `textTertiary`) rather than adding brand-new colors keeps the palette from sprawling per `02-design-system.md`'s governance rule (§8: extend deliberately, don't fork).

---

## 6. New surface: Trust Score Explainer (closes `01-ux-audit.md` §6's transparency gap)

The brief demands transparency ("trust is established by the platform, not by chance" — `README.md`'s own problem statement) but no customer-facing explanation of *how* the score works exists today — only the artisan-facing breakdown widget (`trust_score_card.dart`). Specified here per the brief's "every screen must include" checklist, since this is the one genuinely new screen this phase introduces:

- **Purpose**: let a customer understand why an artisan ranks where they do, building confidence in the platform's trust claim without exposing exact gameable weights.
- **User goal**: "Why should I trust this artisan?" answered in under 10 seconds of reading.
- **Layout**: a bottom sheet (not a full screen — this is a supporting explainer, not a destination) launched from a "ⓘ" affordance next to any Trust Score badge (artisan card, artisan profile, quote list). Shows the tier badge large, then 3-4 plain-language factor rows (not the exact percentages — "Strong completion history," "Fast to respond," "ID verified," "No unresolved disputes") each with a simple filled/partial/empty indicator rather than a raw number, so the underlying weights stay non-obvious to would-be gamers while still being genuinely informative.
- **Components**: `AppBadge` (tier), a new lightweight `TrustFactorRow` component (icon + label + qualitative indicator — reuses `AppShadows`/`AppRadius` tokens, no new visual system needed), a "Learn more" link to a static help-center explainer for anyone who wants full methodology.
- **Interactions**: tap "ⓘ" → sheet slides up (`AppAnimations.normal`, `easeOutCubic`, consistent with §4 of `02-design-system.md`); swipe-down or scrim tap to dismiss.
- **Navigation**: modal, no route change — doesn't add a GoRouter entry.
- **Loading state**: none needed — the artisan doc is already loaded wherever this is triggered from; this reads from data already in memory, no new fetch.
- **Empty state**: a brand-new ("New" tier) artisan shows a distinct message ("New to HandyTrust — building their track record") rather than empty/zero-value factor rows, which would read as a red flag rather than neutrally new.
- **Error state**: N/A (no network call) — if the artisan doc is somehow null, don't show the sheet at all rather than showing a broken one.
- **Success state**: N/A (informational, not transactional).
- **Accessibility**: qualitative indicators must not rely on color alone (per WCAG) — pair every filled/partial/empty state with an icon or text label, not just a colored dot, consistent with the `02-design-system.md` §2.3 finding that color-only signaling is already a latent risk in this app (status chips currently lean on color; this new component shouldn't repeat that pattern).
- **Animations**: standard modal slide-up per the motion system; no bespoke animation needed.
- **Firestore implications**: read-only, no new writes, no new collection — purely a presentation layer over existing `artisans/{uid}` fields.
- **Security considerations**: must not expose the literal formula/weights (gaming risk) — qualitative bucketing (filled/partial/empty per factor) is the actual security control here, not an afterthought; do not build a "view exact breakdown" mode for customers even though `trust_score_service.dart`'s exact-number breakdown already exists for artisans (artisans seeing their own precise breakdown is fine and useful for self-improvement; customers seeing exact competitor-comparable numbers is a gaming vector).

---

## 7. Rollout sequencing (concrete addition to `01.5` Track B's B1-B4)

1. Ship Bug A fix (real response-time instrumentation) and Bug B fix (wire cancellation data in) — these are corrections to already-agreed-on formula components, lowest risk, ship first.
2. Ship §2.1/2.2 Bayesian shrinkage for completion rate and rating — run the backfill migration (§3.3) in the same deploy so no artisan sees a score computed by a mismatched partial formula.
3. Ship §3.1 ranking rewrite (`MatchingService`) — sequenced after 1-2 land and are verified stable, since ranking quality depends on the score being trustworthy first.
4. Ship the Trust Score Explainer (§6) once ranking is live — no point explaining a score that isn't yet driving anything a customer would notice.
5. §4 (Trust & Safety anomaly queue) and §2.5/2.6 (Reports, Punctuality) remain explicitly deferred to `08-messaging-notifications.md` and `07-gps-flow.md` respectively, per their stated dependencies.

---

**Next**: `06-escrow-wallet.md` (sequenced after Hardening Sprint Track A per the roadmap) or `07-gps-flow.md`/`08-messaging-notifications.md` (independent, no blocking dependency) — let me know which to take next.
