# HandyTrust — production-readiness priority report

**Stage:** H1.1. **Nothing in this report has been fixed.** An issue counts as resolved only when its fix is implemented and independently verified.
**Evidence key:** **V** = verified in code, config or an emulator test on 5 November 2026; **U** = unverified concern (needs console access or a device).

## Ranked list

| Rank | Issue | Evidence | Severity | Likelihood | Business / security impact | Complexity | Cost | Depends on | Plan |
|---|---|---|---|---|---|---|---|---|---|
| 1 | No Firestore backup / PITR / restore runbook | **V** (repo); **U** whether anything is set in the console | Critical | Medium | Permanent loss of accounts, jobs and money records; no recovery from bad deploys | Low (console config) + medium (drills) | Low (small DB) | Blaze plan; database location | `HANDYTRUST_FIRESTORE_BACKUP_AND_RECOVERY_PLAN.md` |
| 2 | Release builds signed with the debug key | **V** (`build.gradle.kts`) | High | Certain (whenever released) | Can't publish on Play; inconsistent signatures block upgrades; no stable fingerprint for App Check | Low | None | Owner creates the keystore | `HANDYTRUST_ANDROID_RELEASE_SIGNING_PLAN.md` |
| 3 | Placeholder application ID `com.example.handy_trust` | **V** (7 files) | High | Certain (Play rejects `com.example`) | Blocks store release; changing it after launch creates a new app | Low–medium | None | Domain decision; do it with #2 | `HANDYTRUST_APPLICATION_ID_MIGRATION_PLAN.md` |
| 4 | No staging Firebase project; one project for everything | **V** | High | Medium | Testing risks touching production data and Paystack live mode | Medium | Low | — | `RUMPTYCLOUD_STAGING_DEPLOYMENT_PLAN.md` (H3 prerequisites) |
| 5 | App Check not enabled | **V** (no SDK) | Medium | Medium | Scripted abuse of callables and queries within the rules; quota and cost abuse | Medium (staged) | Low | #2, #3 | `HANDYTRUST_FIREBASE_APP_CHECK_PLAN.md` |
| 6 | Push: server ignores the notification preference and never cleans invalid tokens; one token per user | **V** (`functions/index.js` onNotificationCreated) | Medium | High | Opted-out users still get pushes on devices that keep a token; stale tokens accumulate; multi-device users miss pushes | Low–medium (Functions) | None | Approval of backend change | `STAGE8_2_NOTIFICATION_AUDIT.md` §5 |
| 7 | Chat push previews include message text on the lock screen (background) | **V** (`_messagePreview`) | Medium | High | Private message content visible on locked devices | Low (Functions) | None | Approval | `STAGE8_2_NOTIFICATION_AUDIT.md` §5 |
| 8 | Message `isRead` may be changed by the sender too (rule allows sender or receiver; any value) | **V** (`firestore.rules` messages update) | Low–medium | Low | A sender could fake "read"; read state could be reset | Low (rules) | None | Approval; rules tests | `STAGE8_2_NOTIFICATION_AUDIT.md` §5 |
| 9 | No "delivered" receipt state | **V** | Low | — | Feature gap only | Medium (field + rules + client) | None | Approval | `STAGE8_2_NOTIFICATION_AUDIT.md` §5 |
| 10 | Cloud Storage media not backed up or versioned | **V** (no config in repo); **U** (console) | Medium | Low | Lost photos and evidence after an accidental delete | Low | Low | — | Backup plan §3.6 |
| 11 | No CI (tests and builds run by hand) | **V** | Medium | High | Regressions and unsigned builds reach testers | Medium | Low (free tier) | #2 | — |
| 12 | README states fixed issues as open and claims phone sign-in | **V** | Low | Certain | Misleading for reviewers | Low | None | — | `HANDYTRUST_DOCUMENTATION_CORRECTIONS.md` |
| 13 | Unused Dio `ApiClient` / `SecureTokenManager` with a placeholder URL | **V** | Low | Low | Dead code that could be misused later | Low | None | — | Remove, or rebuild per the RumptyCloud target architecture §4.1 |
| 14 | Router redirect uses `ref.watch` inside the GoRouter callback | **V** (Riverpod debug assertion under tests) | Low | Low | Possible router rebuild churn | Low | None | — | Separate reviewed change |
| 15 | Combined Functions test run interferes in one emulator (`singleProjectMode`) | **V** | Low | — | Test harness only | Low | None | — | Run files separately, or set `singleProjectMode: false` for tests |
| 16 | RumptyCloud platform risks: single region, no SLA, no DB backups, no spend alerts, unscoped account API keys, no bucket versioning | **V** (vendor docs) | Medium for any production use | — | Outage or data loss if used for authoritative or sensitive data | — | — | — | H1 and H1.2 documents; staging and public assets only |

## Recommended order

1. **Week 1 (configuration, no app change):**
   - enable PITR and daily/weekly backups (#1);
   - set up the backup project and retention-locked export (#1);
   - correct the README (#12).
2. **Before any wider distribution:** release signing and application ID together (#2, #3); register fingerprints.
3. **Next:**
   - staging Firebase project (#4) and CI (#11);
   - approved backend notification fixes (#6, #7, #8), with rules and Functions tests on the emulator.
4. **Then:** App Check, monitored then enforced (#5); media versioning (#10).
5. **Later:** "delivered" receipts (#9), code clean-ups (#13, #14).

## Owner approvals required

Items 1–11 each need explicit approval before implementation. None was started in H1.1.
