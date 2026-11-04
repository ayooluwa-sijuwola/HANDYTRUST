# Part 3 — Customer Features

## Post a job ✅
- **Purpose**: capture a job request for artisans to quote on.
- **Entry point**: Explore tab's hero CTA → `/request` (`service_request_screen.dart`).
- **Workflow**: category, description, photos, budget range, urgency, optional scheduled date, one-time GPS capture (prefills address, does not enable live tracking).
- **Database interaction**: creates one `jobs/{jobId}` doc at `status: 'requested'`.
- **Notifications**: none triggered by posting itself (artisans discover it by querying the open feed, not via push).
- **Related screens**: `service_request_screen.dart`.
- **Limitations**: no draft-saving; no milestone/material payment breakdown at posting time (the whole `agreedAmount` model is single-payment — see Part 8).
- **Completion status**: ✅ fully implemented and reachable.

## Browse artisans ✅
- **Purpose**: let a customer proactively discover artisans, independent of a specific posted job.
- **Entry point**: Explore tab / `/browse-artisans` (`browse_artisans_screen.dart`).
- **Workflow**: category/search-driven list of approved+verified artisans.
- **Database interaction**: read-only query against `artisans` (public read, gated to `approvalStatus: approved` + `verificationStatus in [id_verified, trusted]`).
- **Notifications**: none.
- **Related screens**: `browse_artisans_screen.dart`, `artisan_profile_screen.dart`.
- **Limitations**: ranking is not trust-score-driven — `MatchingService`'s `_score()` uses `ArtisanModel.matchScore` (a third, independent rating/completion/response-weighted formula) plus a distance bonus, not the artisan's actual server-computed `trustScore`.
- **Completion status**: ⚠️ works, but ranking doesn't reflect the platform's own trust claim.

## Receive quotes ✅
- **Purpose**: see competing offers from multiple artisans on a posted job.
- **Entry point**: Job Detail screen's quote inbox section (rendered only while `status == requested` and viewed by the job's customer).
- **Workflow**: any approved+verified artisan can submit one quote per job (doc ID == artisanId, so a resubmission overwrites rather than duplicates).
- **Database interaction**: reads `jobs/{jobId}/quotes`.
- **Notifications**: `quote_received` sent to the customer on each new quote (`QuoteService.submitQuote`).
- **Related screens**: `job_detail_screen.dart`.
- **Completion status**: ✅.

## Accept quote ✅
- **Purpose**: commit to one artisan for the job.
- **Entry point**: quote inbox / a specific quote card.
- **Workflow**: `QuoteService.acceptQuote` closes every other pending quote and delegates the job mutation to `JobService.acceptQuote`, which transitions `requested → matched`, sets `artisanId`, all in one Firestore transaction (no partial state possible — audit-logged).
- **Notifications**: `quote_accepted` to the winning artisan.
- **Completion status**: ✅.

## Reject quote ⚠️ (partial — single-quote rejection only)
- **Purpose**: decline one specific offer without accepting another.
- **Workflow**: `QuoteService.rejectQuote` — sets that one quote to `rejected`, no job mutation.
- **Notifications**: `quote_rejected` to that artisan.
- **Limitations**: this is a per-quote action; there's no bulk "reject all and repost" flow — a customer who dislikes every quote just doesn't act on any of them.

## Chat ✅ (see Part 9 for full detail)
- **Purpose**: negotiate and coordinate with a specific artisan before/after matching.
- **Entry point**: quote card / job detail → `/chat/:jobId`.
- **Limitations verified directly in code**: no read receipts UI, no typing indicator; the chat screen's "Pay Now" button is not aware of the Agreement Confirmation gate added later in this codebase (see Part 6/9) — it still renders and is tappable any time `status == 'inChat'`, regardless of `agreementStatus`.

## Confirm Agreement ✅ (the newest customer-facing feature in this codebase)
- **Purpose**: an explicit, locked, two-party checkpoint between negotiation and payment — added specifically because informal chat agreement was judged unsafe for a trust marketplace. Full detail in Part 6.
- **Entry point**: Job Detail screen, `_AgreementSection`, rendered during `inChat`.
- **Limitations**: not surfaced anywhere in chat itself (see above) — a customer negotiating in chat has no visibility into the agreement checkpoint's existence unless they navigate to Job Detail.

## Escrow payment ✅ (full detail in Part 8)
- **Purpose**: pay for the job with the money held until work is confirmed.
- **Entry point**: `/payment/:jobId` from Job Detail (or, currently, from chat — see above).
- **Workflow**: Paystack WebView checkout → webhook confirms `charge.success` → `escrowLocked`, gated (as of the most recent codebase changes) on `agreementStatus == 'confirmed'`.
- **Completion status**: ✅ deposit path; payout-to-artisan automation also now exists (Part 8) but has not been verified against a live transaction.

## Track artisan ⚠️ (partial — no live GPS)
- **Purpose**: know where the artisan is / when they'll arrive.
- **What actually exists**: a manually artisan-set `progressStage` (accepted → onTheWay → workStarted → 25/50/75% → almostFinished → completed), rendered as a discrete-step timeline on Job Detail. **No live position, no map, no ETA exists anywhere in the codebase** — `onTheWay` is a label the artisan taps, with zero location data attached to it. `geolocator`/`geocoding` are used only for the one-time job-posting address capture.
- **Completion status**: ❌ for the "track" part of "track artisan" as commonly understood; ✅ for the discrete progress-stage display.

## Rate artisan ✅
- **Purpose**: leave a star rating + written review after completion.
- **Entry point**: Job Detail's post-completion action → `/review/:jobId`.
- **Workflow**: `ReviewScreen` is hard-gated on `job.status == JobStatus.completed` — attempting to review any other status shows a locked message instead of a form.
- **Database interaction**: creates one `reviews/{reviewId}` doc; rules independently enforce customer-only, completed-job-only, rating 1–5.
- **Completion status**: ✅, and the gating is enforced at both the UI and rules layer, not just one.

## Wallet ✅ (newest screen in the app, single-payment only)
- **Purpose**: see money in motion — escrow held, total spent.
- **Entry point**: bottom nav (a primary tab, not a Profile sub-item, in the current build).
- **Database interaction**: reads the `payments` collection directly (`PaymentModel`), grouped/summed client-side.
- **Limitations**: not milestone-aware — there is no milestone data model in this codebase at all (Part 8), so this screen shows one line per job's whole payment, not a phased breakdown.

## Profile ✅
- **Purpose**: account hub — jobs/chats/reviews shortcuts, notifications, settings, sign out.
- **Entry point**: bottom nav.
- **Known issues, verified by direct code inspection**: the "My Reviews" and "Payment Methods" menu-item mis-routing bugs documented in the prior redesign work for this codebase have been fixed in the version currently in this repository (confirmed: "My Reviews" now routes conditionally rather than to `/notifications`; "Payment Methods" was removed as redundant with the Wallet tab). "About HandyTrust" was previously a no-op button; also fixed.

## History ✅
- **Purpose**: see every job the customer has posted, filterable by status.
- **Entry point**: bottom nav "My Tasks" tab / `/jobs` (`all_jobs_screen.dart`).
- **Workflow**: All / Active / Completed filter chips, plus a fourth **Disputed** filter (added in the most recent work in this codebase) that correctly isolates `disputed` + `resolved` jobs, which the original two-bucket All/Active/Completed split had been silently folding into "Active"/"Completed" respectively.
- **Completion status**: ✅.

## Complaint (dispute) ✅
- **Purpose**: formally flag a problem with a job.
- **Entry point**: Job Detail's dispute action → `/dispute/:jobId`.
- **Workflow**: fixed reason dropdown (5 options including "Other"), free-text elaboration, evidence photo upload (compressed client-side), submitted via `DisputeService.raiseDispute` → `JobService.raiseDisputeWithRecord` (job + `disputes` doc written atomically).
- **Database interaction**: creates `disputes/{disputeId}`, sets job `status: disputed`.
- **Limitations**: only reachable from Job Detail — no "Report an issue" entry point exists inside the chat screen in the code as it currently stands (this was proposed in prior redesign work for this codebase but not found implemented in `chat_screen.dart` as read directly for this audit).
- **Completion status**: ✅ core flow; the chat-entry-point extension is not built.

## Notifications ✅
- **Purpose**: in-app feed of transactional events.
- **Entry point**: bottom nav / header bell icon → `/notifications` (`notifications_screen.dart`).
- **Workflow**: list of `notifications` docs for the signed-in user, mark-all-read, and a mute toggle that writes the same `users/{uid}.notificationsEnabled` field the Settings screen's equivalent toggle writes (confirmed both surfaces are consistent, not duplicate/conflicting write paths).
- **Limitations**: only the fixed, whitelisted set of transactional notification types exists (Part 10) — no reminder-class notifications (escrow, appointment, review-nudge) were found anywhere in the codebase.
- **Completion status**: ✅ for what exists; the reminder-class notification types discussed in prior redesign work for this codebase were not found implemented.

## Search / Filters ⚠️ (basic only)
- **Purpose**: narrow down artisan/job lists.
- **What exists**: category-based filtering on Browse Artisans and the job-status filter chips on My Tasks/History.
- **What does not exist**: no free-text search across artisans or jobs was found in any screen read for this audit; no radius/distance filter control exposed to the customer (distance only factors into the backend ranking formula, invisibly).

---

## Not found anywhere in the codebase (stated explicitly, per the audit's "never guess" rule)
- Live GPS tracking / map / ETA.
- Milestone or material payment splitting.
- Refund workflow as a distinct customer-facing action.
- Chat read receipts, typing indicators, archive, or in-thread search.
- Free-text search across jobs or artisans.
