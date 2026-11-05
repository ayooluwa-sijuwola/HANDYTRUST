# RumptyCloud hybrid integration — security review

**Stage:** H1 (planning).
**Scope:** the risks of adding RumptyCloud alongside Firebase, as described in `RUMPTYCLOUD_TARGET_ARCHITECTURE.md`.
**Sources:**
- RumptyCloud facts come from its official docs and pricing pages, read on 5 November 2026. Undocumented behaviour is treated as **unknown**, not safe.
- HandyTrust facts come from the repository.

## 1. Assets and where they must stay

| Asset | Sensitivity | Location (unchanged) | May RumptyCloud hold it? |
|---|---|---|---|
| Paystack secret key | Critical | Cloud Functions secret | **Never** |
| Gemini API key | High | Cloud Functions secret | Never |
| Firebase service-account / Admin credentials (production) | Critical | Google Cloud | **Not without a separate approved decision** (§4.4) |
| Identity documents and selfies (`verifications/`) | Critical personal data | Firebase Storage | Never |
| Dispute evidence, job photos, exact addresses (`jobs/*/private`) | High personal data | Firebase | Never |
| Payments, escrow, settlements, refunds, chargebacks, payouts, bank details (`artisan_private`) | Critical financial | Firestore + Paystack | Never |
| User profiles, chat, reviews | Personal data | Firestore | Not in this plan |
| Firebase web/Android API keys (`firebase_options.dart`) | Public identifiers, not secrets. Access is governed by rules | Repo | Acceptable (staging project's keys only) |
| QA / design artefacts, synthetic staging data | Low | Repo | Yes |

## 2. Threats and controls

| # | Threat | Likelihood / impact | Control |
|---|---|---|---|
| T1 | **RumptyCloud outage** (single region and zone, no SLA; status history unverifiable) | Medium / Low if non-critical | Only optional workloads; the client fails soft; no core flow depends on it |
| T2 | **Data loss in a RumptyCloud database** ("Automatic backups are not available yet"; no point-in-time recovery; deleting a database deletes its data) | Medium / depends on data | No RumptyCloud database in H2. If one is approved later: only re-creatable data, our own scheduled `pg_dump` to storage **outside** RumptyCloud, documented restore drills, and delete protection by process |
| T3 | **Over-broad GitHub App access** ("all repositories or only selected ones"; repos are "visible to every workspace member who can create deployments") | Medium / Medium | Grant access to **selected repositories only**. For H2, use a **new, separate repo** containing only static QA artefacts, not `handy_trust`. Review installed app permissions in GitHub after install |
| T4 | **CI token is a person's full-role key** ("inherit your current role"; no scoped tokens; must not be shared) | Medium / Medium | Use a dedicated staging workspace so the key's reach is limited to staging. Short expiry (30 or 90 days); revoke on role change; store only as a GitHub Actions secret; prefer git-push deploys (no token needed) for H2 |
| T5 | **Public, unfirewalled deployments** (firewall policies apply to VMs and databases only; no outbound filtering) | High / Low for static, Medium for APIs | Static sites hold no secrets. APIs must verify a Firebase ID token on every request except `/healthz`, rate-limit in-app, and enable CORS only for known origins |
| T6 | **Forged or replayed tokens at a RumptyCloud API** | Low / Medium | Full ID-token verification (signature, `aud`, `iss`, `exp`, `iat`, `sub`); reject anonymous and unverified email; HTTPS only (platform-terminated TLS) |
| T7 | **Revoked user keeps access for up to one hour** (no `checkRevoked` without Admin credentials) | Low / Low for read-only | Acceptable for non-critical, read-mostly endpoints only. Anything sensitive stays in Cloud Functions |
| T8 | **Role confusion**: only `admin` is a token claim; customer and artisan roles are in Firestore | Medium / Medium | Build no customer- or artisan-restricted endpoints on RumptyCloud until roles are minted as claims by a Cloud Function (a future, separately approved change) |
| T9 | **Staging connected to production** (one Firebase project today; no environment switch) | **High** / **Critical** | Hard prerequisite for any app build on RumptyCloud: a separate `handytrust-staging` Firebase project with Paystack **test** keys and a build-time environment switch. Add a CI check that fails if a staging build contains the production project ID |
| T10 | **Secrets in builds or logs** | Low / High | RumptyCloud env vars are encrypted and "deliberately kept out of the build". Still, never put secrets in static sites (everything shipped to a browser is public); never log tokens |
| T11 | **Uncontrolled spend or sudden shutdown** (prepaid USD credit; "Spend alerts are not available yet"; effect of an empty balance undocumented) | Medium / Low for staging | Small fixed budget; named owner checks the balance weekly; free or Tiny tiers; delete unused resources ("Stopped VMs and idle databases are still billed") |
| T12 | **Limited forensics** (audit logs kept 60 days, no documented export) | Low / Low | Export or screenshot audit views at each stage gate; keep our own deployment log in the repo |
| T13 | **Supply chain via auto-deploy** (every push to the branch deploys) | Medium / Low for QA site | Protected branch with required review on the deploy repo; auto-deploy only from that branch |
| T14 | **Personal data in a third-party jurisdiction or provider without certifications** (no compliance claims on the site) | — / High if it happened | Plan sends **no personal data** to RumptyCloud. Any future change requires a Nigeria Data Protection Act 2023 assessment and a data-processing agreement first |
| T15 | **Bucket misuse for sensitive files** (described as "image buckets"; key scopes, encryption at rest, versioning and lifecycle undocumented) | — | Use buckets only for public, non-sensitive assets until these are documented |

## 3. Firebase ID-token verification checklist (for any RumptyCloud API)

- [ ] `Authorization: Bearer` header required; 401 otherwise (except `/healthz`).
- [ ] Verify with the Firebase Admin SDK `verifyIdToken`, or a JWT library using Google's securetoken keys:
  - [ ] RS256 algorithm only;
  - [ ] `aud` = project ID;
  - [ ] `iss` = `https://securetoken.google.com/<project-id>`;
  - [ ] `exp` / `iat` checked, with ≤ 5 min skew;
  - [ ] `sub` present.
- [ ] Reject `firebase.sign_in_provider == "anonymous"`; require `email_verified`.
- [ ] Authorize:
  - [ ] admin endpoints by the `admin === true` claim;
  - [ ] ownership by `uid`;
  - [ ] no Firestore-role endpoints yet.
- [ ] Never log the token. Log uid, route and decision.
- [ ] Per-uid and per-IP rate limits; request size limits; strict CORS allow-list.
- [ ] Separate staging and production project IDs in configuration (env var), never hard-coded.
- [ ] Tests: expired, wrong-audience, wrong-issuer, tampered, anonymous, unverified-email and non-admin tokens are all rejected.

## 4. Specific decisions recorded

1. **Paystack webhook and every money flow stay on Cloud Functions.** RumptyCloud is excluded from the payment path.
2. **No production data in staging.** Synthetic accounts only. Staging uses Paystack test mode.
3. **H2 uses a separate repository** for the QA site, so the RumptyCloud GitHub App never gets the application repository.
4. **No production service-account key on RumptyCloud.** If a later workload needs Admin SDK features (revocation checks, Firestore reads), it needs its own threat model and approval. It would also need a dedicated, minimally privileged service account, with key rotation and a documented revocation path.
5. **No RumptyCloud database for authoritative data**, given the absence of managed backups.

## 5. Existing issues found during the audit (not caused by RumptyCloud)

These are recorded for the owner; none is changed in H1.

- Android `applicationId` is `com.example.handy_trust`, and **release builds use the debug signing key**. Fix both before any store or wide distribution.
- **No Firestore backup or export procedure** is documented in the repo. Firebase holds all authoritative data, so this is the more urgent disaster-recovery gap, and it's independent of RumptyCloud.
- **App Check** is not enabled for Firestore, Storage or Functions.
- **README security notes are stale.** They still describe a client-side Paystack secret and a missing auto-release index, both since fixed.
- **Unused Dio `ApiClient` / `SecureTokenManager`** with a placeholder base URL. Remove it, or rebuild it as in architecture §4.1, before any API integration.
