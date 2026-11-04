# Final User Journey Audit — Group 11, Task 1

Both journeys traced end to end from source (screens, services, Firestore collections, Cloud Functions) — not inferred from memory of earlier sessions. Every row below was re-verified against the current codebase during this pass. No screens were redesigned to produce this document.

Legend: ✅ working and verified · ⚠️ working with a caveat (documented) · 🚧 real gap, not blocking the core path

---

## Customer journey

| Stage | Screen | Service | Firestore collection | Cloud Function | Status | Blockers / notes |
|---|---|---|---|---|---|---|
| Register | `register_screen.dart` | `AuthService.signUp` | `users/{uid}` | none (client write) | ✅ | Email verification is enforced next via router redirect, not a blocker in itself. |
| Login | `login_screen.dart` | `AuthService.signIn` | `users/{uid}` (profile read) | none | ✅ | |
| Post Job | `service_request_screen.dart` | `JobRequestNotifier` | `jobs/{jobId}` (create) + Storage `jobs/{jobId}/{uid}/` | none | ✅ | Images uploaded client-side; failed individual image uploads don't block job creation (existing partial-failure handling, confirmed in Group 3). |
| Receive Quotes | `open_jobs_feed_screen.dart` (artisan side) → `_QuoteInboxSection` (customer side) | `QuoteService.submitQuote` | `jobs/{jobId}/quotes/{artisanId}` | none | ⚠️ | `quote_received` notification is written **client-side** by `QuoteService`, not by a Firestore-trigger Cloud Function (unlike job-status events, unified onto Cloud Functions in Group 9). If the client crashes after the quote write but before the notification call, the quote still exists but the customer isn't notified. Real, narrow, non-blocking — see Task 4 below. |
| Chat | `chat_screen.dart` | `ChatService`/`ChatNotifier` | `jobs/{jobId}/messages/{msgId}` | `onNotificationCreated` (push, for messages that write a notification doc) | ✅ | Redesigned Group 6. |
| Agreement Confirmation | `_AgreementSection` in `job_detail_screen.dart` | `JobService.confirmAgreementAsCustomer` / `acceptAgreementAsArtisan` / `requestAgreementChanges` | `jobs/{jobId}` (`agreementStatus`) | none | ✅ | Pure predicates (`canConfirmAgreement`/`canRespondToAgreement`) unit-tested. |
| Schedule | `_AppointmentSection` | `JobService.proposeAppointmentSlots` / `confirmAppointmentSlot` | `jobs/{jobId}` (`appointmentSlots`, `confirmedAppointment`, `schedulingStatus`) | none | ✅ | Skipped entirely for `urgency == 'asap'` jobs by design (`schedulingSatisfied`). |
| Lock Escrow | `payment_screen.dart` → `payment_webview_screen.dart` | `JobService.initPayment` → Paystack → `paystackWebhook` → `_lockEscrow` | `jobs/{jobId}` (`escrowLocked`, `escrowLockedAt`) + `payments/{id}` (`escrowHeld`) | `paystackWebhook` | ✅ | Redesigned Group 7; escrow-education content added. |
| Track Work | `WorkflowTimeline`/`WorkflowStatusCard` in `job_detail_screen.dart` | `JobService.startWork`, `updateJobProgress` | `jobs/{jobId}` (`inProgress`, `progressStage`) | none | ✅ | |
| Completion (submitted) | `job_detail_screen.dart` (artisan submit flow) | `JobService.submitCompletion` | `jobs/{jobId}` (`submitted`, `submittedAt`, `disputeWindowEndsAt`, `autoReleaseAt`) | `onJobCompleted` → `_sendNotification('submitted')` | ✅ | `disputeWindowEndsAt`/`autoReleaseAt` now guaranteed identical (fixed in the escrow-timing pass between Groups 7–8). |
| Dispute Window | `_DisputeCountdownBanner` | — (read-only display) | `jobs/{jobId}.disputeWindowEndsAt` | `autoReleaseEscrow` (hourly cron, reads `autoReleaseAt`) | ✅ | The two fields the banner shows and the cron reads are the same value now — previously the root cause of the escrow timing bug, confirmed fixed. |
| Release Payment | `job_detail_screen.dart` (confirm button) or automatic | `JobService.confirmComplete` OR `autoReleaseEscrow` → `_releaseEscrow` → `processEscrowRelease` | `jobs/{jobId}` (`completed`), `payments/{id}` (`released`), `escrow_releases/{id}` | `autoReleaseEscrow`, `processEscrowRelease`, `paystackWebhook` (transfer webhook) | ✅ | Real Paystack Transfer, not a status-flip-only "release" — verified in Group 7/8. |
| Review | `review_screen.dart` | review write + rating transaction on `artisans/{uid}` | `reviews/{id}` | `onArtisanRatingChanged` (trust score recompute) | ✅ | Gated to `job.status == 'completed'` by `firestore.rules`. |

---

## Artisan journey

| Stage | Screen | Service | Firestore collection | Cloud Function | Status | Blockers / notes |
|---|---|---|---|---|---|---|
| Register | `register_screen.dart` (role picker) | `AuthService.signUp` | `users/{uid}` | none | ✅ | |
| Verification | `verification_upload_screen.dart` | `VerificationService` | `verifications/{uid}` + Storage `verifications/{uid}/` | `onArtisanVerificationChanged` (trust score recompute) | ✅ | |
| Approval | Admin: `_PendingArtisansTab`/`_ArtisanApplicationCard` | direct Firestore update (admin action) | `artisans/{uid}.approvalStatus` | none | ✅ | **Confirmed a genuinely separate gate from Verification** (different field, different admin tab) — both required for quoting eligibility (`isArtisanEligible()` in `firestore.rules` checks both). |
| Browse Jobs | `open_jobs_feed_screen.dart` | `openJobsFeedProvider` | `jobs` (query: `status == requested`, category) | none | ✅ | Redesigned Group 4; live eligibility banner if approval/verification incomplete. |
| Submit Quote | `_SubmitQuoteSheet` | `QuoteService.submitQuote` | `jobs/{jobId}/quotes/{artisanId}` | none | ✅ | Server-side `isArtisanEligible()` re-check in `firestore.rules` — a client-side-bypassed race can't actually write an ineligible quote. |
| Get Selected | `_QuoteInboxSection` (customer accepts) | `JobService.acceptQuote` | `jobs/{jobId}` (`matched`, `artisanId`) + quotes closed in the same transaction | none | ✅ | One transaction closes competing quotes — verified in original session work. |
| Chat / Agreement / Schedule | shared with customer journey | shared | shared | shared | ✅ | Same mechanisms, both parties. |
| Start Work | `job_detail_screen.dart` | `JobService.startWork` | `jobs/{jobId}` (`inProgress`) | `onJobCompleted` → `_sendNotification('escrowLocked')` fired one step earlier, at lock | ✅ | |
| Submit Completion | `job_detail_screen.dart` | `JobService.submitCompletion` | `jobs/{jobId}` (`submitted`) | `onJobCompleted` → `_sendNotification('submitted')` | ✅ | |
| Receive Payout | automatic | `processEscrowRelease` → Paystack Transfer | `escrow_releases/{id}`, `artisan_private/{uid}` (bank details, read-only) | `processEscrowRelease`, transfer webhook | ✅ | Fully automatic, no artisan-initiated "withdraw" step exists by design — see `design/STITCH_WALLET_AUDIT.md`. |
| Trust Score Update | Dashboard stat card / `TrustScoreCard` | `_recordJobOutcome`, `onArtisanRatingChanged`, `onArtisanVerificationChanged` | `artisans/{uid}.trustScore` | all three above | ✅ | Three independent triggers keep the score current on completion, new reviews, and verification changes — confirmed no gap between them. |

---

## Summary

Both journeys are **structurally complete, source-verified, no blocking gaps**. The one real (non-blocking) finding is the quote-notification's client-side-only write path — inconsistent with the server-triggered pattern the rest of the notification system now uses since Group 9, but not broken (quotes themselves are unaffected; only the notification could theoretically be missed on a client crash mid-flow). Documented as a Task 4 follow-up candidate, not fixed in this audit pass per "do not redesign" scope.
