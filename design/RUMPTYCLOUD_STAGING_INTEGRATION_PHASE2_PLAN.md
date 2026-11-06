# RumptyCloud staging integration — Phase 2 plan (revised design)

> **Implementation status (6 November 2026).** Implemented locally and tested offline; live tests not yet run. See `RUMPTYCLOUD_STAGING_INTEGRATION_IMPLEMENTATION_REPORT.md`. The plan below is kept as written. Where the implementation differs:
> - **Upload path:** proxy is the default and only active path. Presigned PUT is implemented but gated behind `RUMPTY_PRESIGNED_PUT_VERIFIED=true`, to be set only after T2-03 and T2-08 pass. The plan made presigned PUT primary.
> - **K2 secret names:** `RUMPTY_CLEANUP_ACCESS_KEY_ID` / `RUMPTY_CLEANUP_SECRET_ACCESS_KEY` added (§11 named only K1's).
> - **Export switch:** `index.js` exports the media callables only for `demo-*` or `handytrust-staging` project IDs. The emulator discovers functions before reading `.env` files, so an `.env` switch can't work.
> - **Reconciliation (§6):** reports untracked objects and never deletes them (emulator data is ephemeral; no broad bucket clean-up).
> - **T2-04 (POST policy):** not implemented. T2-11 and T2-12 were added.
> - **Thumbnails:** 1 MB and 512 px limit.
> - **`firebase.json` emulator ports:** added for Auth, Functions and Storage.
> - **Android emulator-mode build switch:** `HT_EMULATOR`.


**Date:** 5 November 2026. **Status:** design only.

**Not done:**
- no dependency installed;
- no bucket or key created;
- no credentials entered;
- no live test run;
- nothing deployed or committed.

**Supersedes:** sections 3–8 of `RUMPTYCLOUD_STAGING_INTEGRATION_PHASE1_REPORT.md` wherever they differ.

**Evidence labels.** Every capability claim below carries one of these:

| Label | Meaning |
|---|---|
| **[V]** | Stated in RumptyCloud's documentation (`docs.rumptycloud.com`, read 5 November 2026; see `RUMPTYCLOUD_OBJECT_STORAGE_AUDIT.md`) |
| **[P]** | Observed in our anonymous live probe on 5 November 2026 (no credentials) |
| **[S3]** | Standard Amazon S3 / SigV4 behaviour. **RumptyCloud doesn't document it**, so it's an assumption until a tier-2 test proves it |
| **[D]** | Our design decision |
| **[Q]** | Unresolved question. §11 lists what resolves it and the fallback |

---

## 1. Vendor facts this design relies on

| Fact | Label |
|---|---|
| S3-compatible API, SigV4, endpoint `https://s3.rumptycloud.com`, region `olas-closet`, path-style addressing | [V] [P] |
| Private bucket: anonymous list and GET return 403 | [P] |
| Presigned PUT is supported; the signed Content-Type must match, or `SignatureDoesNotMatch` | [V] |
| Private buckets are read through expiring signed URLs. Presigned GET has no example | [V] (GET: [Q1]) |
| One key covers one bucket; permissions are any combination of list/read/write/delete; no prefix scoping; permissions can't be edited; presigned URLs carry the signing key's rights | [V] |
| Write permission also covers ACLs and tags | [V] |
| Single PUT up to 5 GB; multipart supported (parts ≥ 5 MB, ≤ 10,000 parts); incomplete multipart uploads are auto-deleted after 7 days | [V] |
| No versioning and no object lock: deleted or **overwritten** objects can't be recovered | [V] |
| DeleteObject, and DeleteObjects for up to 1,000 keys | [V] |
| 600 write requests per minute per key (503 SlowDown); reads aren't limited per key | [V] |
| First 10 GB free, then $0.02/GB-month; prepaid; no spend alerts | [V] |
| Internet egress price, request pricing, encryption at rest, durability, SLA | Not documented |

---

## 2. Revised flow and states

```
requestMediaUpload({kind, mimeType, sizeBytes, sha256})
  ├─ auth: signed in, not anonymous, verified email
  ├─ per-kind type/size limits (§3)
  ├─ ONE Firestore transaction:
  │    - rate window + daily count (§4)
  │    - storage quota: reserve sizeBytes (§4)
  │    - pending count (§5)
  │    - create media/{id} {status:'pending', expiresAt: now+15 min, …}
  ├─ presign the PUT (300 s): Content-Type + Content-Length (+ checksum, if proven) signed (§3, §7)
  └─ return {mediaId, uploadUrl, requiredHeaders}

client PUT ──▶ RumptyCloud

confirmMediaUpload({mediaId})
  ├─ caller is the owner; status == 'pending'; not expired
  ├─ status → 'verifying'
  ├─ HeadObject: size == declared, type == declared
  ├─ GetObject (stream): SHA-256 + content checks (§7, §8)
  ├─ pass → 'verified'; reservation becomes usage
  └─ fail → DeleteObject → 'rejected'; reservation released

getMediaUrl({mediaId})  → only if status == 'verified' and caller is allowed → presigned GET (300 s)
deleteMedia({mediaId})  → 'deleting' (access revoked first) → DeleteObject → verify 404 → 'deleted' (§9)
sweep (§6)              → expire abandoned pendings, retry deletions, reconcile orphans
```

**States [D]:**

| From | To |
|---|---|
| `pending` | `verifying` (on confirm) or `expired` (by the sweep) |
| `verifying` | `verified` or `rejected` |
| `verified` | `deleting` |
| `deleting` | `deleted` or `delete_failed` (alerts an admin) |

`getMediaUrl` signs only for `verified`.

**Design rules [D]:**
- The client never supplies an object key, owner, bucket or URL.
- No signed URL is stored.
- The `media/{id}` document is written **before** any URL is signed, so an object normally can't exist without a record.

---

## 3. Size enforcement before and during upload (correction 1)

| Stage | Control | Label |
|---|---|---|
| Before signing | The declared `sizeBytes` must be within the kind's limit (images 5 MB, video 50 MB) and the user's remaining quota. The bytes are reserved in the same transaction | [D] |
| During upload (single PUT) | The presigned PUT **signs `Content-Length` = the declared size**: AWS SDK v3 `getSignedUrl(..., { signableHeaders: new Set(['content-type','content-length']) })` with `ContentLength` on the command. A request with any other length, or with chunked encoding, fails the signature check. The gateway reads exactly that many bytes | SDK: [S3]; gateway enforcement: **[Q2]** |
| During upload (video, if multipart is needed) | The server creates the multipart upload and signs **exactly** `ceil(size/partSize)` UploadPart URLs, each with a signed Content-Length. The total can't exceed the declaration | Multipart [V]; per-part signed length [S3] [Q2] |
| Fallback A, if Q2 fails | Presigned **POST** with a `content-length-range` policy | Not documented: **[Q3]** |
| Fallback B, if Q2 and Q3 fail | Images ≤ 5 MB are uploaded **through** a Function, which streams to RumptyCloud and stops at the limit. Video stays disabled until there's a vendor control | [D] |
| After upload (defence in depth) | HEAD size must equal the declaration; the full-read verification (§7) counts the bytes again | [S3] |

The tier-2 tests must show that an oversized body, an undersized body and a chunked body are all **rejected by RumptyCloud**, not just caught afterwards (T2-03). Until they do, the staging limits rely on Fallback B for anything larger than a test fixture.

---

## 4. Per-user rate limits and storage quotas (correction 2)

All limits are enforced in the Firestore transaction that creates `media/{id}` [D].

| Limit (staging values) | Value | Where |
|---|---|---|
| Upload requests per user | 10 per 10 minutes; 50 per day | `media_quotas/{uid}`: `windowStart`, `windowCount`, `dayStart`, `dayCount` |
| Storage per user (verified + reserved) | 100 MB | `media_quotas/{uid}`: `usedBytes`, `reservedBytes` |
| Total staging storage | 1 GB, well inside the 10 GB free tier [V] | `media_system/limits`: `usedBytes`, `reservedBytes` |
| Signed write URLs, all users | ≤ 120 per minute, 20% of the 600/min per-key limit [V], leaving room for deletes and sweeps | `media_system/limits`: `minute`, `minuteCount` |

**Accounting:**
- Reserved bytes become used bytes on `verified`.
- They're released on `rejected` or `expired`, and on `deleted` for used bytes.
- Every change is in a transaction alongside the status change.

**Errors:**
- Limits are refused with `resource-exhausted` and a retry-after hint. No details of other users are revealed.
- A user exhausting the shared key limit would affect everyone. The global limiter prevents that [D].

Whether deletes and multipart parts count toward the 600 writes/min is **[Q8]**. The design assumes they do.

`media_system/limits` is a single document, which is fine at staging volume. Production needs sharded counters [D].

---

## 5. Maximum pending uploads (correction 3)

| Limit | Value |
|---|---|
| Pending uploads per user | 3 at a time |
| Pending uploads overall (staging) | 30 at a time |
| Pending lifetime | `expiresAt` = 15 minutes; the upload URL expires after 5 minutes [D] |

- A request over a limit is refused (`resource-exhausted`) **after** first expiring the caller's own stale pendings (§6).
- The client can cancel a pending upload (`deleteMedia` on a `pending` record releases it at once).

---

## 6. Clean-up of abandoned and expired uploads (correction 4)

`_sweepMedia(now, limit)` is one pure, testable function [D].

1. **Expired pendings** (`pending` and `expiresAt < now`):
   - HEAD the object; if present, DeleteObject.
   - Abort any multipart upload.
   - Status → `expired`; release the reservation.
2. **Stuck verifying** (`verifying` for more than 10 minutes, e.g. a crashed confirm): treated like an expired pending.
3. **Deletion retries:** see §9.
4. **Orphan reconciliation:**
   - ListObjectsV2 under `staging/` (needs **list** permission [V]).
   - Delete any object older than 24 hours with no `media` record, or whose record is `rejected`, `expired` or `deleted`.

**When it runs:**

| Trigger | Coverage | Label |
|---|---|---|
| Opportunistic | `requestMediaUpload` first sweeps **the caller's own** expired pendings (at most 5) | [D] |
| Scheduled, every 30 minutes | Needs Cloud Scheduler, which is **not available on Spark**. Only after an approved Blaze move | [D] |
| Locally, on Spark | Tests call `_sweepMedia` directly. An admin-only callable `runMediaSweep` runs it on demand in the emulator | [D] |
| Vendor backstop | Incomplete multipart uploads auto-delete after 7 days | [V] |

---

## 7. Real SHA-256 verification (correction 5)

| Method | Status | Label |
|---|---|---|
| **Authoritative:** `confirmMediaUpload` streams the stored object (GetObject) through Node `crypto.createHash('sha256')` and compares it with the declared hash. On mismatch: delete, then `rejected` | Required. No new dependency | Streaming GetObject: [S3] |
| **Early rejection (optional):** sign `x-amz-checksum-sha256` into the PUT, so the store rejects a mismatched body | Used only if T2-05 proves RumptyCloud rejects a wrong checksum | **[Q4]** |
| ETag | **Never** used as proof: it's MD5 for single PUT and opaque for multipart | [S3] |

**Cost:**
- Each verification downloads the object once.
- Staging volumes are negligible; the egress price is not documented.
- For production this must be re-costed before video is enabled.
- Function timeout 120 s, memory 512 MB; streamed, never buffered whole [D].

---

## 8. File-content validation (correction 6)

Content-Type is **not** trusted. In the same streamed pass as §7 [D]:

| Check | Rule |
|---|---|
| Magic bytes | Small in-house sniffer, no dependency: JPEG `FF D8 FF`; PNG `89 50 4E 47 0D 0A 1A 0A`; WebP `RIFF····WEBP`; MP4 `ftyp` at offset 4 with an allowed brand (`isom`, `iso2`, `iso5`, `iso6`, `mp41`, `mp42`, `avc1`). The sniffed type must equal the declared type |
| Image structure | Parse dimensions from the PNG IHDR, the JPEG SOFn segments and the WebP VP8/VP8L/VP8X header. Reject over 8,000 px on a side or over 40 megapixels (decompression-bomb guard) |
| MP4 structure | Walk the top-level boxes: `ftyp` first, `moov` present, `mvhd` duration ≤ 120 s (staging) |
| Not allowed | SVG, HTML and every other type: there's no allow-list entry for them |
| Serving | Presigned GET sets `response-content-type` to the **verified** type and `response-content-disposition: inline`. Whether the gateway honours these overrides is **[Q5]**; if not, the stored Content-Type (signed at upload) is used |

**Production prerequisites, not part of staging:**
- full decode and re-encode;
- EXIF/GPS stripping;
- malware scanning.

Location metadata in phone photos is a privacy issue that must be solved before real photos are stored.

---

## 9. Recovery from failed deletions (correction 7)

1. **Revoke first [D].** `deleteMedia` sets `deleting` **before** calling RumptyCloud, so `getMediaUrl` stops signing immediately. URLs already issued expire within 5 minutes.
2. **Delete:**
   - DeleteObject;
   - then HEAD must return 404 before the status becomes `deleted`;
   - a delete of a missing key is treated as success (S3 returns 204) [S3] [Q6].
3. **On failure:**
   - record `deleteAttempts`, `lastDeleteError` (error name and HTTP status only) and `nextDeleteAt`;
   - backoff 1 min, 5 min, 30 min, 2 h, 12 h, then every 24 h;
   - after 8 attempts → `delete_failed`, plus an `admin_alerts` document.
   - 503 SlowDown [V] and network errors count as retryable.
4. **Idempotency:** repeated `deleteMedia` calls on `deleting` or `deleted` return the current state and do nothing else.
5. **Quota:** used bytes are released on `deleted` only. A failed deletion stays billed against the user's quota.
6. **No versioning [V]:** a successful delete is final. Deletion therefore only ever runs through this audited path, never from client-held URLs (no delete URL is ever signed).

---

## 10. Bucket-key permissions and what they mean (correction 8)

**Recommended: two keys for the staging bucket [D].**

| Key | Permissions | Used for | If it leaks |
|---|---|---|---|
| **K1 "signer"** | read + write | Signing PUT, UploadPart and GET URLs; HEAD/GET for verification; creating, completing and aborting multipart uploads (multipart needs write only [V]) | Reads every object in the bucket. **Overwrites any object, which is destruction even without delete permission, because there's no versioning [V]**. May set ACLs [V]; whether a public-read ACL exposes an object in a private bucket is **[Q7]** |
| **K2 "janitor"** | list + read + delete | `deleteMedia`, the sweep, orphan reconciliation | Lists, reads and deletes everything in the bucket |

**What the split does and doesn't protect:**
- Both keys sit in the same Functions runtime, so a compromise of the runtime exposes both.
- The split gives:
  - least privilege per code path;
  - URLs handed to clients are signed by a key with no list or delete rights;
  - an operator script or a laptop clean-up only ever needs K2.
- A presigned URL grants only the signed method, object key and expiry [S3]. Whether the gateway rejects **unsigned** extra headers such as `x-amz-acl: public-read` on a presigned PUT is **[Q7]**, tested in T2-08.

**Other key rules:**
- **One key with all four permissions** is acceptable *only* for synthetic staging data if the owner prefers it, and never for production.
- **Bucket-wide scope [V]:** a staging key can touch every object in the staging bucket. The staging bucket must never hold production media. Production gets its own buckets and keys.
- **Rotation is manual [V]:**
  - rotate on any suspected exposure;
  - revoke both keys at the end of the staging experiment;
  - record key **names and permissions** (never values) in the run log.

**Owner action:** report the permissions of the key already created (names only). If it has all four, either create K1 and K2 and revoke it, or accept the single key for staging in writing.

---

## 11. Keeping local credentials out of Git (correction 9)

**Checked in the repository today (`git check-ignore -v`):**

| Path | Ignored? |
|---|---|
| `functions/.secret.local` | **Yes** (`.gitignore:48`) |
| `functions/.env.local` | **Yes** (`.gitignore:49`) |
| Emulator logs (`firebase-debug.log`, `firestore-debug.log`, `ui-debug.log`, `pubsub-debug.log`) | **Yes** (`*.log`, `.gitignore:3`) |
| `functions/.env`, `functions/.env.handytrust-staging` | **No.** By design: Firebase reads them at deploy time. **Never put secrets in them** |
| Tracked files named `*.secret*`, `.env*`, `runtimeconfig` or service-account | None (`git ls-files`) |

**Correction to Phase 1 [D]:**
- Local runs use a **`demo-handytrust-media`** emulator project ID. Firebase treats `demo-` projects as emulator-only, so nothing can reach a real project.
- The non-secret settings (`RUMPTY_BUCKET`, `RUMPTY_ENDPOINT`, `RUMPTY_REGION`) go in the **ignored** `functions/.env.local`.
- `functions/.env.handytrust-staging` is created only if a cloud deployment is approved.

**Controls to add:**
1. **Pre-commit check:**
   - a versioned script `tool/check_no_secrets.js` (Node, no dependencies);
   - it scans `git diff --cached` for `RUMPTY_ACCESS_KEY_ID=` or `RUMPTY_SECRET_ACCESS_KEY=` with a value, for 40-character base64-like strings, and for the key-ID prefix held in an ignored local file;
   - the owner installs it as `.git/hooks/pre-commit`.
2. **Repository test:** `git check-ignore` succeeds for `functions/.secret.local` and `functions/.env.local`, and `git ls-files` lists neither.
3. **Logging rule:**
   - `media.js` logs only `{event, mediaId, status, errorName, httpStatus}`;
   - a unit test passes an SDK-style error containing a fake secret and access-key ID, and asserts neither appears in the log line;
   - SDK error objects are never logged whole: S3 error bodies can echo the access-key ID [S3].
4. **Error responses:** callables return fixed messages (`failed-precondition: storage not configured`) and never the SDK message.

**Existing hazard, not a credential leak:**
- **5,752 files under `functions/node_modules` are tracked** (since `efe5398`), although `node_modules/` is now ignored.
- Installing the AWS SDK would modify tracked files and make the diff unreviewable.
- **Owner decision before Phase 2:** stop tracking them (`git rm -r --cached functions/node_modules`) in a separate, approved commit.

**Limits:**
- A local hook can be bypassed (`--no-verify`) and isn't enforced server-side.
- A push-time secret scan would need GitHub settings, which are out of scope.

---

## 12. Spending and clean-up limits for live tests (correction 10)

**Guards before any live run [D]:**
- `RUMPTY_LIVE=1`;
- `RUMPTY_LIVE_BUCKET` must equal the single allow-listed staging bucket (`assets-handytrust-01a0f99e-5d6ffa`);
- the endpoint must be `https://s3.rumptycloud.com`;
- the project ID must start with `demo-`.

Otherwise the live tier is skipped, with no network call.

**Limits per run:**

| Limit | Value |
|---|---|
| Objects created | ≤ 30 |
| Bytes uploaded | ≤ 25 MB |
| Largest object | ≤ 8 MB. The 50 MB video limit is tested by *declaration* and refusal, never by uploading 50 MB |
| Write requests | ≤ 60 per minute, 10% of the key limit |
| Runtime | ≤ 10 minutes, then the harness aborts and cleans up |

**Limits per day:**
- ≤ 5 runs;
- ≤ 125 MB uploaded plus ≤ 125 MB downloaded for verification.

**Clean-up:**
- Every object goes under `staging/livetest/{runId}/`.
- `after()` deletes the run's objects. The next run starts by deleting leftover `livetest` objects older than 1 hour.
- The final ListObjectsV2 of the run prefix **must return 0 objects**, or the run fails and prints the keys (never secrets) for manual deletion.
- Stored data after each run: zero.

**Money:**

| Cost | Expectation | Label |
|---|---|---|
| Storage | **$0**: below 100 MB at any moment, inside the 10 GB free tier | [V] |
| Egress | Price not documented. Transfer is capped at about 0.25 GB per day | — |
| **Hard limit** | The owner keeps the prepaid balance at **$5 or less**, with **auto top-up off** (prepaid, no spend alerts [V]) | — |

- The owner notes the balance before and after each live session.
- **Any decrease stops all live testing** until it's explained.

**Data:** synthetic only. Tests generate their files: random bytes for negative tests, and tiny valid JPEG, PNG, WebP and MP4 fixtures. No production, job, chat, dispute or identity media.

---

## 13. Open questions and how each is resolved

| Q | Question | Resolved by | If the answer is "no" |
|---|---|---|---|
| Q1 | Does presigned GET work on the private bucket? | T2-02 | Serve through a Function proxy (staging only) |
| Q2 | Does the gateway enforce a signed `Content-Length` (and per-part lengths)? | T2-03 | Fallback A or B (§3) |
| Q3 | Is presigned POST with `content-length-range` supported? | T2-04 (only if Q2 fails) | Fallback B |
| Q4 | Is `x-amz-checksum-sha256` verified? | T2-05 | Rely on the authoritative verification only (§7) |
| Q5 | Are `response-content-type` and `response-content-disposition` overrides honoured? | T2-06 | Use the stored Content-Type |
| Q6 | Does DeleteObject on a missing key return success? | T2-07 | Treat 404 as success in code |
| Q7 | Are unsigned `x-amz-acl` headers rejected, and does a public-read ACL expose a private-bucket object? | T2-08 | Treat K1 as able to publish objects. Monitor with periodic anonymous-GET probes; raise with the vendor |
| Q8 | Do deletes and multipart parts count toward the 600 writes/min? | Vendor support / T2-09 observation | Assume they do (already assumed) |
| Q9 | What are the internet egress price, encryption at rest and durability? | Vendor support (owner) | No production use until answered |

---

## 14. Test plan

### Tier 1: offline (always run; S3 faked through `_setMediaS3Fakes`)

| ID | Test |
|---|---|
| T1-01 | Authentication: unauthenticated, anonymous and unverified-email callers are rejected |
| T1-02 | Wrong kind, MIME type or declared size rejected before signing; the signed request includes Content-Type and Content-Length |
| T1-03 | Rate window, daily count, user quota, global quota and the global per-minute limiter (boundary values) |
| T1-04 | Pending limits per user and overall; the caller's own expired pendings are swept before refusal |
| T1-05 | Confirm by a non-owner is denied; an expired pending can't be confirmed |
| T1-06 | SHA-256 mismatch → delete + `rejected` + reservation released |
| T1-07 | Magic-byte sniffing, dimension limits and MP4 structure (valid fixtures pass; renamed, polyglot, oversized-dimension and truncated files fail) |
| T1-08 | `getMediaUrl` only for `verified`, and only for allowed callers |
| T1-09 | Deletion: revoke first; retries with backoff; `delete_failed` alert after 8 attempts; idempotent repeat; quota released only on `deleted` |
| T1-10 | Sweep: expired pendings, stuck verifying, orphan reconciliation |
| T1-11 | Missing credentials → `failed-precondition` with a fixed message; log lines exclude the injected fake secret and key ID |
| T1-12 | Repository: secret and env files are ignored and untracked; the pre-commit script blocks a staged fake secret |
| T1-13 | Rules: `media`, `media_quotas` and `media_system` are not writable by clients; owner read only where intended |

### Tier 2: live staging (opt-in, §12 guards; separate approval)

| ID | Test |
|---|---|
| T2-01 | Full upload → confirm → verified with a real fixture |
| T2-02 | Presigned GET works for the owner; anonymous GET → 403; an expired URL fails |
| T2-03 | Body larger, smaller or chunked compared with the signed Content-Length → rejected by the store |
| T2-04 | Presigned POST size range (only if T2-03 fails) |
| T2-05 | Wrong checksum header → rejected (or documented as ignored) |
| T2-06 | Response-header overrides honoured |
| T2-07 | DeleteObject on a missing key |
| T2-08 | Presigned PUT with an added `x-amz-acl: public-read` header; then anonymous GET must still return 403 |
| T2-09 | Content-Type mismatch → `SignatureDoesNotMatch`; URL expiry enforced |
| T2-10 | Clean-up: the run prefix lists 0 objects at the end |

---

## 15. Exact files for Phase 2 (when approved)

| File | Change |
|---|---|
| `functions/package.json`, `functions/package-lock.json` | Add `@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner` (after the `node_modules` untracking decision) |
| `functions/media.js` (**new**) | Client factory, limits, quotas, state machine, sniffer, SHA-256 verification, the four callables plus `runMediaSweep` (admin), `_sweepMedia`, test fakes |
| `functions/index.js` | `require('./media')` and re-export; no other change |
| `firestore.rules` | `media/{id}` (owner/admin read; no client write); `media_quotas/{uid}` (owner read; no client write); `media_system/{doc}` (no client access) |
| `functions/test/media_offline.test.js` (**new**) | Tier 1 |
| `functions/test/media_live.test.js` (**new**) | Tier 2, skipped unless the §12 guards pass |
| `functions/test/fixtures/media/*` (**new**, a few KB each) | Synthetic JPEG, PNG, WebP and MP4, plus malformed variants |
| `firestore-tests/media_rules.test.js` (**new**) | Rules tests for T1-13 |
| `tool/check_no_secrets.js` (**new**) | Pre-commit secret scan (T1-12) |
| `lib/models/media_ref.dart`, `lib/core/services/media_service.dart`, `lib/providers/media_provider.dart` (**new**) | Client request → PUT (with the required headers) → confirm; not wired into any screen |
| `test/media_service_test.dart` (**new**) | Client tests with a fake callable and HTTP |
| `functions/.env.local`, `functions/.secret.local` | **Local only, ignored, created by the owner**. Never committed |
| `.gitignore` | No change needed (already covers both); add `tool/.secret-prefix.local` |

---

## 16. Owner decisions for Phase 2

1. Untrack `functions/node_modules` in a separate commit, or accept a noisy dependency diff.
2. Key setup: K1 and K2 (recommended), or written acceptance of one all-permission key for staging only. Report permissions by name only.
3. Approve tier 1 (offline) implementation: no network, no credentials, $0.
4. Separately approve tier 2 live tests, with the §12 limits and the $5 prepaid ceiling with auto top-up off.
5. Ask the vendor Q8 and Q9 (needed before any production decision, not for staging).
6. Blaze for `handytrust-staging`: only needed for a cloud deployment and the scheduled sweep. Not requested.
