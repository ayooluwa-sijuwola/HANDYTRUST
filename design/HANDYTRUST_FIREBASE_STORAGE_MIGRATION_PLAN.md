# HandyTrust — Firebase Storage → RumptyCloud migration plan (H1.2)

> **Superseded in part (5 November 2026):** see `RUMPTYCLOUD_MEDIA_MIGRATION_ROADMAP.md` for its phases and the "sensitive media not migrated" row (dispute evidence is now in scope as the last category; identity documents stay excluded). The rest of this document still applies.

**No file was moved, copied or deleted. No upload destination was changed.**

## 1. Inventory (verified)

| Workflow | Upload (client) | Stored reference | Delete | Rule path |
|---|---|---|---|---|
| Avatar | `ProfileService.uploadAvatar` → `profiles/{uid}/avatar.jpg` | `users.photoUrl`, `artisans.profileImageUrl` | `ProfileService.removeAvatar` | `profiles/{uid}` |
| Legacy profile photo | `StorageService.uploadProfilePhoto` → `users/{uid}/profile.jpg` (**no callers**) | — | `adminDeleteUser` (prefix) | `users/{uid}` |
| Job photos | `JobRequestNotifier` → `uploadJobImageBytes` → `jobs/{jobId}/{uid}/image_n.jpg` | `jobs.imageUrls` | none | `jobs/{jobId}/{uid}` |
| Completion photos | `SubmitWorkScreen` → `jobs/{jobId}/{uid}/{before,after}/...` | `jobs.beforePhotoUrls`, `jobs.completionImageUrls` | none | same |
| Chat images | `ChatNotifier.sendImageBytes` → `jobs/{jobId}/{uid}/image_<ms>.jpg` | `messages.imageUrl` | none | same |
| Portfolio | `PortfolioService` → `artisan_portfolio/{uid}/image_n.jpg` | `artisans.portfolioImageUrls`, `portfolio_projects.imageUrls` | `deletePortfolioImage` (`refFromURL`); `adminDeleteUser` (prefix) | `artisan_portfolio/{uid}` |
| Verification | `VerificationScreen` → `verifications/{uid}/{selfie,id_front}.jpg` | `verifications.selfieUrl` / `governmentIdUrl` | `adminDeleteUser` (prefix) | `verifications/{uid}` |
| Dispute evidence | dispute screens → `disputes/{id}/{uid}/evidence_n.jpg` | `disputes.evidenceImageUrls`, `artisanEvidenceUrls` | none (retained) | `disputes/{id}/{uid}` |

- No videos and no documents today; all uploads are JPEG.
- **Every installed app version** reads stored `https://firebasestorage.googleapis.com/...` URLs directly, so **those files must stay available indefinitely** for old versions.

## 2. Phases (each needs approval)

| Phase | Scope | Gate |
|---|---|---|
| 0 | Staging only: staging Firebase project; RumptyCloud staging workspace and buckets; Functions secrets; the `media/` design and rules written as a proposal with emulator tests | Audit tests T1–T20 pass in staging |
| 1 | App understands both providers (`media/{id}` with `provider`); still uploads to Firebase | New app version adopted by users |
| 2 | **Public media only**: new avatars and portfolio images go to RumptyCloud behind a flag in `config/platform` (`mediaProviderPublic`) | Flag can be turned off instantly |
| 3 | **Private media** (job, completion and chat photos), only if the security-review conditions are met | Written owner risk acceptance |
| 4 | Backfill of public media: copy → SHA-256 compare → write `media/{id}` with `legacyUrl` → keep the Firebase original | 100% checksum match |
| — | Sensitive media | **Not migrated** |

## 3. Rules for every phase

- **Never delete Firebase files during migration.** Old app versions and stored URLs depend on them. A later clean-up needs its own approval, after old versions are retired and the backfill is verified.
- **Idempotent backfill:** keyed by source path, so a re-run skips verified items. Duplicates are prevented by a `(sourcePath)` unique media ID.
- **Integrity:** compare size and SHA-256 per object; report mismatches; do not switch references until they match.
- **Rollback:** flag off → new uploads go back to Firebase. Readers handle both providers, so nothing breaks. Backfilled RumptyCloud copies can stay or be deleted.
- **Costs during migration:** both stores are paid for while duplicate copies exist (small at current volumes; see the cost analysis).

## 4. Required changes (when approved)

- **Backend:**
  - callables `requestMediaUpload`, `confirmMediaUpload`, `getMediaUrls`, `deleteMedia`;
  - a pending-upload sweeper;
  - `media/` rules and indexes;
  - Functions secrets;
  - a fix for the `adminDeleteUser` `profiles/` prefix (M2).
- **Flutter:**
  - `MediaService` (S3 PUT via the presigned URL with `dio`, multipart for video, progress, retry);
  - a `MediaRef` widget resolving public URL / signed URL / legacy URL;
  - dual-write of `mediaIds` beside URL fields;
  - a feature flag.
