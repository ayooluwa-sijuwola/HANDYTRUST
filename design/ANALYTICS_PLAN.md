# Analytics Readiness Plan

Audit + plan only. No `firebase_analytics` (or any analytics package) exists in `pubspec.yaml` today — confirmed by the same dependency check as the Crashlytics plan. **No tracking calls added anywhere in this pass**, per instruction. This maps each requested event to its real, existing trigger point in the codebase, so implementation later is a matter of inserting one call per site, not re-discovering where things happen.

## Why this matters for HandyTrust specifically
The events requested split cleanly along the two journeys already documented in `design/FINAL_USER_JOURNEY_AUDIT.md` — this plan is deliberately structured to mirror that document rather than invent a separate taxonomy.

---

## Authentication

| Event | Real trigger point |
|---|---|
| `signup_completed` | `RegisterScreen._register`, after `authNotifierProvider.signUp` returns success (not on tap — only once the account genuinely exists) |
| `login_success` | `LoginScreen._signIn`, after `authNotifierProvider.signIn` returns `true` |

## Marketplace

| Event | Real trigger point |
|---|---|
| `job_created` | `ServiceRequestScreen._submitRequest`, after `jobRequestNotifierProvider.submitRequest` reaches `state.success` |
| `quote_submitted` | `_SubmitQuoteSheetState._submit` in `open_jobs_feed_screen.dart`, after `quoteServiceProvider.submitQuote` succeeds |
| `quote_accepted` | `_QuoteInboxSectionState._accept` in `job_detail_screen.dart`, after `quoteServiceProvider.acceptQuote` succeeds |

## Money

| Event | Real trigger point |
|---|---|
| `escrow_locked` | Ideally server-side, inside `_lockEscrow` (`functions/index.js`) right after the transaction commits — more reliable than a client-side event, since it fires exactly once regardless of which client (or none, if the app was closed when the webhook landed) triggered it. If client-side tracking is preferred for consistency with the other events in this table, the matching point is `PaymentWebviewScreen`'s `_onPaymentCallback` on `verified == true`. |
| `payment_completed` | Same call site as `escrow_locked` — HandyTrust's "payment" and "escrow lock" are the same moment (lump-sum escrow model, no separate "payment received before lock" state) — worth firing both events at that one point rather than searching for two distinct moments that don't exist. |
| `payout_completed` | `functions/index.js`'s `transfer.success` webhook handler (where `escrow_releases.status` becomes `'completed'`) — server-side, same reliability argument as `escrow_locked`. |

## Trust

| Event | Real trigger point |
|---|---|
| `verification_completed` | `VerificationService.approve` (fires once, server-authoritative — this is an admin action, so "completed" here means the admin's approval, not the artisan's document submission; if the intent is "artisan submitted for review" instead, the trigger point is `verification_upload_screen.dart`'s submit handler — worth confirming which of the two this event name is meant to mean before implementing, since they're different moments with different owners). |
| `dispute_created` | `JobService.raiseDisputeWithRecord`, after the transaction commits — or its call site in `job_detail_screen.dart`'s dispute-raising UI, if client-side tracking is preferred. |

---

## Implementation notes for when this is built (not now)

- **Client vs. server-side firing**: three of the eight events above (`escrow_locked`, `payment_completed`, `payout_completed`) have a materially more reliable trigger point in Cloud Functions than on the client — money events happening exactly once, server-side, regardless of app state, is worth the small added complexity of using the Firebase Admin SDK's server-side analytics logging (or a Firestore-triggered function that logs the event) rather than trusting a client to still be open at the right moment. This is a real design decision to make at implementation time, not before.
- **PII**: none of the 8 events need to carry personal data (email, phone, bank details) as parameters — job category, amount (already not PII on its own), and status are enough for each. Worth setting this as a stated rule before implementation, not discovering it after the first event ships with something it shouldn't carry.
- **No tracking added in this pass** — this document is the map, not the implementation.
