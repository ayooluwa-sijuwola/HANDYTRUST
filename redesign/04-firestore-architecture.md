# 04 — Firestore, Storage & Cloud Functions Architecture

Formalizes the backend data/security architecture, incorporating the config-rules split (`02-design-system.md`/`01-ux-audit.md` 3.7), the rate-limiting design owed since 2.7, and the new fields/collections implied by `05-trust-score.md` and the Phase 1.5 hardening sprint's Track A. Also extends into **Storage rules**, which no prior phase examined directly — reading `storage.rules` for this doc surfaced two previously-unflagged privacy gaps (§4).

---

## 1. Canonical collection map (verified against `firestore.rules` directly, cross-checked with `README.md`)

| Collection | Purpose | Access pattern |
|---|---|---|
| `users/{uid}` | Account profile, roles, status | Owner/admin read; `accountStatus` admin-write-only |
| `users/{uid}/favorites/{artisanId}` | Saved artisans | Owner-only |
| `artisans/{uid}` | Public artisan profile | Public read gated on approved+verified; server-managed fields (`trustScore`, `rating`, etc.) blocked from owner writes |
| `artisan_private/{uid}` | Bank details, private ID data | Owner/admin only |
| `jobs/{jobId}` | Core job lifecycle doc | State-machine-validated transitions (`_isValidJobTransition`); open-feed read for any artisan while `requested` |
| `jobs/{jobId}/auditLogs/{logId}` | Immutable job audit trail | Job party/admin read; server-transaction write only |
| `jobs/{jobId}/messages/{msgId}` | Chat | Job-party scoped; multi-artisan pre-match isolation |
| `jobs/{jobId}/quotes/{quoteId}` | Quotes, doc ID = artisanId | Artisan create/edit while pending; customer accept/reject |
| `payments/{paymentId}` | Payment/escrow records | Payer/artisan/admin read; admin-write |
| `reviews/{reviewId}` | Ratings | Customer-create on completed job only; no update |
| `disputes/{disputeId}` | Disputes | Raiser/against-party/admin |
| `verifications/{uid}` | Identity submission | Owner/admin |
| `portfolio_analytics/{artisanId}` | View counts | Owner/admin read |
| `fcm_tokens/{uid}` | Push tokens | Write-only by owner, no client read |
| `escrow_releases/{id}` | Payout queue | Customer-create; admin read/update — **formalized in §2, currently has no consuming function per `01-ux-audit.md` 1.1** |
| `admins/{uid}` | Admin registry | Admin read; **no client write at all** |
| `config/{doc}` | App config | Currently broad `read: if isSignedIn()` — **split proposed in §3** |
| `support_tickets/{ticketId}` | Support | Owner/admin |
| `notifications/{notifId}` | In-app feed | Target-user read; whitelisted-type create |
| `account_deletion_requests/{uid}` | Deletion requests | Owner/admin |
| `admin_audit_logs/{logId}` | Admin action trail | Admin-only, immutable |
| `portfolio_projects/{projectId}` | Portfolio projects | Public read; owner-artisan write |

This table is now the canonical reference — cite it instead of re-deriving from `firestore.rules` in future phases.

---

## 2. `escrow_releases` — formalized schema (executes `01.5` Track A1)

Currently just `{status: 'pending'}` plus whatever `JobService.confirmComplete` writes. Formalized schema for the payout consumer function:

```
escrow_releases/{id}
  jobId: string
  customerId: string
  artisanId: string
  amount: number                    // kobo, matching payments/ convention
  status: 'pending' | 'processing' | 'completed' | 'failed'
  paystackRecipientCode: string?    // set once a Transfer Recipient is created/reused
  paystackTransferCode: string?     // set on transfer initiation
  paystackTransferReference: string?
  failureReason: string?            // e.g. "no_bank_details", "paystack_transfer_failed", "recipient_creation_failed"
  retryCount: number                // default 0
  createdAt: Timestamp
  processedAt: Timestamp?           // set on completed/failed
  lastAttemptAt: Timestamp?
```

**Rules change needed**: current rule (`create` by customer, `read/update` by admin) is still correct in shape — add a field-diff restriction so client-side `update` is impossible entirely once the payout Cloud Function owns all writes post-creation (only the customer's initial `create` and the Function's Admin-SDK writes should ever touch this doc — admin dashboard *read* access stays, but admin should not hand-edit `status` directly without going through the retry/reconciliation function, to avoid an admin manually marking something `completed` when Paystack never actually confirmed it).

**New index needed**: `escrow_releases`: `status ASC, createdAt ASC` — required for the reconciliation sweep (`01.5` A5: find `pending`/`processing` releases older than an SLA window) and for admin dashboard's Escrow Monitoring queue (`10-admin-redesign.md`). Not present in `firestore.indexes.json` today (new collection, nothing to have indexed yet) — add before `06-escrow-wallet.md`/Track A ships.

---

## 3. `config` collection split (executes 3.7)

Current: single `config/{doc}` with blanket `read: if isSignedIn()`. Split:

```
config/public       — Paystack public key, feature flags, app version gates
                       read: if isSignedIn()   (unchanged, genuinely safe to expose broadly)

config/internal      — reserved for anything that becomes sensitive later
                       read: if false           (no client read at all, ever)
                       write: if false           (Admin SDK / console only, unchanged)
```

This doesn't change today's behavior (nothing currently reads `config/internal` client-side) — it makes the *rule itself* enforce the safe/sensitive split structurally, per `01-ux-audit.md`'s corrected 3.7 finding, rather than relying on nobody ever adding a sensitive field to the broadly-readable doc.

---

## 4. Storage rules — direct review (not covered by any prior phase)

Read `storage.rules` directly for this doc. The admin-check mechanism mismatch (`request.auth.token.admin == true`, a custom claim, vs. Firestore rules' `/admins/{uid}` doc-existence check) is confirmed exactly as `README.md`/`01-ux-audit.md` describe — addressed in §5 below. Two **new** findings, not previously flagged:

### 4.1 🟠 Job images are readable by any signed-in user, indefinitely — broader than the Firestore doc they belong to
`match /jobs/{jobId}/{uid}/{allPaths=**} { allow read: if isSignedIn(); ... }` — any authenticated user can read any job's photos, forever, regardless of whether they're a party to that job. Firestore's own `jobs/{jobId}` document read rule is properly scoped (customer/matched artisan/admin, or any artisan only transiently while `status=='requested'`) — Storage's rule is broader than the data it's attached to. This is very plausibly *intentional* for the open-feed browsing case (an artisan considering a job should see its photos before quoting) — but that justification only holds while the job is still `requested`. Once a job is matched, paid, and completed, there's no remaining reason for a stranger to keep permanent read access to (potentially) photos of someone's home interior.

**Fix**: this is a genuine Storage-rules limitation worth being honest about — Storage rules *can* call `firestore.get()` to check a Firestore document's fields (cross-service rule reads are supported), so the fix is technically available: `allow read: if isSignedIn() && (isOwner(uid) || <job party check via firestore.get(/databases/(default)/documents/jobs/$(jobId))> || <job.status == 'requested'>)`. This adds a Firestore read to every Storage read check (a real cost/latency tradeoff, not free), so it's a genuine engineering decision, not a one-line fix — flagged for `11-production-roadmap.md` rather than assumed trivial.

### 4.2 🟠 Dispute evidence photos are readable by any signed-in user — the sharper version of the same gap
`match /disputes/{disputeId}/{uid}/{allPaths=**} { allow read: if isSignedIn(); ... }`. This one has no "open feed" justification at all — dispute evidence exists specifically because something went wrong between two specific parties, and Firestore's own `disputes/{disputeId}` rule correctly restricts read to the raiser, the against-party, and admins only. Storage's blanket `isSignedIn()` read directly contradicts that scoping for the attached evidence photos, which may show substandard work, personal living spaces, or (if a user carelessly attaches the wrong file) ID documents. This is the more serious of the two findings — dispute evidence is exactly the kind of content the brief's "trust, transparency, accountability" framing would expect to be tightly scoped, and today it isn't.

**Fix**: same `firestore.get()` cross-service pattern as 4.1, checking `raisedBy`/`raisedAgainst` on the corresponding `disputes/{disputeId}` doc (or, cheaper, mirror the dispute's authorized-uid pair onto the storage path itself at upload time if avoiding the extra read is a priority — a design tradeoff to make explicitly, not default into). **This one should be prioritized above 4.1** — no legitimate open-access use case competes with tightening it, unlike job photos' feed-browsing case.

### 4.3 What's already correct
- Verification documents (`/verifications/{uid}`) — correctly owner/admin-only read, and the code comment shows a real prior fix (contentType validation added after noticing every other path had it but this one didn't) — good hygiene, cite as the pattern to replicate.
- Profile photos (`/users/{uid}`) and portfolio photos (`/artisan_portfolio/{uid}`) — broad read is correct here; both are meant to be public-facing by design (avatars, portfolio showcase), unlike 4.1/4.2's private content.
- Every path correctly enforces `isOwner(uid)` on write plus size/contentType limits — the write side of Storage rules has no gaps found.

---

## 5. Reconciling the dual admin-authorization mechanism

Confirmed directly: Firestore rules check `/admins/{uid}` doc existence; Storage rules check `request.auth.token.admin == true`. `onAdminGranted`/`onAdminRevoked` (`functions/index.js`) already sync the claim *from* the doc — so the sync direction exists, but per `README.md`'s own install instructions, granting admin today still requires **three manual steps** (Firestore doc, custom claim, `roles` array), only one of which (the claim) is actually auto-derived from another (and that auto-derivation itself only fires if the doc-creation trigger runs, which requires the doc to be created first through some other means).

**Proposed single-flow fix**: a callable Cloud Function `grantAdmin({targetUid})`, admin-only-callable (checks the caller's own admin status first), that in one Admin-SDK transaction: creates the `/admins/{uid}` doc, sets the custom claim directly (redundant with the trigger, but removes any dependency on trigger latency/ordering), and adds `'admin'` to the target's `users/{uid}.roles` array. This collapses three manual steps into one function call, removes the "partially admin" failure mode the audit flagged, and gives admin-granting itself an audit trail for free if it also writes an `admin_audit_logs` entry (which today's process — manual console/CLI steps — doesn't produce). `onAdminGranted`/`onAdminRevoked` triggers stay as a safety net for any doc created by other means, not the primary path.

---

## 6. Rate limiting & abuse prevention (executes 2.7)

No App Check integration exists anywhere in the app (verified — every `appCheck` hit in the repo is inside `node_modules`, none in first-party code) and no Cloud Function-side counters were found guarding any write path.

**Two-layer recommendation**:

1. **Firebase App Check**, enabled across all client platforms (Play Integrity on Android, DeviceCheck/App Attest on iOS, reCAPTCHA Enterprise on web) and enforced on Cloud Functions callables + Firestore/Storage. This is the cheap, broad layer — it doesn't rate-limit legitimate users, it blocks traffic that isn't coming from the real app at all (scripted abuse, scraping, replayed requests from a non-app client). Low engineering cost, high leverage; should ship as part of the Phase 1.5 hardening sprint's Track C, not deferred to a later phase.

2. **Per-user, per-action counters** for the specific actions with real abuse value, enforced in the Cloud Functions layer (Firestore rules alone can't cheaply rate-limit, since rules have no persistent counter state across requests):

| Action | Proposed limit | Rationale |
|---|---|---|
| Job posting | e.g. 10/day per customer | Prevents feed-spam that degrades the open-jobs feed for artisans |
| Quote submission | e.g. 30/day per artisan | Prevents a single artisan blanket-quoting every open job regardless of fit |
| Chat message send | e.g. 60/hour per user per job | Prevents harassment/spam within a thread without limiting genuine back-and-forth |
| Review creation | Already naturally capped (one per completed job, enforced by rules) — no additional limit needed |
| Dispute creation | e.g. 5/month per customer, flagged (not blocked) above that — ties into `05-trust-score.md` §4's Trust & Safety anomaly queue rather than a hard block, since a genuinely unlucky customer could legitimately need more |

**Implementation pattern**: a small Cloud Function-side helper (a Firestore transaction against a per-user-per-action-per-window counter doc, e.g. `rate_limits/{uid}_{action}_{windowStart}`) called at the top of each relevant callable/trigger before the real write proceeds. This is a new, small piece of shared infrastructure — flag it as its own task in `11-production-roadmap.md`, not something to bolt onto each service individually without a shared helper (or it'll be reimplemented five slightly-different ways, the same pattern this program keeps finding elsewhere — see §7).

---

## 7. Write-authority governance (formalizing a pattern this program keeps re-discovering)

`01-ux-audit.md` and `02-design-system.md` independently found the same shape of problem three times: `JobService` vs. `EscrowService` (2.3), two admin-audit-log services (3.2), and three timeline-named widgets / two snackbar helpers (`02-design-system.md` §6.2). The common root cause: no explicit rule that **one service owns all writes to a given collection**.

`JobService` already demonstrates the correct pattern — it's the sole writer to `/jobs`, enforces the state machine, and every other service that needs to touch a job's status calls into it rather than writing directly. `NotificationService` does the same for `/notifications`. **Formalize this as a standing rule**: before adding a new write path to any collection, check whether a canonical service already owns it; if a genuine second write path is needed, it must be justified in a code comment (as `NotificationService`'s design already does implicitly) not silently duplicated. Apply this retroactively to close 2.3 (delete `EscrowService`) and 3.2 (consolidate the two admin-audit-log services) as part of the Phase 1.5 hardening sprint's Track C, not as new work — it's cleanup of exactly the gap this section names.

---

## 8. Audit trail gap: artisan document changes have no history

`jobs/{jobId}/auditLogs/{logId}` gives a complete, immutable trail of every job mutation — genuinely good engineering, already praised in `01-ux-audit.md` §0. **No equivalent exists for `artisans/{uid}`.** Every `trustScore` recompute, every admin approval/rejection, every suspension is a direct field overwrite with no history retained — so a support ticket like "why did my trust score suddenly drop" or "when was I approved" currently has no answer beyond the artisan's *current* state. Admin-initiated changes (approve/reject) do get an `admin_audit_logs` entry (via `AdminAuditService`, once §7's consolidation picks the canonical one) — but the automatic Cloud-Functions-triggered recomputes (`onArtisanRatingChanged`, `onArtisanVerificationChanged`, `_recordJobOutcome`, `_adjustDisputeCount`) do not, since they're not admin actions and were never routed through that service.

**Recommendation**: add a lightweight `artisans/{uid}/scoreHistory/{entryId}` subcollection, written in the same transaction as every `trustScore` recompute (same technique already used for `jobs/{jobId}/auditLogs`) — just `{trustScore, previousScore, reason, timestamp}`, not a full snapshot. This is a small addition with real support/trust-and-safety value (§`05-trust-score.md` §4's anomaly detection would also benefit from having this trail to query against) — sized right for inclusion whenever `05-trust-score.md`'s formula changes ship, since that's the same deploy that's already touching every trust-score write path.

---

## 9. Index audit

Went through every entry in `firestore.indexes.json` and matched it against a real query use case found in the codebase — all 19 existing composite indexes plus 2 field overrides correspond to an actual query (customer/artisan job lists, the auto-release scheduler confirmed correct in `01.5`, artisan discovery by category+rating and category+trustScore, reviews/disputes/payments by owner, message collection-group by job, admin audit logs by admin/action, portfolio projects). **No orphaned or clearly-missing index was found for any query in the current codebase** — the one real gap (`autoReleaseEscrow`) was already retracted as false in `01-ux-audit.md`'s errata.

**New indexes this program's own recommendations will require, tracked here so none are missed at build time**:
- `escrow_releases: status ASC, createdAt ASC` (§2 above)
- `artisans: category ASC, approvalStatus ASC, geohashPrefix ASC, trustScore DESC` (or equivalent) once `05-trust-score.md` §3.3's distance-bucketed ranking query is implemented — exact shape depends on whether geohash-prefix range queries or a fixed bucket field is chosen; flagged for whoever implements that ranking rewrite to finalize
- `rate_limits` collection (§6) — likely doesn't need a composite index if looked up by exact document ID (`{uid}_{action}_{windowStart}`) rather than queried, worth confirming once implemented

---

## 10. What this doc is deliberately not doing

- Not proposing a Firestore schema rewrite — the existing structure (job-scoped subcollections for messages/quotes/auditLogs, top-level collections for cross-cutting concerns) is sound and matches Firestore best practice for this access pattern. Every change above is additive or a scoping fix, never a restructure.
- Not designing the rate-limit counter's exact storage mechanism in full (Firestore transaction counters vs. a dedicated service like Memorystore/Redis) — that's an implementation decision for whoever builds §6, not a architecture-phase call, since it depends on expected write volume this program can't estimate pre-launch.
- Not re-litigating the automated-testing/CI gap (`01-ux-audit.md` §4, `README.md`'s own "Known Limitations") — real, but that's a process/tooling gap for `11-production-roadmap.md`, not a data-architecture one.

---

**Next**: `06-escrow-wallet.md` (Hardening Sprint Track A — the `escrow_releases` schema above is its direct input) is the natural next step, or `07-gps-flow.md`/`08-messaging-notifications.md` remain available with no dependency. Let me know which to take next.
