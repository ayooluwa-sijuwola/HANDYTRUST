# RumptyCloud hybrid integration — staging deployment plan

**Stage:** H1 proposal. Nothing in this plan has been executed. Each stage below needs the owner's explicit approval.

## 1. Recommended first workload (Stage H2): static QA / design-review site

**What:** a static site serving HandyTrust's review artefacts:
- the Stage 8 / 8.1 preview gallery;
- approved-vs-implemented comparison sheets;
- visual-QA reports;
- release notes for test APKs.

It's deployed from a **new, separate GitHub repository** (e.g. `handytrust-qa-site`) to a RumptyCloud **Static Site** in a dedicated workspace, **"HandyTrust Staging"**.

**Why this first:**

| Criterion | Assessment |
|---|---|
| Touches production Firebase, Paystack or user data | No |
| Secrets required | None |
| Exercises the documented platform features we'd rely on later | GitHub App install (selected repo only), auto-deploy on push, build logs, HTTPS, subdomain custom domain, rollback to a previous artifact, workspace isolation, prepaid billing |
| Real value | Gives reviewers a shareable link instead of local files |
| Impact if RumptyCloud is down or removed | Reviewers fall back to the files in the repo |

**Why not the Flutter web app first:** it would need a separate staging Firebase project, a build-time environment switch, a web Paystack checkout (`webview_flutter` has no web support) and web push. Those are code and configuration changes outside H1, and without them a web build would point at production. That workload is proposed as H3 below.

## 2. Prerequisites for H2 (owner actions)

1. Approve this plan and a staging budget (see §6).
2. Create a RumptyCloud account and a workspace named **HandyTrust Staging**. Top up a small prepaid balance.
3. Create a new GitHub repository for the QA site, with a protected `main` branch that requires review.
4. Choose a subdomain (e.g. `qa.<your-domain>`). Root domains are not supported.
5. Decide whether the site is public or should require a login. RumptyCloud documents no access protection for static sites, so assume **public**. Publish only material you're happy to be public.

## 3. H2 procedure (for when approved)

| Step | Action | Verification |
|---|---|---|
| 1 | Populate the QA repo with exported static files only (HTML, images, Markdown→HTML). No app source, no `firebase_options.dart`, no `.env` | Repo review: no secrets, no personal data (`git grep` for keys and emails) |
| 2 | Install the RumptyCloud GitHub App with **"Only select repositories"** → the QA repo | GitHub › Settings › Applications shows one repo |
| 3 | Create deployment: type **Static Site/SPA**, branch `main`, build method Auto (plain static) or a minimal Dockerfile | Build logs stream; run reaches Active |
| 4 | Add the subdomain; create the DNS CNAME as instructed in the console | HTTPS certificate served by the platform; HTTP redirects to HTTPS |
| 5 | Push a trivial change | Auto-deploy run recorded with its trigger |
| 6 | **Rollback drill:** use Rollback to the previous artifact | Previous version served without a rebuild; record the time taken |
| 7 | Record cost after 7 days from the billing Usage tab | Within budget |
| 8 | Write `design/RUMPTYCLOUD_H2_REPORT.md`: what worked, documentation gaps found (artifact retention, cold start, empty-balance behaviour) | Owner review |

**Exit criteria:** deploy, custom subdomain, HTTPS, rollback and billing all behave as documented. No secret or personal data is in the site.

## 4. Later stages (outline only; each needs separate approval)

### H3 — Flutter web staging

**Prerequisites:**
- A new Firebase project `handytrust-staging`: Auth, Firestore, Storage and Functions, deployed from the same repo with Paystack **test** secrets and synthetic data.
- A build-time environment switch in Flutter (`--dart-define=ENV=staging` or flavors) selecting staging `FirebaseOptions`.
- A CI guard that fails a staging build containing the production project ID `handytrust`.
- Web Paystack checkout: redirect or new-tab flow instead of `webview_flutter`, with a callback that relies on the existing `verifyPayment` / webhook.
- Optional web push (`firebase-messaging-sw.js`).

**Deploy:**
- `flutter build web --dart-define=ENV=staging`;
- served as a Static Site/SPA on `staging.<domain>`;
- auth domain added to the staging Firebase project's authorized domains.

**Exit:** a full customer → artisan → payment (test mode) → escrow → release journey on staging, with production untouched.

### H4 — First non-critical API (optional)

- **Example:** a read-only `release-notes` / `app-config-hints` API used by the app's About screen, failing soft.
- **Security:** Firebase ID-token verification exactly as in `RUMPTYCLOUD_SECURITY_REVIEW.md` §3; no production service-account key; no writes to Firebase.
- **Staging first**, verifying tokens issued by the staging project.

### Not planned

The following are not planned. Reopening any of them needs a new decision and threat model:
- the payment webhook, escrow, payouts or disputes;
- notifications;
- a RumptyCloud database as a system of record;
- Firestore backups in RumptyCloud buckets;
- identity documents or other personal data.

## 5. Rollback plans

| Level | Trigger | Action | Effect on production |
|---|---|---|---|
| Release | A bad deploy | RumptyCloud **Rollback** button (redeploys the previous stored artifact; no rebuild) | None |
| Service | Platform problem or unacceptable behaviour | Disable auto-deploy; stop or delete the deployment; remove the DNS CNAME | None |
| Platform | Abandon RumptyCloud | Delete the workspace's deployments, buckets and VMs; revoke API keys; uninstall the GitHub App; archive the QA repo or host it elsewhere (e.g. Firebase Hosting, already configured) | None, because nothing authoritative moved |
| H3 web staging | Staging misbehaves | Stop the static site; staging Firebase project is unaffected and testers return to APKs | None |

## 6. Costs (from the published pricing, USD, 5 November 2026)

| Item | Tier | Published price | Notes |
|---|---|---|---|
| H2 QA site | Free deployment (scale-to-zero) or Tiny | $0 or up to ~$2.00/mo | Free tier: "5 apps that sleep when idle" (one page also says 3). Cold-start delay on wake is undocumented |
| Vulnerability scanning | Add-on, on by default | $0.50 per app / month | Can be switched off for a static site |
| Bucket (if used for images) | First 10 GB free | $0.02/GB-month beyond | In-network egress free |
| H3 web staging | Tiny / Starter | ~$2–4/mo | Plus the staging Firebase project's own (likely free-tier) usage |
| H4 API | Starter | ~$4/mo | Always-on avoids cold starts on token-verified calls |
| **Expected total, H2** | | **$0–3 / month** | |
| **Expected total, H2–H4** | | **≈ $7–12 / month** | Excludes staff time |

**Billing behaviour to plan around:**
- Prepaid credit, billed in USD. NGN appears as a display currency on the pricing page.
- No spend alerts yet.
- Idle databases and stopped VMs are still billed.
- What happens when credit runs out isn't documented.

**Action:** assign a named owner to check the balance weekly.

## 7. Dependencies

| Dependency | Needed for |
|---|---|
| RumptyCloud account, workspace and prepaid credit | H2+ |
| GitHub repository for QA artefacts; GitHub App install (selected repo) | H2 |
| Domain with DNS access (subdomains) | H2+ |
| Staging Firebase project; Flutter environment switch; web Paystack checkout; CI guard | H3 |
| Paystack test-mode keys for staging | H3 |
| Firebase ID-token verification library in the API runtime | H4 |
| Data-protection assessment (Nigeria Data Protection Act 2023) | Before any personal data reaches RumptyCloud (not planned) |

## 8. Risks summary

| Risk | Rating | Mitigation |
|---|---|---|
| Single-region, no-SLA outage | Medium | Only non-critical workloads; fail soft |
| No managed database backups | High if a database were used | No database planned; own `pg_dump` regime if ever approved |
| Staging accidentally using production Firebase | Critical | Separate project + CI guard before H3 |
| Over-broad repo or API-key access | Medium | Separate QA repo; selected-repo install; dedicated workspace; short-expiry keys |
| Undocumented behaviour (empty balance, artifact retention, cold starts, bucket encryption) | Medium | Measure during H2 and record in the H2 report before relying on it |
| Pricing and doc inconsistencies (free-app count, vCPU per tier) | Low | Confirm in the console before committing budget |
