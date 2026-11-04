# Admin User Deletion Audit

Traced from source: `admin_dashboard_screen.dart` → `_UserListTile._deleteUser` → `adminDeleteUser` (Cloud Function) → Firebase Auth / Firestore / Storage / `firestore.rules`. The premise ("don't assume the delete button works") was correct — it didn't, in several concrete ways.

## Current behavior, as found (before this fix)

**Two-step, split-authority flow**: the Dart client did a Firestore batch delete of `users/{uid}` and `artisans/{uid}` directly, then called `adminDeleteUser` as a "best-effort" side effect whose failure was shown as a soft warning, not a real error.

| Requirement 1 item | Actually happened? |
|---|---|
| Firebase Auth account | **No** — `adminDeleteUser` called `admin.auth().updateUser(uid, {disabled:true})`, never `deleteUser()`. The account, email, and phone number persisted forever, just locked out. A function named "delete" did not delete. |
| `users/{uid}` | Yes, via the client-side batch. |
| `artisans/{uid}` | Yes, via the client-side batch, if `user.isArtisan`. |
| Profile images (Storage) | **No** — nothing in either the client or the function touched Storage. |
| Verification documents (Storage) | **No** — same. |

**Audit log**: `AdminAction.userDeleted` already existed in the enum — and was never used. No audit entry was written for a deletion at all, unlike suspend/reactivate/beta-toggle, which all correctly call `AdminAuditService.log(...)`. Requirement 3's "keep audit logs before deletion" was not met at all, in either order.

## What happens to related data (requirement 2)

Traced every collection that references a `uid`:

| Collection | Field | What happened |
|---|---|---|
| `jobs` | `customerId`, `artisanId` | Untouched (correct — see below) |
| `jobs/{id}/quotes` | doc ID / `artisanId` | Untouched (correct) |
| `jobs/{id}/messages` | `senderId` | Untouched (correct) |
| `payments` | `payerId`, `artisanId` | Untouched (correct) |
| `reviews` | `customerId` | Untouched (correct) |
| `notifications` | `userId` | **Untouched (bug)** — pure personal data, no other party depends on it, safe and appropriate to delete |
| `verifications/{uid}` | doc ID | **Untouched (bug)** — selfie/ID URLs orphaned forever |
| `artisan_private/{uid}` | doc ID | **Untouched (bug)** — bank details orphaned forever |
| `users/{uid}/favorites` | subcollection | **Untouched (bug)** — the deleted user's own saved-artisans list |
| other users' `favorites` entries pointing at a deleted **artisan** | `artisanId` | **Untouched (bug)** — a fan-out reference to an account that no longer exists |
| `portfolio_projects` | `artisanId` | **Untouched (bug)** |

`jobs`/`quotes`/`payments`/`reviews` being left alone is the *correct* behavior, not a bug — they're the other party's transaction and reputation history, and requirement 4 explicitly rules out removing financial records incorrectly. The bug was everywhere else: seven collections/subcollections of the deleted account's *own* personal data were never cleaned up, and neither was Storage.

## Fix implemented

**Single, authoritative, server-side deletion path.** `adminDeleteUser` (`functions/index.js`) now does everything, in order:
1. Verifies the caller is a real admin (unchanged) and adds a new guard: an admin cannot delete their own account through this action (a likely-mistake case with no legitimate use, not explicitly requested but a cheap and obvious safety addition alongside the self-deletion checks the task did ask for).
2. Writes the `admin_audit_logs` entry (`AdminAction.userDeleted`, with a snapshot of name/email/`wasArtisan`) **before** any destructive action.
3. Deletes the real Firebase Auth account (`admin.auth().deleteUser`, not disable).
4. Deletes Storage objects under `users/{uid}/`, `verifications/{uid}/`, `artisan_portfolio/{uid}/`.
5. Deletes `users/{uid}`, `artisans/{uid}` (if present), `verifications/{uid}`, `artisan_private/{uid}`, the user's own `favorites` subcollection, `portfolio_projects` where `artisanId == uid`, `notifications` where `userId == uid`, and — via a `collectionGroup('favorites')` query — every *other* user's favorite entry pointing at a deleted artisan.
6. Explicitly does **not** touch jobs, quotes, chat messages, payments, reviews, disputes, or `escrow_releases` — documented in the function's own comment so a future edit doesn't "fix" this by deleting financial history.

**`firestore.rules`**: `users/{uid}` and `artisans/{uid}` delete rules changed from `isAdmin()` to `false`. This is the requirement-4 hardening: previously *any* authenticated admin session could delete these documents directly from the client, skipping the audit log and cleanup entirely — the exact split-authority gap that caused this bug. Admin SDK calls (this Cloud Function) bypass rules regardless, so the function is unaffected; only the unaudited client-direct path is closed.

**`admin_dashboard_screen.dart`**: `_deleteUser` no longer does its own Firestore batch — it calls `adminDeleteUser` and treats a failure as a real failure (previously the Firestore delete "succeeded" client-side regardless of whether the Cloud Function call worked, which is exactly backwards now that the function is the actual source of truth). Confirmation dialog copy updated to accurately describe what's deleted vs. kept.

## Requirement 4 checklist

- **Normal users cannot delete other users**: enforced by the `admins` collection membership check in `adminDeleteUser` (unchanged, already correct) *and now also* by `firestore.rules`' `if false` — even a compromised or buggy client path can no longer delete these documents directly.
- **Artisans cannot delete themselves through admin APIs**: an artisan is not in `admins`, so `adminDeleteUser` rejects them before any deletion logic runs. Unchanged, already correct — confirmed, not assumed.
- **Deletion requires confirmation**: already present (`showDialog` before calling `_deleteUser`'s logic), kept, copy updated.
- **No orphaned financial records removed incorrectly**: `jobs`, `quotes`, `payments`, `reviews`, `escrow_releases` are explicitly excluded from cleanup — verified above, not assumed.

## Residual, honestly flagged
Screens that look up a profile by `uid` (e.g. a job's artisan card, a chat header) will now more often encounter a genuinely-deleted document instead of one that merely never existed — `safeDocStream`/`safeStream` already return `null` rather than throwing for a missing document, but this pass did not audit every single screen for a graceful "Deleted User" fallback versus a blank/broken-looking card. Worth a follow-up UI sweep, not done here to keep this change scoped to the deletion flow itself.

## Files changed
`functions/index.js` (`adminDeleteUser`, full rewrite), `firestore.rules` (`users/{uid}`, `artisans/{uid}` delete rules), `lib/screens/admin/admin_dashboard_screen.dart` (`_deleteUser`), `test/admin_audit_log_test.dart` (new).

## Tests performed
- `test/admin_audit_log_test.dart` (new, 3 tests): the `AdminAction.userDeleted` ↔ `'userDeleted'` string-literal contract between Dart and `functions/index.js` (nothing type-checks this across the language boundary), `AdminAuditLogModel.fromJson` resolving a deletion-shaped entry correctly, and the unknown-action fallback not crashing the admin activity history.
- The actual server-side deletion sequence (Auth deletion, Storage cleanup, Firestore cascade, collection-group query) is Admin-SDK Cloud Functions code with no emulator harness in this repo — same standing, previously-disclosed gap as every other Cloud Function in this codebase. Flagged, not silently skipped.
- `flutter analyze`: full project, pre-existing issues only, none introduced.
- `flutter test`: full suite, all passing (see final count in the response this document accompanies).
