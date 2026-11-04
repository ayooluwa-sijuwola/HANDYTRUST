# Part 22 — Rebuild Recommendation

Final classification. ✅ Reuse unchanged · 🟡 Refactor · 🟠 Rewrite · 🔴 Remove completely. Every entry states why, not just the label.

## ✅ Reuse unchanged
- **`JobService` and its state machine** — sound, transactional, audit-logged, correctly extended (not rewritten) by the Agreement Confirmation feature. No finding across all 22 parts argues for touching this.
- **`firestore.rules`' core patterns** (field-diff scoping, the `_isValidJobTransition` mirror of the Dart state machine, the pre-match chat isolation logic) — genuinely careful engineering, confirmed by direct reading, not just by reputation.
- **The design-token system** (`AppColorsExtension`, spacing/radius/shadow/animation tokens) — Part 21.
- **`safeStream`/`safeDocStream`, `StorageService`, the auth self-healing pattern** — small, correct, general-purpose.
- **Riverpod + GoRouter as the architecture** — nothing in this audit found either choice wanting; the problems found are inconsistent application (duplicate services, confusing file names), not the frameworks themselves.

## 🟡 Refactor
- **Escrow payout automation** — the logic is right, the shape is right, but it has never executed against a live transaction. Refactor here means: verify the Paystack bank-code table, run it against test-mode transfers, add the emulator/rules-testing infrastructure this codebase has none of (Part 20), then trust it — not rewrite it.
- **Trust Score → ranking** — `MatchingService` needs to read `trustScore` instead of `ArtisanModel.matchScore`. Small, surgical, high-value — explicitly *not* a rewrite candidate (Part 18).
- **`responseTimeMinutes` instrumentation** — add a real write path (e.g., on first quote/first chat reply); the formula consuming it is already correct.
- **Admin dashboard pagination** — move `AdminDataTable`'s data source to cursor-based Firestore queries; the table component and section structure don't need rebuilding.
- **Chat/Agreement Confirmation disconnect** — surface `agreementStatus` in the chat app bar and gate the "Pay Now" button on it; this is a UI read of a field that already exists, not new backend work.
- **Storage rules for dispute evidence and job photos** — narrow the read rule using the `firestore.get()` cross-service pattern this codebase already uses elsewhere in Firestore rules; doesn't require a Storage architecture change.
- **Notification system** — extend the existing 12-type whitelist with reminder classes and `dispute_resolved`; the delivery mechanism (Cloud-Functions-originated FCM + the in-app feed) doesn't need rebuilding.
- **Admin dual-authorization** — collapse to one grant flow (a single callable that sets both the Firestore doc and the custom claim atomically); the two underlying mechanisms don't both need to be rebuilt, just unified behind one entry point.

## 🟠 Rewrite
- **Milestone/material payment data model** — nothing to refactor because nothing exists; this is new architecture, not a fix to old architecture, and it touches the job schema, payment schema, and escrow-release schema simultaneously enough that it should be designed once, deliberately, rather than incrementally bolted onto the current single-payment model field by field.
- **Live GPS/location tracking** — same reasoning; zero existing code to build from beyond the one-time address capture, which should be kept as-is and left alone by whatever GPS system gets built.
- **Artisan discovery/ranking as a whole system** (not just the trust-score wiring fix above) — once trust score is wired in correctly, the broader question of geohash-bucketed distance queries vs. the current full-category-scan-plus-client-rank approach (Part 3/4) is worth a real rewrite once artisan density grows past what a `limit(100)` scan comfortably handles.
- **Mobile-native admin experience** — the current admin section is one desktop-shaped layout regardless of screen size; a genuine mobile admin experience (different information density, different primary actions) is a rewrite of that surface, not a responsive tweak to the existing one.

## 🔴 Remove completely
- **`EscrowService`, `DemoEscrowService`, `PaymentService.simulatePayment`, and the entire `/demo-payment/:jobId` route** — three historical duplicate write paths plus an ungated demo screen reachable in production. Delete outright once the demo flow (if still wanted at all) is rebuilt behind an explicit debug/staging-only gate.
- **`phone_login_screen.dart`, `customer_registration_screen.dart`** — dead code, pending only the product decision of whether phone auth is wanted at all in V2; if yes, rebuild it deliberately rather than resurrecting the unrouted screen as-is (it was never verified working end-to-end, having never been reachable).
- **`lib/firebase/auth/` and `lib/firebase/firestore/`** — the parallel, largely-unused abstraction layer alongside `lib/core/services/*`. Carrying two mental models of the same responsibility into V2 serves no one.
- **One of the two admin-audit-log services** — keep whichever is actually canonical (not conclusively determined by this pass, per Part 14/19 — worth a final grep-every-call-site pass before deletion), remove the other.
- **The consolidatable duplicates**: one of the three job-timeline widgets (merge into one), one of the two snackbar helpers (merge into one).
- **`google_fonts` dependency** — declared, never used; remove rather than leave as a foot-gun for a future contributor who reaches for it instead of the deliberately-bundled offline-safe `Inter` asset.

---

## The one-paragraph summary
This is not a codebase that needs to be thrown away — the core transactional architecture (`JobService`, the rules mirroring it, the audit-log discipline) is genuinely well-built and should anchor V2 directly. What needs real new work is narrow and identifiable: milestone payments and live GPS don't exist at all and need designing from scratch; escrow payout automation exists but has never been proven against a real transaction; trust score is computed correctly but isn't consulted by the one place that should consult it. Everything else — the duplicate services, the two admin-auth mechanisms, the unrouted dead screens, the client-side-only admin pagination — is real, confirmed debt, but it's debt with a clear, bounded fix, not a reason to rebuild what's already working.
