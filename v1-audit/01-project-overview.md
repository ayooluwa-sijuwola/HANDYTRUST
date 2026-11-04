# Part 1 — Project Overview

## What HandyTrust currently is

A Flutter + Firebase two-sided services marketplace connecting customers in Nigeria with identity-verified artisans (plumbers, electricians, carpenters, AC repair, and similar trades). Core loop: a customer posts a job → artisans quote → the customer accepts and negotiates → both parties explicitly confirm the agreed terms (a checkpoint added late in this codebase's history — see Part 6) → payment is held in escrow via Paystack → the artisan does the work and submits proof → the customer confirms (or a 48-hour timer auto-releases) → escrow is paid out to the artisan's bank account via a Cloud-Function-driven Paystack Transfer (also added late — see Part 8) → the customer reviews the artisan, and the artisan's server-computed Trust Score updates. A parallel admin surface (web-dashboard-style, reachable from within the same app) handles verification approval, dispute resolution, user/job management, and support.

## Major modules

- **Auth & onboarding** — email/password registration with a two-step artisan flow, email verification gate, role selection for dual-role accounts.
- **Customer-side marketplace** — job posting, artisan discovery/browsing, quote comparison, chat, agreement confirmation, escrow payment, job tracking, review.
- **Artisan-side marketplace** — profile/verification, open-jobs feed, quoting, agreement review, live-location "on my way" tracking, progress reporting, completion submission, portfolio, bank/payout details.
- **Escrow & payments** — Paystack-integrated deposit, webhook-confirmed escrow lock, manual or auto-release, and (as of the most recent work in this codebase) an actual Paystack Transfer payout to the artisan.
- **Trust Score** — a server-computed, 5-factor weighted score recalculated by Cloud Function triggers on every relevant event (rating, verification, completion, dispute).
- **Messaging** — per-job chat, including a pre-match multi-artisan phase.
- **Notifications** — FCM push + an in-app notification feed, both driven by a fixed, whitelisted set of event types.
- **Admin** — an 8+-section dashboard (user/artisan/job management, verification queue, disputes, reviews, support, deletion requests, audit logs, analytics) reachable inside the same Flutter app via a distinct shell.
- **Wallet** — a payment-history screen (added recently; reads the existing single-payment-per-job data model, not a milestone ledger — no milestone model exists in this codebase).

## Folder structure

```
lib/
├── core/
│   ├── auth/            secure token storage, auth-related Riverpod providers
│   ├── constants/       service category list
│   ├── errors/          typed job exceptions
│   ├── firebase/        Firebase bootstrap
│   ├── network/         Dio client, auth interceptor
│   ├── services/        the single-writer service layer — 20+ domain services
│   └── utils/           safe Firestore stream/parse helpers
├── firebase/
│   ├── auth/             a second, largely unused auth abstraction (see Part 19)
│   ├── firestore/        a second, largely unused Firestore repository abstraction (see Part 19)
│   └── messaging/        LocalNotificationService (the one actively-used piece of this folder)
├── models/               plain Dart data classes — JobModel, UserModel, ArtisanModel, QuoteModel, etc.
├── providers/            ~20+ Riverpod provider files, roughly one per domain
├── routes/                single GoRouter configuration + auth-aware redirect logic
├── screens/               organized by feature folder (auth, home, artisan, job, chat, payment, admin, ...)
├── theme/                 design tokens — colors, typography, spacing, motion
├── widgets/                shared/reusable widgets
├── main.dart              bootstrap: Firebase init → local-notification init → runApp
└── test/                  one test file (added in the most recent work — see Part 2's note on testing)

functions/
└── index.js               all Cloud Functions, single file

firestore.rules, firestore.indexes.json, storage.rules, firebase.json    — backend config, repo root
```

**Two structural duplications exist in `lib/`, both confirmed by direct inspection**: `lib/core/services/` (the real, actively-used write layer) vs. `lib/firebase/auth/` + `lib/firebase/firestore/` (an earlier, parallel abstraction that appears largely unused in practice) — documented fully in Part 19 (Dead Code) rather than here.

## Architectural pattern

A single-writer service layer (`lib/core/services/*`) is the only code that writes to Firestore or Storage from the client. The most consequential example is `JobService`, which owns every write to the `jobs` collection, enforces a hand-rolled state machine (`allowedTransitions`), and writes an immutable audit-log entry atomically with every mutation inside a Firestore transaction — no screen or provider writes to `/jobs` directly. `QuoteService`, `NotificationService`, and others follow the same "one canonical writer per collection" convention, though it is not perfectly followed everywhere (two near-duplicate admin-audit-log services and two escrow-related service classes both exist — see Part 19).

Screens are Riverpod `ConsumerWidget`/`ConsumerStatefulWidget`s. Providers sit between screens and services, mostly as thin `StreamProvider`/`FutureProvider`/`StateNotifierProvider` wrappers around a service method (Part 13 catalogs these).

## State management

**Riverpod** (`flutter_riverpod`), exclusively — no other state-management library is used anywhere in the app. Read state flows through `StreamProvider`s watching Firestore snapshot streams (via a `safeStream`/`safeDocStream` helper that normalizes stream errors so a `StreamProvider` never gets permanently stuck in an error state from a transient issue). Write/mutation state flows through `StateNotifierProvider`s wrapping `AsyncValue<void>` (loading/data/error), the clearest example being `EscrowNotifierProvider`, which every job-lifecycle mutation (accept artisan, open chat, init payment, confirm complete, start work, submit completion, propose/confirm appointment, cancel, update progress, and — as of the most recent work — confirm/accept/reject the agreement) routes through.

## Navigation

**GoRouter** (`go_router`), a single declarative route table (`lib/routes/router.dart`) with one centralized `redirect:` callback handling every cross-cutting access rule: unauthenticated → `/login`, unverified email → `/verify-email`, suspended account → `/suspended`, admin-route guard (`/admin/*`), and a dual-role interstitial (`/role-select`). This callback is re-evaluated on auth-state change, on the user's own profile document changing (e.g. an admin suspends them mid-session), and on the resolved admin-claim state — not just on navigation events. The admin section uses a `ShellRoute` to keep its sidebar/chrome mounted across section switches rather than remounting on every click. Full route table in Part 16.

## Firebase services used

| Service | Role |
|---|---|
| **Firebase Authentication** | Email/password only in the currently-reachable UI; a phone-auth screen exists in code but is not routed (Part 19) |
| **Cloud Firestore** | Primary database — every collection cataloged in Part 11 |
| **Firebase Storage** | Job photos, profile photos, verification documents, portfolio photos, dispute evidence |
| **Cloud Functions (2nd gen, Node.js 20)** | Paystack webhook handling, scheduled escrow auto-release, escrow payout automation (Paystack Transfer), trust-score recomputation triggers, admin-claim sync, dispute alerting, FCM push sending, two AI-adjacent/admin callables |
| **Firebase Cloud Messaging** | Push notifications, sent server-side from Cloud Functions only — no client ever calls FCM's send API directly |

No Firebase Analytics, Crashlytics, Remote Config, or App Check integration was found anywhere in the codebase.
