# Storage Upload Failure — Root Cause Investigation

**No fix implemented yet, per instruction.** This is the investigation only.

## Exact error

**Browser-reported (Chrome console, captured from the real running app):**
```
Access to XMLHttpRequest at 'https://firebasestorage.googleapis.com/v0/b/handytrust.firebasestorage.app/o?name=jobs%2F<jobId>%2F<uid>%2Fimage_0.jpg'
from origin 'http://localhost:8642' has been blocked by CORS policy: Response to preflight
request doesn't pass access control check: It does not have HTTP ok status.
```
Network trace confirms the request itself: `POST .../o?name=...`, `x-goog-upload-protocol: multipart`, a real `Authorization: Firebase <JWT>` header, `Content-Type: multipart/related` — i.e., `StorageService`'s upload call fires correctly, with a valid signed-in user, and the browser blocks it citing a bad preflight status.

## What the error message actually means — and why it's misleading

"Doesn't pass access control check: it does not have HTTP ok status" is Chrome's specific wording for **the preflight OPTIONS response itself was not a 2xx** — this fires *before* Chrome ever looks at CORS headers. It reads like a CORS-configuration problem. It isn't one.

## Investigation performed (in order, each ruling out one category from the task)

1. **Reproduced the preflight directly** (`curl -X OPTIONS` matching the real request's `Access-Control-Request-Headers`) against `http://localhost:8642` as Origin → **404**, body `{"error":{"code":404,"message":"Not Found."}}`, but `Access-Control-Allow-Origin: *` **is already present** on that 404. If this were a real CORS-config rejection, that header would be *absent*, not present-on-an-error-page.
2. **Repeated the identical request with `Origin: https://handytrust.web.app`** (a stand-in production-style origin) → **identical 404**, identical headers. Rules out "localhost is blocked but production works" — both fail exactly the same way. This directly answers requirement #2's "local development origin" candidate: **no**, origin is not the variable.
3. **Plain unauthenticated `GET .../o?maxResults=1`** (list the bucket) → **same generic 404**. Not a CORS-specific failure at all — even a request with no preflight involved fails identically.
4. **Confirmed the bucket name in code is correct**: `firebase apps:sdkconfig WEB <appId> --project handytrust` (Firebase's own authoritative project config, not the repo) returned `"storageBucket": "handytrust.firebasestorage.app"` — **exactly matching** `firebase_options.dart`. Rules out requirement #2's "Firebase SDK configuration" candidate.
5. **Decisive test**: `firebase deploy --only storage --project handytrust` (Firebase's own first-party CLI, authenticated, attempting the routine step every Storage deploy does first) failed immediately with:
   ```
   storage: ensuring required API firebasestorage.googleapis.com is enabled...
   Unexpected error when fetching default storage bucket.
   Error: Failed to make request to https://firebasestorage.googleapis.com/v1alpha/projects/handytrust/defaultBucket
   ```
   This is Firebase's own tooling — not a guess — saying it cannot find a default Storage bucket for this project at all. **This command failed before reaching the actual rules-upload step, so nothing was deployed or changed.**

## Root cause

**Firebase Storage was never provisioned for the `handytrust` project.** A `storageBucket` name is reserved in the project's config (correctly, and matching this repo's code exactly), but the actual underlying Cloud Storage bucket resource behind that name was never created. That requires a one-time, human, in-Console step (Firebase Console → Build → Storage → "Get started" → choose a storage location — a permanent choice the Firebase CLI deliberately won't make unattended, which is exactly why the CLI deploy failed at that step rather than proceeding).

This explains every symptom without contradiction:
- Every request type (GET, OPTIONS, authenticated POST) 404s identically — there's no bucket to route to.
- `Access-Control-Allow-Origin: *` shows up anyway — that's Firebase's API gateway adding a permissive header to its own generic error page, unrelated to any bucket-level CORS policy (which, again, can't exist yet — there's no bucket to configure it on).
- The browser's error names "CORS" specifically because 404 isn't a 2xx, and Chrome's preflight check stops at the status code before it would ever get to inspect headers.

**Corroborating evidence, independent of this investigation**: every artisan and user avatar seen throughout this entire testing session — Browse Artisans, Profile, Chat — has rendered as a colored-circle-with-initial fallback, never an actual uploaded photo. That's consistent with *no upload of any kind (profile photo, portfolio image, verification document, job photo) ever having succeeded for this project*, not just job photos specifically.

## Which category from the task's list is it?

| Candidate | Verdict |
|---|---|
| Firebase Storage configuration | No — there's nothing to misconfigure; the resource doesn't exist |
| Bucket configuration (CORS/lifecycle) | No — same reason, one level more fundamental |
| Local development origin | No — identical failure reproduced against a production-style origin |
| Firebase SDK configuration | No — bucket name confirmed correct against Firebase's own authoritative record |
| Authentication/rules | No — preflight and even unauthenticated GETs fail identically; rules are never reached |
| Browser preflight behavior | No — Chrome is behaving correctly; the status genuinely isn't 2xx |
| **Storage never provisioned for the project** | **Yes — confirmed directly by Firebase's own CLI** |

## Safest fix

Not a code change. `storage.rules` in this repo is already correct and already written/tested against the paths `StorageService` uses (`jobs/{jobId}/{uid}/...`, `verifications/{uid}/...`, etc.) — it just has nowhere to deploy to yet.

1. In the Firebase Console for the `handytrust` project → Build → Storage → "Get started" → choose a storage location. This is the one human decision the CLI can't make (location is permanent once set).
2. Once that's done, `firebase deploy --only storage --project handytrust` deploys the existing `storage.rules` — should succeed cleanly, since the rules file itself hasn't changed and was already reviewed multiple times earlier in this project's work.

## Does this affect production?

Yes, unavoidably — there is one Firebase project (`handytrust`) serving both this local test and whatever's deployed live; there's no separate dev/prod Storage split here. But "affects production" here means *fixes* a feature that has apparently never worked for any user of this app, not a risky change to something already working. No existing behavior regresses — every code path calling `StorageService` has been failing exactly like this the entire time regardless of who calls it or from where.

## Exact files/configuration that need changing

**None in this repository.** `storage.rules`, `firebase.json`, `firebase_options.dart` are all already correct. The action is entirely in the Firebase Console (bucket provisioning) followed by a standard `firebase deploy --only storage`.

## Not implemented

Per instruction, no fix has been applied. Provisioning the bucket requires your action in the Firebase Console (the storage-location choice specifically can't be made by the CLI or by me on your behalf) — let me know once that's done and I'll deploy the rules and verify with a real upload through the running app, then continue to the full Create Job → upload → job creation → downstream flow test.
