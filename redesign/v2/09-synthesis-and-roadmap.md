# V2 — Closing Synthesis & Build Order

The v2 pacing plan is complete (`00-overview.md`). This doc does what `11-production-roadmap.md` did for the original 11-phase program: turns a stack of specs into one actionable build order, and consolidates every real (non-visual) bug this pass found into a single checklist so none get lost in eight separate files.

---

## 1. What actually changed vs. the original 11-phase program

Nothing functional. `01`, `04`, `05`, `06`, `07`, `08`, `10`, `11` are unaffected — the escrow payout gap, the Trust Score ranking fix, the Firestore/Storage hardening, the milestone/GPS/messaging designs are all still exactly the plan. What v2 changed is presentation and a small number of workflow fixes discovered *because* rebuilding each screen from scratch forced a close read of code this program hadn't examined line-by-line before:

- Cards: bordered-white → borderless gray-fill, app-wide including admin.
- Nav: floating frosted bar + gradient FAB → flat bar, filled-pill active state, Wallet promoted from a Profile row to a primary tab, FAB removed (post-a-job becomes an in-content action).
- Admin's color system unified to derive from brand tokens instead of a hand-rolled duplicate (zero visual change, removes future drift risk).
- A standing accessibility rule (color as icon/fill, never small text) applied everywhere, after finding the same contrast bug three separate times before generalizing it.

## 2. What's spec'd vs. what's actually built

**Implemented in code**: only the four auth screens (`login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart`, `verify_email_screen.dart`) plus the shared `auth_scaffold.dart` widgets, plus the one build-fix (`notification_provider.dart`'s missing import). Everything else in `redesign/v2/01`–`08` is a reviewed spec, not yet code.

**This matters for sequencing**, not just as a status note: several v2 screens are specs *for data that doesn't exist yet in the running app* — the Wallet summary card, Job Detail's milestone section, Home's real (non-fake) escrow progress, and Admin's Escrow Monitoring/Trust Score Management sections all assume the Phase 1.5 hardening sprint (`01.5-critical-review-and-hardening-sprint.md`) has shipped. Building those screens' UI against a backend that still doesn't pay artisans or rank by trust score would mean either faking the data (actively misleading, the exact trap `v2/01`'s escrow-card fix was designed to avoid) or building the screen twice.

## 3. Recommended build order (implementation order, not spec order)

1. **Phase 1.5 hardening sprint, actually implemented** — Tracks B (trust-score ranking) and C (demo-gating, config rules) first since they're small and independent; Track A (escrow payout automation) is the larger, most consequential piece. This was always the real prerequisite; the v2 visual work didn't change that, it just produced more screens now waiting on it.
2. **Design-system foundation in code**, no backend dependency, unblocked today: the borderless-card theme change, the nav-bar rebuild (flat bar, pill active-state, Wallet tab, FAB removal), `AdminColorsExtension`. This is the same kind of work already done for the auth screens — pure UI, ready now.
3. **Screens with zero backend dependency** — build these next, in roughly this order: Profile/Settings (four real bugs to fix while restyling), My Tasks (the new Disputed filter), Artisan Dashboard/Portfolio/Verification/Open Jobs Feed (the rejected-banner fix, the proactive Verify-Later messaging). None of these need the hardening sprint to have shipped.
4. **Screens that need the hardening sprint** — Home's real escrow card, Wallet, Job Detail's milestone section and consolidated timeline, Admin's new sections. Build after step 1 lands.
5. **Artisan Profile** sits between 3 and 4 — its core content has no backend dependency, but the dead-end-CTA fix (a real "Request a Quote" path from general discovery) touches `MatchingService`, which step 1 also touches — worth sequencing right after the hardening sprint's ranking work for that reason, not because the whole screen needs it.

## 4. Consolidated bug/gap checklist (every real, non-visual finding from the v2 pass)

Pulled from all eight screen docs into one list — check these off independently of the visual rebuild, since several are cheap fixes that don't need to wait for anything above:

- [ ] `artisan_profile_screen.dart`: general-discovery profile view has no primary CTA at all (`v2/02`) — **do not wait for the hardening sprint on this one**; a minimal version (route to `/request` pre-filled) needs no ranking fix.
- [ ] Job Detail renders three overlapping timeline widgets simultaneously (`v2/05`) — consolidate into one `JobLifecycleTimeline`.
- [ ] Job detail lacks a "Report an issue" entry point (chat had an interim fix already; job detail never got one) (`v2/05`).
- [ ] `profile_screen.dart`: "My Reviews" → `/notifications` (wrong), "Payment Methods" → `/jobs` (wrong, and now redundant with the Wallet nav tab — remove, don't fix), "About HandyTrust" → no-op (`v2/06`).
- [ ] `settings_screen.dart`: "Push Notifications" → `/notifications` (wrong; should point at the not-yet-built preferences screen from `08-messaging-notifications.md` §5).
- [ ] My Tasks' active/completed filter silently flattens disputed jobs into "completed" — add a Disputed filter (`v2/04`).
- [ ] Artisan Dashboard has no banner for a `rejected` approval status — only `pending`/`approved` are handled (`v2/07`).
- [ ] Escrow promo card (Home) must never show a fixed/fake progress percentage when no real active job exists — already fixed in the spec, flagged here so it doesn't regress if reimplemented from scratch later (`v2/01`).

None of these were visual issues — every one would need fixing even if this program had never touched a single color.

## 5. Open product decisions still waiting on you
Restated from where they were first flagged, since they're easy to lose track of across eight files:
- Is phone-based sign-in an intended entry point? (`phone_login_screen.dart`, `customer_registration_screen.dart` are dead code, first flagged in `03-ia-navigation-journeys.md`, still unresolved.)
- Should the escrow promo card / Trust Score Explainer merge into one "How HandyTrust protects you" surface, or stay separate? (`v2/01`, flagged not decided.)
- "My Reviews" — build the minimal screen, or remove the menu entry until a real one exists? (`v2/06`, leaned toward building but not decided for you.)

---

**Where this leaves things**: full functional plan (`00`–`11`) and full visual plan (`v2/00`–`08`) both exist and agree with each other. The gap between "spec'd" and "shipped" is now the whole remaining project — I'd suggest starting with step 2 above (the design-system foundation in code) since it's immediately buildable, touches every future screen, and is the same scope of work as the auth-screen implementation already done. Say the word and I'll start there, or point me at a different piece.
