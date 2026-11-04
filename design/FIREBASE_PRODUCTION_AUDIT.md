# Firebase Production Configuration Audit

Audit only. Every claim below verified by reading `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `functions/index.js`, and the repo's dependency/config files directly.

---

## firestore.rules
Reviewed collection-by-collection across this entire program (most recently: `admin_alerts` fixed in Group 10). No bare `allow write: if true` exists anywhere. Every collection either scopes writes to the owning user, requires `isAdmin()`, or is Cloud-Functions-only (`allow create/update: if false`, since the Admin SDK bypasses rules regardless). ✅ Production-appropriate.

## storage.rules
Reviewed in full during Group 11. All four upload paths (`jobs/`, `users/`, `artisan_portfolio/`, `verifications/`, `disputes/`) are owner-write-only with file-size and content-type (`image/.*`) restrictions. `verifications/` is additionally read-restricted to owner-or-admin (correctly, since these are ID/selfie documents). **One thing verified, not assumed**: `storage.rules`' `isAdmin()` uses a different mechanism (Auth custom claim) than `firestore.rules`' `isAdmin()` (Firestore document existence) — confirmed kept in sync by `onAdminGranted`/`onAdminRevoked` Cloud Functions triggers, not a live bug. ✅ Production-appropriate, with one inherent Firebase limitation worth documenting: a custom-claim change only reaches a client after their ID token refreshes (re-login or up to ~1h) — a newly-granted admin may briefly have dashboard access before Storage access catches up.

## Firebase Auth settings
Enforced in code, not just console config: email verification is a hard router-redirect gate (`router.dart` — unverified users can only reach `/verify-email`), anonymous sessions are explicitly excluded from meaningful access (`storage.rules`' `isSignedIn()` explicitly blocks the `anonymous` sign-in provider; `firestore.rules` patterns throughout distinguish real accounts). **Needs console-side verification** (not visible from source): which sign-in providers are actually enabled in the Firebase Console, whether email enumeration protection is on, and password policy strength — these are project-console settings, not something this codebase controls or that reading source can confirm.

## Cloud Functions configuration
Every function touching a secret declares it explicitly (`{ secrets: ['PAYSTACK_SECRET_KEY'] }`) — the key is read from `process.env.PAYSTACK_SECRET_KEY` at call time, sourced from Firebase Secret Manager, never hardcoded or stored in Firestore (a prior architecture, explicitly noted as fixed in `paystack_service.dart`'s own doc comment, before this program began). ✅ Correct pattern, consistently applied across every Paystack-touching function.

## Indexes
`firestore.indexes.json` has composite indexes for every multi-field query used in this program (jobs by customer/artisan + status + date, payments by payer/artisan/job, the `status+autoReleaseAt` index the auto-release cron depends on, artisan discovery by category/availability/approval/rating). **All indexes needed by code changes made across this entire program are present in the file** — but a file existing locally is not the same as it being deployed. **Action required before launch**: `firebase deploy --only firestore:indexes` against the real project, and confirm via the Firebase Console that all indexes show `Enabled` (composite indexes can take minutes to hours to build on a populated production dataset — plan for that, don't assume instant availability).

## Environment variables / secrets exposure
No `.env` file, no hardcoded `sk_live`/`sk_test` string, no server secret found anywhere in `lib/` (grepped explicitly for Paystack secret-key patterns and generic secret-like strings). The one API-key-shaped string present in the client (`lib/firebase_options.dart`'s `apiKey` fields) is the standard FlutterFire-generated **public** client configuration — Firebase's own documentation states these are safe to embed client-side; the real access boundary is `firestore.rules`/`storage.rules`, already reviewed above. ✅ No exposure found.

## Debug/demo paths
`kDebugMode`-gated demo payment fallback (`payment_screen.dart` → `demo_escrow_screen.dart`/`demo_escrow_service.dart`) — confirmed in Group 11 to be real, referenced, and correctly excluded from release-mode builds by the `kDebugMode` guard itself (Dart's `kDebugMode` constant is `false` in release builds, tree-shaken by the compiler — this isn't just a runtime check, the demo path's calling branch is dead code in a release binary). ✅ Correctly controlled.

## Admin access protection
`isAdmin()` (Firestore) requires a document in `admins/{uid}` — not a role field on the user's own profile (which the user could otherwise never write to themselves, but a document-existence check is a stronger, more conventional pattern: granting/revoking admin is an explicit separate write to a separate collection, not a mutable field). Storage admin access is claim-based and auto-synced (above). Client-side "isAdmin" checks (e.g., `isAdminProvider` gating the Profile menu's admin entry point) are UI convenience only — every actual admin action (verification approve, dispute resolve, user suspend) is re-enforced server-side by the same `isAdmin()` rule. ✅ Correctly layered — no client-only permission gate found.

## Production collections — permission summary

| Collection | Read | Write |
|---|---|---|
| `jobs` | parties + eligible artisans (open jobs) + admin | transition-gated, role-checked |
| `payments` | payer/artisan/admin | admin only (Cloud Functions bypass) |
| `escrow_releases` | *(no client rule needed — Cloud-Functions-only in practice; not currently client-readable)* | Cloud Functions only |
| `admin_alerts` | admin only *(fixed Group 10)* | Cloud Functions only |
| `notifications` | owner only | owner (isRead/readAt only) + admin + server-only types |
| `artisan_private` | owner/admin | owner |
| `verifications` (Firestore) | owner/admin | owner (create/update per VerificationService flow) |
| `disputes` | raiser/target/admin | create: raiser; update: admin or the responding party (scoped fields) |

**One gap noticed while building this table, not previously flagged**: `escrow_releases` has no explicit `firestore.rules` match block, same class of issue as `admin_alerts` before Group 10 — but here it's **correctly** unreadable, since nothing in the app currently needs to read it client-side (the admin dashboard doesn't currently surface individual release records, only the aggregate `admin_alerts` for stuck ones). Not a bug today, but worth a deliberate rule (even an explicit `allow read: if isAdmin(); allow write: if false;`) if a future admin screen ever needs to show release history directly, rather than relying on default-deny by omission a second time.

---

## Summary
No secret exposure, no missing security boundary found. Two action items before launch: deploy indexes/rules to the real project (not yet done — this program only edited local rule/index files), and verify Firebase Console-side Auth settings (outside what source review can confirm).
