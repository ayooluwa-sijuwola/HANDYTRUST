# Security Audit — HandyTrust (Flutter + Firebase)

Scope: firestore.rules (full read), storage.rules (full read), functions/index.js (admin claims, escrow/payout, payment callables), client code cross-references in lib/.

## Part 1 — Firestore rules, collection by collection

- **users/{uid}**: read owner/admin only. Create: owner, requires uid match + name string >=2 chars (no other field restrictions). Update: admin, or owner as long as accountStatus isn't touched. Delete: false (admin deletion Cloud-Function-only via adminDeleteUser).
- **users/{uid}/favorites/{artisanId}**: owner-only CRUD, no update.
- **artisans/{uid}**: public read requires approved+verified, else owner/admin. Create: owner, must start pending. Update: admin, or owner excluding protected-field list (rating, totalRatings, trustScore, approvalStatus, accountStatus, betaTester, etc.); verificationStatus self-escalation capped at id_submitted. Delete: false.
- **artisan_private/{uid}** (bank details): read/write owner or admin; NO field-level schema validation on write.
- **jobs/{jobId}**: read = job parties, open-job-feed artisans, or admin. Create: customer, must start requested. Update: gated by _isValidJobTransition plus narrowly hasOnly()-scoped side-channel updates (negotiation amount, agreement confirmation, appointment scheduling, progress stage). Delete: admin only.
  - jobs/{jobId}/auditLogs/{logId}: create by job parties, immutable after.
  - jobs/{jobId}/messages/{msgId}: create/read scoped to job parties + pre-match artisans; isRead-only update.
  - jobs/{jobId}/quotes/{quoteId}: doc ID=artisanId; create requires eligible+verified artisan; update scoped to pending-artisan-edit or customer-accept/reject.
- **payments/{paymentId}**: read=payer/artisan/admin. **Create: signed-in, payerId==auth.uid, status in ['pending','escrowHeld'] — NO validation of jobId ownership, amount, or artisanId.** Update: admin only. Delete: false.
- **escrow_releases/{releaseId}**: **defined in TWO separate, non-exclusive match blocks** (lines 443-450 and 513-521) — see Findings.
- **reviews/{reviewId}**: read=any signed-in user. **Create: customer of a completed job, but no check that artisanId matches job's actual artisan, no doc-ID-to-jobId binding enforced by rules** — see Findings. Update false, delete admin only.
- **disputes/{disputeId}**: read=raiser/target/admin. Create: raiser must be job's customer (artisans cannot self-file). Update: admin, or accused party appending response fields only.
- **portfolio_analytics/{artisanId}**: monotonic view-counter, read owner/admin.
- **fcm_tokens/{uid}**: write owner-only, read false (Cloud Functions only).
- **admins/{uid}**: read admin-only, write false — no client path to self-grant admin. CONFIRMED SAFE.
- **config/{doc}**: read any signed-in user, write false.
- **support_tickets/{ticketId}**, **account_deletion_requests/{uid}**, **verifications/{uid}**: standard owner/admin patterns, correctly scoped.
- **admin_audit_logs**, **admin_alerts**: admin read, Cloud-Function-only create, immutable.
- **notifications/{notifId}**: read owner-only. **Create: admin, or any signed-in user targeting a DIFFERENT userId with a whitelisted type and forced isRead:false — no check target user has any relationship to sender/job** — see Findings.
- **portfolio_projects/{projectId}**: read any signed-in user; write scoped to artisan owner.

## Part 2 — Storage rules

- jobs/{jobId}/{uid}/**: write=owner of uid path segment, <=5MB, image content-type. **Read = any signed-in user** (not job parties only).
- users/{uid}/** (profile photo): write owner-only; read any signed-in user (acceptable — public profile photo only).
- artisan_portfolio/{uid}/**: write owner-only, read any signed-in user (intended — public portfolio).
- verifications/{uid}/** (selfie/gov ID): read owner/admin only (admin via token.admin custom claim) — correctly scoped.
- disputes/{disputeId}/{uid}/**: write = owner of uid segment; **read = any signed-in user**, not scoped to the two dispute parties + admin the way Firestore disputes collection is.

Storage's isAdmin() uses the admin CUSTOM CLAIM; Firestore's isAdmin() uses exists(/admins/{uid}). Kept in sync server-side by functions/index.js onAdminGranted/onAdminRevoked triggers, and admins/{uid} is client-write-false, so no client path to desync/forge either. CONFIRMED SAFE. (Note: cross-reference Cloud Functions audit — onAdminGranted/onAdminRevoked have ZERO deployed status and no in-app UI writes to /admins/{uid} at all; until deployed AND admin's token refreshes, admin-gated Storage ops will fail even for real admins — separate INFRASTRUCTURE finding, not a vulnerability.)

## Part 3 — Findings

### Finding 1 — P0: Customer can fabricate a fully-paid escrow without any real payment, and self-deal payouts to an account they control
Rule: firestore.rules:395 (_isValidJobTransition, paymentPending->escrowLocked: (isAdmin()||isCust), no other field constraint) + firestore.rules:415-417 (payments create rule: status in ['pending','escrowHeld'], no amount/jobId/artisanId validation).
CONFIRMED-BY-INSPECTION the write shape is real app-native code: lib/core/services/payment_service.dart:15-42 (PaymentService.simulatePayment) creates a payments doc with status:escrowHeld then calls JobService.lockEscrow (job_service.dart:479-485) to flip jobs/{id}.status to escrowLocked. In-app only reached when kDebugMode is true (payment_screen.dart:317-328), but kDebugMode is a CLIENT compile-time flag with ZERO server enforcement — underlying Firestore writes are exactly what rules permit for any authenticated customer, release build or not, app UI or raw SDK call.
**Exploit (CODE-LEVEL ONLY)**: customer creates job, gets to paymentPending, then via direct SDK: (a) payments.add({payerId:self, jobId, artisanId, amount:<anything>, status:'escrowHeld'}), (b) jobs/{id}.update({status:'escrowLocked'}) — both pass rules, no Paystack charge ever occurs. Since transition rule doesn't hasOnly()-restrict fields, same write can also reassign artisanId to a second account the attacker controls. Attacker's "artisan" account walks escrowLocked->inProgress->submitted, original customer confirms submitted->completed. processEscrowRelease reads amount from whatever payments doc matches jobId (no status check) and artisanId from job, fires a REAL Paystack Transfer — moving real platform money to an attacker-controlled account for a job never actually paid for.

### Finding 2 — P0: Duplicate/conflicting escrow_releases match blocks break payout idempotency
Same root cause as payment/escrow agent's Finding 1/2 (duplicate match blocks, lines 443-450 vs 513-521). CONFIRMED-BY-INSPECTION not purely theoretical: lib/core/services/escrow_service.dart:105 (EscrowService.confirmComplete) calls escrow_releases.add({...}) — auto-generated ID, REJECTED by correct block A (releaseId==jobId) but PERMITTED by loose block B. EscrowService not wired into any current screen/provider (dead code in UI sense) but nothing in rules stops any authenticated customer performing the identical .add() write directly via SDK.
**Exploit**: customer creates second escrow_releases doc (arbitrary ID, status:'pending') for a job that already has (or will have) the canonical jobId-keyed release. processEscrowRelease (onDocumentCreated, fires on ANY new doc in collection) processes both independently — two real Paystack transfers for one job's escrow, draining platform's Paystack balance.

### Finding 3 — P1: Fake reviews can be attributed to any artisan
firestore.rules:456-463 — reviews create only checks customerId==auth.uid, rating bounds, jobId refers to a completed job owned by that customer. NEVER checks request.resource.data.artisanId == getJob(jobId).artisanId, and no doc-ID-to-jobId binding enforced by rules (only client convention, review_screen.dart:216).
**Exploit**: any customer with >=1 completed job can create arbitrary-ID review docs citing that jobId but pointing artisanId at ANY artisan on the platform, repeatedly, any rating/comment — fabricated 5-star or sabotage 1-star reviews for artisans never transacted with. reviews readable by any signed-in user, drives public artisan reviews list.
Note: companion write to artisans/{uid}.rating/totalRatings from review_screen.dart:257-260 IS correctly blocked by artisans update rule's protected-field list — that escalation path closed, but leaves rating-aggregation silently broken in production (caught by empty catch(_){} at line 262-264 per error-handling audit) — functional bug, not itself a vulnerability.

### Finding 4 — P2: Job photos and dispute evidence readable by any authenticated user, not just involved parties
storage.rules:24-29 (jobs/{jobId}/{uid}/**) and :62-67 (disputes/{disputeId}/{uid}/**) both use `allow read: if isSignedIn()` — any signed-in user, not job/dispute parties + admin. Firestore's own jobs/disputes collections correctly scope reads to parties/admin; Storage doesn't mirror that. Exposure mitigated by Firestore auto-IDs being hard to guess, but exactly the "any authenticated user" over-broad pattern on personal/sensitive data (home interiors, dispute evidence).

### Finding 5 — P3: Notification spam/spoofing to arbitrary users
firestore.rules:551-563 — any signed-in user can create a notifications doc for ANY other userId (no relationship/job-party check) as long as type is whitelisted and isRead:false. Title/body content otherwise attacker-controlled.

### Finding 6 — P3: messages.isRead update not scoped to job parties
firestore.rules:282-284 — allow update if isSignedIn() && diff(...).affectedKeys().hasOnly(['isRead']), no isJobParty/receiverId check. Any signed-in user can toggle read/unread on any message in any job's chat thread. Minor griefing issue.

### Finding 7 — P3: artisan_private and users writes lack field-level schema validation
artisan_private/{uid} write rule (:110-113) no schema check at all; users/{uid} create/update (:46-66) only restricts accountStatus, arbitrary extra fields (e.g. self-added role/isAdmin field) writable by owner. NOT currently exploitable (verified no client code trusts such a field for authorization) but latent defense-in-depth gap.

## Part 4 — Explicitly requested vulnerability classes: results

- **Client-writable role/claim field trusted for admin privileges**: NOT FOUND. auth_provider.dart:157-184 (isAdminProvider) explicitly reads admins/{uid} existence — same source of truth as rules, deliberate (comment: "not UserModel.roles, which is a separate field nothing currently sets"). UserModel.isAdmin (user_model.dart:68, backed by client-writable roles array) NEVER referenced anywhere else in lib/ for authorization (zero call sites). Admin custom claims only settable via functions/index.js:790-808, triggered off admins/{uid} doc changes, write:false for clients. CONFIRMED-BY-INSPECTION.
- **Cross-user job/quote/escrow/payment writes**: NOT FOUND as direct ownership bypass — every write rule checks customerId/artisanId/payerId against request.auth.uid. Real issue is Findings 1-2 (self-owned job fraud, not cross-user theft).
- **allow read/write: if true or if request.auth != null only, on sensitive financial/personal data**: Firestore has none. Storage has the pattern on jobs/** and disputes/** reads (Finding 4).
- **Admin screens UI-gated but not rule/claim-protected server-side**: NOT FOUND as a gap — AdminShell and router guard both gate on isAdminProvider (backed by admins/{uid} existence, same as rules), adminDeleteUser independently re-checks admins/{uid} server-side. CONFIRMED-BY-INSPECTION.
- **Storage overwrite/delete of another user's files, missing content-type/size validation**: NOT FOUND — every write path checks isOwner(uid) against embedded path segment, every path enforces size + image/.* content-type.
- **TODO/FIXME/leftover debugging rules**: no literal TODO/FIXME in either rules file, but duplicate escrow_releases match blocks (Finding 2) read exactly like an un-cleaned-up leftover — block A's own comment ("Previously had no match block at all... Made explicit here") strongly suggests author was unaware block B already existed elsewhere in the file.

**Recommend prioritizing Findings 1 and 2 (P0, real-money exposure) first — both stem from jobs/payments/escrow_releases rules trusting client-asserted state (status, escrowLocked, arbitrary amount) instead of requiring these transitions to originate only from the webhook/Admin-SDK path.**

## Cross-reference note
This agent's Findings 1-3 independently corroborate the payment/escrow pipeline agent's Findings 1-3 (same root causes found via different investigation paths — rules-first here, pipeline-trace there). Two independent agents reaching the same conclusion increases confidence this is a real, not hallucinated, finding. Still CODE-LEVEL ONLY — not exploited live against production during this audit (explicitly out of scope/forbidden by audit rules).
