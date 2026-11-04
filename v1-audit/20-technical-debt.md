# Part 20 — Technical Debt

What should not be copied into V2 as-is, organized by category. Cross-references Parts 1–19 rather than re-deriving.

## Architecture
- **Two independent admin-authorization mechanisms** (Firestore-doc-based in `firestore.rules`, custom-claim-based in `storage.rules`), synced one-way by a Cloud Function trigger with an inherent propagation delay. V2 should collapse this to one mechanism, one grant flow.
- **No single canonical writer per collection, in three confirmed places**: escrow/payment (`JobService` vs. `EscrowService`/`DemoEscrowService`/`PaymentService`), admin audit logging (two services), and — structurally — the `lib/firebase/*` vs. `lib/core/services/*` parallel abstraction. `JobService` itself is the *correct* pattern (Part 21); the debt is everywhere that pattern wasn't followed.
- **A Firestore-writable collection with no rules coverage** (`admin_alerts`) — a gap that should have been caught by a rules-review pass before shipping the Cloud Functions that write to it.

## Patterns
- **Three separate, competing "how trustworthy/good is this artisan" formulas** in the same codebase: the real `trustScore` (server-computed, correct), `ArtisanModel.matchScore` (what ranking actually uses), and the Trust Score client-side display mirror. V2 should have exactly one.
- **A field that's set once and never updated again** (`responseTimeMinutes`, hardcoded `30.0` at registration) feeding a formula that assumes it's live data. This is a real instrumentation gap, not a formula bug — the formula is fine, its input is fake.
- **Data tracked but never consumed** (`cancelledJobsCount`/`cancellationRatePercent` computed on every job outcome, never read by the trust-score function that would plausibly want them).

## Performance
- **Client-side-only pagination in the admin dashboard** (`AdminDataTable`) — the full collection is read before the UI shows "page 1," confirmed directly. At any meaningful admin dataset size this is a real cost and latency problem, not a hypothetical one.

## Security
- **Storage read rules broader than the Firestore rules protecting the same logical content**, most seriously for dispute evidence (any signed-in user, not just dispute parties) and less seriously for job photos (Part 12).
- **`config`'s broad read rule with no structural separation of "safe" vs. "potentially sensitive" fields** — currently safe in practice (no secret is stored there), but the rule itself doesn't make that safety structural.
- **A Paystack bank-code table with unverified accuracy for newer fintech banks**, mitigated but not eliminated by an account-resolution safety check (Part 8) — V2 should either verify this table against Paystack's live bank list or fetch bank codes dynamically rather than maintaining a static guess.

## Code duplication
Covered fully in Part 19 — three services duplicating the payment/escrow write path, two admin-audit-log services, three job-timeline widgets, two snackbar helpers, two auth/Firestore abstraction layers.

## Navigation
- **Two independent entry points to payment on the same job** (Job Detail's action button, chat's app-bar button) with no shared pre-check — both eventually hit the correct backend gate, but a user can walk further into a blocked flow than necessary before discovering it (Part 6/9/16).
- **Confusingly-named provider files** (`job_provider.dart` vs. `escrow_provider.dart` actually owning the job streams) — a real discoverability cost for anyone extending this codebase, confirmed by direct inspection, not a guess.

## Data models
- **No milestone/material-payment concept at all** — every escrow feature in this codebase (deposit, lock, release, payout) operates on a single whole-job amount. V2's data model should decide this deliberately rather than bolt it on later, since it touches the job schema, the payments schema, and the escrow-release schema simultaneously.
- **`jobs` is a very wide document** (Part 11 lists ~35+ fields including the newest agreement-confirmation additions) — every job-lifecycle feature added a few more optional fields to the same document rather than ever introducing a subcollection for phase-specific data. This has worked because Firestore documents are cheap and the field-diff rules pattern scales to it, but it's worth naming as a real design choice with a real ceiling, not a free lunch.

## What should be kept exactly as a *pattern*, even where individual pieces need work (see Part 21 for the positive case)
The transactional-write-plus-atomic-audit-log pattern in `JobService`, the field-diff rules technique, and the `safeStream`/`safeDocStream` error-normalization helpers are all genuinely good engineering that happened to sit inside a codebase with the debt listed above — the debt is in *inconsistent application* of good patterns, not in the patterns themselves.
