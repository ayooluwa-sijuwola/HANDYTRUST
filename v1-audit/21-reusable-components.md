# Part 21 — Reusable Components

Code good enough to carry into V2 largely unchanged. The inverse of Part 20 — same codebase, the parts that hold up.

## Services / patterns
- **`JobService`'s transactional-write-plus-atomic-audit-log pattern** — the single strongest piece of engineering in this codebase. Every mutation validated against a real state machine, every write audit-logged in the same transaction, consistency fields stamped automatically. This is the template every other write-heavy service should have followed (Part 20 notes where that didn't happen) — reuse the *pattern* even where individual duplicate services built around it should not survive.
- **`safeStream`/`safeDocStream`** (`lib/core/utils/safe_firestore.dart`) — normalizes Firestore stream errors so a `StreamProvider` never gets permanently stuck. Small, general-purpose, no reason to rewrite.
- **`AuthService.userProfileStream`'s self-healing pattern** — recovering a missing `/users/{uid}` doc rather than surfacing a permanent null. A good defensive pattern against the exact non-atomic-signup gap Part 2 names as debt; worth keeping the mitigation even while fixing the root cause in V2.
- **Field-diff rules technique** (`request.resource.data.diff(resource.data).affectedKeys().hasOnly([...])`) — used consistently and correctly throughout `firestore.rules` for narrow, single-purpose partial updates. A genuinely good Firestore-rules idiom, reusable as-is.
- **The pure-predicate-plus-transaction split** in the newest `JobService` methods (`canConfirmAgreement`/`canRespondToAgreement`/`canInitPayment` as standalone functions the transaction methods call) — this is what made the Agreement Confirmation feature's unit tests possible without any Firestore mocking infrastructure. Worth adopting as the standard shape for any future business-rule-gated mutation.

## Design system / UI
- **`AppColorsExtension` + `context.colors`** (`ThemeExtension` pattern) — correct, idiomatic Flutter theming with working dark-mode `lerp()`. No architectural change needed.
- **`AppSpacing`/`AppRadius`/`AppShadows`/`AppAnimations`** token sets — a real, disciplined design-token system (per this codebase's own design-system analysis), not ad-hoc magic numbers scattered per screen.
- **The shared auth-scaffold widgets** (`AuthLogoBadge`, `AuthCard`, `AuthFieldLabel`, `SocialSignInRow`, `AuthDivider`, `AuthFooter`) — built in the most recent work specifically to avoid duplicating the same card/logo/social-row styling across login/signup/forgot-password; a good small instance of "one canonical widget per concept."
- **`shimmer_loaders.dart`** — a working loading-skeleton system already covering the app's major list types.

## Utilities
- **`StorageService`** — size limits, retry-with-backoff on `getDownloadURL()`, per-purpose upload methods (job/profile/verification/portfolio/dispute). Solid, no rewrite needed.
- **Image compression thresholds** applied consistently across every upload path (chat 500KB, avatar 600KB, portfolio/verification 800KB) — a real, working discipline worth preserving as a named constant set rather than re-deriving.

## Models
- **`JobModel`/`QuoteModel`/`AuditLogModel`** — clean, hand-written `fromJson`/`toJson`, defensive null-handling on every field (`?? default` throughout), the kind of care that would otherwise be handled by a codegen package (`freezed`/`json_serializable`, neither of which this codebase uses) but is done correctly by hand here.

## What's reusable as a *concept* even where the code itself needs rework
Trust Score's 5-factor weighted formula (Part 4/18) is conceptually sound — the problem is one frozen input and a ranking consumer that ignores it, not the formula's design. The Agreement Confirmation checkpoint's state-machine shape (a sub-state within an existing status, not a new top-level status) is exactly the right instinct for extending `JobStatus` without destabilizing it, and should be the template for any future sub-state need.
