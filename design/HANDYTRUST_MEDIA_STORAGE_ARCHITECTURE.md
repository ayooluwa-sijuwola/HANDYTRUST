# HandyTrust — media storage architecture (H1.2 proposal)

> **Superseded in part (5 November 2026):** see `RUMPTYCLOUD_MEDIA_MIGRATION_ROADMAP.md` for the classification in §1 (customer profile pictures are private; dispute evidence is in scope as the last category) and the bucket layout (three buckets: public, private, evidence). The rest of this document still applies.

**Not implemented.** Firebase stays the authority for identity, data, rules and authorisation. RumptyCloud would store and serve media files.

## 1. Classification and recommended home

| Class | Media | Recommended store | Why |
|---|---|---|---|
| **Public** | Profile photos; public artisan portfolio images | RumptyCloud **public** bucket (phase 2) | Already shown to anyone who views a profile; low harm if exposed; good first candidate |
| **Private** | Customer job photos, before/after completion photos, chat images and documents, videos and their thumbnails | RumptyCloud **private** bucket with short-lived signed reads (phase 3, **only after** the gaps in the audit are closed or accepted) | Personal data; access must follow job membership |
| **Highly sensitive** | Government ID, selfies (`verifications/`), dispute evidence | **Stay in Firebase Storage** | No encryption-at-rest, durability or versioning evidence on RumptyCloud; evidence must be retained |

## 2. Upload flow (signed PUT issued by Firebase)

```
Flutter ── callable requestMediaUpload(kind, jobId?, mimeType, size) ──▶ Cloud Functions (Firebase)
   │                                   verifies: Firebase Auth (non-anonymous, verified email),
   │                                   role + ownership from Firestore (same checks as the rules),
   │                                   kind ↔ mime ↔ size limits; creates media/{id} status=pending
   │◀── { mediaId, uploadUrl (presigned PUT, ≤ 5 min, exact key + Content-Type) } ──
   ├── PUT bytes ─────────────────────────────────────────▶ RumptyCloud bucket
   └── callable confirmMediaUpload(mediaId) ──▶ Functions: HEAD object (size, type),
                                               mark verified or delete + reject;
                                               attach mediaId to the job/message/profile
```

- **The signing service is a Cloud Function, not a RumptyCloud API.**
  - Functions already hold Admin SDK access to Firestore roles and job membership, so there's no need to verify ID tokens on another platform or copy a service account there.
  - The RumptyCloud keys live only as Functions secrets: one write-only upload key and one read-only signing key per bucket. The delete key is used only by the deletion job.
- **The client never supplies object keys or owner IDs.** The server generates the key and binds it to `media/{id}.ownerUid = request.auth.uid`.
- Size is checked after upload (HEAD). Whether size can be enforced in the presigned PUT is undocumented, so oversized objects are deleted and the media is rejected.

## 3. Download flow

- **Public media:** a stable public URL derived from the object key (`assets.rumptycloud.com/...`). Store the key, not the URL.
- **Private media:**
  1. The callable `getMediaUrls(mediaIds[])` checks the same relationship the Firestore rules check (job party, conversation member, admin).
  2. It returns signed GET URLs valid for 5–15 minutes.
  3. The client caches them only until expiry.

## 4. Object keys (naming is not authorisation)

`{env}/{kind}/{yyyy}/{mm}/{uuid-v4}.{ext}`, e.g. `prod/job-photo/2026/11/3f6c…e1.jpg`.

- **No uid, job ID or name in the key.** Keys aren't guessable, and nothing personal leaks through them.
- **Separate prefixes per kind:** `avatar`, `portfolio`, `job-photo`, `completion`, `chat`, `video`, `thumb`, `admin`. These help lifecycle and cost reporting only.
- **Separate buckets per environment and class:** `ht-prod-public`, `ht-prod-private`, `ht-staging-*`, in separate RumptyCloud workspaces.
- **Authorisation** comes from the Firestore `media/{id}` document plus job, conversation and role checks in Functions. A key alone gives nothing: private objects need a signed URL.

## 5. Firestore metadata (proposed; no schema change made)

`media/{mediaId}`, written only by Cloud Functions; client read allowed by the rules for the owner and related parties:

| Field | Example | Notes |
|---|---|---|
| `provider` | `rumpty` \| `firebase` | Dual-provider during migration |
| `bucket`, `objectKey` | `ht-prod-private`, `prod/job-photo/...` | Stable reference; never store only a signed URL |
| `kind` | `job-photo` | — |
| `visibility` | `public` \| `private` \| `sensitive` | — |
| `mimeType`, `sizeBytes`, `width`, `height`, `durationMs` | — | Verified server-side |
| `ownerUid` | — | From `request.auth`, never from the client |
| `jobId` / `conversation` (`jobId`, `participants`) | — | Drives access |
| `status` | `pending` → `verified` \| `rejected` → `deleting` → `deleted` | — |
| `thumbnailMediaId` | — | — |
| `createdAt`, `verifiedAt`, `deletedAt`, `deleteAttempts`, `retainUntil` | — | Retention and deletion |
| `legacyUrl` | Firebase download URL | Migration only |

Entities gain `mediaIds` lists **alongside** the existing URL fields (`imageUrls`, `completionImageUrls`, `beforePhotoUrls`, `imageUrl`, `profileImageUrl`, `portfolioImageUrls`) until old app versions are retired.

## 6. Processing

| Operation | Where | Notes |
|---|---|---|
| Image compression / resize | **Flutter** (existing `flutter_image_compress`; EXIF/GPS stripped since Stage 7.1) | Unchanged |
| Thumbnails | Flutter generates them and uploads as a second media item | RumptyCloud documents no transforms |
| Video limits and validation | Flutter (duration / size pre-check) + Functions (HEAD size, MIME) | e.g. ≤ 60 s, ≤ 100 MB (owner to decide) |
| Video thumbnail | Flutter (would need a new plugin; needs approval) or server (ffmpeg in Functions: heavier) | — |
| Progress / interruption | Multipart upload for videos (> 8 MB); single PUT for images | Incomplete parts auto-expire after 7 days |
| Duplicates | Client-side content hash in the request; Functions return the existing verified media for the same owner + hash | — |

## 7. Failure modes

| Failure | Behaviour |
|---|---|
| RumptyCloud down | New uploads fail with a clear retry message. The phase-1/2 feature flag can route new uploads back to Firebase Storage. Existing Firebase files keep working |
| Confirm never called | Pending media older than 24 h is swept: object deleted, record marked rejected |
| Signed URL expired | The client requests a fresh one |
