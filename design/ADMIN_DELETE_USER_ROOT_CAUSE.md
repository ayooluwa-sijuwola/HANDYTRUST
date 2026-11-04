# Admin "Delete User" Root-Cause Investigation

## Symptom

Clicking Delete on a user in Admin → Users throws `firebase_functions/not-found` (`NOT_FOUND`), raised at `_UserListTileState._deleteUser` (`admin_dashboard_screen.dart:4473`), and the raw exception was shown directly to the admin.

## Investigation

**1. Exact Cloud Function name called by the client.**
`lib/screens/admin/admin_dashboard_screen.dart:4473-4475`:
```dart
await FirebaseFunctions.instance
    .httpsCallable('adminDeleteUser')
    .call({'uid': user.uid});
```
No explicit region (`FirebaseFunctions.instance`, not `.instanceFor(region: ...)`) — defaults to `us-central1`.

**2. Does the function exist in source?**
Yes. `functions/index.js:1140`, `exports.adminDeleteUser = onCall(async (request) => {...})`, using `firebase-functions/v2/https`. It checks `request.auth`, checks an `/admins/{uid}` doc exists, validates the target `uid`, blocks self-deletion, writes an audit log first, then deletes the Firebase Auth account, cleans up Storage, and deletes the account's own Firestore documents (not jobs/payments/reviews/disputes — those belong to the other party too). The function itself is correctly written and matches the client's call signature exactly.

**3. Is it deployed to the currently configured project?**
No. `firebase functions:list` against the active project returned: **"No functions found in project handytrust."** Not just `adminDeleteUser` — every function in `functions/index.js` (13 total: webhooks, schedulers, Firestore triggers, and 3 other callables) has zero deployed instances.

**4/5. Region — deployed vs. client.**
Moot: nothing is deployed, so there is no live region to compare against. For completeness, neither the function definition nor the client specify an explicit region, so both would resolve to the same default (`us-central1`) if deployment succeeded. Region mismatch is ruled out as a contributing cause.

**6. Do the Flutter app and Firebase Functions target the same project?**
Yes, confirmed both ways: `.firebaserc` → `"default": "handytrust"`, `firebase use` → `handytrust` (current); `lib/firebase_options.dart` → `projectId: 'handytrust'` on every platform target. No project mismatch.

**7. Was the function renamed/removed while the client still references the old name?**
No. The name, signature, and call contract match exactly between client and source. This is not a drift/rename bug.

**8. Current Firebase plan — can Cloud Functions actually be deployed here?**
This is the root cause. A scoped deploy attempt (`firebase deploy --only functions:adminDeleteUser`) — the most direct way to get an authoritative answer — failed immediately, before touching any function, with:

> Your project **handytrust** must be on the **Blaze (pay-as-you-go) plan** to complete this command. Required API `artifactregistry.googleapis.com` can't be enabled until the upgrade is complete.

2nd-gen Cloud Functions (`firebase-functions/v2`, what this project uses) require Cloud Build and Artifact Registry, both of which require an active Blaze billing plan. The `handytrust` project is currently on the free **Spark** plan. Deployment fails at the API-enablement step, before any function is ever created — which is exactly consistent with `firebase functions:list` showing nothing deployed at all, and with the earlier, separately-documented finding in this project that Firebase Storage was also never provisioned (`design/STORAGE_UPLOAD_ROOT_CAUSE.md`) — both are symptoms of the same underlying gap: this project has never been upgraded off the Spark plan.

## Root cause

**Not** a naming, region, project, or code bug. `adminDeleteUser` is correctly written and the client calls it correctly — it has simply never been deployable, because the `handytrust` Firebase project is on the Spark plan, and Spark cannot host Cloud Functions (2nd gen) at all. Every `httpsCallable` in this app (`adminDeleteUser`, `initializePaystackTransaction`, `verifyPayment`, `analyzeJob`) is equally affected — none of them have ever had a deployed backend to call. This is a project-configuration/billing gap, not an application defect.

## What was fixed vs. what remains blocked

**Fixed:** production error handling. `_deleteUser`'s catch block previously did `showErrorSnackbar(context, 'Failed to delete user: $e')` — interpolating the raw exception (package/class names, error codes) directly into UI shown to the admin. It now shows a single fixed string, **"Unable to delete user. Please try again."**, regardless of what actually failed, while the full exception and stack trace still go to `debugPrint` for developer/log visibility. Verified live in both light and dark mode — screenshots below.

**Still blocked, and correctly so:** actual user deletion. Per the explicit constraints of this task, none of the following were done as a workaround:
- Firestore rules were **not** weakened. `firestore.rules:65`, `/users/{uid}`: `allow delete: if false;` — unconditional, for every caller including admins, by deliberate prior design (its own comment references this exact tradeoff: a client-side admin delete was removed on purpose because it skipped the audit log, Storage cleanup, and real Auth deletion that only the Cloud Function performs).
- Authentication was **not** bypassed.
- The Cloud Function was **not** replaced with a client-side deletion. Client-side code cannot delete another user's Firebase Auth account or their Storage files at all (no permission model for it), so this was never a viable "fix" — only a way to fake success while leaving the Auth account and files behind.
- The error was **not** hidden or claimed fixed. Delete still fails, correctly and honestly, with a clean message instead of a leaked exception.

**To actually unblock deletion:** the `handytrust` Firebase project needs to be upgraded to the Blaze plan (https://console.firebase.google.com/project/handytrust/usage/details), after which `firebase deploy --only functions:adminDeleteUser` (or a full `firebase deploy --only functions`, since none of the 13 functions are deployed) needs to be run. This requires a billing decision only the project owner can make — consistent with this session's standing instruction not to modify the Firebase billing plan unilaterally, the upgrade itself was not performed.

## Validation performed

- `flutter analyze` — no new issues (12 pre-existing, unrelated).
- `flutter test` — 85/85 pass.
- `flutter build web --release` — clean build.
- Live, real-account test in the running app: opened Admin → Users, selected a real test user, clicked Delete, confirmed the dialog. Result: the user is **not** deleted (still present in the list afterward, count unchanged) — correct, honest behavior given the function isn't deployed. The snackbar shown was exactly **"Unable to delete user. Please try again."**, with the full technical detail (`[firebase_functions/internal] internal`, uid, stack trace) visible only in the browser console/debug log. Verified in both Light and Dark Mode.
- Non-admin protection: verified in source — the Cloud Function itself re-checks `/admins/{uid}` server-side (so even a stolen/forged client call is rejected), and the client-side router already blocks non-admins from ever reaching `/admin/*` at all. Full end-to-end testing of an unauthorized *deployed* call isn't currently possible, since no function is deployed for any caller to reach.

## Conclusion

This is not fixed, and is not claimed to be. The application-level bug (leaking raw exception detail to the admin) is fixed and verified. The underlying reason deletion doesn't work — no Cloud Functions are deployed to this project because it's on the Spark plan — is an environment/billing blocker outside application code, reported here rather than worked around.
