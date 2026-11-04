# Phase 12 — Production Launch Preparation Report

No screens redesigned, no unnecessary features added, no architecture rewritten. Companion documents: `design/PRODUCTION_PAYSTACK_CHECKLIST.md`, `design/FIREBASE_PRODUCTION_AUDIT.md`, `design/CRASHLYTICS_IMPLEMENTATION_PLAN.md`, `design/ANALYTICS_PLAN.md`.

---

## 1. Launch readiness score: 8/10

Down half a point from the prior 8.5/10 final-audit score — not because this phase found the system in worse shape, but because it found one genuinely new, real, higher-severity issue the prior audit's scope didn't reach (Paystack duplicate-payout race condition, below). Everything else this phase touched came back clean or was closed.

## 2. Completed preparation tasks

- **Paystack sandbox readiness audit** — payment initiation, verification, and escrow-lock-on-success all confirmed correct and server-authoritative. One critical finding (below).
- **Firebase production configuration review** — rules, storage rules, secrets handling, indexes, and admin-permission consistency all reviewed and confirmed sound. One new minor gap found (`escrow_releases` has no explicit rule — currently harmless since nothing reads it client-side, documented for future-proofing).
- **Crash reporting plan** — no Crashlytics exists; full implementation plan written, nothing installed (compatibility confirmed against the current `firebase_core` version).
- **Analytics plan** — no analytics package exists; all 8 requested events mapped to their real, existing trigger points in the codebase, nothing instrumented.
- **Dead code removal** — `phone_login_screen.dart` and `customer_registration_screen.dart` **deleted** (zero references confirmed fresh, router checked, imports checked, `flutter test` still 44/44 after removal). A second, previously-undocumented dead cluster found and reported, not deleted (below).
- **Performance quick win applied** — `ArtisanCard`'s profile photo (the single most-repeated image across the app — shown in every artisan list on Home, Browse Artisans, and Artisan List) now uses `CachedNetworkImage` instead of `Image.network`. The package was already a dependency and already proven working in `UserAvatar` — zero new risk, real disk-cache win. 7 other `Image.network` call sites identified and documented, not touched this pass (see Task 6 detail below).
- **Final release test** — `flutter clean` → `pub get` → `analyze` → `test` → `build apk --release`, all run fresh after the deletions and the image-caching change.

## 3. Remaining manual tests
All from `design/PRODUCTION_PAYSTACK_CHECKLIST.md`'s manual test table: a real Paystack sandbox run (initialize → pay → verify → lock → complete → payout), a decline-card test, the `BANK_CODES` table verification against Paystack's live bank list, and — highest priority — an attempt to reproduce the duplicate-payout race condition below in a sandbox environment.

## 4. Production risks

### 🔴 Critical — Paystack duplicate payout race condition (new finding this phase)
`_releaseEscrow` (the Cloud Function the hourly auto-release cron calls) reads and writes a job's status with no transaction and no precondition check, unlike `JobService.confirmComplete` (the customer-manual path), which is properly transactional. If a customer manually confirms a job in the same narrow window the auto-release cron is processing that same job, **both paths can create their own `escrow_releases` document**, and the Firestore-trigger `processEscrowRelease` fires unconditionally on each — resulting in two real Paystack Transfers for one job. Low probability (the race window is only the ~1 hour around a 14-day deadline expiring, and only if the customer confirms in that exact window), high severity (real, unrecoverable money movement). **Not fixed in this phase** — flagged per this phase's own "do not rewrite architecture" scope, but the fix is small and precisely specified in the Paystack checklist (wrap `_releaseEscrow` in a transaction with a `status !== 'submitted'` guard, mirroring `confirmComplete`'s existing pattern). **Recommend fixing before real payouts run.**

### 🟡 Moderate
- `BANK_CODES` table unverified against Paystack's live bank list (fails safely if wrong, but could block real payouts).
- Firestore rules/indexes edited across this entire program are only correct in the local files — **not yet deployed** to the real Firebase project. `firebase deploy --only firestore:rules,firestore:indexes` has not been run as part of any group in this program.
- Android build toolchain warnings: Kotlin 2.0.10 (below Flutter's soon-to-be-required 2.1.0 minimum) and Java 8 source/target level (marked obsolete by the JDK itself). Neither blocks today's build; both should be scheduled before they become hard failures.

### 🟢 Low / informational
- `escrow_releases` collection has no explicit Firestore rule (currently harmless — nothing client-side reads it — but worth a deliberate rule rather than relying on default-deny-by-omission a second time, same class of issue `admin_alerts` had before Group 10).
- A fully isolated, provably dead 4-file cluster found: `lib/core/auth/auth_providers.dart`, `lib/core/auth/secure_token_manager.dart`, `lib/core/network/api_client.dart`, `lib/core/network/auth_interceptor.dart` — zero references from any actively-used file, confirmed by grep. Appears to be a legacy `dio`-based auth/API layer superseded by the Firebase-SDK-direct pattern used everywhere else in this app (`lib/providers/auth_provider.dart`). **Not deleted this pass** — unlike the two screens named explicitly in this phase's instructions, this cluster wasn't pre-cleared for removal; flagging with full proof for a deliberate decision rather than acting unilaterally on a 4-file, dependency-touching removal.
- `assets/fonts/Inter/static/` (~30 individual-weight TTF files) and the italic variable font are present in the repo but **not declared anywhere in `pubspec.yaml`'s `fonts:` section** (only the one regular variable-font file is) — meaning they're not bundled into the app at all today. Pure repo bloat, zero runtime effect either way. Not removed this pass (same reasoning as above — a batch-file removal not explicitly pre-cleared).

## 5. UX issues
Carried over from the prior final audit, unchanged: `resolved` job status has no dedicated action-buttons-area card (outcome still visible via the dispute thread); no "agreement confirmed" notification exists in either direction. Neither touched this phase (UI changes are out of scope for a hardening-only phase).

## 6. Deployment checklist
1. **Fix the duplicate-payout race** (or explicitly accept the risk with a documented mitigation plan) before enabling real payouts.
2. **Deploy Firestore rules and indexes** to the real project — confirm every index shows `Enabled` in the Console before relying on the queries that need them (composite indexes can take time to build against a populated dataset).
3. **Verify `BANK_CODES`** against Paystack's live `GET /bank?country=nigeria`.
4. **Run the Paystack sandbox manual test table** end to end.
5. **Verify Firebase Console-side Auth settings** (enabled sign-in providers, password policy) — not visible from source.
6. Decide on the `core/auth`/`core/network` dead cluster and the unbundled font files — action or explicitly defer.
7. Schedule the Kotlin/Java toolchain version bumps.
8. When ready: implement Crashlytics (plan is written) before wide release, so day-one crashes are visible.

## 7. Recommended beta launch plan
1. **Closed beta first** (a small, known set of real artisans + customers, not a public launch) — this surfaces the kind of edge-case timing behavior (like the duplicate-payout race) that only shows up under real, imperfectly-timed usage, in a setting where a mistake is recoverable and cheap.
2. **Fix the critical payout race before beta**, not after — this is the one finding in this whole program directly touching real money duplication; it's a small fix and should not ship even to a beta with real Paystack transactions.
3. **Enable Crashlytics before beta**, not after — a beta with real users and no crash visibility means every early bug report is guesswork.
4. **Deploy rules/indexes and re-run the Paystack manual test table against the real (sandbox-mode) project** before inviting the first beta user.
5. Widen from beta to general availability only after at least one real end-to-end job (post → quote → pay → complete → payout → review) has been observed succeeding in production conditions, not just sandbox.

---

This is the final phase of the HandyTrust production-readiness program. No new feature development follows.
