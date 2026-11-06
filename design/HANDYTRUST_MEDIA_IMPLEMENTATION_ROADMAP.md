# HandyTrust — media implementation roadmap (H1.2)

> **Superseded in part (5 November 2026):** see `RUMPTYCLOUD_MEDIA_MIGRATION_ROADMAP.md` for the order in §1 (phases M0–M9, one category at a time). The rest of this document still applies.

**Planning only. Nothing implemented.**

## 1. Recommended order

1. **Prerequisites (from H1.1):**
   - staging Firebase project;
   - Firestore backups;
   - release signing and app ID;
   - CI.
2. **Fix existing issues independently of RumptyCloud:**
   - M2: delete `profiles/{uid}/` on account deletion (Functions);
   - remove the unused `uploadProfilePhoto` (legacy `users/` path).
3. **Staging proof** (RumptyCloud staging workspace, test buckets, keys as Functions secrets in the staging project):
   - run tests T1–T20 (§3);
   - get a written egress quote.
4. **Owner decision:** proceed with public media only, or stop.
5. **Phase 1:** dual-provider reading (app release).
6. **Phase 2:** public media to RumptyCloud behind a flag; backfill public media; monitor 30 days.
7. **Phase 3** (optional, after conditions): private media.
8. **Sensitive media:** stays in Firebase.

## 2. Work items

| Area | Item |
|---|---|
| Backend | Callables `requestMediaUpload`, `confirmMediaUpload`, `getMediaUrls`, `deleteMedia`; scheduled `sweepPendingMedia` and `retryMediaDeletes`; `media/` rules + indexes; secrets `RUMPTY_*_KEY` (write / read / delete per bucket); M2 fix |
| Flutter | `MediaService` (presigned PUT with progress; multipart for video; retry with backoff; duplicate hash); `MediaImage` resolver (public / signed with cache-until-expiry / legacy URL); feature flag from `config/platform`; upload error states |
| Deletion | Soft-delete → Functions delete with the delete key → mark `deleted`; idempotent (missing object counts as success, **to be verified**); retries with backoff; **retention:** dispute evidence and completion photos of disputed or recently completed jobs are never auto-deleted; account deletion removes public media and keeps job media (same policy as `adminDeleteUser`) |
| Ops | Key rotation runbook; weekly usage check (no spend alerts); outage switch (flag) |

## 3. Test plan (none executed yet)

| # | Test | Where |
|---|---|---|
| T1 | Authenticated upload succeeds; record verified | Staging |
| T2 | Unauthenticated `requestMediaUpload` rejected | Emulator |
| T3 | Non-party upload for a job rejected; suspended user rejected | Emulator |
| T4 | User A can't get a signed URL for B's private media | Emulator + staging |
| T5 | Private object fetch without a signature denied | Staging |
| T6 | Presigned PUT after expiry fails | Staging |
| T7 | Wrong Content-Type fails (`SignatureDoesNotMatch`) | Staging |
| T8 | Oversized upload detected by HEAD and deleted | Staging |
| T9 | Interrupted multipart upload resumes / expires after 7 days | Staging |
| T10 | Duplicate (same hash) returns existing media | Emulator |
| T11 | Confirm never called → swept after 24 h | Emulator |
| T12 | Delete flow idempotent; missing object handled | Staging |
| T13 | Deleted media no longer gets URLs | Emulator |
| T14 | Expired signed GET re-requested by the client | Widget + staging |
| T15 | Customer / artisan separation (party checks) | Emulator |
| T16 | Old Firebase URLs still render in the new app | Widget |
| T17 | An old app version still works after phase 2 | Device |
| T18 | Upload/download latency from Nigerian mobile networks vs Firebase | Staging device |
| T19 | Key revocation stops presigned URLs signed with it | Staging |
| T20 | RumptyCloud outage → flag fallback to Firebase | Staging |

## 4. Decisions requiring owner approval

1. Proceed to the staging proof (create a staging workspace, buckets and keys).
2. The `media/` schema and rules (backend).
3. Which media classes may move (recommended: public only).
4. Video support and limits (and any new Flutter plugin).
5. Accept or reject the risks: no versioning, encryption at rest not documented, single zone, no SLA, unknown egress price.
6. The M2 Functions fix (independent of RumptyCloud).
