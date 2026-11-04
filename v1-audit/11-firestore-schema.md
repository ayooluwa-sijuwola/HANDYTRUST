# Part 11 — Firestore: Complete Schema

Every collection confirmed by direct reading of `firestore.rules` (the ground truth for what collections the app is *designed* to have) cross-checked against actual write sites in the service layer and Cloud Functions.

## `users/{uid}`
Account profile. Key fields (from `UserModel` and confirmed write sites): `name`, `email`, `roles: string[]`, `activeRole`, `location?`, `username?`, `isAvailable?` (also mirrored onto `artisans` for artisan accounts), `notificationsEnabled: bool`, `accountStatus` (admin-write-only), `accountDeletionRequested?`. Owner/admin read only.
- **Subcollection**: `favorites/{artisanId}` — doc ID == artisanId, owner-only.

## `artisans/{uid}`
Public artisan profile. Fields include `category`, `skills`, `bio`, business info, `approvalStatus`, `verificationStatus`, `rating`, `totalRatings`, `completedJobs`, `totalJobs`, `cancelledJobsCount`, `cancellationRatePercent`, `openDisputeCount`, `responseTimeMinutes` (hardcoded `30.0` at creation, never updated by any confirmed write path — Part 4), `trustScore` (Cloud-Function-computed only, client writes blocked by rules), `isAvailable`, `portfolioImageUrls: string[]`. Public read gated to `approvalStatus: 'approved'` + `verificationStatus in ['id_verified','trusted']`; owner can write most fields but is explicitly blocked from writing the server-managed ones listed above.

## `artisan_private/{uid}`
Bank details and private ID data. Fields: `bankName` (display string, not a Paystack code — Part 4/8), `accountName`, `accountNumber`, and — added by the most recent Cloud Functions work — `paystackRecipientCode` (cached Transfer Recipient ID, written by the payout function via Admin SDK, not client-writable in practice though the rule itself allows owner write). Owner/admin only.

## `jobs/{jobId}`
The core entity — by far the largest field set in the schema. Confirmed fields: `customerId`, `artisanId`, `category`, `description`, `imageUrls`, `completionImageUrls`, `beforePhotoUrls`, `status`, `agreedAmount`, `paymentReference`, `disputeReason`, `disputeResolution`, `disputeWindowEndsAt`, `artisanNotes`, `customerLat`/`customerLng`/`customerAddress`, `budgetMin`/`budgetMax`, `urgency`, `scheduledDate`, `createdAt`/`matchedAt`/`escrowLockedAt`/`startedAt`/`submittedAt`/`completedAt`/`autoReleaseAt`, `appointmentSlots: Timestamp[]`, `confirmedAppointment`, `progressStage`, `progressUpdatedAt`, `cancelledBy`/`cancellationReason`/`cancelledAt`, `aiSuggestion` (a map, set only if the customer accepted the Gemini job-description suggestion at posting time), `lastUpdatedAt`/`lastUpdatedBy`/`updateVersion` (server-stamped consistency fields on every write). **Added by the most recent work in this codebase**: `agreementStatus`, `agreementScope`, `agreementConfirmedByCustomer`/`agreementConfirmedByArtisan` (bool), `agreementCustomerConfirmedAt`/`agreementArtisanConfirmedAt`, `agreementChangesRequestedReason`, `agreementUpdatedAt` — all optional, absent on any job predating this feature.
- **`auditLogs/{logId}`** — immutable (no update/delete, ever), server-written inside every `JobService` transaction. Also queryable cross-job via `collectionGroup('auditLogs')` for admin.
- **`messages/{msgId}`** — the chat thread (Part 9). Doc-ID-less (auto-generated), fields per `MessageModel`: `senderId`, `receiverId`, `text`, `type`, `imageUrl?`, `proposedAmount?`, `isRead`, `createdAt`.
- **`quotes/{quoteId}`** — doc ID == artisanId (Part 7). Fields per `QuoteModel` as listed there.

## `payments/{paymentId}`
`jobId`, `payerId`, `artisanId`, `amount`, `status` (`pending → escrowHeld → released`, or `failed`), `paystackReference`, `paystackAccessCode?`, `authorizationUrl?`, `createdAt`, `paidAt?`, `releasedAt?`. Payer/artisan/admin read; admin-only update.

## `reviews/{reviewId}`
`jobId`, `customerId`, `artisanId`, `rating` (1–5 int), `comment?`, `createdAt`. Create restricted to the job's customer, on a `completed` job only, one review per completed job (not structurally enforced by doc ID the way quotes are — enforced only by the create rule's conditions). No update permitted; admin delete only.

## `disputes/{disputeId}`
`jobId`, `raisedBy` (always the customer — Part 6), `againstUserId`, `reason`, `evidenceImageUrls`, `status` (`open → resolved`/`dismissed`), `artisanResponseText?`/`artisanEvidenceUrls?`/`artisanRespondedAt?` (the against-party's one-shot response), `resolution?`, `adminNote?`, `resolvedAt?`.

## `verifications/{uid}`
Selfie/ID submission tracking. `status` (`unverified`/`id_submitted`/`pending_later`/`id_verified`/`rejected`/`trusted`, inferred from the verification-status vocabulary used elsewhere), submission timestamps. Owner/admin read; owner create; owner update only while `rejected`/`pending_later` (resubmission window); admin update freely.

## `portfolio_analytics/{artisanId}`
One doc per artisan, `viewCount` — incremented by any signed-in viewer, read restricted to owner/admin (so an artisan can see their own view count but a customer browsing can't see how popular a profile is).

## `fcm_tokens/{uid}`
`token`, `updatedAt`. Write-only by the owning user — **no client read permission exists at all**, by design (only Cloud Functions, via Admin SDK, ever read tokens to send pushes).

## `escrow_releases/{id}`
Confirmed original fields: `jobId`, `requestedAt`, `status`, `requestedBy`. **Expanded significantly by the most recent Cloud Functions work**: `status` now spans `pending → processing → completed`/`failed`, plus `failureReason` (a specific string per failure cause: `no_bank_details`, `unknown_bank:*`, `account_verification_failed:*`, `recipient_creation_failed`, `paystack_transfer_failed`, `paystack_transfer.failed`/`paystack_transfer.reversed`), `paystackRecipientCode`, `paystackTransferCode`, `paystackTransferReference`, `processedAt`, `reason` (set on the auto-release path). Read admin-only; create by the job's customer (the manual-confirm path) — the auto-release and Cloud-Function-driven writes happen via Admin SDK, which bypasses this rule entirely; client `update` is admin-only, meaning a client can never edit a release document post-creation.

## `admins/{uid}`
Existence-based admin registry — doc presence grants Firestore-rules-level admin. Admin-only read; **`allow write: if false` unconditionally** — no client, not even an existing admin, can create or delete an entry; provisioning is manual (Firebase CLI/Console) or via the `onAdminGranted`/`onAdminRevoked` Cloud Function triggers reacting to a doc that was created some other way.

## `config/{doc}`
App-wide config (Paystack public key, feature flags). Signed-in read, `allow write: if false`. A historical version of this document/collection's read pattern was flagged in prior analysis of this codebase as capable of exposing a secret key if one were ever placed there client-side-readable — the client code that would have read a secret from here has since been replaced with a Cloud-Functions-only path (Part 8/17), though the collection's broad-read rule shape itself is unchanged.

## `support_tickets/{ticketId}`
Owner/admin read; owner create; admin-only update (resolve).

## `notifications/{notifId}`
See Part 10 for the full field/type breakdown. `userId`, `type`, `title`, `body`, `isRead`, `readAt?`, `jobId?`, `createdAt`.

## `account_deletion_requests/{uid}`
`uid`, `status` (`pending`/`cancelled`, admin can set others), `requestedAt`. Owner/admin read; owner create/cancel while pending; admin update freely.

## `admin_audit_logs/{logId}`
Admin action trail — `adminId`, `action`, `timestamp`, and per-action detail fields. Admin-only read/create, immutable (no update/delete). **Two near-duplicate services both write to this collection** (`AdminAuditLogService` and `AdminAuditService`) — see Part 14 and Part 19.

## `portfolio_projects/{projectId}`
`artisanId`, title, description, image URLs, `createdAt`. Public read (signed-in), owner-artisan-only write.

## `admin_alerts/{id}` — real, actively written, but structurally unreadable by any client
Confirmed by direct reading of `functions/index.js`: written by `onDisputeCreated`, `_alertAdminDispute` (both dispute-related), and `reconcileStuckEscrowReleases` (stuck payout releases) — three separate write sites, all via Admin SDK. **`firestore.rules` has no `match` block for this collection at all** — grepped directly, zero results. Under Firestore's default-deny model, this means no client, including an authenticated admin using the Flutter admin dashboard, can read this collection today; only the Admin SDK (Cloud Functions, or manual Firebase Console access) can see its contents. This is the structural reason Part 5 found no admin UI consuming these alerts — one couldn't be built against the current rules without first adding a rule for this collection.

---

## Collections referenced only historically, not found as currently active
None found beyond what's listed above — every collection referenced in `firestore.rules` has at least one confirmed write site in the application code, and every collection with a confirmed write site (including `admin_alerts`) is accounted for here. `config/paystack`'s historical secret-key-storage pattern (mentioned above) is the one instance of a *field-level* pattern that's no longer exercised by any current client code path, without the collection itself being unused.
