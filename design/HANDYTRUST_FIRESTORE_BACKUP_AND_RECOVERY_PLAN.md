# HandyTrust — Firestore backup and disaster-recovery plan

**Stage:** H1.1 assessment. Nothing has been enabled, exported or provisioned.
**Date:** 5 November 2026.
**Sources:** Firebase documentation for Firestore scheduled backups (`firebase.google.com/docs/firestore/backups`) and PITR (`/docs/firestore/pitr`), read on that date. The Firestore pricing page could not be read in full, so no per-GiB backup prices are quoted here; use the Google Cloud calculator for the project's location.

## 1. Current state (verified in the repository)

- **Single database:** all authoritative records live in one Firestore database in project `handytrust`: accounts, jobs, chat, payments, escrow, settlements, refunds, chargebacks, disputes, audit logs.
- **No backup in place:** there is no backup schedule, export job, PITR setting or restore runbook in the repository or its documentation. Whether anything is configured in the console is **unverified**; check *Firestore → Disaster recovery* before acting.
- **Location unknown:** the database location is not recorded in the repo. Backups are stored in the same location as the database (documented).
- **Severity:** this is the most serious open recovery gap. A faulty deployment, a bad migration, an over-broad admin delete or a compromised credential could destroy records that also back money movements (escrow, settlements, refunds).

## 2. Mechanisms available (documented)

| Mechanism | What it gives | Limits (documented) |
|---|---|---|
| **Scheduled backups** | Consistent point-in-time snapshot of the whole database, including index configuration | Up to one daily and one weekly schedule per database; retention up to **14 weeks**; no choice of time of day; stored in the **same location** as the database; requires Blaze; restore goes to a **new** database; TTL policies not included; deleting the database does not delete backups |
| **Point-in-time recovery (PITR)** | One version per minute for the last **7 days**; stale reads for partial recovery; clone or export at a whole-minute timestamp | Off by default; no free tier; can't reach back 7 days right after enabling; only one version per minute |
| **Managed export / import** (`gcloud firestore export` to a Cloud Storage bucket) | Copy outside the database; can target a bucket in another project or location | Not a consistent snapshot unless taken from a PITR timestamp; import overwrites by document ID; costs reads + storage |

## 3. Recommended design

1. **Enable PITR** (7-day, minute-level). This covers the most likely incidents: a bad deploy, a script error or an accidental delete noticed within days. It restores single documents or collections without a full restore.
2. **Daily scheduled backup with 14-week retention, plus weekly with 14-week retention.** This covers corruption noticed after PITR's 7 days.
3. **Independent copy:** a weekly managed export from a PITR timestamp (consistent) into a Cloud Storage bucket in a **separate Google Cloud project** (`handytrust-backups`) with:
   - a separate billing alert;
   - **uniform bucket-level access**;
   - **object retention lock** (e.g. 90 days), so a compromised production credential can't delete the copies;
   - access granted only to a dedicated backup service account (write) and two named owners (read).

   Scheduled backups live inside the production project, so they share its blast radius; this copy doesn't.
4. **Not on RumptyCloud** for now. Bucket encryption at rest, key scoping, durability and object lock are undocumented there (`RUMPTYCLOUD_INTEGRATION_AUDIT.md`), and these exports contain personal and financial records.
5. **Storage rules and indexes** are versioned in git (`firestore.rules`, `storage.rules`, `firestore.indexes.json`). Restores rely on the repo for rules; whether backups include rules is not documented.
6. **Cloud Storage files** (photos, ID documents, evidence) are **not** covered by Firestore backups. Enable **object versioning** (with a lifecycle rule to expire non-current versions after 30 days) or a scheduled transfer to the backup project. This is a separate approval.

## 4. Objectives

| Objective | Target | How |
|---|---|---|
| **RPO** (data loss) | ≤ 1 minute for incidents noticed within 7 days; ≤ 24 hours beyond that, up to 14 weeks | PITR; daily backup |
| **RTO** (time to working service) | ≤ 4 hours for partial recovery; ≤ 1 business day for full recovery | Partial: stale read and write-back script. Full: restore to a new database, then switch the app (see §6) |

## 5. Access, encryption and monitoring

- **IAM:**
  - backup schedules: `roles/datastore.backupSchedulesAdmin` for one ops owner;
  - restore: `roles/datastore.restoreAdmin`, granted just-in-time;
  - the backup project is separate, with its own owners;
  - no developer keeps standing restore rights.
- **Encryption:** Google-managed encryption at rest is the default for Firestore and Cloud Storage. Customer-managed keys (CMEK) are optional and would need their own decision.
- **Monitoring:**
  - a Cloud Monitoring alert if no backup completes within 26 hours;
  - a monthly check that the latest backup and export exist;
  - the result recorded in a restore log.

## 6. Restore procedures (to be rehearsed before relying on them)

- **A. Partial (PITR stale read).** Identify the affected documents and the minute before the incident, read them at that timestamp, and write them back through an admin script. Every write is logged; financial collections are restored only with a second person reviewing.
- **B. Full (scheduled backup).**
  1. Restore to a new database ID (e.g. `restore-2026-11-05`).
  2. Verify document counts and spot-check money records.
  3. Then either point the app and Functions at the restored database (a code change: named database), or copy collections back into `(default)` by export/import.
  4. Pause Paystack webhook processing during cut-over; Paystack retries deliveries.
- **C. Drill:**
  - each quarter, restore the latest backup into a scratch database in a **non-production** project and verify counts;
  - record the RTO achieved;
  - delete the scratch database afterwards.

## 7. Cost (structure; prices to be confirmed for the location)

- PITR storage: billed on average database size; no free tier.
- Backups: storage per GiB-month for each retained backup; restore is charged per GiB restored.
- Exports: document reads plus Cloud Storage per GiB-month in the backup bucket.
- For a database of a few GiB (likely today), all of these are small (single-digit to low-double-digit USD per month). Confirm in the Google Cloud pricing calculator before approval.

## 8. Approvals needed (nothing done yet)

1. Enable PITR on `(default)`.
2. Create daily and weekly backup schedules (14-week retention).
3. Create a `handytrust-backups` project and bucket with retention lock, plus a backup service account.
4. A Cloud Storage versioning/transfer decision for media.
5. A quarterly restore drill in a non-production project.
