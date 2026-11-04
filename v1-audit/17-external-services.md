# Part 17 — External Services & Integrations

## Firebase (see Part 1 for the summary table; detail here)
- **Authentication** — email/password only reachable; phone-auth code exists but is unrouted (Part 2/15).
- **Cloud Firestore** — primary database, every collection cataloged in Part 11.
- **Cloud Storage** — job/profile/verification/portfolio/dispute-evidence photos, `storage.rules` detailed in Part 12.
- **Cloud Functions** (2nd gen, Node.js 20, single file `functions/index.js`) — the full function list: `paystackWebhook`, `autoReleaseEscrow`, `onJobCompleted`, `onArtisanRatingChanged`, `onArtisanVerificationChanged`, `onAdminGranted`, `onAdminRevoked`, `onDisputeCreated`, `initializePaystackTransaction`, `verifyPayment`, `analyzeJob`, `adminDeleteUser`, and — added by the most recent work — `processEscrowRelease`, `reconcileStuckEscrowReleases`. 14 functions total.
- **Cloud Messaging (FCM)** — push, server-originated only (Part 10).
- **Not integrated anywhere in this codebase**: Firebase Analytics, Crashlytics, Remote Config, App Check, Performance Monitoring, Realtime Database, Hosting-served dynamic content (only static `build/web` hosting is configured in `firebase.json`).

## Paystack
Integration is entirely Cloud-Functions-mediated — no client code holds a secret key (a prior, historical client-side-secret pattern has been replaced, per Part 8/12). REST endpoints called directly via `axios` from `functions/index.js`:
- `POST /transaction/initialize` — deposit initiation.
- `GET /transaction/verify/:reference` — the client-callable secondary confirmation path.
- Webhook receiver for `charge.success` (deposit) and (added by the most recent work) `transfer.success`/`transfer.failed`/`transfer.reversed` (payout).
- `POST /transferrecipient` — creates a payout recipient, requires a Paystack bank code the app's own data model doesn't natively store (Part 4/8).
- `GET /bank/resolve` — account-holder-name verification, added as a safety check before any payout.
- `POST /transfer` — initiates the actual payout.
- HMAC-SHA512 webhook signature verification against `PAYSTACK_SECRET_KEY` (a Firebase Functions secret, never a Firestore-stored value).

## Google Gemini (`@google/generative-ai`, `gemini-2.0-flash`)
One callable, `analyzeJob` — an opt-in job-description assistant at posting time. Classifies into one of 13 fixed categories, rewrites the description for clarity, returns a confidence score; accepts up to 3 base64 images. Explicitly scoped and sanitized (category is checked against the fixed list before being trusted; confidence is clamped 0–1). Not a chatbot, not stateful, nothing persisted server-side beyond the response returned to the client (the client decides whether to save the suggestion onto the job doc).

## Location / Maps
- **`geolocator`, `geocoding`** — used for exactly one purpose across the entire codebase: a one-time position capture + reverse-geocode at job-posting time (`service_request_screen.dart`), prefilling the job's address. **No live tracking, no map rendering package (`google_maps_flutter` or equivalent) exists anywhere** — confirmed absent from `pubspec.yaml`.
- **`permission_handler`** — present as a dependency; the specific location-permission request flow found in this codebase goes through `geolocator`'s own permission API directly at the one call site above, not through this package independently.

## Media
`image_picker` (gallery/camera capture across chat, job photos, portfolio, verification, dispute evidence), `flutter_image_compress` (client-side compression before every confirmed upload path — thresholds vary: 500KB for chat images, 600KB for avatars, 800KB for portfolio/verification), `cached_network_image` (network image caching/display).

## Payments UI
`webview_flutter` (renders the Paystack checkout page), `url_launcher` (present as a dependency; no confirmed call site was independently re-verified for this Part).

## Notifications
`flutter_local_notifications` (foreground push display, Part 10).

## Networking / Storage / Offline
`dio` (an HTTP client dependency; `lib/core/network/` contains an API client + auth interceptor — not confirmed to be actively used by any traced feature in this audit, since every real network call found in the codebase goes through `cloud_functions`/`cloud_firestore`/`firebase_storage`'s own SDKs, not a raw Dio client), `flutter_secure_storage` (secure token storage, `lib/core/auth/secure_token_manager.dart` — existence confirmed, contents not independently re-read for this Part), `connectivity_plus`, `shared_preferences` (local theme persistence, confirmed via `theme_provider.dart`'s usage pattern).

## UI/Animation
`google_fonts` (a declared dependency, confirmed in prior analysis of this codebase to be **unused** — the theme hardcodes the bundled `Inter` font's literal string name instead of calling `GoogleFonts.inter()`), `shimmer`, `flutter_animate`, `lottie`, `fl_chart` (admin charts).

## Not integrated anywhere
Any SMS provider (no OTP/SMS code found despite the old root-level `AUTH_AUDIT_REPORT.md` referencing OTP-based demo registration), any social-auth SDK (Google/Apple sign-in buttons exist visually but call no real SDK, Part 2), any dedicated search service (Algolia/Typesense/similar — no free-text search exists per Part 3), any map/geocoding-beyond-one-shot service, any error-tracking/observability service (no Crashlytics, Sentry, or equivalent).
