# HandyTrust Billing Dependency Audit

Read-only investigation. No code, rules, or billing plan changed. Confirms and extends two prior findings in this project: `design/STORAGE_UPLOAD_ROOT_CAUSE.md` (Storage never provisioned) and `design/ADMIN_DELETE_USER_ROOT_CAUSE.md` (zero Cloud Functions deployed; `handytrust` is on the Spark plan, which cannot host 2nd-gen Cloud Functions).

## Method

- Read every one of the 15 exported functions in `functions/index.js` in full (not summarized) to determine exactly what each does, what triggers it, and what it writes.
- For every client-side feature that calls a Cloud Function (`httpsCallable`) or touches Storage (`StorageService`), read the calling code to determine whether a fallback exists, whether the failure is silent or surfaced, and whether it's gated to debug builds only.
- Re-confirmed deployment status: `firebase functions:list` → "No functions found in project handytrust." Re-confirmed project/billing: a scoped `firebase deploy --only functions:adminDeleteUser` attempt failed with "Your project handytrust must be on the Blaze (pay-as-you-go) plan..." Storage confirmed never provisioned (`design/STORAGE_UPLOAD_ROOT_CAUSE.md`, independently re-verified this session's `firebase deploy --only storage` history).
- Did not assume a feature works because client code exists — traced each one to its actual backend dependency and, where deployment could be checked, checked it.

---

## Feature-by-feature inventory

### 1. Delete User (Admin)
- **Feature:** Admin → Users → Delete
- **Firebase/Google service:** Cloud Functions (`adminDeleteUser`, 2nd gen `onCall`)
- **Required plan:** Blaze
- **Current implementation:** Client calls the callable; function does real Firebase Auth deletion + Storage cleanup + audited Firestore cleanup. Client-side Firestore `delete` on `/users/{uid}` is rules-blocked (`allow delete: if false`) by deliberate design — no fallback exists or should exist.
- **Deployed/available:** No (confirmed via `functions:list` and a direct deploy attempt)
- **Blocked:** Yes, completely
- **User impact:** Admin cannot delete any user account. Error handling was fixed separately (see `design/ADMIN_DELETE_USER_ROOT_CAUSE.md`) so the failure is now reported cleanly instead of leaking internals — the action itself still doesn't work.
- **Production importance:** Required for GDPR/NDPR-style data-deletion requests and abuse response.
- **P0/P1/P2:** **P0**

### 2. Payment Initiation (Customer pays for a job)
- **Feature:** Post-agreement "Pay Now" → Paystack checkout
- **Firebase/Google service:** Cloud Functions (`initializePaystackTransaction`, `onCall`), Paystack API
- **Required plan:** Blaze (for the function) + a live Paystack secret key
- **Current implementation:** `PaystackService.initializeTransaction()` calls the callable. On failure, `payment_screen.dart` branches on `kDebugMode`: in a **debug build**, it silently falls back to `DemoEscrowScreen`, a fully client-side simulated payment (no real money, explicitly commented as dev-only). In a **release build** (i.e., real production), the fallback is deliberately disabled — the error is surfaced as inline text (`'Payment could not be started: $e'`, itself leaking the raw exception, similar in kind to the delete-user bug though not in scope to fix here) and payment cannot proceed.
- **Deployed/available:** No
- **Blocked:** Yes, completely, in production. (Only "works" via the debug-only simulated fallback, which is explicitly not real.)
- **User impact:** No customer can pay for a job in the deployed app today. This is upstream of everything else in the payment/escrow chain.
- **Production importance:** Core monetization path — the entire business model depends on this.
- **P0/P1/P2:** **P0**

### 3. Payment Verification / Escrow Lock (post-checkout)
- **Feature:** Confirming a Paystack charge succeeded and locking funds in escrow
- **Firebase/Google service:** Cloud Functions (`verifyPayment` callable **and** `paystackWebhook` `onRequest`, both call the same `_lockEscrow` helper)
- **Required plan:** Blaze
- **Current implementation:** Two independent paths, both server-side only, both undeployed. `payment_webview_screen.dart` calls `verifyPayment` after the Paystack redirect; Paystack's own `charge.success` webhook independently calls the same lock logic (belt-and-suspenders design — whichever fires first wins). Since #2 above already blocks payment initiation in production, this is currently unreachable either way.
- **Deployed/available:** No
- **Blocked:** Yes, completely
- **User impact:** Even if a payment were somehow initiated, there is no way for the app to learn it succeeded.
- **Production importance:** Core to the escrow trust model this app is built around.
- **P0/P1/P2:** **P0**

### 4. Escrow Payout (paying the artisan)
- **Feature:** Real money transfer to an artisan's bank account after job completion
- **Firebase/Google service:** Cloud Functions (`processEscrowRelease`, Firestore-triggered on `escrow_releases/{id}` creation), Paystack Transfer API
- **Required plan:** Blaze
- **Current implementation:** The client (`JobService.confirmComplete`) **does** successfully write the `escrow_releases` document and flip the job to `completed` — that part is a pure Firestore write and works fine. But per this function's own source comment: *"Without this function, 'released' was only ever a Firestore status flip — no money moved."* It's a Firestore trigger, not a callable, so there is categorically no client-side way to invoke or simulate it.
- **Deployed/available:** No
- **Blocked:** Yes, completely — and **silently**. The job UI will show "completed"/"payment released" language with no error, while the artisan's `escrow_releases` document sits in `pending` status forever and no money moves. This is the most dangerous blocked feature in the app precisely because nothing visibly fails.
- **User impact:** Artisans are never actually paid, with no error surfaced to anyone.
- **Production importance:** This is the other half of the core escrow promise — money must actually move for the trust model to mean anything.
- **P0/P1/P2:** **P0**

### 5. Auto-Release Escrow (14-day no-response safety net)
- **Feature:** Automatically release escrow if a customer doesn't respond within 14 days of work submission
- **Firebase/Google service:** Cloud Functions (`autoReleaseEscrow`, `onSchedule`, hourly)
- **Required plan:** Blaze
- **Current implementation:** Scheduled function; no client equivalent is possible (nothing runs when the app isn't open).
- **Deployed/available:** No
- **Blocked:** Yes, completely
- **User impact:** An artisan whose customer goes silent has no automatic protection — they'd need a working #4 (payout) to ever get paid regardless, so this compounds on top of an already-blocked feature.
- **Production importance:** Important safety net, but moot until #4 works.
- **P0/P1/P2:** **P1** (P0 once #4 is restored)

### 6. Stuck-Release Reconciliation
- **Feature:** Daily sweep flagging any payout stuck in `pending`/`processing` for 2+ hours
- **Firebase/Google service:** Cloud Functions (`reconcileStuckEscrowReleases`, `onSchedule`, daily)
- **Required plan:** Blaze
- **Current implementation:** Writes to `admin_alerts`, which the Admin Dashboard's "Operational Alerts" card reads.
- **Deployed/available:** No
- **Blocked:** Yes
- **User impact:** None directly visible to end users; admin loses the automated backstop, but see #4 — nothing is actually processing payouts to get stuck in the first place right now.
- **Production importance:** Operational safety net, not user-facing.
- **P0/P1/P2:** **P2**

### 7. Push Notification Delivery (FCM send)
- **Feature:** Actually delivering a push notification to a user's device/browser
- **Firebase/Google service:** Cloud Functions (`onNotificationCreated`, Firestore-triggered), Firebase Cloud Messaging (FCM itself is free on Spark — only the *trigger that calls it* is blocked)
- **Required plan:** Blaze (for the trigger function)
- **Current implementation:** FCM token registration (`local_notification_service.dart`) works fine client-side — tokens are saved. But the only thing that ever calls `messaging.send()` is this one Cloud Function, reacting to any new `notifications/{id}` document. Undeployed → zero pushes ever sent, regardless of notification type or how the in-app document was created.
- **Deployed/available:** No
- **Blocked:** Yes, completely — for **every** notification type
- **User impact:** No user ever receives a push notification (new message, quote, dispute, payment event, anything) unless they have the app open and are actively watching the in-app list.
- **Production importance:** Materially degrades engagement/responsiveness (e.g. artisans not knowing about a new job in time), but the in-app record still exists for several types (see #8) so it's not full data loss.
- **P0/P1/P2:** **P1**

### 8. In-App Notification Creation — mixed
- **Feature:** The `notifications` documents that back the bell icon / Notifications screen
- **Firebase/Google service:** Split — most types are pure client-side Firestore writes (`NotificationService.send()`, called directly by `dispute_service.dart`, `quote_service.dart`, `verification_service.dart`, `escrow_provider.dart` (agreement-flow notices), `review_screen.dart`); job-lifecycle-status types (escrow locked, work submitted, payment released, dispute-from-status-change) are written **only** by the Cloud Function `_sendNotification`, called from the undeployed `onJobCompleted`/`_lockEscrow`.
- **Required plan:** None for the client-written subset; Blaze for the job-lifecycle subset
- **Current implementation:** See above — this is not one feature but two, sharing one collection.
- **Deployed/available:** Partially — client-write paths work; server-only types don't exist at all right now.
- **Blocked:** Partially. Quote/dispute/verification/review notifications work today. Escrow-locked, work-submitted, and payment-released in-app notifications are never created (on top of #7's push-delivery gap on top of that).
- **User impact:** Users see some but not all lifecycle events reflected in their notification list; the missing subset happens to be exactly the payment-related ones.
- **Production importance:** Meaningful gap in a marketplace where "did my payment go through" is a top user question.
- **P0/P1/P2:** **P1**

### 9. Job Photo Upload (required for job posting)
- **Feature:** Attaching photos when posting a new job — currently a **required** field, blocking job creation entirely
- **Firebase/Google service:** Firebase Storage
- **Required plan:** Blaze (current Firebase policy requires Blaze to provision a new Storage bucket)
- **Current implementation:** `StorageService.uploadJobImageBytes()` → fails identically to every other Storage call (see `design/STORAGE_UPLOAD_ROOT_CAUSE.md` — the bucket itself was never provisioned, independent of and in addition to the Spark-plan constraint).
- **Deployed/available:** No — no bucket exists at all
- **Blocked:** Yes, completely, and it blocks something else too: **no new job can be created**, since a photo is required.
- **User impact:** Customers cannot post new jobs at all in the current environment.
- **Production importance:** This is the literal top of the funnel — nothing else in the app matters if this doesn't work.
- **P0/P1/P2:** **P0**

### 10. Profile Photo Upload
- **Feature:** Setting a profile picture (customer or artisan)
- **Firebase/Google service:** Firebase Storage
- **Required plan:** Blaze
- **Current implementation:** `StorageService.uploadProfilePhoto()`, same failure mode as #9.
- **Deployed/available:** No
- **Blocked:** Yes
- **User impact:** Every user in the app renders as a colored-circle initial fallback — confirmed directly observed throughout this project's testing (no real photo has ever successfully uploaded).
- **Production importance:** Cosmetic/trust-signal, not functionally blocking.
- **P0/P1/P2:** **P2**

### 11. Verification Document Upload (ID + selfie)
- **Feature:** Artisan identity verification — selfie and government ID photo
- **Firebase/Google service:** Firebase Storage
- **Required plan:** Blaze
- **Current implementation:** `StorageService.uploadVerificationPhoto()`, same failure mode. Note: the *rest* of the verification flow (submitting for review, admin approve/reject, `verificationStatus` field, the Beta Tester bypass mechanism) is pure Firestore and works fine — only the document capture step is blocked.
- **Deployed/available:** No
- **Blocked:** Yes — an artisan literally cannot submit the documents needed to become verified
- **User impact:** No artisan can complete real verification. The existing Beta Tester admin toggle is the only way an unverified artisan can be marked eligible to quote today — a deliberate, documented, controlled workaround for testing, not a substitute for real verification at scale.
- **Production importance:** Verification is core to the "trust" in HandyTrust's trust model.
- **P0/P1/P2:** **P0**

### 12. Portfolio Image Upload
- **Feature:** Artisans showcasing past work photos
- **Firebase/Google service:** Firebase Storage
- **Required plan:** Blaze
- **Current implementation:** `StorageService.uploadPortfolioImage()`, same failure mode.
- **Deployed/available:** No
- **Blocked:** Yes
- **User impact:** No artisan can build a portfolio; customers can't see past work when choosing an artisan.
- **Production importance:** Meaningful trust/conversion signal, not launch-blocking on its own.
- **P0/P1/P2:** **P2**

### 13. Dispute Evidence Upload
- **Feature:** Attaching photos as evidence when raising or responding to a dispute
- **Firebase/Google service:** Firebase Storage
- **Required plan:** Blaze
- **Current implementation:** `StorageService.uploadDisputeEvidence()`, same failure mode. The rest of the dispute flow (raising, responding with text, admin resolve/dismiss) is pure Firestore and works.
- **Deployed/available:** No
- **Blocked:** Yes (photo attachment only)
- **User impact:** Disputes can still be raised and resolved on text alone; evidence photos can't be attached.
- **Production importance:** Reduces dispute-resolution quality but doesn't block the flow entirely.
- **P0/P1/P2:** **P1**

### 14. AI Job Assistant ("Analyze with AI")
- **Feature:** Suggests a job category and rewrites the description on Post a Job
- **Firebase/Google service:** Cloud Functions (`analyzeJob`, `onCall`), Google Generative AI (Gemini) API
- **Required plan:** Blaze (for the function) + a Gemini API key/quota
- **Current implementation:** `AiService.analyzeJob()` calls the callable. Unlike most other call sites in this app, this one already catches `FirebaseFunctionsException` specifically and maps it to a clean, pre-written user-facing message (`AiServiceException`) — good existing practice, worth noting as a positive example (this is the same pattern the delete-user fix now also uses).
- **Deployed/available:** No
- **Blocked:** Yes, completely
- **User impact:** The "Analyze with AI" button fails cleanly with a friendly message; job posting itself is unaffected (it's an optional enhancement, not a gate).
- **Production importance:** Nice-to-have, not core.
- **P0/P1/P2:** **P2**

### 15. Admin Custom-Claim Sync
- **Feature:** Keeping a Firebase Auth custom claim (`admin: true`) in sync with the `/admins/{uid}` Firestore doc
- **Firebase/Google service:** Cloud Functions (`onAdminGranted`/`onAdminRevoked`, Firestore-triggered)
- **Required plan:** Blaze
- **Current implementation:** `firestore.rules`' `isAdmin()` check reads the Firestore doc directly (not the claim) — this is why the Admin Dashboard itself is fully reachable and functional today despite this trigger being undeployed. `storage.rules`' `isAdmin()` check, per its own code comment, reads the **claim** instead. Since the claim-sync trigger never fires, that claim is never set for any admin.
- **Deployed/available:** No
- **Blocked:** Yes, but currently **inert** — Storage doesn't work at all yet (see #9-13), so no admin-only Storage operation has been exercised to reveal this compounding gap. It will surface as a second, independent blocker the moment Storage is provisioned but Functions still aren't deployed.
- **User impact:** None visible today; will become an admin-Storage-access bug later if Storage and Functions aren't fixed in the same pass.
- **Production importance:** Worth flagging now so it isn't mistaken for a new bug later.
- **P0/P1/P2:** **P2** (today) — re-evaluate if Storage is provisioned before Functions are deployed

### 16. Trust Score Live Recalculation
- **Feature:** Recomputing an artisan's trust score whenever their rating, verification status, or dispute count changes
- **Firebase/Google service:** Cloud Functions (`onArtisanRatingChanged`, `onArtisanVerificationChanged`, `onJobCompleted`, all Firestore-triggered)
- **Required plan:** Blaze
- **Current implementation:** The underlying fields (`rating`, `totalRatings`, `verificationStatus`, `completedJobs`) are written correctly by client-side services (`ReviewScreen`, `VerificationService`, etc.) — that data is accurate. Only the **derived** `trustScore` field's recalculation is server-side and blocked, so it goes stale the moment any of its five inputs change after the artisan document was last touched by something else that happens to also update it.
- **Deployed/available:** No
- **Blocked:** Yes, for the derived field specifically
- **User impact:** Trust scores shown in the app can silently drift out of sync with the real underlying rating/verification/completion data.
- **Production importance:** Undermines the specific "TrustScore" feature this app is named around.
- **P0/P1/P2:** **P1**

### 17. Dispute Admin Alerting
- **Feature:** Surfacing a newly-raised dispute as an "Operational Alert" / notification for admins
- **Firebase/Google service:** Cloud Functions (`onDisputeCreated`, `_alertAdminDispute` inside `onJobCompleted`, both Firestore-triggered)
- **Required plan:** Blaze
- **Current implementation:** Writes to `admin_alerts`. The **Disputes section itself** reads the `disputes` collection directly (`DisputeService.watchOpenDisputes()`, live Firestore query) and works fine independent of this — admins can and do see open disputes in the dedicated section. What's missing is only the proactive "Operational Alerts" card surfacing it before an admin thinks to check the Disputes tab.
- **Deployed/available:** No
- **Blocked:** Yes, for the alert-surfacing path only
- **User impact:** None for customers/artisans. Admins must actively check the Disputes section rather than being alerted; combined with #6, the "Operational Alerts" card will effectively always show "No active alerts" regardless of real platform state, since nothing currently writes to that collection.
- **Production importance:** Reduces admin responsiveness; the underlying data (disputes themselves) is never lost or hidden.
- **P0/P1/P2:** **P2**

### 18. Paystack Webhook Endpoint
- **Feature:** The HTTP endpoint Paystack calls to report `charge.success`/`transfer.success`/`transfer.failed`/`transfer.reversed` events
- **Firebase/Google service:** Cloud Functions (`paystackWebhook`, `onRequest`), which is also how Cloud Functions provisions the Cloud Run service backing every 2nd-gen function
- **Required plan:** Blaze
- **Current implementation:** N/A — no deployed URL exists for Paystack to call at all.
- **Deployed/available:** No
- **Blocked:** Yes, completely — see #3
- **User impact:** Same as #3.
- **Production importance:** Same as #3.
- **P0/P1/P2:** **P0** (same root issue as #3, listed separately since it's a distinct entry point)

---

## Admin actions specifically — most are unaffected

Cross-referencing every Admin Dashboard action against its backend (from the redesign audit earlier in this project): **only Delete User depends on a Cloud Function.** Approve/Reject Artisan, Approve/Reject Verification, Suspend/Reactivate User, Resolve/Dismiss Dispute, Delete Review, Respond & Resolve Support Ticket, Mark Deletion Request Resolved, Beta Tester toggle, and the entire Analytics/Audit Logs read surface are all direct, admin-gated Firestore writes/reads — none of them touch Cloud Functions or Storage, and all of them work correctly on Spark today (verified live, this project, multiple prior sessions).

---

## A. Features that work entirely on Spark

- Auth (sign in/up/reset/verify), all Firestore-backed CRUD (jobs, quotes, chats, reviews — text only, disputes — text only)
- Admin Dashboard: every action **except** Delete User (Users/Artisans management, Verifications approve/reject, Disputes resolve/dismiss, Reviews delete, Support Tickets, Deletion Requests, Beta Tester toggle, Audit Logs, Analytics)
- In-app notifications for quotes, disputes, verification outcomes, reviews, and agreement-flow events (client-written)
- FCM token registration (the send trigger is blocked, but registration itself is free/functional)
- Trust score's *underlying* fields (rating, verification status, completed-job counts) — only the derived recalculation is blocked
- "Analyze with AI" button's **error handling** (fails cleanly; the feature itself is blocked, see section C)
- Firebase Hosting (this app has been built and served throughout this entire project without issue — Hosting is not Spark-restricted)

## B. Features blocked on Spark (with no working alternative in production)

- Payment initiation, verification/escrow-lock, and payout (sections 2, 3, 4, 18) — the entire real-money path
- Job photo upload → blocks new job creation entirely (section 9)
- Profile photo, verification document, portfolio, and dispute-evidence uploads (sections 10-13)
- Push notification delivery, for every notification type (section 7)
- Job-lifecycle in-app notifications specifically (escrow-locked/submitted/payment-released) (section 8)
- Delete User (section 1)
- Trust score auto-recalculation (section 16)
- Auto-release escrow, stuck-release reconciliation, dispute admin-alerting, admin claim-sync (sections 5, 6, 15, 17) — operational/background safety nets

## C. Features requiring Blaze specifically

Every item in section B requires Blaze, because every one of them is either a Cloud Function (2nd gen, categorically requires Blaze to deploy) or Firebase Storage (a new bucket, under current Firebase policy, also requires Blaze to provision). There is no feature in this app that's blocked by something *other than* the Spark-plan ceiling — no Cloud Run usage exists outside what Cloud Functions itself provisions, and no other paid GCP service (Maps, Vertex AI direct, BigQuery, etc.) is referenced anywhere in the codebase.

## D. Features requiring external services (beyond Firebase's own plan)

- **Paystack**: a live secret key (`PAYSTACK_SECRET_KEY`, stored as a Functions secret) is required regardless of Firebase plan — upgrading to Blaze alone does not make payments work without also configuring this.
- **Google Generative AI (Gemini)**: `GEMINI_API_KEY`, similarly a separate credential/quota from Firebase billing, required for the AI Job Assistant.
- Both are already wired for Functions Secret Manager in the source (`secrets: ['PAYSTACK_SECRET_KEY']` / `secrets: ['GEMINI_API_KEY']`) — whether those secrets are actually populated with live values in this project was not verifiable from this environment (Secret Manager contents aren't readable via the CLI access available here) and should be confirmed separately before relying on either integration post-upgrade.

## E. Minimum infrastructure required for production

To reach a genuinely functional production state (not just "billing enabled"), in order:

1. **Upgrade `handytrust` to Blaze.** Unlocks the ability to deploy Functions and provision Storage — necessary but not sufficient on its own.
2. **Provision the Storage bucket** (Firebase Console → Storage → Get started → choose a location — the one step that must be a human decision) and deploy `storage.rules` (already correct, no changes needed).
3. **Deploy all 15 Cloud Functions** (`firebase deploy --only functions`) — the source for all of them is already correct and was not changed by this audit.
4. **Confirm `PAYSTACK_SECRET_KEY` and `GEMINI_API_KEY`** are populated as live Functions secrets with real, working values (separate from the Blaze upgrade itself).
5. **Verify the `BANK_CODES` table** in `processEscrowRelease` against Paystack's live `GET /bank?country=nigeria` endpoint before the first real payout — the function's own code comment already flags this as unverified from within this environment.
6. Re-run the full Create Job → Upload Photo → Post → Match → Pay → Escrow Lock → Submit → Release → Payout chain end-to-end with a real (small) transaction before considering payments production-ready.

Steps 2-3 have no meaningful ordering constraint between them once step 1 is done; both were independently blocked by Spark and neither depends on the other completing first.

## F. Recommended point to upgrade to Blaze

**Now, or as the very next step before any further feature work** — not because of urgency pressure, but because every P0 item in this audit (real job posting, payments, escrow, payouts, user deletion, identity verification) is fully blocked without it, and every one of them was already built and is just waiting on infrastructure, not further development. Continuing to build new features on top of an app that can't post a job, take a payment, or pay an artisan compounds technical debt without validating any of it against the real, paid backend it was designed for. The two Storage/Functions root-cause investigations already completed in this project (referenced throughout this document) found **zero code changes needed** on either front — both are purely deployment/provisioning steps once billing is enabled, which is the fastest and lowest-risk path back to a genuinely working app.

The one legitimate reason to delay: if there is a hard budget constraint on enabling pay-as-you-go billing before a specific date/funding milestone. That is a business decision outside the scope of this audit — this report exists so that decision can be made with a complete, accurate picture of what is and isn't actually working today.
