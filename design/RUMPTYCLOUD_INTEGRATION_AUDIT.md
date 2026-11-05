# RumptyCloud hybrid integration — Stage H1 audit

**Date:** 5 November 2026
**Status:** audit and planning only. No resources created, nothing connected, deployed or changed.
**Companion documents:**
- `RUMPTYCLOUD_TARGET_ARCHITECTURE.md`
- `RUMPTYCLOUD_SECURITY_REVIEW.md`
- `RUMPTYCLOUD_STAGING_DEPLOYMENT_PLAN.md`

**Evidence rules:**
- Repository facts were read from the current working tree (branch `stage-8-ui-replacement`; baseline commit `7e16eb1`).
- RumptyCloud facts come only from `docs.rumptycloud.com`, `rumptycloud.com` and `rumptycloud.com/pricing`, read on 5 November 2026.
- Anything those pages do not state is marked **not documented**. It is never assumed to exist.

---

## Part A — HandyTrust today

### A1. Application architecture

| Layer | Implementation |
|---|---|
| Client | Flutter 3.41 / Dart 3.11 app, Android first. `ios/`, `web/`, `macos/`, `windows/` and `linux/` scaffolds exist. Riverpod 2 for state, GoRouter 13 for navigation. Stage 8/8.1 presentation layer in `lib/ui/` |
| Backend | One Firebase project, `handytrust` (`.firebaserc`): Authentication, Cloud Firestore, Cloud Storage, Cloud Functions (2nd gen, Node.js 22), Firebase Cloud Messaging |
| Payments | Paystack, server-side only (Cloud Functions hold the secret key) |
| AI | Google Gemini, called from one Cloud Function (`analyzeJob`) |
| Server-side business rules | Firestore security rules (`firestore.rules`, 1,147 lines; `storage.rules`, 109) plus Cloud Functions. Rules are the security boundary; app navigation is not |

The app talks to Firebase directly through the FlutterFire SDKs. There is no other backend: no REST API, no API gateway and no database outside Firestore.

### A2. Firebase integrations

| Product | Used for | Client package |
|---|---|---|
| Authentication | Email/password sign-in, email verification, Firebase-hosted password reset. Anonymous sessions are treated as signed-out by the router and the rules | `firebase_auth` 6.5 |
| Cloud Firestore | All application data (A2.1) | `cloud_firestore` 6.8 |
| Cloud Storage | Profile photos, job photos, portfolio, verification documents, dispute evidence (A7) | `firebase_storage` 13.4 |
| Cloud Functions | Payments, escrow, settlement, notifications, trust score, deadlines, admin finance (A3) | `cloud_functions` 6.3 |
| Cloud Messaging | Push notifications; tokens in `fcm_tokens/{uid}`; sent by `onNotificationCreated` | `firebase_messaging` 16.5 + `flutter_local_notifications` |
| Hosting | Configured in `firebase.json` (`public: build/web`), but no web build exists in the repo | — |

**A2.1 Firestore collections.**
- Top level:
  - `users`, `artisans`, `artisan_private`, `admins`
  - `jobs` (subcollections `quotes`, `messages`, `private`, `events`)
  - `payments`, `escrow_releases`, `settlements`, `refunds`, `chargebacks`, `platform_losses`, `financial_events`
  - `disputes`, `reviews`, `notifications`, `fcm_tokens`
  - `verifications`, `portfolio_projects`, `portfolio_analytics`, `booking_responses`
  - `support_tickets`, `account_deletion_requests`
  - `admin_alerts`, `admin_audit_logs`
  - `config` (incl. `config/platform`)
- The Firestore database location is set at project creation and is not recorded in the repository. Confirm it in the Firebase console before any latency or data-residency decision.

### A3. Cloud Functions (`functions/index.js`, 4,147 lines, 33 deployed functions)

No region is set in code, so every function uses the Cloud Functions 2nd-gen default (`us-central1`).

**Secrets:** `PAYSTACK_SECRET_KEY` and `GEMINI_API_KEY`, set with `firebase functions:secrets:set`.

| Kind | Functions | Responsibility |
|---|---|---|
| HTTPS endpoint (1) | `paystackWebhook` | Paystack events, verified by HMAC-SHA512 over the raw body. Handles charges (escrow lock), transfers (payout status), refunds and chargebacks |
| Callable: payments (3) | `getPaymentBreakdown`, `initializePaystackTransaction`, `verifyPayment` | Server-computed charge (5% platform fee); Paystack initialization with an idempotency claim; verification fallback |
| Callable: marketplace (2) | `artisanWithdrawFromJob`, `analyzeJob` | Artisan withdrawal / booking decline reopens the job; Gemini job analysis |
| Callable: admin (10) | `adminResolveDispute`, `adminResolveCancellation`, `adminRefundCharge`, `adminRetryRefund`, `adminRetryPayout`, `adminCloseChargeback`, `adminSetChargebackInvestigation`, `adminSetPayoutFreeze`, `adminBackfillJobLocationPrivacy`, `adminDeleteUser` | Settlement and refund execution, payout retries, chargeback handling, payout freeze, privacy backfill, account deletion. All check `admins/{uid}` server-side |
| Scheduled (5) | `autoReleaseEscrow` (hourly), `reconcileStuckEscrowReleases` (daily), `reconcileRefunds` (3-hourly), `expireMarketplaceDeadlines` (hourly), `expireAbandonedPayments` (hourly) | 14-day review auto-release, release-queue repair, refund reconciliation, booking/quote/job deadlines, abandoned-payment cleanup |
| Firestore triggers (12) | `processEscrowRelease`, `onNotificationCreated`, `onQuoteWritten`, `onMessageCreated`, `onJobCreatedProtectLocation`, `onJobCompleted`, `onReviewCreated`, `onArtisanRatingChanged`, `onArtisanVerificationChanged`, `onAdminGranted`, `onAdminRevoked`, `onDisputeCreated` | Paystack transfers, push delivery, server-generated notifications, private-location split, stats and trust score, admin custom claims, dispute alerts |

**Tests:**
- Cloud Functions: 266 tests (15 files).
- Rule suites: Firestore 139 and Storage 9.
- End-to-end emulator suite: 16 tests.
- All green on 5 November 2026 (see `STAGE8_1_IMPLEMENTATION_REPORT.md`).

### A4. Flutter services and repositories

The app uses a service + provider pattern with no repository layer. Services in `lib/core/services/` wrap Firestore, Storage and Functions; Riverpod providers in `lib/providers/` expose streams.

| Area | Services |
|---|---|
| Identity and profiles | `auth_service`, `profile_service`, `artisan_profile_service`, `verification_service`, `artisan_eligibility` |
| Marketplace | `job_service` (client mirror of the state machine), `quote_service`, `matching_service`, `distance_matching`, `chat_service`, `favorite_service`, `portfolio_service` |
| Money (read-mostly) | `paystack_service` (callables only), `escrow_service`, `payment_summary`, `artisan_earnings_summary`, `admin_finance_service` (admin callables) |
| Trust and support | `dispute_service`, `trust_score_service`, `support_ticket_service`, `notification_service`, `admin_audit_service` |
| Presentation logic | `workflow_gate_service`, `customer_booking_logic`, `artisan_work_logic`, `notification_category` |
| Storage | `storage_service` (job, dispute and verification images), `profile_service` (avatar), `portfolio_service` |

**Unused HTTP layer:**
- `lib/core/network/api_client.dart` (Dio, base URL placeholder `https://api.example.com/`) and `auth_interceptor.dart` are wired into `apiClientProvider`, but nothing uses them.
- `SecureTokenManager` stores a bearer token that nothing ever saves.
- This is where a future RumptyCloud API client would plug in. It should be rebuilt to send a fresh Firebase ID token per request (`FirebaseAuth.currentUser.getIdToken()`), not a stored token. See the security review.

### A5. Authentication and role authorization

**Sign-in:** Firebase Authentication with email/password. Email verification is required before the app opens (router gate).

**Roles:**

| Role | Where it is stored | Who can set it |
|---|---|---|
| Customer / artisan | `users/{uid}.roles` (array) and `activeRole`; the artisan public profile is `artisans/{uid}` | Client, within rule constraints; artisan approval is admin-only |
| Admin | `admins/{uid}` document. Mirrored to a Firebase **custom claim** `admin: true` by `onAdminGranted` / `onAdminRevoked` | Admin SDK / console only |

**Enforcement:**
- **Firestore rules:** `isSignedIn()` (non-anonymous), `isOwner`, `isAdmin()` (an `admins/{uid}` document exists) and job-party checks.
- **Storage rules:** use the `admin` custom claim.
- **Cloud Functions:** re-check every role server-side.
- **Navigation:** GoRouter redirects exist for UX only.

**Implication for RumptyCloud:**
- A Firebase ID token carries `uid`, `email_verified`, the sign-in provider and the `admin` claim.
- It does **not** carry customer or artisan roles; those live only in Firestore.

### A6. Payment and escrow architecture

1. The client asks `getPaymentBreakdown` for the server price.
2. `initializePaystackTransaction` creates the Paystack transaction with the secret key (Functions secret) and returns the authorization URL.
3. The app opens checkout in `webview_flutter` (`payment_webview_screen.dart`).
4. Paystack's webhook → `paystackWebhook` verifies the HMAC and locks escrow (`_lockEscrow`). `verifyPayment` is the client-triggered fallback.
5. Work, then submission, then a 14-day review (`REVIEW_WINDOW_MS`). Release happens on customer approval or by `autoReleaseEscrow`, through the `escrow_releases` queue → `processEscrowRelease` → Paystack transfer. Payout status comes back via the webhook.
6. Refunds, settlements, chargebacks and payout freezes are server-only, through admin callables and the webhook.

**What the client can and cannot do:**
- The client never holds the Paystack secret.
- `/config` is readable by signed-in users, but the old secret-in-Firestore path was removed in remediation (`paystack_service.dart` now only calls the callables).
- **The README's "Security caveat" and "Known limitations" sections are out of date on this and on the auto-release index, which now exists.** They should be corrected in a documentation pass.

**Webhook URL:** the Paystack webhook is the default HTTPS URL of `paystackWebhook` in `us-central1`. It is part of the money path and must not move.

### A7. File upload and storage

| Path | Contents | Rule |
|---|---|---|
| `profiles/{uid}/` | Avatar | Owner write; image only; < 5 MB |
| `users/{uid}/` | User images | Owner; image; < 5 MB |
| `jobs/{jobId}/{uid}/` | Job, before and after photos | Job party; image; < 5 MB |
| `artisan_portfolio/{uid}/` | Portfolio | Owner; image; < 5 MB |
| `verifications/{uid}/` | Government ID and selfie | Owner write, admin read |
| `disputes/{disputeId}/{uid}/` | Dispute evidence | Dispute party; admin read |

**Before upload:**
- Images are compressed on the client (`flutter_image_compress`).
- EXIF, GPS and XMP metadata are stripped (Stage 7.1 `JpegMetadata.strip`).
- Content type is fixed to `image/jpeg`.

**After upload:**
- URLs are stored in Firestore.
- Access is controlled by Storage rules tied to Firebase identities.

### A8. Environment configuration

| Item | Current state |
|---|---|
| Firebase projects | **One:** `handytrust`. No staging or test project. Emulator test runs use `demo-*` project IDs |
| Client configuration | `lib/firebase_options.dart` (FlutterFire, all platforms point at `handytrust`). No `--dart-define`, no `String.fromEnvironment`, no build flavors |
| Server configuration | Functions secrets (`PAYSTACK_SECRET_KEY`, `GEMINI_API_KEY`); business settings in Firestore `config/platform` (fee %, windows, radius, minimum job value) |
| Emulators | `firebase.json`: Firestore on 8090, `singleProjectMode: true`. The app has no emulator switch |
| Android identity | `applicationId = "com.example.handy_trust"`. **Release builds are signed with the debug key** (`build.gradle.kts`). Both must change before any store release |
| App Check | Not used |

### A9. Deployment procedures (as they exist)

- **Backend:** manual, from a developer machine (README):
  - `firebase functions:secrets:set PAYSTACK_SECRET_KEY` and `GEMINI_API_KEY`
  - `firebase deploy --only functions,firestore:rules,firestore:indexes,storage:rules`
- **App:** manual `flutter build apk`, distributed outside a store.
- **Not in place:**
  - CI/CD (no `.github/workflows`);
  - a staging environment;
  - automated releases;
  - Firestore backup or export schedule (not found in repo or docs);
  - documented rollback.
- **Web:** Firebase Hosting is configured, but there's no web build or web deployment procedure. The web app also lacks:
  - Paystack checkout (`webview_flutter` has no web implementation);
  - web push (no `firebase-messaging-sw.js`).

---

## Part B — RumptyCloud, as documented

| Capability | What the official documentation states | Not documented / caveats |
|---|---|---|
| **Company and region** | Built and operated in Lagos. "currently operates from a single region in Lagos": `lagos-1`, one zone. More zones planned | No named legal entity on the homepage; no compliance certifications claimed |
| **App deployments** | From a GitHub repo via the RumptyCloud GitHub App; branch + optional root directory; "Static Site/SPA" or "Web Service/Backend"; build "Auto" (framework detection) or Dockerfile; auto-deploy on push (default on); superseded builds cancelled | Image-based deploys; monorepo detail; PR previews appear on the pricing page only |
| **Instance sizes** | Docs: Tiny 0.25 vCPU / 512 MB ~$2/mo · Starter 0.75 vCPU / 1 GB ~$4 · Scale 1 vCPU / 2 GB ~$8 · Pro 2 vCPU / 4 GB ~$15. Free: 5 deployments, scale-to-zero | **The pricing page differs:** Tiny "up to 0.5" vCPU, Starter "up to 1", Scale "up to 1.5". It also says 3 free apps in one place and 5 in another. Cold-start times not documented |
| **Ports and health checks** | One port per deployment (default 8080, injected as `PORT`); readiness path (default `/`) must answer **unauthenticated** | Health-check timeout and interval |
| **HTTPS and domains** | "The platform terminates HTTPS at the edge"; custom domains and automatic HTTPS included; **"root domains are not supported yet"**, so subdomains only | DNS procedure, certificate details |
| **Environment variables** | Encrypted, "treated as secrets", injected at runtime only, "deliberately kept out of the build" | Per-environment variable sets; secret-version history |
| **Logs and monitoring** | Build logs stream live per run; pricing lists live logs, metrics and health checks for deployments; VM metrics page exists | Log retention, log export or drains, alerting |
| **Rollback** | Successful builds keep their image; a "Rollback" button redeploys a previous artifact without rebuilding; any stored artifact can be deployed | How many artifacts are kept |
| **Persistent storage (apps)** | Filesystem wiped on every deploy unless a volume is attached. With a volume: exactly one instance, brief stop on deploy, 1–512 GiB, can grow but never shrink, cannot be removed | — |
| **VMs** | Ubuntu 24.04 / Debian 12; no public IP by default; SSH as root through the CLI; snapshots ("Save a point in time and rebuild from it") | Automatic snapshots or backups; data-loss guarantees |
| **Managed databases** | Postgres, Redis, MySQL; connection string in console. **"Automatic backups are not available yet"**: "no scheduled snapshots, point-in-time recovery, or managed restore flow". Manual `pg_dump` / `psql` only. "Deleting a database removes the instance and its data." | Versions, HA or replicas, TLS, plans. The docs homepage's "Managed databases with backups" contradicts the backups page |
| **Object storage (Buckets)** | "S3-compatible"; endpoint `https://s3.rumptycloud.com`; path-style addressing; public buckets via a permanent `assets.rumptycloud.com` URL; private buckets via server-generated signed URLs; per-bucket access keys (secret shown once, revocable). 10 GB free, then $0.02/GB-month; in-network egress free | Described as "image buckets"; **dashboard uploads are limited to listed image, document and video types**; arbitrary object types via the S3 API, max object size, key permission scopes, CORS, versioning, lifecycle, encryption at rest and replication are not stated |
| **Workspaces** | "top-level container for all your resources"; "Resources are not shared between workspaces"; example of separate production and testing workspaces | Role definitions; invite flow; per-workspace billing |
| **API keys and CLI** | Personal keys that "inherit your current role in each workspace"; expiry 30 d / 90 d / 1 y / 2 y / never; immediate revoke; use as `RUMPTY_TOKEN` in GitHub Actions; "must not be shared with teammates" | **No scoped or service tokens**; no documented rotation |
| **Firewall** | Default deny inbound; allow rules; **applies to VMs and databases only**; "Outbound filtering is not enforced yet" | Firewalling deployments |
| **Audit logs** | Create, update, delete and lifecycle actions, failed attempts, sign-in and sign-out with IP; **retained 60 days** | Export; viewer roles |
| **Billing** | **Prepaid credit in USD**, drawn down hourly; invoices per cycle; "Stopped VMs and idle databases are still billed"; **"Spend alerts are not available yet"** | What happens to resources when credit runs out |
| **SLA, support, status** | No SLA or uptime guarantee stated; support via Discord, docs and GitHub; public status page | Status page renders client-side; incident history could not be read for this audit. No email, ticket or phone support listed |

### B1. Constraints that shape every recommendation

1. **Single region, single zone, no SLA.** Anything placed on RumptyCloud can be fully unavailable with no failover. It must therefore be non-critical: HandyTrust must keep working, including money flows, when RumptyCloud is down.
2. **No automatic database backups** and no point-in-time recovery. Any RumptyCloud database needs our own scheduled `pg_dump` to storage outside RumptyCloud, plus restore drills. Until then, it may hold only re-creatable data.
3. **No spend alerts and prepaid credit.** Cost control is manual. The effect of an empty balance is undocumented, so a staging workload could stop without warning.
4. **No scoped API tokens.** CI would use a person's key with that person's full workspace role.
5. **Firewall policies don't cover deployments.** Deployed APIs are public and must authenticate every request themselves.
6. **Buckets are image- and media-oriented**, and their key scopes and encryption at rest are undocumented. They can't yet be assessed for sensitive files.

---

## Part C — Integration opportunities

| # | Opportunity | Fit | Risk | Verdict |
|---|---|---|---|---|
| 1 | **Static QA / design-review site** (visual-QA galleries, approved previews, release notes) from a dedicated repo | Static Site, git deploy, HTTPS, rollback | Very low: no app data, no Firebase credentials | **Recommended first workload (H2)** |
| 2 | **Flutter web staging build** against a new, isolated Firebase staging project with Paystack *test* keys | Static Site/SPA | Medium: needs a staging Firebase project, a client config switch and web Paystack checkout (code changes). Must never point at production | Second workload (H3), after its prerequisites |
| 3 | **Public marketing / landing site** (future web hosting) | Static Site, subdomain | Low | Good candidate once a domain plan exists (no root-domain support) |
| 4 | **Independent non-critical API** (e.g. app-version / release-notes feed, public category catalogue) verifying Firebase ID tokens | Web Service | Low–medium: public endpoint; token verification required | Later. Design in the target architecture |
| 5 | **Background jobs** (e.g. nightly link checks, test-data seeding for staging) | Web Service or VM | Low on staging data only | Later |
| 6 | **Off-Google copy of Firestore exports** (disaster recovery) | Buckets | **High:** production personal data and financial records; undocumented encryption at rest and key scopes; image-oriented buckets | **Not recommended now** |
| 7 | Moving verification documents, payments, escrow, webhooks, notifications or the database | — | Critical | **Out of scope by owner decision. Do not do** |

The recommended first workload and its rationale are in `RUMPTYCLOUD_STAGING_DEPLOYMENT_PLAN.md`.
