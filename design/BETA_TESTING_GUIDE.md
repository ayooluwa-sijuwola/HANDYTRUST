# Beta Testing Guide — Quoting Without Real Verification

How to let a small number of approved test artisans submit quotes and be matched to jobs without completing real identity verification, for controlled beta testing, without weakening production security for anyone else.

## What this is

An admin-only, per-artisan `betaTester` flag on `artisans/{uid}`. An artisan with `betaTester: true` is treated as eligible to quote/be matched (`isArtisanEligible()` in `firestore.rules`) even while `verificationStatus` is still `unverified` or `id_submitted`. Nothing else about verification changes.

## What this is NOT

- **Not a global toggle.** There is no environment variable or build flag that relaxes verification for everyone — that would be exactly the "weakening production security" the task ruled out. The bypass is scoped to individual Firestore documents an admin explicitly edited.
- **Not a change to what "Verified" means.** A beta tester's quotes are written with `artisanVerified: false` (enforced server-side — see below), so they never display the Verified badge to a customer. Customers can still tell the difference.
- **Not a change to admin approval.** `isArtisanEligible()` still requires `approvalStatus == 'approved'` either way — an admin must have reviewed the account at all; only the *identity-verification* half of the bar is bypassable, and only for accounts an admin explicitly flagged.
- **Not client-settable.** `betaTester` is in `artisans/{uid}`'s forbidden-fields list for owner updates (`firestore.rules`) — an artisan cannot grant this to themselves no matter what they write from the client.

## How to enable it

1. Admin Dashboard → Users tab → select the artisan (must already be `approvalStatus: 'approved'`), or filter the list to **Beta Testers** to review who's currently flagged.
2. In the user detail panel, flip the **Beta Tester** switch on.
3. Confirm in the dialog. The switch reflects the live `betaTester` value read from Firestore; the user's row in the main list also shows a **Beta** badge next to their role.

The artisan can now:
- See their eligibility check pass in the Open Jobs Feed (no more "must be verified" block).
- Submit, edit, and withdraw quotes.
- Be selected/matched into a job (`requested → matched`).

They still cannot: appear in general public artisan discovery (`browse_artisans_screen.dart`/`artisan_list_screen.dart` — the `artisans/{uid}` public-read rule is unchanged and still requires real verification), show a Verified badge anywhere, or have their Trust Score affected — `betaTester` is never read by `_computeTrustScore`/`TrustScoreService`.

## How to disable it
Same panel, flip the switch off, confirm. The artisan immediately needs real verification to quote again, exactly like any other artisan — no residual state anywhere.

## Where the enforcement actually lives (defense in depth)
1. **`firestore.rules`** — `isArtisanEligible()` is the single function every quote create/update and every `requested → matched` job transition calls. This is the real, server-enforced gate; nothing client-side can be trusted instead of it.
2. **`firestore.rules`** — `isReallyVerified()` is a *separate* function used only to constrain the `artisanVerified` field's value on quote writes, independent of eligibility. This is what keeps a beta tester's quote from ever claiming the Verified badge, even though they're allowed to quote.
3. **`firestore.rules`** — `artisans/{uid}`'s update rule blocks the owner from writing `betaTester` at all; only `isAdmin()` can — this is also the one automated regression guard covering "unauthorized user attempting to modify betaTester" (`test/artisan_eligibility_test.dart`, since there's no Firestore emulator in this repo to test the rule's actual runtime behavior).
4. **`lib/core/services/artisan_eligibility.dart`** — `ArtisanEligibility.canQuote`/`isReallyVerified` is the *one* Dart mirror of the two rules functions above, used by both `open_jobs_feed_screen.dart` (UI gating) and `quote_service.dart` (the `artisanVerified` field written onto every quote) — not two separately-drifting copies. This is a UX/consistency mirror only — the rules above are the real authority, per this app's standing architecture (`WorkflowGateService`/`JobService`'s same client-mirrors-server pattern).

## Audit trail
Every toggle is logged via `AdminAuditService` as an `AdminAction.betaTesterChanged` entry (serialized action type: `beta_tester_changed`), with `adminId`/`targetId`/`timestamp` as top-level fields and `metadata: {previousValue, newValue, name}` — visible in the admin dashboard's activity history for that user.

## Root cause fixed alongside this (see also: verification flow debug summary)
While tracing the verification submission flow to build this feature safely, found and fixed the actual reason an artisan could not submit verification at all: `ios/Runner/Info.plist` had no `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` keys, so iOS silently refused every camera/photo-library permission request before this feature was ever relevant. Beta testing is an *additional* option for specific accounts, not a workaround for that bug — real verification now works after the Info.plist fix.
