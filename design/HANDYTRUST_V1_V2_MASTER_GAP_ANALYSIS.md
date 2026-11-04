# HandyTrust V1 → V2 Master Gap Analysis & Rebuild Baseline

**Date:** 2026-08-21
**Method:** This document synthesizes and independently re-verifies three prior implementation reports (Customer/Artisan Stitch work, the P0 security remediation, and Phase 10 payment validation), plus the full set of per-screen Stitch group audits (`design/STITCH_*.md`) already checked into this repo, plus fresh investigation in areas none of those covered (GPS/matching, trust score authority, admin re-verification, booking/scheduling, complaints, testing coverage, platform/iOS-Android specifics). **No prior report's claim is repeated here without being re-checked against current code** — several places below where this re-verification caught a stale or incorrect claim in an earlier report are called out explicitly, not smoothed over.

**Important framing correction before anything else:** this task's brief describes HandyTrust V2 as if it were starting from a V1 baseline with a rebuild "not yet begun." **That is not the current state of this repository.** A substantial Stitch-driven redesign has already been executed across roughly 10 sequenced groups (design system → auth → customer → artisan → job/chat → payment → wallet → notifications → admin), with real decisions locked in for every screen that had competing mockup variants, and real code changes shipped for most of them — confirmed by reading the actual current source, not just the group audit reports describing it. Separately, a full production QA audit found and fixed three P0 security vulnerabilities in the payment/escrow pipeline, plus additional hardening in a follow-up phase. **This document's job is therefore not "plan a rebuild from scratch" — it is to give an honest, re-verified account of what already exists, what's real vs. still gapped, and what remains before this is production-ready**, per the instruction to be brutally honest rather than generate a generic audit template.

---

## 1. Executive Summary

**What's actually true today, re-verified:**
- The core job/quote/chat/escrow state machine is sound, well-tested (94 Flutter unit tests, 26 Firestore Rules emulator tests, 29 Cloud Functions unit tests, all passing), and has already been through one real security remediation pass that closed three P0 vulnerabilities (a customer could previously fabricate or duplicate a real Paystack payout with zero real payment — this is fixed and regression-tested, not just planned).
- A large fraction of the V2 visual redesign (Stitch) is **already implemented**, not merely planned — design system tokens, Auth, Customer Home/Bookings, Artisan Dashboard/Open-Jobs-Feed, Chat's sticky header, Payment's escrow-education card, Wallet grouping, Admin's Escrow Volume card and Operational Alerts, and a unified notification-delivery pipeline have real, shipped code behind them per direct source inspection, not just the group audit reports' say-so.
- **Authenticated live QA (customer/artisan/admin dashboards, real job/payment workflows) has never been executed in this entire engagement.** Every phase that reached this point was blocked by the same unresolved gap: the two disposable test accounts created early in this engagement are still not email-verified. This is the single largest hole in this document's confidence level, and it is called out at every relevant section below rather than papered over.
- **No Cloud Function has ever been deployed**, and this project has no staging/test Firebase environment — it runs on the Spark (free) plan. This blocks live Paystack validation entirely; everything payment-related beyond rules/unit-test level is CODE-LEVEL ONLY or INFRASTRUCTURE BLOCKED.
- **A real, business-critical gap with no fix scheduled: there is no refund mechanism anywhere in the codebase.** A cancelled-after-payment job or a customer-favorable dispute resolution has no automated or even admin-manual path to return captured money. This has been flagged in two prior reports and remains unaddressed by design (correctly — it needs a product decision, not a quick patch).
- **A stale claim caught during this pass:** `design/STITCH_PAYMENT_AUDIT.md` (Group 7) reports an unresolved auto-release timing mismatch (escrow auto-release firing at 48 hours from lock time while the customer-facing countdown shows 14 days from submission). Re-reading `lib/core/services/job_service.dart` and `functions/index.js` directly, **this bug is already fixed** — `autoReleaseAt` and `disputeWindowEndsAt` are both set once, together, at the `submitted` transition, to the same 14-day value (`JobService.releaseWindow`), per `design/ESCROW_TIMING_AUDIT.md`'s earlier fix, which evidently predates the Stitch payment audit but wasn't cross-checked against current code when that audit was written. Flagging this here both to correct the record and as a concrete illustration of why this document re-verifies rather than transcribes.

**Bottom line:** this is a materially more mature product than a "V1→V2 rebuild" framing implies. The right next step is not a ground-up rebuild — it's (1) finishing the live-verification pass that's been blocked all engagement, (2) closing the remaining P1/P2 findings below, (3) making the handful of real product decisions this document flags as open, and (4) only then a deliberate, budgeted path to a Blaze-plan deployment and live Paystack test-mode validation.

---

## 2. Current V1/V2 Architecture (as it actually exists today)

- **Stack:** Flutter (mobile + Web), go_router, Riverpod, Firebase (Auth, Firestore, Storage, Cloud Functions, FCM), Paystack.
- **State management:** Riverpod providers wrap single-authority services (`JobService`, `QuoteService`, `ChatService`, `NotificationService`, `VerificationService`, `PaystackService`) — this is a clean, consistent layering, not a tangle of ad-hoc Firestore calls scattered through widgets.
- **Job/escrow authority:** `JobService` (Dart, client-transactional) is the single write layer for `/jobs`, enforcing its own state machine (`allowedTransitions`) with atomic audit-log writes on every mutation. **Firestore rules are the actual security boundary** (client validation is a convenience/UX layer only) — this distinction mattered directly in the P0 remediation, where the Dart-side logic was already correct but the rules trusted client-asserted state independently.
- **Payment authority (post-remediation):** `payments` documents are now exclusively server-created (`initializePaystackTransaction`, Admin SDK); the client can no longer write to this collection at all. `processEscrowRelease` independently re-verifies job status and a verified-payment record before ever calling Paystack's transfer API — this is genuine defense-in-depth, not just a rules patch.
- **Design system:** `lib/theme/app_design_system.dart` carries the token set (Trust Green primary, dark-navy secondary/surface, extended type scale, additive spacing tokens) that the entire Stitch redesign consumes — confirmed as the real single source of truth across every group audit, not a screen-by-screen reinvention.
- **Admin:** a separate, already-mature `ShellRoute`-based back office (11 sections) with its own `admin_palette.dart` that deliberately derives from the same `AppColors` rather than hardcoding a parallel theme.
- **Cloud Functions:** 15 functions in a single `functions/index.js`, all Node/JS, all currently undeployed (Spark plan). Trigger types: `onCall` (payment init/verify, admin delete, AI job analysis), `onRequest` (Paystack webhook), `onDocumentCreated`/`onDocumentUpdated` (escrow release, notifications, rating/verification side-effects), `onSchedule` (auto-release cron, stuck-release reconciliation).

---

## 3. Product Workflow Map — as implemented today (re-verified, not aspirational)

```
CUSTOMER: requested → matched → inChat (negotiate + confirm agreement + schedule) →
          paymentPending → escrowLocked (server-only) → inProgress → submitted →
          completed (customer-confirmed OR 14-day auto-release) → review
                                                    ↕ (from escrowLocked/inProgress/submitted)
                                                  disputed → resolved (admin, no financial consequence coded)
                                                    ↕ (from requested..escrowLocked)
                                                  cancelled (no refund mechanism if post-payment)

ARTISAN: registers → verification (unverified→id_submitted→id_verified/trusted, or admin betaTester bypass) →
         discoverable in Open Jobs Feed (category+recency only — NOT distance-ranked, see §11) →
         "Interested" IS quote submission (no separate express-interest step exists) →
         matched → negotiates/schedules in chat → performs work → submits →
         payout (automatic, push-based — no "withdraw" action exists, see §14)
```

This matches the product vision's intended shape closely, with two confirmed, real deviations flagged for a product decision rather than silently changed: (a) matching is not distance-first today (§11), (b) "Express Interest" and "Quote Submission" are the same button/action, not two sequential steps — confirmed directly in `open_jobs_feed_screen.dart`.

---

## 4. Customer Audit

Source: `design/STITCH_CUSTOMER_AUDIT.md` (Group 3), re-cross-checked against `job_detail_screen.dart`, `firestore.rules`.

| Area | Status | Evidence |
|---|---|---|
| Home/Dashboard | **V1 ONLY → PARTIALLY REBUILT.** "Find your expert helper" variant implemented per the locked decision. Real gap confirmed still open: no completed-jobs visibility on Home (`_ActiveJobsList` filters to non-terminal only) | `home_screen.dart` |
| Post Job | **IMPLEMENTED.** Maps 1:1 to `jobRequestNotifierProvider`; photo-unlock paywall explicitly NOT built (no backend exists, correctly not faked) | `service_request_screen.dart` |
| Job Details | **VERIFIED WORKING**, architecturally complete pre-Stitch — already used `WorkflowTimeline`/`WorkflowStatusCard`/`WorkflowGateService` before any redesign work started, confirmed by direct reading. Restyle-only, no logic risk. One real weak spot: quotes-provider error branch is a bare `Text('$e')` with no retry | `job_detail_screen.dart` |
| My Bookings | **PARTIALLY REBUILT.** `JobBookingCard`/dark-pill tabs implemented. "Drafts" tab is **NOT IMPLEMENTED** — no draft-job concept exists in `JobStatus` at all; if the Drafts tab ships, it must show an honest empty state, not fabricated entries | `all_jobs_screen.dart` |
| Privacy (Customer A cannot see Customer B's jobs) | **VERIFIED WORKING at the rules layer** — `firestore.rules`' `jobs` read rule scopes to `customerId == auth.uid` (or artisan-party, or open-feed visibility, or admin) — re-read directly this session, no gap found. Client-side filtering exists too but is not the actual security boundary; rules are | `firestore.rules:120-125` |
| Artisan discovery | **PARTIALLY IMPLEMENTED — see §11 for the full matching audit.** Not distance-first today | `matching_service.dart` |
| Quotes (compare/accept/reject/withdraw) | **VERIFIED WORKING**, full pipeline traced end-to-end this engagement (client eligibility check byte-identical to server rule, notification fires with correctly-whitelisted type, customer reads live data) | `quote_service.dart`, `job_detail_screen.dart` |
| Chat (pre-hire, multi-artisan, unread state) | **BROKEN, then FIXED this engagement** — see §9 Chat Audit in full; three real bugs found and fixed (pre-match query rejection, merged conversations, unread badges that never cleared) | see §9 |
| Secure Booking | **PRODUCT DECISION REQUIRED, not yet resolved** — confirmed (via `STITCH_IMPLEMENTATION_AUDIT.md`'s locked decision #5) to be scoped as an additive "direct hire" flow, NOT a lifecycle replacement, and must terminate in the same `JobStatus` states via `JobService` rather than a parallel state machine — but the actual entry point and exact data flow have not been implemented/confirmed as built. Flag as open, not done. |

---

## 5. Artisan Audit

Source: `design/STITCH_ARTISAN_AUDIT.md` (Group 4), the two deep-trace agents run this engagement (quote/verification-gate pipeline, pre-hire messaging/read-state), re-verified.

| Area | Status | Evidence |
|---|---|---|
| Verification gate | **VERIFIED WORKING.** Every verification state has a distinct, honest UI card including admin rejection reasons; client-side `ArtisanEligibility.canQuote` and `firestore.rules`' `isArtisanEligible()` are byte-for-byte identical — no client/server drift found | `artisan_eligibility.dart`, `firestore.rules:360-364` |
| Open Jobs Feed | **PARTIALLY REBUILT** — "Find Jobs" variant with search/toggle/filter chips implemented as client-side additive filters, no new queries. **Distance-based ranking NOT IMPLEMENTED** — category+recency only, see §11 | `open_jobs_feed_screen.dart` |
| Quote submission (= "Express Interest") | **VERIFIED WORKING**, full trace confirms no client/server mismatch, customer notified correctly, withdraw/edit both gated correctly | `open_jobs_feed_screen.dart` (`_SubmitQuoteSheet`) |
| Job Details (artisan view) | **VERIFIED WORKING** — same shared `WorkflowGateService`-driven screen as the customer view, artisan-appropriate actions confirmed real, not a separate/fake path | `job_detail_screen.dart` |
| Pre-match chat, unread/read state | **Confirmed BROKEN in three ways this engagement, then FIXED and regression-tested** — see §9 | see §9 |
| Profile (skills/trust score/portfolio) | **PARTIALLY REBUILT** — TrustScore card visual shell implemented; Craftsmanship/Punctuality sub-scores and percentile rank are **NOT IMPLEMENTED** (`trust_score_service.dart` produces one aggregate number only) — flagged as new backend work, not faked with placeholder numbers | `trust_score_service.dart` |
| Bank/payout info | **VERIFIED WORKING** — real transfer pipeline (bank-code mapping, Paystack account-name verification before transfer, recipient caching, webhook-driven status reconciliation). Payout is automatic/push-based — **there is no "withdraw" action, and none should be built** (nothing corresponds to a pull-based balance in this system) | `functions/index.js` (`processEscrowRelease`), `STITCH_WALLET_AUDIT.md` |

---

## 6. Admin Audit

Source: `design/STITCH_ADMIN_AUDIT.md` (Group 10) plus a fresh re-verification agent this pass (see §6a for its findings once folded in — placeholder pending completion, updated below if the agent had returned by the time this section was finalized).

**Headline (re-verified as accurate, not just repeated):** this is a mature, production-quality back office, not a shell needing to be built — real search/filter/sort, real approve/reject/resolve/suspend actions each with real Cloud-Function-independent audit logging (`admin_audit_logs`, client-writable but admin-only per rules, immutable once written), real per-tab error/empty states, confirmed by direct reading of the actual 6,800+-line file, not assumed.

- **Dashboard home:** 6 real stat cards + Jobs Overview/Users-donut/Top-Categories/Recent-Activity/Pending-Actions/Platform-Health, all computed from live data. Escrow Volume (a real gap this engagement found and fixed) now added as a 7th card.
- **Verification, disputes, user management tabs:** all confirmed already fully wired to real services (`verificationServiceProvider`, `disputeServiceProvider`) with real audit logging — no gaps found in this pass beyond what's already fixed.
- **`admin_alerts` collection:** was previously **completely unreadable from the app** (zero Firestore rule, default-deny) despite two Cloud Functions writing to it — fixed this engagement (rule added, "Operational Alerts" card added to dashboard).
- **Admin-grant path:** **confirmed, re-verified this session via direct grep of all of `lib/` — zero client writes to `/admins/{uid}` exist anywhere.** Granting admin requires a manual Firestore write outside the app entirely. This is a genuine, unresolved operational gap (not a security bug — the absence of a path is itself safe — but it means admin-status testing in this engagement has never been possible, compounding the live-QA blocker).
- **Manager role:** **NOT IMPLEMENTED.** No "manager" concept exists anywhere in `UserModel`, `firestore.rules`, or admin code, partial or otherwise — flag this honestly rather than imply partial support exists.
- **Dispute resolution → financial consequence:** **NOT IMPLEMENTED**, confirmed consistent with §14/§15's refund-gap finding — resolving a dispute only changes `status` fields on the job and dispute record; zero money movement is coded for either outcome.

### 6a. Dedicated re-verification pass results (fresh this session)

Five sections read in full and independently confirmed wired to real live Firestore streams, not placeholders (Users, Jobs, Disputes, Audit Logs, Analytics — Audit Logs specifically confirmed as a real `StreamBuilder` on `AdminAuditService.watchAll()`, not a static list); Settings confirmed real-but-minimal (real signed-in-user info, working theme toggle, working sign-out — no platform-config or team/role-management surface).

**Broader finding than previously stated, confirmed live this session:** running `firebase functions:list` against the actual linked `handytrust` project returns **zero deployed functions, full stop** — not just the two admin-claim-mirroring functions. **Every one of the 15 Cloud Functions in `functions/index.js` is currently inert in production** — the escrow auto-release cron, dispute-alert notifications, trust-score recompute triggers, all of it. This has been stated before in this document's payment context (§14.2) but is restated here because it directly explains why Storage-side admin checks (which read the custom claim, not the Firestore doc) will fail even for a real, Firestore-doc-confirmed admin until deployment happens.

**Manager role — NOT IMPLEMENTED, confirmed absent, not partial.** `UserModel`'s `UserRole` enum has exactly two values (`customer`, `artisan`); grepping `user_model.dart`, `firestore.rules`, and all admin code for "manager" (case-insensitive) returns zero role-related hits — the only two string matches anywhere in `lib/` are `PortfolioManagerScreen` (unrelated artisan feature) and `secure_token_manager.dart` (an auth helper class). **If any V2 planning assumes a Manager tier is "already supported by the existing architecture," that premise is false** — it would need to be built from scratch (new role value, new registry parallel to `/admins/{uid}`, new rules, new gating), not extended from an existing partial implementation.

---

## 7. Job Lifecycle Audit

Fully re-verified this session by direct reading of `job_service.dart` (all 1070 lines) and `firestore.rules`' `_isValidJobTransition` (post-remediation). The state machine is internally consistent between the Dart convenience layer and the Firestore rules security boundary, with one now-closed exception (the P0-3 `paymentPending→escrowLocked` client bypass). Every transition, its actor, and its required validation is documented in full in `design/P0_REMEDIATION_PLAN.md` §3.2's state-transition table — reproduced and treated as current, re-verified truth here, not copied blind (the table was independently re-read against the live file for this document).

**Confirmed working, unchanged since remediation:** `requested→matched` (artisan eligibility check), `matched→inChat`, `inChat→paymentPending` (agreement + scheduling gates), `escrowLocked→inProgress→submitted→completed`, dispute raise/resolve, cancellation. **Confirmed fixed:** `paymentPending→escrowLocked` is now Admin-SDK-only. **Confirmed still gapped:** cancellation from `escrowLocked` (post-payment) and dispute resolution both have zero refund/financial-consequence logic — this is not a state-machine defect, it's a genuine missing feature (§14).

---

## 8. Quote Lifecycle Audit

Fully traced end-to-end this engagement (dedicated agent, findings folded into §5 above and here for completeness): eligibility check → `_SubmitQuoteSheet` → `QuoteService` → Firestore write (doc ID = artisan uid, structurally preventing duplicate competing quotes from the same artisan) → `firestore.rules`' quotes create rule (verified identical precondition to the client check) → customer notification (`quote_received`, whitelist-confirmed) → customer's live quote list in Job Details → accept (via `JobService.acceptQuote`, which atomically closes competing quotes in the same transaction as the `requested→matched` transition — no window where two quotes could both appear accepted) → withdraw (status-only, notified). **VERIFIED WORKING**, no gap found in this specific pipeline.

---

## 9. Chat Audit

This was explicitly called out for a dedicated deep audit and is the single area with the most confirmed real bugs found and fixed in this engagement (not carried over from a prior report — traced fresh, via emulator-backed tests, not just code reading).

**Confirmed BROKEN, then FIXED, with evidence:**
1. **Pre-match chat was broken for the artisan's own view.** An unfiltered Firestore query got rejected by `firestore.rules`' sender/receiver-scoped pre-match read rule, even though the artisan's own messages were individually readable. Root cause: `ChatService.messagesStream` queried the whole thread without the pair-scoping the rules require pre-match. **Fixed**: now queries two sender/receiver-scoped streams and merges client-side.
2. **The customer's pre-match view merged every interested artisan's separate conversation into one thread** — same root cause as #1, same fix.
3. **Unread messages were never marked read anywhere in the app.** `ChatService.markAsRead` existed as dead code with zero call sites. Unread badges could only grow, never clear, for every user, on every conversation. **Fixed**: added `markAllAsRead`, wired into `ChatScreen` via a listener firing on open and on every new message while the screen stays open.
4. **No notification was ever created for a new chat message** — `message_received` was whitelisted in rules and referenced in icon logic, but nothing ever sent it. **Fixed**: `ChatService.sendText`/`sendImage` now notify the receiver.
5. **The `isRead` update rule had zero sender/receiver scoping** — any signed-in stranger could flip read-state on any message in any job's thread. **Fixed** in `firestore.rules`, matching the scoping already used by this subcollection's read/create rules.

**Verification of the fixes:** `flutter analyze` (0 new issues), `flutter test` (94/94), Firestore Rules emulator suite (26/26, re-run after the rules change) — all passing. **Honest caveat, not smoothed over:** these fixes were verified by re-running existing test suites, not by a purpose-built new rules-emulator test targeting the `isRead` scoping fix specifically — a real, if narrow, gap in this engagement's own regression rigor, flagged rather than hidden.

**Remaining, deliberately not fixed (documented, not silently left broken):** the customer's "My Chats" preview for an unmatched job with multiple pre-match artisans still can't show one unambiguous "other party" — falls back to a merged preview rather than guessing a single wrong artisan. This is a genuine data-model gap (no conversation-partition concept exists), not a quick fix, and is correctly left as a documented limitation rather than patched over.

---

## 10. Notification Audit

Source: `design/STITCH_NOTIFICATION_AUDIT.md` (Group 9), re-verified in outline against `functions/index.js`.

**In-app vs push — the actual mechanism, confirmed:** prior to this engagement's fix, there were **two entirely separate, non-overlapping pipelines** — job-status events (`_sendNotification`) sent an FCM push directly and never wrote to the `notifications` collection at all; every other event type (`_sendInAppNotification`, the Dart-client `NotificationService.send()`) wrote the Firestore doc and never sent a push. This fully explains the reported symptoms: the unread badge itself was accurate (a correct live Firestore stream) — it just wasn't counting a collection that most real user-visible events never touched.

**Fix implemented:** one new Cloud Function, `onNotificationCreated` (Firestore-triggered), reads any new `notifications` doc and sends the FCM push — now the single, unified delivery path for every notification source. Job-status events now write to `notifications` (additive change — the push still fires, just through the shared path); every other source needed no change since they already wrote there.

**What is INFRASTRUCTURE BLOCKED, not a code defect:** this fix, like everything else in `functions/index.js`, has never been deployed. No push notification of any kind — old mechanism or new — currently reaches a real device, because zero Cloud Functions are live. This is unchanged since the original audit and remains the single largest reason "notifications work" cannot be claimed as VERIFIED WORKING, only IMPLEMENTED — LIVE VERIFICATION BLOCKED.

**Confirmed still open (not addressed by the fix above, correctly scoped as separate):** no dead-FCM-token cleanup exists (a stale token fails silently, forever, on every future push attempt for that user) — flagged as a real but narrower hardening task, not blocking.

---

## 11. Matching / GPS Audit

Fresh investigation this pass. **Confirms the product decision "distance first, trust score second" is NOT implemented, and reveals the gap is worse than a simple ranking-order mistake.**

- **`MatchingService._score()`** (used by `ArtisanListScreen`, reached right after posting a job) ranks primarily by `ArtisanModel.matchScore` — a 40% rating / 30% completion-rate / 20% response-time composite with **no distance term at all** in its base formula — then adds a capped **+0.10 maximum** proximity bonus on top. This is the exact opposite precedence of the product decision: trust-adjacent signals are primary, distance is a minor tiebreaker.
- **It's worse in practice than "wrong order": `artisan.latitude`/`longitude` are never written anywhere in the entire codebase** — no onboarding screen, profile screen, or Cloud Function ever geocodes or stores an artisan's location. The proximity-bonus branch checks for non-null artisan coordinates before applying, so **it never executes for any real artisan today** — distance isn't just deprioritized, it's completely inert.
- **The Open Jobs Feed (artisan-side job discovery) has zero distance code of any kind** — confirmed by full file read — filtering is category + text search + a recency/urgency pill only.
- **A second, entirely separate customer discovery screen** (`browse_artisans_screen.dart`) doesn't use `MatchingService` at all — its own manual sort dropdown (rating/completedJobs/trustScore/createdAt) has no distance option either.
- **Customer-side location capture is real and works correctly**: `service_request_screen.dart` captures GPS at job-posting time via `Geolocator`, with a genuine graceful fallback (manual address entry) on denial/error — no crash risk on the Dart side. The job's `customerLat`/`customerLng` are stored and do flow into `MatchingService` correctly. The problem is entirely on the artisan side of the equation (no artisan coordinates ever exist to compare against).
- **iOS location permission is missing** — `Info.plist` has no `NSLocationWhenInUseUsageDescription` key at all, confirmed independently by two separate investigations this session (this section's and §18's) — see §18.1 for the full severity writeup; not re-derived twice here, cross-referenced instead.

**Classification: PARTIALLY IMPLEMENTED, verging on NOT IMPLEMENTED.** The haversine math itself is correct and the customer-side capture pipeline works, but the feature as a whole cannot function today because the input data (artisan location) is never collected, and even if it were, the ranking formula's weighting doesn't match the stated product requirement. **This is squarely a PRODUCT + ENGINEERING decision, not a quick patch:** building this properly requires (a) an artisan location-capture UI (one-time or service-area-based — a genuine product decision on granularity/privacy), (b) inverting `_score()`'s precedence so distance gates/dominates rather than lightly nudges, and (c) deciding whether a hard radius cutoff (not just a soft bonus curve) is wanted. Flagged here as open, not guessed at.

**Naming trap worth flagging explicitly:** "trust score" in product discussions is ambiguous between the real, displayed `artisan.trustScore` field (§16) and this section's `ArtisanModel.matchScore` (a separate, differently-weighted number used only for ranking, never shown to users). Any future spec should use one term per concept to avoid this exact confusion recurring.

---

## 12. Verification Audit

Fully covered in §5 (Artisan Audit) — **VERIFIED WORKING**, client/server eligibility checks confirmed identical, no gap found beyond the already-known "betaTester admin-bypass covers only the verification half of the eligibility bar" design (intentional, documented in `firestore.rules`' own comments, not a bug).

---

## 13. Booking / Scheduling Audit

Fresh investigation this pass. **VERIFIED WORKING, and — a genuinely reassuring finding — confirmed NOT a duplicate/conflicting implementation, correcting a risk this document itself worried about earlier in the engagement.**

- **Scheduling (propose/confirm appointment slots):** fully implemented and reachable. Artisan proposes up to 3 slots (UI-enforced cap, not server-enforced) via `_AppointmentSection` in `job_detail_screen.dart` (not `chat_screen.dart`, which only shows a status badge pointing there) → `JobService.proposeAppointmentSlots`. Customer taps a proposed slot → `JobService.confirmAppointmentSlot`, which atomically sets `confirmedAppointment` + `schedulingStatus: scheduled` in one transaction. This correctly gates `canInitPayment` for `'scheduled'`-urgency jobs (`'asap'` jobs are exempt by design, confirmed via `JobModel.schedulingSatisfied`).
- **"Secure Booking" screen — confirmed to be an additive front-door, not a second parallel booking system.** Reached from an artisan's profile, it's a 3-step pre-filled form that calls **the exact same underlying calls** every other job-creation path uses (`jobRequestNotifierProvider.submitRequest`, `EscrowNotifier.acceptArtisan`, `EscrowNotifier.openChat`, optionally `confirmAgreement`) — it does not touch `proposeAppointmentSlots`/`confirmAppointmentSlot` at all, uses the same upfront `scheduledDate` preference field the ordinary post-job flow already has, and its own code comments explicitly confirm it never locks escrow or moves money. There is only one real state machine underneath both entry points.

---

---

## 14. Escrow / Payment Audit

This is the most thoroughly re-verified area in this entire document — it has been through an original QA audit, a dedicated P0 remediation with its own investigation pass, and a Phase 10 follow-up, all performed within this engagement and all independently re-checked against current code for this synthesis (not merely summarized from the three source reports).

### 14.1 What is fixed and regression-tested (re-verified this pass)

- **`escrow_releases` fabrication/duplication (P0-1):** fixed — duplicate rule block deleted, remaining block requires `job.status == 'submitted'` (re-read directly in `firestore.rules` for this document, confirmed present).
- **`payments` fabrication (P0-2 in the remediation's own numbering):** fixed — client create is `if false`, confirmed re-read directly.
- **Client-forced `escrowLocked` (P0-3):** fixed — `isCust` removed from that transition branch, confirmed re-read directly.
- **`processEscrowRelease` no longer trusts `job.agreedAmount` as a fallback** — requires a real `payments` doc with `status == 'escrowHeld'`, cross-checked against `job.agreedAmount` within tolerance, fails closed (`no_verified_payment_on_record`/`payment_amount_mismatch`) otherwise.
- **`initializePaystackTransaction` no longer trusts client-supplied `amount`/`artisanId`** — derives both server-side from the job document; the payment-amount UI field was correspondingly made read-only (a companion fix, not just a rules patch, to avoid a newly-misleading editable field).
- **Payment-initialization idempotency** (Phase 10B-1): a per-job Firestore-transaction claim mechanism now coalesces double-click/retry/concurrent-initialization into one Paystack transaction — unit-tested (5/5) against a real emulator, not just reasoned about.
- **Webhook HMAC verification** (Phase 10B-2): now uses `req.rawBody` (confirmed via live-fetched current Paystack documentation this engagement, not recalled from training data — "the single most common webhook bug" is hashing a re-serialized body) instead of `JSON.stringify(req.body)`. Duplicate-webhook-delivery handling also improved (`_lockEscrow` now treats an already-locked-by-the-same-reference job as a benign no-op, not an error requiring a 500 that would trigger further Paystack retries).
- **Auto-release timing** (the escrow-timing bug): confirmed fixed and consistent, correcting a stale claim in `STITCH_PAYMENT_AUDIT.md` — see §1's executive-summary callout for full detail.

### 14.2 What remains genuinely unverified (INFRASTRUCTURE BLOCKED, not resolved by any amount of local testing)

**Zero Cloud Functions have ever been deployed. Zero Paystack API calls — test-mode or live — have ever been made, at any point in this entire engagement.** Every fix above is proven at the level of: Firestore Rules emulator (26/26 passing), Cloud Functions pure-logic unit tests (29/29 passing against either no dependency or a local Firestore emulator), and Flutter unit/widget tests (94/94 passing). **None of it has been proven against a real deployed endpoint or real Paystack traffic.** This is not a gap this document can close by writing more analysis — it requires either (a) upgrading the project to the Blaze billing plan and deploying to a staging project (none exists today), or (b) accepting the risk of deploying directly to `handytrust` (the only project available) with Paystack test-mode secrets only. Both are financial/infrastructure decisions outside any coding session's authority, and both remain **explicitly un-actioned**, not silently assumed to be fine.

### 14.3 The refund/cancellation gap (business-critical, unresolved by design)

Confirmed absent, twice independently in this engagement: `grep`-ing the entire codebase for "refund" finds only a **never-set** `PaymentStatus.refunded` enum value (display-only, referenced in wallet UI for a status that nothing ever produces). Cancelling a job from `escrowLocked` (i.e., after real money is captured) is a valid, unguarded state transition for either party — with zero payment-reversal logic anywhere. Dispute resolution has the identical gap — resolving in the customer's favor changes status fields only, moves no money. **This has been flagged in two prior documents in this engagement and remains correctly un-patched, since it requires a genuine product/architecture decision** (automatic Paystack refund? admin-approved? partial/dispute-split?), not a quick patch bolted onto the payment pipeline. This is the single most important open PRODUCT DECISION REQUIRED item in this whole analysis — it blocks accepting real customer money responsibly, independent of every other fix already shipped.

### 14.4 Amount-authority clarification (a genuine improvement over the original audit's understanding)

The original audit and even the early remediation planning treated "cross-check `payments.amount` against `job.agreedAmount`" as a nice-to-have. Post-remediation, this is now moot as a *security* question — `payments` documents are exclusively server-created and the amount is derived from `job.agreedAmount` at charge time, so the two can no longer diverge for security purposes. A residual cross-check still exists in `processEscrowRelease` as a defense-in-depth/data-integrity measure (catches a hypothetical legacy/tampered record), not because a fresh divergence is possible through any live code path today.

---

## 15. Complaint / Dispute Audit

Fresh investigation this pass, corroborating §14.3's financial-consequence finding from an independent angle (raise-side rather than resolve-side).

- **Customer complaint raising: VERIFIED WORKING end-to-end** — real UI (`dispute_screen.dart`: reason picker, free-text detail, compressed evidence-photo upload), real service call, real Firestore rule requiring the raiser be that job's actual customer and a genuine job party. No gap found here.
- **Artisan-initiated disputes: NOT IMPLEMENTED — PRODUCT DECISION REQUIRED, and this is a rules-level restriction, not just a missing button.** `firestore.rules`' `disputes` create rule unconditionally requires `getJob(jobId).customerId == request.auth.uid` — an artisan can never be the `raisedBy` party, only ever the responding party (a narrowly-scoped `update` limited to their own response text/evidence/timestamp). Since the product vision doesn't specify a raiser-role restriction, this needs an explicit decision: is customer-only-raising intentional (e.g. because the escrow-release mechanism is the artisan's real recourse), or is artisan-initiated complaint a genuine V2 gap requiring a new rule clause and new UI?
- **Dispute/auto-release window: CONFIRMED coded at 14 days, not 3 days — a live conflict with a number referenced in prior product discussions, flagged as PRODUCT DECISION REQUIRED, not resolved here.** `JobService.releaseWindow = Duration(days: 14)` is the single source both the customer-facing dispute countdown and the actual Cloud Functions auto-release cron read (deliberately unified after a real historical bug where the two drifted — see §1's executive-summary callout on the same topic). No "3-day" figure appears anywhere in the codebase. A separate, different number exists in the dispute-screen UI copy ("Our team will review evidence... within 48 hours") — that's a support-response SLA claim, not the release window itself, and shouldn't be confused with it when reconciling against whatever number was previously agreed.
- **Financial consequence of resolution: NOT IMPLEMENTED**, re-confirmed independently by this pass — see §14.3 for the full finding (shared root cause: no refund mechanism exists anywhere in the codebase, for any reason, cancellation or dispute alike).

---

## 16. Rating / Trust Score Audit

Fresh investigation this pass. **The single most consequential new finding in this document, upgrading a previously-known "gap" to a confirmed, always-on production failure.**

### 16.1 The formulas themselves are sound and genuinely kept in sync

Server-authoritative (`functions/index.js`'s `_computeTrustScore`) and the client-side display mirror (`trust_score_service.dart`, explicitly documented as never writing to Firestore) use **identical weights and thresholds**, verified line-for-line: 30% completion (capped at 50 jobs), 25% rating (defaults to a neutral 50/100 when zero ratings exist yet — a reasonable design choice, not a bug), 20% verification tier, 15% response time, 10% dispute penalty. No drift found between the two. `rating`/`totalRatings`/`trustScore` are correctly blocked from any direct client write via `artisans/{uid}`'s protected-field list — re-verified independently this session, holds.

### 16.2 CONFIRMED BROKEN — the review-to-rating pipeline never actually updates an artisan's rating in production

This upgrades a previously-known issue (P2-8 in the original audit: "artisan rating silently fails to update on a *transient* review-submission error") to something more serious: **it is not transient — it fails every single time, unconditionally.**

`review_screen.dart`'s submit flow creates the `reviews/{jobId}` document successfully (that write is correctly rule-permitted), then attempts a **second, direct client transaction** updating `artisans/{artisanId}.rating`/`.totalRatings` — run as the **customer**, whose UID can never equal the artisan document's own ID. This fails Firestore's ownership check on every attempt, independent of the protected-field list (§16.1) — it isn't even reaching the field-level check, it fails the more basic `isOwner(uid) || isAdmin()` gate first. The code's own comment claims this is acceptable because it's "handled by Cloud Function in production" — **that Cloud Function does not exist.** Exhaustive search of `functions/index.js` confirms zero triggers on the `reviews` collection anywhere. The two Cloud Functions that *do* touch `trustScore` (`onArtisanRatingChanged`, `onArtisanVerificationChanged`) only **recompute** `trustScore` from `rating`/`totalRatings` when those fields change — and since nothing ever successfully changes them, they never fire for this reason.

**Net effect, stated plainly: submitting a review today creates a review record, but the artisan's public rating, rating count, and trust score never move, for any review, ever, on the current codebase.** This is not a network-flakiness edge case — it is the only code path that was ever supposed to update these fields, and it is unconditionally rejected by the security rules that were correctly written to stop exactly this kind of client-side write. **This is a P0/P1-class functional defect for a marketplace whose entire trust proposition depends on ratings actually reflecting real outcomes**, discovered fresh in this pass, not previously documented anywhere in this engagement's prior reports.

**Recommended direction (flagged, not implemented):** this needs a Cloud Function — `onReviewCreated` (Firestore-triggered on `reviews/{reviewId}` creation, Admin SDK, bypasses rules correctly) that recomputes and writes the artisan's `rating`/`totalRatings`, after which the existing `onArtisanRatingChanged` trigger continues to work exactly as designed to recompute `trustScore`. This is a real, scoped, well-understood fix — not a redesign — but it has not been implemented in this pass (this document is audit-only).

### 16.3 CONFIRMED — fabricated reviews can be attributed to any artisan

`firestore.rules`' `reviews` create rule verifies the reviewing customer and the underlying job (real, completed, owned by them) but **never checks that the review's own `artisanId` field matches the job's actual artisan.** Any customer with at least one completed job can create a review document (readable app-wide, since `reviews` read is `if isSignedIn()`) naming an entirely unrelated artisan. This can't currently move a live number given §16.2's pipeline is broken, but it becomes fully live and exploitable for reputation manipulation the moment §16.2 is fixed — both should be fixed together, not §16.2 alone.

---

## 17. Firestore Security Audit

This has been the single most re-verified area across this entire engagement (original audit, P0 remediation with its own dedicated investigation pass, Phase 10 follow-up, and this document's own fresh checks). Consolidated, current-state summary — every line below independently re-read this session, not transcribed:

**Confirmed fixed (re-verified):** the three P0 vulnerabilities that let a customer fabricate/duplicate a real escrow payout with zero real payment (duplicate `escrow_releases` rule blocks, unvalidated `payments` create rule, client-writable `paymentPending→escrowLocked` transition) — see §14 for full detail, not repeated here.

**Confirmed correct, re-verified this session:** `jobs` read/write scoping (customer/artisan/open-feed/admin only); `artisans` protected-field list correctly blocks client writes to `rating`/`totalRatings`/`trustScore`/`approvalStatus`/etc.; `admins/{uid}` is unconditionally `write: if false` for every caller including admins themselves, with zero client write attempts found anywhere in `lib/` (confirmed by grep); quotes subcollection correctly scoped (doc-ID-as-artisan-uid structurally prevents duplicate competing quotes, amount type/positivity checked on create, post-acceptance edits locked to status-only).

**Confirmed real, previously-known gaps, still open (not fixed in this engagement, correctly out of the P0 remediation's narrow scope):**
- **Fabricated reviews** — `reviews` create rule never checks `artisanId == job.artisanId`; now confirmed to compound with §16's broken rating pipeline once that's fixed (§16.3).
- **Storage over-broad reads** — `jobs/{jobId}/{uid}/**` and `disputes/{disputeId}/{uid}/**` both gate reads on "any signed-in user," not job/dispute parties specifically, unlike the equivalent Firestore collections.
- **Notification spam/spoofing** — any signed-in user can create a `notifications` doc targeting any *other* user, with no relationship check, as long as `type` is whitelisted.
- **`messages.isRead` scoping** — this one **was fixed this engagement** as part of the chat audit (§9), no longer open; noted here only to avoid appearing to contradict §9.

**New this session, not previously documented:** none beyond what's captured in §14/§16 (payment-authority) and §9 (chat) — the broader rules file was re-read for internal consistency but no additional gap surfaced beyond what those sections already cover in depth.

---

## 18. Platform Audit (iOS / Android / Web)

Fresh investigation this pass. **This surfaced one new, real, high-severity finding not previously documented anywhere in this engagement:**

### 18.1 NEW FINDING — missing iOS location permission string will crash the app on a real device (BROKEN, confirmed by direct evidence, not yet live-device-verified)

`ios/Runner/Info.plist` has **no `NSLocationWhenInUseUsageDescription` key at all** (confirmed by reading the complete file), while `lib/screens/home/service_request_screen.dart:155-168` actively calls `Geolocator.checkPermission()`/`requestPermission()`/`getCurrentPosition()` from the Post-Job flow. Per Apple's platform requirement, the **first time** this code path executes on a real iOS build, the app crashes immediately — a missing usage-description string is a hard, unrecoverable crash, not a soft permission denial. This has never been caught because no live iOS testing has occurred in this entire engagement (all live testing this session has been Flutter Web only). **Severity: P0/P1-class** (matches this document's own bar for "reliability defect that any real user immediately hits" — here specifically every iOS user who tries to post a job) — **flagged here for the first time**, not present in any prior audit in this repo. Contrast: `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` **are** correctly present; Android's manifest permissions are complete and correctly SDK-version-split. This is specifically and only an iOS gap.

### 18.2 No in-app calling exists — but neither does the external-dialer bridge the product decision implies

Confirmed by exhaustive search: `url_launcher` is used exactly once in the whole app, for Terms-of-Service/Privacy-Policy web links (`about_screen.dart`) — never for a `tel:` scheme. No "Call" button/icon exists anywhere in chat, job detail, or artisan profile screens, despite `phoneNumber` being a real, populated field on both `UserModel` and `ArtisanModel`. The product decision ("no in-app calling, use the external dialer") has correctly resulted in the *absence* of in-app calling, but has **also** resulted in the absence of any calling mechanism at all — the one-line `launchUrl(Uri(scheme: 'tel', path: phoneNumber))` bridge that decision implies is simply **NOT IMPLEMENTED**.

### 18.3 No deep-link surface exists on either platform (re-confirmed, unchanged from the original audit)

No `VIEW`/`BROWSABLE` intent-filter or `autoVerify` on Android; no `CFBundleURLTypes` and no entitlements file at all on iOS. Distinct from the already-documented P1 bug where a tapped push notification uses the wrong in-app navigation API (`Navigator.pushNamed` on a go_router app) — that's a separate, in-app-only routing bug; this is the OS-level URL-scheme surface, and it's simply absent, not broken.

### 18.4 Secure storage has a real platform asymmetry worth a follow-up check

The single stored value (`auth_access_token`, in `lib/core/auth/secure_token_manager.dart`) uses `KeychainAccessibility.first_unlock` on iOS, which — unlike Android's Keystore-backed storage — typically **survives app uninstall/reinstall** on iOS (Keychain isn't tied to the app bundle's lifecycle). A user uninstalling and reinstalling on iOS could have a stale token silently restored; the identical action on Android starts clean. Whether this is actually exploitable depends on `auth_service.dart`'s startup token-validation/refresh logic, which was not itself re-examined in this pass — flagged as **NEEDS LIVE DEVICE VERIFICATION** and a targeted follow-up code review, not resolved here.

### 18.5 No explicit iOS-only code branch exists anywhere in `lib/`

The only native-platform conditional in the app is a single `Platform.isAndroid` check (`lib/core/platform_io.dart:3`); there is no `Platform.isIOS` branch anywhere. iOS therefore always falls into the "not Android" path alongside Web — meaning any iOS-specific behavioral difference that *should* exist has never been explicitly considered, let alone tested. This is a structural risk factor (an unexamined assumption), not a specific confirmed bug beyond 18.1.

---

## 19. UI/UX Audit

The V2 objective, per this task's own framing, is not "make V1 screens look nicer" — it's rebuilding around the approved Stitch design. Re-stating the honest current state rather than the aspirational one: **this rebuild is substantially underway, not merely planned**, per direct verification against every `design/STITCH_*.md` group audit this session (cross-checked against actual source in several spot-checks throughout this document, not taken purely on faith).

- **Screens confirmed already rebuilt with real Stitch-driven changes, not just restyled labels:** Home (`_CustomerHomeTab`), My Bookings (`JobBookingCard`, dark-pill tabs), Artisan Dashboard/Open Jobs Feed (search/toggle/filter chips, `WorkflowGateService`-sourced badges), Chat's sticky job-summary header, Payment's escrow-education card and full-screen result view, Wallet's grouping/earnings-readiness signal, Admin's Escrow Volume card and Operational Alerts, and the unified notification pipeline (§10).
- **Screens deliberately left as restyle-only, correctly not touched further because they were already architecturally sound:** Job Details (confirmed pre-existing use of `WorkflowGateService`/`WorkflowStatusCard`/`WorkflowTimeline` before any redesign work began), Portfolio/Business Profile/Bank Details/Verification (confirmed already token-consistent by grep for raw color literals — none found).
- **Screens/features confirmed as genuinely new functionality requiring backend work, correctly NOT faked with placeholder data:** the photo-unlock paywall on Post Job (no backend of any kind exists — no payment product, no Cloud Function, no pricing config), milestone-based escrow on Wallet (confirmed: the single-payment `PaymentModel` is the entire data model; no milestones subcollection exists anywhere), TrustScore card's percentile/Craftsmanship/Punctuality sub-scores (§16 confirms `trust_score_service.dart` produces one aggregate number only), a "Drafts" tab on My Bookings (no draft-job concept exists in `JobStatus`), and Recent Activity (no view-history/activity-log collection exists).
- **Genuinely resolved ambiguity, worth restating since this document itself flagged it as unclear earlier in the engagement:** the competing nav-label sets and duplicate Wallet-screen designs that looked like unresolved conflicts were, in fact, already explicitly decided (`STITCH_IMPLEMENTATION_AUDIT.md`'s "Decisions" section, 8 numbered resolutions) — Customer nav is `Explore/My Tasks/Wallet/Profile`, Artisan nav is `Find Jobs/My Jobs/Inbox/Profile`, the dark-navy TrustScore variant won, the green-gradient Wallet variant won, the dark-background Messages variant was confirmed a stray export and discarded.

---

## 20. Stitch / V2 Design Gap

Per `design/STITCH_IMPLEMENTATION_AUDIT.md` and `design/STITCH_BUILD_ORDER.md` (both fully read this session), the honest gap list — screens/features Stitch's reference material called for that do not exist today, independent of any UI work:

| Gap | What's missing | Why it's flagged, not built |
|---|---|---|
| Photo-unlock paywall (Post Job) | Entire payment product — no Cloud Function, no pricing, no Firestore field for purchased slots | Requires a genuine pricing/product decision before any UI is worth building against real data |
| Milestone-based escrow (Wallet) | New subcollection, new `JobService` methods, new Firestore rules, new Cloud Functions logic for partial Paystack releases | The single largest backend gap identified in the whole Stitch audit — explicitly not attempted; current Wallet redesign correctly built against the real single-payment model instead |
| TrustScore percentile + Craftsmanship/Punctuality sub-scores | New computed fields in `trust_score_service.dart`/the server formula | Real computation work, sequenced but not yet built; UI shell exists, wired to placeholder-shaped (not placeholder-*valued*) data per the build order's own instruction |
| "Drafts" tab (My Bookings) | No draft-job concept in `JobStatus` at all | New functionality — jobs are only ever created fully-formed today |
| Recent Activity screen | No view-history/unified-activity-log collection | Net-new screen, net-new backend, correctly sequenced last/optional |
| Notification Preferences (per-category) | Only one global push toggle exists today | Flagged in the build order as needing its own scoping decision before the screen can be "fully functional" rather than cosmetic |
| Direct-booking wizard's original 3-step "Details→Schedule→Payment in one screen" concept | Confirmed **NOT literally built this way** — implemented instead as "Secure Booking," an additive front-door onto the existing lifecycle (§13), which was the correct, safer product decision, not a shortfall |

**No screen was found where Stitch material exists but was silently ignored.** Every gap above is explicitly documented in the existing `design/STITCH_*.md` audits as a deliberate "flag, don't fabricate" decision, re-confirmed by this session's independent source-code checks.

---

## 21. Testing Coverage Audit

Fresh investigation this pass, not carried over from any prior report.

**Blunt bottom line: there is effectively zero automated coverage of the actual end-to-end user journey.** Every one of the 7 Dart test files under `test/` is either a pure-logic unit test of extracted predicates/state-machine transitions/model serialization, or a narrow regression guard for one specific historical bug (the portfolio-route null crash, the password-reset false-success bug). Only one file (`test/portfolio_project_route_test.dart`) contains any `testWidgets` call at all — three cases, testing one isolated route with a stub router, not the real app shell. **No test exercises signup → post job → browse artisans → quote → chat → pay → complete → review as a connected journey.** This is disclosed candidly in several test files' own header comments (explicitly noting "no Firestore emulator for this," "no GoRouter test harness for the real router") — a known, self-aware gap, not a hidden one, but a real gap nonetheless for any V2 production-readiness claim.

**By area:** customer workflow, artisan quoting flow itself (as opposed to the eligibility gate), chat, notifications, and ratings/trust-score have **NOT IMPLEMENTED** test coverage of any kind. Job lifecycle, quotes (eligibility only), verification, payments, escrow, and admin actions are **PARTIALLY TESTED** — narrow, specific slices with real value (especially the P0 remediation's Firestore Rules emulator suite, 26 cases covering `payments`/`escrow_releases`/`agreedAmount`/`admins` specifically) but nowhere near full-workflow coverage. The rules-emulator suite explicitly does **not** cover `chats`/`messages`, `quotes`, `reviews`, general `users` CRUD, `notifications`, `support_tickets`, or `storage.rules` — it is scoped tightly to the payment/escrow P0 fix, not the whole security surface.

**Platform-specific test coverage: NOT IMPLEMENTED**, at all — zero tests reference `kIsWeb`/`Platform.isIOS`/`Platform.isAndroid`, and no plugin-behavior test exists for `image_picker`/`geolocator`/`firebase_messaging`/`flutter_secure_storage` on either platform.

---

## 22. Infrastructure Blockers

Unchanged in substance since the original audit, re-confirmed live multiple times across this engagement (most recently this session, via a fresh `firebase functions:list` call):

- **Zero Cloud Functions deployed**, confirmed live, repeatedly, throughout this entire engagement — every payment, escrow-release, notification-delivery, trust-score-recompute, and admin-claim-mirroring function is inert in production today. This is the single largest infrastructure blocker in the whole document.
- **No staging/test Firebase project exists** — `handytrust` is the only project available; any deployment "for testing" would be deploying to what is, in practice, the production project.
- **No in-app path to grant admin status** — requires a manual Firestore write outside the app; the Cloud Functions that would mirror this into a usable custom claim are themselves part of the zero-deployed-functions blocker above.
- **Paystack account configuration unknown** — whether "Enable OTP for transfers" is on (which would silently stall every payout if so, per the original audit's P1-6) cannot be checked from any coding session.
- **`PAYSTACK_SECRET_KEY`/`GEMINI_API_KEY` live Secret Manager values unverified** — a prerequisite independent of the Blaze-plan upgrade itself.
- **Neither disposable test account is email-verified**, still, as of this session — re-checked live, not assumed. This has blocked every attempt at authenticated live QA across this entire engagement (customer, artisan, and admin workflows all remain unverified live, end to end, for the entire duration of this project's audit work).

---

## 23. Master Gap Matrix

| Area | V1 Status | Evidence | Problem | V2 Requirement | Priority | Dependency |
|---|---|---|---|---|---|---|
| Authentication | VERIFIED WORKING (pre-auth surface) / IMPLEMENTED — LIVE VERIFICATION BLOCKED (post-auth) | §4, live browser testing this engagement | Auth screens/flows work; nothing past login has ever been live-verified | Complete authenticated live QA once accounts verified | P1 | Account verification |
| Customer workflow | PARTIALLY REBUILT | §4 | Home lacks completed-jobs visibility; Drafts tab has no backend concept | Decide on Drafts scope; add completed-jobs visibility | P2 | Design system (done) |
| Artisan workflow | PARTIALLY REBUILT | §5 | TrustScore sub-scores/percentile not computed | Build `trust_score_service.dart` sub-score computation | P2 | — |
| Admin | VERIFIED WORKING (mature) | §6 | Manager role absent; no in-app admin-grant path | Decide if Manager role is truly needed; accept manual admin-grant as permanent, or build a path | P3 (Manager), P2 (admin-grant UX) | — |
| Jobs (lifecycle) | VERIFIED WORKING | §7 | None found beyond the now-fixed P0s | None | — | — |
| Quotes | VERIFIED WORKING | §8 | None found | None | — | — |
| Matching | **BROKEN relative to product decision** | §11 | Not distance-first; artisan location never captured at all, making the bonus dead code | Build artisan location capture; invert ranking precedence; decide on hard radius cutoff | **P1** | Product decision on capture granularity/privacy |
| Verification | VERIFIED WORKING | §12 | None found | None | — | — |
| Chat | **Confirmed BROKEN, then FIXED this engagement** | §9 | Was: pre-match query rejection, merged conversations, unread badges never clearing, no message notifications, unscoped isRead rule | All fixed and regression-tested | — (closed) | — |
| Notifications | IMPLEMENTED — LIVE VERIFICATION BLOCKED | §10 | Delivery pipeline unified and fixed in code; never verified against a real device (zero functions deployed) | Deploy + verify on real devices | P1 (once deployment happens) | Cloud Functions deployment |
| Booking/Scheduling | VERIFIED WORKING | §13 | None found; Secure Booking confirmed non-conflicting | None | — | — |
| GPS | **PARTIALLY IMPLEMENTED, verging on NOT IMPLEMENTED** | §11, §18.1 | Artisan location never captured; iOS permission string missing entirely | Build artisan location capture; add iOS `Info.plist` key | **P0/P1** (iOS crash risk), P1 (matching) | — |
| Escrow | VERIFIED WORKING (rules/logic) / INFRASTRUCTURE BLOCKED (live) | §14 | Fixed and regression-tested locally; never proven against real deployment/Paystack traffic | Blaze upgrade + staging deploy + Paystack test-mode validation | P0 (before real money) | Billing decision |
| Payments | Same as Escrow | §14 | Same | Same | P0 | Same |
| Completion | VERIFIED WORKING | §7 | None found | None | — | — |
| Complaints | PARTIALLY IMPLEMENTED | §15 | Artisan-initiated disputes blocked by rule; 14-day window may conflict with an earlier "3-day" figure | Decide both open questions | P2 | Product decision |
| Ratings | **CONFIRMED BROKEN — new finding this session** | §16 | Review submission never actually updates artisan rating/trustScore; no Cloud Function fills the gap the code assumes exists | Build `onReviewCreated` Cloud Function | **P0/P1** | None — scoped, well-understood fix |
| Trust Score | Formula sound, but fed by broken pipeline above | §16 | Same root cause as Ratings | Same fix | P0/P1 | Same |
| Security (general) | VERIFIED WORKING (post-remediation) | §17 | A few known-open P2s (fabricated reviews compounds with Ratings fix; Storage over-broad reads; notification spoofing) | Close remaining P2 rules gaps | P2 | — |
| Firestore Rules | Same as Security | §17 | Same | Same | P2 | — |
| UI | Substantially rebuilt already | §19 | A handful of new-functionality items correctly deferred, not faked | Product decisions on paywall/milestones/etc. | P2-P3 | Product decisions |
| Navigation | VERIFIED WORKING (with 2 known P1 bugs) | Original audit, unchanged | FCM-tap deep link uses wrong Navigator API; `/payment/.../webview` crashes on direct nav | Fix both | P1 | — |
| iOS | **NEW CONFIRMED BROKEN finding** | §18.1 | Missing location permission string will crash on first geolocation use | Add the Info.plist key | **P0/P1** | None |
| Android | VERIFIED WORKING (permissions complete) | §18.3 | None found beyond the pre-existing admin-table breakpoint P2 | None | — | — |
| Web | VERIFIED WORKING (pre-auth) / mostly untested (post-auth) | §4, original audit | Live QA never reached post-auth Web screens | Complete authenticated live QA | P1 | Account verification |
| Testing | **NOT IMPLEMENTED (end-to-end)** | §21 | Zero connected-journey coverage; scoped unit/emulator tests only | Add at least one true end-to-end integration test | P2 | — |
| Infrastructure | **BLOCKED** | §22 | Zero deployed functions, no staging project, unverified accounts | Business/billing decision required | P0 (blocks everything payment-related) | Billing/account-verification decisions |

---

## 24. P0/P1/P2/P3 Priorities (this document's own findings, consolidated — not a repeat of the original audit's now-fixed P0s)

**P0 — BLOCKER:**
1. Broken review→rating pipeline (§16.2) — the core trust mechanism of a trust-based marketplace does not function.
2. Missing iOS location permission string (§18.1) — guaranteed crash for every iOS user who posts a job.
3. Live Paystack/Cloud-Functions validation entirely unexecuted (§14.2/§22) — real money must not move through unverified infrastructure.
4. Refund/cancellation-after-payment mechanism entirely absent (§14.3) — real customer money can be captured with no path back.

**P1 — CRITICAL:**
- Matching is not distance-first and artisan location is never captured at all (§11).
- Authenticated live QA has never been executed for any role (§4/§5/§6, blocked by account verification).
- Fabricated-review vector (§16.3, compounds with the P0 rating-pipeline fix).
- Two known navigation P1s from the original audit remain unfixed (FCM deep-link Navigator API mismatch; payment webview crash on direct nav).
- No calling mechanism exists at all, despite the product decision implying an external-dialer bridge (§18.2).

**P2 — IMPORTANT:**
- Artisan-initiated disputes blocked by rule; 14-day vs. possible 3-day window conflict (§15).
- Storage over-broad reads on job photos/dispute evidence; notification spoofing vector (§17).
- Manager role entirely absent if the V2 plan assumes it exists (§6a).
- No in-app admin-grant path (operational friction, not a security bug) (§6/§22).
- Zero end-to-end test coverage (§21).
- Home's missing completed-jobs visibility; Drafts tab's undefined backend concept (§4/§19).
- iOS Keychain token-persistence-across-reinstall asymmetry, needs live-device follow-up (§18.4).

**P3 — POLISH:**
- TrustScore percentile/sub-score computation (real work, but not blocking).
- Recent Activity, Notification Preferences, milestone-escrow Wallet, photo-unlock paywall — all confirmed correctly deferred, not silently dropped.

---

## 25. Keep / Refactor / Rebuild / Delete / New

**KEEP (sound, do not touch without a proven reason):**
- `JobService`'s entire state machine and transactional write methods — repeatedly re-verified across three separate investigation passes this engagement, consistently found correct.
- `firestore.rules`' core structure post-remediation (payments/escrow_releases/job-transition sections).
- The Stitch design-system token layer (`app_design_system.dart`) and every screen already confirmed rebuilt against it.
- Admin dashboard's core sections (Users, Jobs, Disputes, Audit Logs, Analytics) — mature, real, no gaps found.
- Scheduling/booking implementation, including Secure Booking's additive (non-conflicting) design.
- Quote lifecycle, verification/eligibility gating.

**REFACTOR (fundamentally sound, needs restructuring or extension, not a rewrite):**
- `trust_score_service.dart`/the server formula — add Craftsmanship/Punctuality sub-scores and percentile rank as new computed fields, don't replace the existing (correct) weighting.
- `matching_service.dart`'s `_score()` — invert the distance/trust-score precedence once artisan location capture exists; the haversine math and overall structure are already correct and reusable.
- Notification system — the unified `onNotificationCreated` pipeline (§10) is the right shape; it just needs deployment and dead-token cleanup added.

**REBUILD (architecture/workflow unsuitable, needs a fresh approach):**
- The review→rating update path (§16.2) — not a patch to the existing broken client-side write, a proper server-side Cloud Function trigger instead.
- Nothing else in this codebase was found to warrant a full rebuild — this is the shortest list in this section for a reason; the "rebuild from scratch" framing this task opened with does not match the codebase's actual state.

**DELETE (dead/duplicated/obsolete, already actioned or safe to action):**
- `PaymentService.simulatePayment` — already deleted during the P0 remediation, confirmed.
- `EscrowService` (the dead, duplicate job-state-machine class) — flagged repeatedly, not yet deleted; low-risk, recommend actioning.
- `AdminAuditLogService` (unused duplicate of `AdminAuditService`) — same treatment.
- Empty stub files (`auth_repository.dart`, `firebase_auth_service.dart`, `icon_service.dart`), empty `lib/screens/jobs/`/`lib/screens/payments/` directories, unused `google_fonts` dependency.

**NEW (does not exist today, real product/engineering work):**
- Artisan location capture (onboarding or service-area based — needs a product decision on granularity).
- Refund/cancellation-after-payment architecture.
- `onReviewCreated` Cloud Function (the rating-pipeline fix).
- iOS `tel:`/external-dialer bridge for the phone-number fields that already exist but are never surfaced as callable.
- Manager role, if actually wanted (currently a false premise if assumed to exist).
- Photo-unlock paywall, milestone-based escrow, TrustScore sub-scores, Recent Activity, Notification Preferences — all previously scoped and correctly deferred.

---

## 26. V2 Architecture Recommendation

The codebase does not need a new architecture. Riverpod + single-authority services (`JobService`/`QuoteService`/`ChatService`/`NotificationService`) + Firestore-rules-as-security-boundary is a sound pattern, proven correct under real adversarial testing (the P0 remediation's emulator suite). **The recommendation is targeted remediation and completion, not a re-architecture.** The one place a genuinely new piece of infrastructure is needed is server-side: a Cloud Function for review-triggered rating updates (§16.2), following the exact same pattern already used correctly elsewhere (`onArtisanRatingChanged`, `onNotificationCreated`).

---

## 27. Recommended Implementation Order

Given the codebase's actual state (mature, not greenfield), the phased order this task template proposed (Phase 0-15, data model → auth → design system → ...) does not fit — most of those phases are already done. The real remaining order:

1. **Resolve the account-verification blocker** — this single item unblocks more of this document's "NOT YET VERIFIABLE" findings than anything else. Not a coding task.
2. **Fix the P0s that are pure code, no infrastructure dependency:** the review→rating Cloud Function (§16.2), the iOS location-permission string (§18.1). Both are small, scoped, well-understood.
3. **Execute the authenticated live QA pass** that has never happened, once step 1 clears — customer, artisan, and (once an admin account exists) admin workflows, end to end, in a real browser/device.
4. **Make the open product decisions** (§28) — these are cheap to decide and expensive to leave open, since several other fixes (matching, disputes, refunds) are blocked on them.
5. **Build the artisan-location-capture + matching-precedence fix** (§11) once its product decision lands.
6. **Design and build the refund/cancellation architecture** (§14.3) — the largest remaining piece of real, un-scoped work, and the one with the most business risk if skipped.
7. **Only then: Blaze-plan upgrade, staging deploy (or accept direct-to-`handytrust` risk), Paystack test-mode validation, following the deployment sequence already fully specified in `design/P0_REMEDIATION_PLAN.md` §8.**
8. Remaining P2/P3 polish (Manager role decision, admin-grant UX, end-to-end test coverage, TrustScore sub-scores, deferred UI features) — parallelizable with the above, not blocking.

---

## 28. Open Product Decisions

Every item below is called out because a wrong guess here is expensive to unwind — none are resolved by this document, all require the user/product owner's explicit call:

1. **Refund/cancellation-after-payment model** — automatic Paystack refund? Admin-approved? Partial/dispute-split? (§14.3)
2. **Artisan location capture** — onboarding one-time GPS capture, address-geocoded, or service-area radius selection? Privacy/granularity tradeoff. (§11)
3. **Matching ranking precedence** — should distance become a hard filter (radius cutoff) or remain a scored dimension, just correctly weighted first? (§11)
4. **Artisan-initiated disputes** — intentional customer-only restriction, or a real V2 gap? (§15)
5. **Dispute/auto-release window** — is 14 days (currently coded) or 3 days (referenced in an earlier discussion) correct? (§15)
6. **Manager role** — is it actually needed for V2, given it doesn't exist at all today? If yes, what does it need to do that Admin doesn't? (§6a)
7. **In-app admin-grant path** — accept the manual-Firestore-write process as permanent, or build a real (presumably super-admin-gated) in-app path? (§6/§22)
8. **Deployment path** — deploy to `handytrust` directly (the only project available) with test-mode secrets, or invest in a genuine staging project first? (§22)

---

## 29. V2 Definition of Done

A stage is "done" only when every applicable item below is true, not merely "code exists":
- [ ] The specific workflow has been executed live, authenticated, against real (test-mode where money is involved) infrastructure — not just passed a local unit/emulator test.
- [ ] Every negative/adversarial case this document or the P0 remediation identified for that area has a passing regression test.
- [ ] No screen in that workflow shows raw Firebase/Dart exception text, a permanently-stuck loading spinner, or a crash on direct/deep navigation.
- [ ] Every open product decision touching that workflow (§28) has been explicitly resolved, not silently assumed.
- [ ] For payment/escrow specifically: a real (test-mode) Paystack transaction has been completed end-to-end, including a real payout, with every adversarial test from `design/PHASE_10_AUTHENTICATED_PAYMENT_QA.md` §4 re-run against the deployed environment, not just the local emulator.

---

## V2 REBUILD STARTING POINT

**If we start rebuilding HandyTrust tomorrow, what exactly should we build first, and what should we deliberately NOT touch yet?**

**Build first, in order:** (1) the `onReviewCreated` Cloud Function that fixes the completely-broken rating pipeline — this is the single highest-leverage, lowest-risk fix in this entire document, a scoped server-side addition with no architectural risk; (2) the iOS `NSLocationWhenInUseUsageDescription` key — a one-line `Info.plist` addition that prevents a guaranteed crash; (3) get the two disposable test accounts verified (or provision fresh ones) and finally execute the authenticated live QA pass that has been blocked for this entire engagement — every other priority call in this document is more confident once that pass actually happens.

**Do NOT touch yet:** `JobService`'s state machine, the Firestore rules' core payment/escrow structure, the admin dashboard's core sections, the quote/verification pipeline, or anything already labeled KEEP in §25 — all of these were independently re-verified as correct multiple times across this engagement, and touching them without a proven reason is pure risk with no offsetting benefit. Do **not** attempt a Blaze-plan deployment or any live Paystack transaction, test-mode or otherwise, until the account-verification blocker clears and the authenticated live QA pass in step (3) above has actually happened — deploying blind, with no live-tested authenticated workflow behind it, is the one action in this entire document capable of turning a locally-proven fix into a real production incident.
