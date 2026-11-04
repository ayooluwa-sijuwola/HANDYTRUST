# Part 19 — Dead Code

Confidence marked per item — 🟢 confirmed by direct grep/read during this audit pass, 🟡 carried forward from this codebase's own prior established analysis, not independently re-verified line-by-line here.

## Unused/unreachable screens
🟢 `phone_login_screen.dart`, `customer_registration_screen.dart` — fully built, confirmed by grep to be imported nowhere and by direct reading of `router.dart` to have no route. Genuinely dead, not just under-linked.

## Unused/duplicate services
🟢 `EscrowService` (`escrow_service.dart`) — a full second job-state-machine implementation, confirmed still present, confirmed by grep to be used exclusively by `demo_payment_provider.dart` (the demo path). Not touched by any production payment flow.
🟢 `DemoEscrowService`, `PaymentService.simulatePayment` — confirmed present, both explicitly demo/legacy paths per their own code comments, both still reachable (`/demo-payment/:jobId` remains an active, ungated route).
🟡 `AdminAuditLogService` vs. `AdminAuditService` — two services writing to the same `admin_audit_logs` collection with equivalent `log()` signatures. Both confirmed to still exist as files (glob); which call sites use which was not individually re-traced for every consumer in this pass.
🟡 `lib/firebase/auth/` (`AuthRepository`, `FirebaseAuthService`) and `lib/firebase/firestore/` (`FirestoreRepository`) — a second, parallel abstraction layer alongside the actively-used `lib/core/services/*`. Confirmed to exist as files; their actual call-site usage was not re-grepped fresh in this pass, carried forward from this codebase's own prior analysis, which found them largely unused in favor of the `core/services` layer.

## Unused dependency
🟡 `google_fonts` — declared in `pubspec.yaml`; the theme hardcodes the literal string `'Inter'` rather than calling `GoogleFonts.inter()` anywhere, per prior analysis of this codebase. Not independently re-grepped for this specific pass.

## Duplicate widgets
🟢 `JobProgressTracker`, `JobTimelineWidget`, `JobProgressTimeline` — confirmed by direct reading of `job_detail_screen.dart` to all three render on the same screen simultaneously, never consolidated into one component despite this being identified as overdue in this codebase's own prior design-system analysis.
🟡 `app_snackbars.dart` / `error_snackbar.dart` — two snackbar helpers with overlapping responsibility, per prior analysis of this codebase; both confirmed to still exist as files, not independently re-traced for every call site in this pass.

## A collection that's effectively "dead" from the client's perspective, though actively written
🟢 `admin_alerts` — written by three Cloud Functions (`onDisputeCreated`, `_alertAdminDispute`, `reconcileStuckEscrowReleases`), but has zero `firestore.rules` coverage (grepped directly, no match) — under Firestore's default-deny model, no client, including an authenticated admin, can read it. Functionally dead from the app's point of view despite being live-written server-side. See Part 11/12.

## Provider-layer duplication (Part 13)
🟢 `simulatePaymentProvider` (in `payment_provider.dart`) and the entire `demo_payment_provider.dart` file exist alongside the real `customerPaymentsProvider`/`artisanPaymentsProvider` — confirmed by direct grep of provider declarations, not carried forward.

## What is *not* dead, despite superficially looking like it might be
- `EscrowNotifier`'s naming (in `escrow_provider.dart`) suggests escrow-specific scope but actually owns every job-lifecycle mutation, confirmed by direct reading (Part 6/13) — this is a naming/discoverability issue, not dead code.
- The two-file job-provider split (`job_provider.dart` holding only `jobRequestNotifierProvider`, `escrow_provider.dart` holding the actual job streams) is confusing but both files are actively used, confirmed by grep — neither is dead.
