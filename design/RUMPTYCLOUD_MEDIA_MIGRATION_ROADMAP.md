# HandyTrust — RumptyCloud media migration roadmap (long-term)

**Date:** 5 November 2026.

**Status:** planning only. This records the owner's long-term objective and a phased path toward it. It does **not** authorise implementing or migrating any category. Every phase, category and environment below needs its own approval.

**Owner objective:** move all approved application media to RumptyCloud, one category at a time, each subject to its own security approval.
- Firebase stays responsible for authentication, authorisation, metadata and access decisions.
- RumptyCloud stores the media objects.
- **Identity documents are excluded.**

**Builds on:**
- `RUMPTYCLOUD_STAGING_INTEGRATION_PHASE2_PLAN.md`: upload design, quotas, verification, deletion, keys, live-test limits;
- `HANDYTRUST_FIREBASE_STORAGE_MIGRATION_PLAN.md`: media inventory;
- `HANDYTRUST_MEDIA_STORAGE_ARCHITECTURE.md`: object keys, `media/{id}` metadata;
- `HANDYTRUST_MEDIA_COST_AND_PERFORMANCE_ANALYSIS.md`.

---

## 1. Principles for every phase

1. **One category at a time.** Each category has its own feature switch, its own staging proof, its own production approval, and its own backfill approval.
2. **Order within a category:**
   1. staging, synthetic data;
   2. production **new uploads** behind a switch;
   3. **backfill** of existing files;
   4. much later, clean-up of the Firebase originals.

   Each step is a separate approval.
3. **Firebase decides, RumptyCloud stores.**
   - Every upload URL and every private read URL is issued by a Cloud Function, after checks that reproduce the Firestore rule for the parent document.
   - `media/{id}` in Firestore is the record of truth.
   - RumptyCloud keys exist only as Functions secrets.
4. **Reversible.** Turning a category's switch off sends new uploads back to Firebase Storage. Media already in RumptyCloud stays readable through the same resolver.
5. **Firebase originals are never deleted during migration.** Installed app versions read stored Firebase URLs directly.
6. **Identity documents** (`verifications/{uid}/…`: selfie, government ID) **stay in Firebase Storage permanently**. So Firebase Storage remains in use even after every in-scope category has moved.
7. **No category moves without its media being classified by who can see it today** (§3). Migration must not widen access.

---

## 2. What this changes in earlier plans

| Earlier statement (H1.2) | Now |
|---|---|
| Dispute evidence "stays in Firebase Storage" | **In scope long-term**, as the last category, after its own security review and approval (M8) |
| Private media: "keep in Firebase Storage until…" (optional phase) | **In scope long-term**, one category at a time, each after its own security review (M6, M7) |
| "Profile photos" classed as public | **Only artisan profile pictures are public-facing.** The rules let only the owner and admins read customer profile pictures (`firestore.rules:141`), so they're private (M4) |
| Two production buckets (public, private) | **Three:** public, private, evidence (§4). Keys can't be limited to a folder, so a bucket is the only isolation boundary |
| Video and documents implied as migrations | **Neither exists today** (no video or document upload in the app). Portfolio video and job/chat attachments are **new features** needing product approval, not migrations |

These banners were added to the H1.2 documents: `HANDYTRUST_FIREBASE_STORAGE_MIGRATION_PLAN.md`, `HANDYTRUST_MEDIA_STORAGE_ARCHITECTURE.md`, `HANDYTRUST_MEDIA_SECURITY_REVIEW.md` and `HANDYTRUST_MEDIA_IMPLEMENTATION_ROADMAP.md`.

---

## 3. Categories: what exists today and who can see it

The "who can see it today" column comes from `firestore.rules`, read on 5 November 2026. Today every stored Firebase download URL is also a bearer link (finding M1): anyone holding it can download the file.

| Category | Exists today? | Current location and reference | Who can see it today (rules) | Class | Phase |
|---|---|---|---|---|---|
| Synthetic test files | — | — | — | Test | **M0** |
| Artisan profile pictures | Yes | `profiles/{uid}/avatar.jpg` → `artisans.profileImageUrl`, `users.photoUrl` | Any signed-in user, once the artisan is approved and verified; before that, owner and admin (`:176-181`) | Public-facing | **M2a** |
| Artisan portfolio images | Yes | `artisan_portfolio/{uid}/image_n.jpg` → `artisans.portfolioImageUrls`, `portfolio_projects.imageUrls` | Any signed-in user (`portfolio_projects`, `:1112`; artisan document as above) | Public-facing | **M2b** |
| Customer profile pictures | Yes | `profiles/{uid}/avatar.jpg` → `users.photoUrl` | **Owner and admin only** (`:141`) | Private, low sensitivity | **M4** |
| Artisan portfolio videos | **No** (new feature) | — | Would follow portfolio | Public-facing | **M5** |
| Job photos | Yes | `jobs/{jobId}/{uid}/image_n.jpg` → `jobs.imageUrls` | Customer, assigned artisan, admin, **and any artisan account while the job is open** (`:248-251`) | Private (semi-shared while open) | **M6a** |
| Completion photos (before/after) | Yes | `jobs/{jobId}/{uid}/{before,after}/…` → `beforePhotoUrls`, `completionImageUrls` | Job parties, admin | Private | **M6b** |
| Job attachments (documents) | **No** (new feature) | — | Would follow job | Private | **M6c** |
| Chat images | Yes | `jobs/{jobId}/{uid}/image_<ms>.jpg` → `messages.imageUrl` | Sender, receiver, admin | Private | **M7a** |
| Chat attachments (documents) | **No** (new feature) | — | Would follow message | Private | **M7b** |
| Dispute evidence | Yes | `disputes/{id}/{uid}/evidence_n.jpg` → `evidenceImageUrls`, `artisanEvidenceUrls` | Raiser, other party, admin (`:933-937`) | Private, evidential | **M8** |
| Thumbnails | **No** (none generated today) | — | Same as the parent media | Same as parent | With each parent's phase |
| Identity documents | Yes | `verifications/{uid}/…` | Owner, admin | Highly sensitive | **Excluded: never migrated** |

**Notes from the inventory:**
- **Job photos and chat images share the same Firebase path** (`jobs/{jobId}/{uid}/`). A backfill must therefore select files by their **Firestore reference** (`jobs.imageUrls` versus `messages.imageUrl`), never by path prefix. Otherwise one category would migrate the other's files.
- **Existing rule discrepancy (not part of this migration, but blocks M6a):**
  - The jobs rule comment says "Approved+verified artisans may also read jobs still open for quoting".
  - The rule uses `isArtisanAccount(uid)`, which only checks that an `artisans/{uid}` document **exists** (`:58-60`).
  - So an artisan account still awaiting approval can read open jobs and their photo links.
  - Which one is intended must be decided and fixed before M6a, because the new URL-issuing function must reproduce the intended rule, not a wider one.
- **No minimum-app-version mechanism exists** (no such check found in `lib/` or `functions/`). Section 6 explains why private categories depend on one.

---

## 4. Buckets and keys (production; staging mirrors this with separate buckets)

RumptyCloud facts this rests on:
- a key belongs to exactly one bucket, can't be limited to a folder, and its permissions can't be changed;
- there's no versioning, so an overwrite or delete is permanent.

So **a separate bucket is the only way to stop a leak in one class from reaching another.**

| Bucket (names illustrative) | Holds | Signing key | Clean-up key | Notes |
|---|---|---|---|---|
| `ht-prod-public` | Artisan profile pictures, portfolio images and videos, their thumbnails | read + write | list + read + delete | Public reads (see decision D-1). Contains only already-public content |
| `ht-prod-private` | Customer profile pictures, job photos, completion photos, job attachments, chat images and attachments, their thumbnails | read + write | list + read + delete | Signed reads only, ≤ 5-minute URLs, issued after relationship checks |
| `ht-prod-evidence` | Dispute evidence and its thumbnails | read + write | **Not deployed in the normal runtime.** Deletion only by a separately approved retention job | Backup copy with a second provider (§7.4) |
| `ht-staging-*` | Synthetic data only (the existing staging bucket) | per the Phase 2 plan | per the Phase 2 plan | Never holds real user media |

**Other rules:**
- Production and staging use separate RumptyCloud workspaces.
- Object keys follow `{env}/{kind}/{yyyy}/{mm}/{uuid}.{ext}`, with no user ID, job ID or name in them.
- Keys are rotated by hand, on any suspected exposure, and on staff change.

---

## 5. Phases

Every phase has a staging part and a production part, approved separately. "Exit" means the condition for asking for the next approval.

### M0: synthetic staging files (current Phase 2 plan)

| | |
|---|---|
| **Scope** | Tier 1 offline and tier 2 live tests with synthetic files only (approvals A7 and A8 in `STAGE8_2_AND_RUMPTYCLOUD_REVIEW_DECISIONS.md`) |
| **Exit** | Size enforcement during upload (Q2) resolved, or a fallback chosen; presigned GET (Q1), missing-object delete (Q6) and ACL behaviour (Q7) settled; every run leaves 0 objects |
| **Also needed before any public bucket** | Prove that a public bucket refuses **anonymous listing** (otherwise every public object can be enumerated), and that public URLs support range reads (needed for video) |

### M1: foundations (no user media moves)

All of these are needed before the first real file:

1. **Provider-aware reading in the app.**
   - A media resolver handles three cases: public RumptyCloud URL, a signed URL obtained from a callable, or the legacy Firebase URL.
   - Documents gain `mediaIds` **alongside** the existing URL fields.
   - Released and adopted before any switch is turned on.
2. **Minimum-supported-version mechanism.**
   - `config/platform.minSupportedVersion` plus an update prompt.
   - Required before any private category (§6).
3. **Deletion and erasure path.**
   - Account deletion and admin deletion remove the user's RumptyCloud media through the deletion state machine.
   - Fix existing finding M2 (avatars under `profiles/{uid}/` are not deleted today).
4. **Production infrastructure.**
   - The owner creates the production workspace, buckets and keys.
   - Secrets go in Secret Manager. Production already runs Cloud Functions, which needs Blaze; confirm with the billing page before this phase.
   - Staging deployment needs Blaze on the staging project (approval A4).
5. **Operations.**
   - A balance-check routine, because RumptyCloud has no spend alerts. For example, a weekly check with a minimum-balance threshold, and an agreed top-up policy.
   - Runbooks for key rotation and compromise.
   - A dashboard for verification failures, sweeps and deletion failures.
   - Measure upload and download latency on MTN, Airtel and Glo.
6. **Vendor and legal.**
   - Vendor answers on egress price, encryption at rest and durability (Q8, Q9).
   - Data-processing terms with RumptyCloud.
   - Privacy notice update. This is an owner/legal step: profile pictures are personal data even when public.

**Exit:** the provider-aware app version is adopted by an agreed share of active users (decision D-7).

### M2: public-facing media, new uploads

- **M2a: artisan profile pictures.** **M2b: portfolio images**, with client-generated thumbnails. Each has its own switch, enabled one after the other, with at least 14 days between them.
- **Store:** `ht-prod-public`.
  - If D-1 is "public bucket": the permanent public URL is **also written into the legacy URL fields**, so older apps keep showing the image.
  - Only verified uploads are published.
- **Exit for each category:**
  - 30 days at a verification failure rate below 1%;
  - no objects without a `media` record, and no stuck deletions;
  - deletion and account-deletion drills passed;
  - rollback drill done (switch off → new uploads back on Firebase; existing items still visible).

### M3: public-facing backfill

For each category, separately (artisan avatars, then portfolio):
1. Copy the Firebase originals.
2. Compare size and SHA-256.
3. Create `media/{id}` with `legacyUrl`.
4. Switch new-app references.
5. **Keep the Firebase originals.**

**Details:**
- Idempotent: keyed by source path.
- A mismatch report must be empty before references switch.
- Rate-limited below the per-key limit of 600 writes per minute.

### M4: customer profile pictures

- Private by the current rules, so stored in `ht-prod-private` with signed reads.
- Only the owner and admins see them today, so this needs a **light security review** (access parity, erasure, EXIF removal).
- The full review for job, chat and dispute media is not required.
- Order: new uploads, then backfill, each approved separately.
- **Accepted limitation:** a customer using an older app on a second device won't see their own new avatar until that app is updated.

### M5: portfolio videos (new feature)

- Needs **product approval** first. It's a new capability, not a migration.
- **Prerequisites:**
  - size enforcement proven for multipart (Q2);
  - range reads on public URLs proven (M0);
  - limits defined (e.g. MP4/H.264, ≤ 60 s, ≤ 50 MB);
  - client-side compression and a poster-frame thumbnail (new Flutter packages, assessed at that time);
  - an egress estimate, since video may dominate cost (cost analysis, scenario C).
- RumptyCloud has no documented transcoding or streaming, so clips are served as uploaded.

### M6: job media. Needs security review SR-JOB (§8) and explicit approval

| Step | Category | Notes |
|---|---|---|
| **M6a** | Job photos | First fix the open-job rule discrepancy (§3). The signing function then reproduces the corrected rule. Note: an artisan who loses access (another artisan booked) can't get new URLs after that, which is tighter than today's permanent bearer links |
| **M6b** | Completion photos | Retention: never deleted automatically while a job is disputed or recently completed (existing policy) |
| **M6c** | Job attachments (new feature) | Needs product approval **and malware scanning** (RumptyCloud documents no scanning, so a scanning service is a separate cost and approval). Start with PDF only |

**Prerequisites:**
- minimum-version enforcement **switched on**, set to the provider-aware version;
- EXIF/GPS removal before storage. Job photos are often taken at the customer's home;
- a backup copy of private media (decision D-4).

### M7: chat media. Needs security review SR-CHAT and explicit approval

- **M7a: chat images**, selected by `messages.imageUrl` (not by path).
- **M7b: chat attachments**, a new feature, with the same scanning requirement as M6c.
- Access is checked against the message's sender and receiver (plus admin), reproducing the messages read rule.
- Messages can't be edited after sending, so a message's media list is fixed when it's confirmed.

### M8: dispute evidence. Needs security review SR-EVIDENCE and explicit approval (last category)

Additional mandatory controls:
- **Retention and legal hold:**
  - a written retention period (decision D-5);
  - nothing deleted while a dispute is open or under hold;
  - the evidence bucket's delete key exists only in a separately approved retention job.
- **Integrity:**
  - SHA-256 recorded at upload and checked again on every admin access, plus a periodic sample check;
  - objects are never overwritten: the server never signs a second upload for an existing key.
- **Independent backup:** every evidence object also copied to a **different provider** (for example, kept in Firebase Storage), with a restore test. RumptyCloud has no versioning and its durability isn't documented.
- **Access audit:** every signed-URL request for evidence writes an audit record (who, when, which item); admin views included.
- **Backfill** of existing evidence keeps the Firebase originals as the independent backup.

### M9: clean-up of Firebase originals (per category, much later)

**Only when all of these hold:**
- every supported app version uses the resolver (the minimum version is enforced);
- the category's backfill has been verified;
- the backup policy no longer relies on the Firebase copy.

**Rules:**
- One approval per category.
- Dispute evidence originals stay as long as they serve as the independent backup.
- Identity documents are never touched.

---

## 6. Compatibility with older app versions

- Older apps read the URL fields directly and know nothing about signed URLs.
- **Public bucket:** a permanent public URL can go into the legacy fields, so older apps keep working, with no forced update.
- **Private buckets:** the legacy fields can't hold expiring URLs. An older app on the **other** party's phone (an artisan viewing a customer's job photo) would show nothing. **Therefore no private category (M6–M8) may switch on until the minimum-version mechanism is enforced.** M4 is the exception; its only effect is on the owner's own second device.
- Firebase originals of every category stay readable until M9.

---

## 7. Cross-cutting requirements by kind of media

### 7.1 Thumbnails

- Created on the client: images with the existing `flutter_image_compress` package; video poster frames with a new package (M5).
- Stored as separate `media` records with `parentMediaId`, in the **same bucket and class** as the parent.
- Checked on the server: type, ≤ 512 px.
- Deleted with the parent.
- RumptyCloud documents no image resizing, so nothing is generated on the vendor side.

### 7.2 Videos

- Multipart upload with server-issued, length-signed part URLs.
- Duration and size limits, and structure checks (Phase 2 plan §8).
- No transcoding, so clips are served as uploaded.
- An egress estimate is required in the approval.

### 7.3 Documents (job and chat attachments)

- New features.
- Type allow-list (PDF first).
- Structure validation.
- **Malware scanning before the file becomes readable by the other party.**
- Served as attachments, not inline.

### 7.4 Backups

| Class | Backup copy |
|---|---|
| Public | Optional. The originals are recoverable from the uploader |
| Private | Required before M6. Second location decided under D-4 |
| Evidence | Required, with a **different provider** |

RumptyCloud provides no versioning and documents no durability figure.

---

## 8. Security review template (SR-JOB, SR-CHAT, SR-EVIDENCE; reduced form for M4)

Each review is written for one category and approved on its own.

1. **Access parity:**
   - list every role that can read the parent document under the rules;
   - a test suite runs the **same fixtures** against the rules emulator and against the URL-issuing function, and the results must match exactly.
2. **Access ending:** URL lifetime ≤ 5 minutes; what happens when a relationship ends (job reassigned, account suspended, admin removed).
3. **Data minimisation:** EXIF/GPS removal; no personal data in object keys or logs.
4. **Content safety:** type sniffing, structure checks, and malware scanning for documents.
5. **Backup and restore:** location, restore test, and recovery time.
6. **Retention and deletion:** per-category retention; account-deletion behaviour; legal hold.
7. **Legal:** data-processing terms cover the category; privacy notice; data-protection assessment (owner/legal).
8. **Audit:** access logging where evidential (mandatory for M8).
9. **Older-app impact:** minimum version enforced; what older apps show.
10. **Incident response:** key-compromise runbook for that bucket, and how affected users are notified.
11. **Cost:** storage and egress estimate for the category.
12. **Rollback:** switch back to Firebase; existing items stay readable.

---

## 9. Approvals required (each cell is a separate approval)

| Category | Security review | Staging | Production, new uploads | Backfill | Firebase clean-up (M9) |
|---|---|---|---|---|---|
| Synthetic (M0) | Covered by the Phase 2 plan | A7 / A8 | — | — | — |
| Foundations (M1) | — | Yes | Yes (app release; buckets and keys) | — | — |
| Artisan profile pictures (M2a / M3) | Covered by the Phase 2 plan + D-1 | Yes | Yes | Yes | Yes |
| Portfolio images (M2b / M3) | Covered by the Phase 2 plan + D-1 | Yes | Yes | Yes | Yes |
| Customer profile pictures (M4) | Reduced review | Yes | Yes | Yes | Yes |
| Portfolio videos (M5) | Product approval + review | Yes | Yes | — (new) | — |
| Job photos (M6a) | **SR-JOB** + rule fix | Yes | Yes | Yes | Yes |
| Completion photos (M6b) | **SR-JOB** | Yes | Yes | Yes | Yes |
| Job attachments (M6c) | Product approval + **SR-JOB** + scanning | Yes | Yes | — (new) | — |
| Chat images (M7a) | **SR-CHAT** | Yes | Yes | Yes | Yes |
| Chat attachments (M7b) | Product approval + **SR-CHAT** + scanning | Yes | Yes | — (new) | — |
| Dispute evidence (M8) | **SR-EVIDENCE** + D-5 | Yes | Yes | Yes | Only if no longer the backup |
| Identity documents | — | **Excluded** | **Excluded** | **Excluded** | **Excluded** |

---

## 10. Decisions for the owner (when the relevant phase approaches)

| # | Decision | Recommendation |
|---|---|---|
| D-1 | Public-facing media: public bucket (permanent public URLs, works with older apps) or private bucket with signed URLs (needs a forced update, more calls) | **Public bucket** for artisan profile pictures and portfolio. Exposure stays the same as today's bearer URLs. Conditional on the anonymous-listing test passing |
| D-2 | Customer profile pictures: private (matches the current rules) or public-facing | **Private** (M4) |
| D-3 | Build the minimum-supported-version mechanism | **Yes, in M1.** Required before M6 |
| D-4 | Backup location for private media: second RumptyCloud bucket (protects only against key misuse) or another provider | Decide after the vendor's durability answer (Q9). Evidence always uses another provider |
| D-5 | Dispute-evidence retention period and legal-hold policy | Owner/legal |
| D-6 | Portfolio video and document attachments as product features | Separate product decisions; documents need a scanning service |
| D-7 | Share of active users on the provider-aware version before switches are turned on | For example ≥ 90% for public categories; minimum version enforced for private ones |
| D-8 | Intended rule for artisans reading open jobs (existence of an artisan document, or approved and verified) | Decide before M6a; currently wider than its own comment |

**Not authorised by this document:** any implementation, any production bucket or key, any migration, any switch, any deletion.
