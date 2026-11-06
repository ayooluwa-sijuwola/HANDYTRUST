# HandyTrust — README corrections

**Stage:** H1.1. **The README was not edited.** Each statement below was checked against the current code (5 November 2026).

| # | README location | Current statement (abridged) | Verified current behaviour | Proposed text |
|---|---|---|---|---|
| 1 | §Security model, line ~158 | "`paystack_service.dart` reads the Paystack **secret key** from Firestore `/config/paystack` and uses it from the client" | **Outdated.** `lib/core/services/paystack_service.dart` only calls the callables `getPaymentBreakdown`, `initializePaystackTransaction` and `verifyPayment`. The secret is a Functions secret (`PAYSTACK_SECRET_KEY`) and never reaches the client | "Payments: the app never holds a Paystack key. Prices, transaction initialisation and verification run in Cloud Functions using a Functions secret; Paystack's webhook is verified by HMAC-SHA512 on the raw body." |
| 2 | §In progress, line ~252 | "client-side PaystackService verification path has the secret-key exposure issue … a simulated `DemoEscrowService` path is reachable" | **Outdated.** The exposure path is removed (#1). `demo_escrow_service.dart` and the demo payment screen were deleted (a Stage 8 source guard checks they stay gone) | Remove the bullet |
| 3 | §In progress, line ~253, and §Known limitations, line ~265 | "auto-release query … has no matching composite index … the comment says 48h while JobService sets 7 days" | **Outdated.** `firestore.indexes.json` contains an index including `autoReleaseAt`. The server review window is **14 days** (`REVIEW_WINDOW_MS`) and sets `autoReleaseAt` on submission | "Escrow auto-release: `autoReleaseEscrow` (hourly) releases payment when the 14-day review period after submission ends, unless a rework or dispute is open." |
| 4 | §In progress, line ~254 | "Firestore deletion succeeds independently of `adminDeleteUser`; if the function isn't deployed the Auth account stays enabled" | **Outdated.** The admin UI calls only the `adminDeleteUser` callable, which checks admin rights, writes the audit log and calls `admin.auth().deleteUser`. There's no separate client-side Firestore deletion | "Admin user deletion runs entirely in the `adminDeleteUser` Cloud Function (admin-checked, audit-logged). Job history, payments and reviews are kept." |
| 5 | §Architecture, lines ~89, ~151, ~236 | "email/password **and phone** sign-in" | **Incorrect.** No phone authentication exists (`verifyPhoneNumber` / `PhoneAuthProvider` appear nowhere in `lib/`) | "Firebase Authentication — email and password, with email verification and Firebase-hosted password reset." |
| 6 | §Architecture, line ~92 | "Cloud Functions … and **two callables** (AI job analysis, admin user deletion)" | **Outdated.** 33 functions: 15 callables, 1 HTTPS webhook, 5 scheduled, 12 Firestore triggers (`RUMPTYCLOUD_INTEGRATION_AUDIT.md` §A3) | List the function groups as in the audit table |
| 7 | §Planned, lines ~316–317 and §Summary, line ~326 | Repeats #1–#4 as open work | Fixed in remediation Stages 1–7.3 | Remove; replace with the open items in `HANDYTRUST_PRODUCTION_READINESS_PRIORITY_REPORT.md` |

## Statements to add (verified, not guarantees)

- **Security boundary:**
  - Firestore and Storage security rules plus Cloud Functions checks are the security boundary;
  - app navigation is not;
  - tests: rules 139, Storage rules 9, Functions 266 and an end-to-end emulator suite of 16, passing on 5 November 2026.
- **Known gaps (honest):**
  - no Firestore backup or PITR configured (as far as the repo shows);
  - release builds signed with the debug key;
  - placeholder application ID;
  - App Check not enabled.
- **Avoid:** do **not** claim encryption, compliance, certification or uptime guarantees. None are evidenced in the repository.

## Approval needed

Apply these edits to `README.md` (a documentation-only change).
