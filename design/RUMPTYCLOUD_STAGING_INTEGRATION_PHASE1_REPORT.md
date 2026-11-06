# RumptyCloud staging integration — Phase 1 report

**Date:** 5 November 2026. **Scope:** inspection and design only.

**Not done:**
- no code written for this integration;
- no dependency installed, nothing deployed, no Blaze upgrade;
- no secret seen, stored or logged by me;
- nothing committed.

**Supplied by the owner:**
- Firebase `handytrust-staging` (alias `staging`, Spark plan);
- RumptyCloud endpoint `https://s3.rumptycloud.com`, region `olas-closet`, private bucket `assets-handytrust-01a0f99e-5d6ffa`;
- an access key created and stored privately by the owner.

## 1. Existing architecture findings (verified in the repository)

- **Functions:**
  - one codebase `functions/` (`runtime: nodejs22`, `engines.node: 22`), **CommonJS** (`require`), single `index.js` (~4,300 lines);
  - `firebase-functions` ^5.1.1 (2nd gen `onCall` / `onRequest` / triggers), `firebase-admin` ^12.6, `axios`, `@google/generative-ai`;
  - secrets declared by name in function options (`{ secrets: ['PAYSTACK_SECRET_KEY'] }`) and read from `process.env`;
  - the emulator reads `functions/.secret.local`, which is git-ignored.
- **Projects:** `.firebaserc` has `default: handytrust` and **`staging: handytrust-staging`**. This alias is an uncommitted local edit I didn't make.
- **Media today:** Firebase Storage only. All uploads go through `StorageService` / `ProfileService` / `PortfolioService` as JPEG `putData`, and the long-lived download URL is stored in Firestore. Full inventory: `HANDYTRUST_FIREBASE_STORAGE_MIGRATION_PLAN.md` §1.
- **Storage abstraction:** no provider abstraction exists. Each service writes a Firebase path and returns a URL.
- **Security:** `storage.rules` (image only, < 5 MB, owner/party paths); no `media` collection; no S3 SDK.
- **Pattern to reuse:** callables already check auth and roles server-side (e.g. `adminDeleteUser`, `getPaymentBreakdown`), and tests use injectable fakes (`_setPaystackFakes`, `_setPushSender`). The media functions can follow the same pattern.

## 2. RumptyCloud compatibility findings

| Item | Finding | Evidence |
|---|---|---|
| Endpoint / region / addressing | `https://s3.rumptycloud.com`, region `olas-closet`, **path-style** | Docs (`buckets/access-keys-and-s3`) **and** live probe: the bucket resolves in the path |
| Bucket privacy | Anonymous list and GET → **403 AccessDenied** | **Live probe, no credentials** (5 Nov 2026) |
| Browser CORS | Preflight from an unknown origin → 403 | Live probe. Irrelevant for the Android app; needed only for web |
| Presigned PUT | Documented (`@aws-sdk/s3-request-presigner`, `expiresIn: 300`; Content-Type must match) | Docs |
| Presigned GET | Private buckets "use signed read URLs"; no SDK example | Docs. **To prove in the live test** |
| Key permissions | One key per bucket; list/read/write/delete chosen at creation; not editable; presigned URLs inherit the key's rights; no prefix scoping | Docs |
| Size | 5 GB single PUT; multipart (≥ 5 MB parts) | Docs. **Whether presigned URLs can enforce a maximum size is undocumented**, so size is checked after upload |
| Versioning / encryption at rest / durability / SLA | Not available / not documented | Docs (see `RUMPTYCLOUD_OBJECT_STORAGE_AUDIT.md`) |
| Backend | Error format (`tx…-rumpty-object` request IDs) suggests a Ceph-RGW-style S3 gateway | **Inference only** |

**Open question for the owner:** which permissions does the created key have? Recommended: **two keys** (write+read for signing; delete for clean-up), or at minimum one key with read+write+delete. Note the bucket-wide scope.

## 3. Proposed implementation (staging, synthetic media only)

### Flow

```
Flutter ──callable requestMediaUpload({kind, mimeType, sizeBytes, sha256})──▶ Functions
   Functions: request.auth required (non-anonymous, verified email); kind ∈ {test-avatar, test-portfolio,
   test-thumb, test-video}; MIME / size limits per kind; generate key
   "staging/{kind}/{yyyy}/{mm}/{uuid}.{ext}"; write media/{id} {status:'pending', ownerUid, …};
   return { mediaId, uploadUrl (PUT, 300 s, Content-Type bound) }
Flutter ──PUT bytes──▶ RumptyCloud (private bucket)
Flutter ──callable confirmMediaUpload({mediaId})──▶ Functions: owner check; HeadObject → size/type
   match → status 'verified' (else DeleteObject + 'rejected')
Flutter ──callable getMediaUrl({mediaId})──▶ Functions: owner (staging rule; later: relationship
   checks) → presigned GET (300 s)
Flutter ──callable deleteMedia({mediaId})──▶ Functions: owner/admin → status 'deleting' →
   DeleteObject → 'deleted' (idempotent; retries)
```

### Rules

- The client never sends object keys or owner IDs.
- No credentials leave Functions.
- Every decision is made by Firebase (Auth + Firestore).

### Metadata: `media/{mediaId}`

Written by Functions only; client read for the owner (and admins). Fields:

| Group | Fields |
|---|---|
| Location | `provider: 'rumpty'`, `bucket`, `objectKey` |
| Content | `kind`, `mimeType`, `sizeBytes`, `sha256` |
| Ownership and access | `ownerUid`, `visibility: 'private'` |
| Lifecycle | `status` (`pending` \| `verified` \| `rejected` \| `deleting` \| `deleted`), `createdAt`, `verifiedAt`, `deletedAt`, `deleteAttempts` |

No signed URL is ever stored.

### Limits (staging)

| Kind | Allowed types | Maximum size |
|---|---|---|
| Images | `image/jpeg`, `image/png`, `image/webp` | 5 MB |
| Video | `video/mp4` | 50 MB, single PUT; multipart is a later phase |

## 4. Required dependencies

| Package | Purpose | Compatibility |
|---|---|---|
| `@aws-sdk/client-s3` (v3) | Head / Delete / (later) multipart | Supports Node 22; CommonJS `require` works |
| `@aws-sdk/s3-request-presigner` (v3) | Presigned PUT/GET | Same |

- Configured with `endpoint: 'https://s3.rumptycloud.com'`, `region: 'olas-closet'`, `forcePathStyle: true`.
- **Impact:** adds about 3–5 MB to the Functions bundle. No change to existing workflows; the new callables are independent.
- **Flutter:** no new package. Uploads use the existing `dio` or `http` to PUT bytes to the presigned URL. New `MediaService` and model; no UI change in Phase 1–2.

## 5. Security considerations

- **Secrets:**
  - `RUMPTY_ACCESS_KEY_ID` and `RUMPTY_SECRET_ACCESS_KEY` as Functions secrets;
  - **locally only** in `functions/.secret.local` (already git-ignored), created by the owner;
  - `RUMPTY_BUCKET`, `RUMPTY_ENDPOINT`, `RUMPTY_REGION` as non-secret params.
  - Never logged: the logger records `mediaId` and status only.
  - A pre-commit check: `git grep` for the key prefix must return nothing.
- **Bucket-wide keys:** mitigated by server-generated random keys, 300-second URLs bound to one key and Content-Type, and no client-supplied paths.
- **Private by default:** no public-read ACLs, even for "public" kinds in staging.
- **No versioning:** a delete is permanent, so deletion happens only through the audited function. Synthetic data only.
- **Access loss:** no new URLs after ownership or relationship ends; issued URLs expire within 5 minutes.
- **Data:** synthetic files only (generated test images and a short generated MP4). No job, chat, dispute, identity or production media.

## 6. Emulator testing plan

| Tier | Runs | Network | Credentials |
|---|---|---|---|
| **1 — offline** (always) | Functions + Firestore + Auth emulators; S3 client and presigner injected as fakes (`_setMediaS3Fakes`) | None | None |
| **2 — live staging** (opt-in: `RUMPTY_LIVE=1`) | Same tests against the real private bucket from the local emulator | Outbound to RumptyCloud | Owner's `functions/.secret.local` |

**Tests (both tiers unless noted):**

1. Authorised upload: signed PUT works; confirm marks the media verified.
2. Unauthenticated / anonymous / unverified-email caller rejected.
3. Wrong kind, MIME or declared size rejected before signing; an oversized actual upload is detected by HEAD → deleted and rejected.
4. Expired upload URL (signed with a 1-second expiry) refused (tier 2) / expiry encoded (tier 1).
5. Authorised download URL for the owner; **unauthorised user** gets `permission-denied`; anonymous GET of the object → 403 (tier 2).
6. Content-Type mismatch on PUT → `SignatureDoesNotMatch` (tier 2).
7. Deletion: owner allowed, other user denied; repeat delete idempotent; missing object handled.
8. Missing or invalid credentials: the function returns `failed-precondition` with no secret in the error, and is logged without the secret.
9. Clean-up: tier 2 deletes every object it created; a run report lists the keys created and deleted.

## 7. Billing and deployment limitations

- **`handytrust-staging` is on Spark.** The official pricing page lists Cloud Functions and Secret Manager as **"Not applicable"** on Spark, so the media callables **cannot be deployed** to that project, and cloud secrets aren't available.
- **Workable without Blaze:** the Functions **emulator** on a developer machine, using `functions/.secret.local`, talking to the real RumptyCloud bucket (tier 2). Auth and Firestore emulators stand in for the project.
- **Cloud deployment of the signing service would need Blaze** on the staging project (a cost decision; not requested). The Functions free allowances on Blaze are documented (2M invocations/month, etc.).
- **RumptyCloud cost:**
  - storage 10 GB free, then $0.02/GB-month;
  - synthetic tests stay well under 100 MB, so **expected cost $0**;
  - internet egress price is undocumented, but volumes here are negligible;
  - billing is prepaid with no spend alerts: keep the balance minimal, with no auto top-up.

## 8. Exact files that would change (when approved)

| File | Change |
|---|---|
| `functions/package.json` / lockfile | Add `@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner` |
| `functions/media.js` (**new**) | S3 client factory, key generation, limits, `requestMediaUpload`, `confirmMediaUpload`, `getMediaUrl`, `deleteMedia`, test fakes |
| `functions/index.js` | `require('./media')` and export the four callables (no other change) |
| `functions/.secret.local` (local only, **owner creates; never committed**) | `RUMPTY_ACCESS_KEY_ID`, `RUMPTY_SECRET_ACCESS_KEY` |
| `functions/.env.handytrust-staging` (new, non-secret) | `RUMPTY_BUCKET`, `RUMPTY_ENDPOINT`, `RUMPTY_REGION` |
| `firestore.rules` | `match /media/{id}`: client read for owner/admin; client write denied |
| `functions/test/media_emulator.test.js` (**new**) | Tier 1 + tier 2 tests (§6) |
| `lib/models/media_ref.dart`, `lib/core/services/media_service.dart`, `lib/providers/media_provider.dart` (**new**) | Client upload/confirm/get-URL with progress and retry; not wired into any screen in this phase |
| `test/media_service_test.dart` (**new**) | Client tests with a fake callable and HTTP |
| `.gitignore` | Confirm `.secret.local`; add `functions/.env.*.local` |

## 9. Decisions for the owner

1. Approve Phase 2 implementation (dependencies, `media.js`, rules, tests) for **local emulator use**.
2. Confirm the key's permissions, or create a second delete-only key. Place the secrets in `functions/.secret.local` yourself.
3. Permit tier-2 live tests from the emulator against the staging bucket (synthetic data, about $0).
4. Decide later whether to move `handytrust-staging` to Blaze for cloud deployment (cost decision).
