# Part 4 — Artisan Features

## Dashboard ✅
- **Purpose**: role-specific daily entry point.
- **Entry point**: bottom nav Explore tab (artisan mode) → `ArtisanHomeTabContent`.
- **Workflow**: conditional sections in a fixed order — pending-approval banner (`approvalStatus == 'pending'`), availability toggle (only once approved), verification/trust card, stats row, quick actions, jobs section. If no `artisans/{uid}` doc exists at all, auto-redirects to `/register/artisan`.
- **Known gap, verified by direct inspection**: there is a `pending` banner and an `approved` availability toggle, but **no banner state for a rejected application** — an artisan whose verification was rejected sees neither the pending state nor the approved state; nothing on this screen explains why they're stuck.
- **Completion status**: ✅ for the paths it handles; ⚠️ for the missing rejected-state banner.

## Nearby jobs / Open Jobs Feed ✅
- **Purpose**: browse jobs available to quote on.
- **Entry point**: `/open-jobs` (`open_jobs_feed_screen.dart`).
- **Workflow**: shows every job at `status: 'requested'` in the artisan's category, visible to *any* registered artisan regardless of approval/verification state — actually submitting a quote requires the full approved+verified gate, enforced by rules (`isArtisanEligible`), not just the UI.
- **Known gap, verified by direct inspection**: no persistent messaging on this screen distinguishing an eligible artisan from an unverified one before they attempt to quote — the block is discovered only via a rules rejection at submission time.

## "Interested" button ❌ — does not exist as a distinct mechanic
There is no "interested" concept separate from quoting anywhere in the codebase — an artisan's only expressed-interest action on an open job is submitting an actual quote (or messaging the customer pre-match, which the rules explicitly permit while a job is still `requested`). The brief-style feature list some documentation uses (including this audit's own request) names "Interested button" as if it's a lighter-weight action than quoting; no such button, field, or collection was found.

## Quote submission ✅
- **Purpose**: propose a price and terms for an open job.
- **Entry point**: Open Jobs Feed card.
- **Workflow**: `QuoteService.submitQuote` — labor cost + optional materials cost (total = sum), duration in days, optional notes. Document ID == artisan's UID, so resubmission overwrites rather than creates a second competing quote. A denormalized snapshot of the artisan's name/rating/trust tier/verification/trust score is written into the quote at submission time (avoids an N+1 read when the customer's quote inbox renders).
- **Database interaction**: `jobs/{jobId}/quotes/{artisanId}`.
- **Notifications**: `quote_received` to the customer.
- **Completion status**: ✅.

## Chat ✅ — see Part 9
Same screen/mechanism as the customer side (Part 3) — no artisan-specific chat behavior found beyond role-based message alignment/color.

## Accepted jobs ✅
Surfaced via the "My Tasks" tab (`all_jobs_screen.dart`, filtered by `artisanId` instead of `customerId`) — same screen, same filter chips (including the Disputed filter), role-branched internally rather than a separate screen.

## Availability ✅
- **Purpose**: toggle whether the artisan currently accepts new jobs.
- **Entry point**: Dashboard.
- **Workflow**: writes `isAvailable` to **both** `artisans/{uid}` and `users/{uid}` in one batched write (`_toggleAvailability`) — the only place in the codebase found writing to both collections for the same logical field in a single action.
- **Completion status**: ✅.

## Verification ✅
- **Purpose**: identity verification (selfie + government ID) required before quoting is possible.
- **Entry point**: `/verification` (`verification_upload_screen.dart`).
- **Workflow**: front-camera selfie + ID photo capture, both compressed client-side; checks for and displays any existing submission's status on load (handles resubmission correctly). A **"Verify Later"** deferral path exists, writing a `pending_later` status that lets the artisan proceed to browse jobs without uploading anything, at the cost of being unable to quote until they do complete verification.
- **Notable, already-fixed defensive code found in this file**: a code comment documents that both image pickers previously crashed with an uncaught `setState() after dispose()` error if the camera activity backgrounded mid-capture — this has already been fixed with `mounted` checks, confirmed present in the version read for this audit.
- **Completion status**: ✅.

## Trust score ✅ (server-computed, real — not a placeholder)
- **Purpose**: a composite reputation signal meant to drive discovery ranking.
- **Where it's computed**: `functions/index.js`'s `_computeTrustScore` — 5 weighted factors (30% completed-job volume, 25% rating, 20% verification, 15% response time, 10% dispute history), recomputed by Cloud Function triggers whenever any input changes.
- **Two verified defects in the inputs feeding this formula**: `responseTimeMinutes` is set to a hardcoded `30.0` once at artisan registration and never updated by any code path found anywhere in the repository — every artisan's response-time component is therefore identical and non-discriminating. Separately, `cancelledJobsCount`/`cancellationRatePercent` are computed and stored on every job outcome but never actually read by `_computeTrustScore` — the brief's "cancelled jobs" signal is tracked but structurally disconnected from the score.
- **Where it's displayed**: a client-side mirror (`TrustScoreService.breakdown()`) reproduces the same formula for the artisan's own breakdown UI — display-only, never writes.
- **Known gap**: the discovery/matching ranking (`MatchingService`) does not read `trustScore` at all — it ranks by a third, separate formula (`ArtisanModel.matchScore`). The score is real and correctly computed, but does not drive the ranking it's meant to.

## History ✅ — same as "Accepted jobs" above, same screen, all statuses via the filter chips.

## Wallet ✅ — same screen as Part 3, artisan variant reads `artisanId`-filtered payments (escrow held, total paid out).

## Notifications ✅ — same screen/mechanism as Part 3, no artisan-specific behavior found.

## Calendar ❌ — does not exist
`appointmentSlots` (artisan-proposed, up to a UI-enforced cap) and `confirmedAppointment` (customer-picked) exist as plain `DateTime` list/value fields on the job document, rendered as a simple slot-picker inline on Job Detail (`_AppointmentSection`) — there is no calendar view, no cross-job schedule visualization, and no conflict detection between two jobs' confirmed times anywhere in the codebase.

## Tracking (artisan side) ⚠️ — same as customer-side finding in Part 3
The artisan sets `progressStage` manually, including tapping "On My Way" — no location data is captured or transmitted at any point. No map package (`google_maps_flutter` or equivalent) exists in `pubspec.yaml`.

## Completion ✅
- **Purpose**: submit proof of finished work.
- **Entry point**: Job Detail's primary action while `inProgress` → `/job/:jobId/submit` (`job_completion_screen.dart`).
- **Workflow**: at least one "before" (arrival) photo, at least one "after" (completion) photo, optional notes — matches `JobService.submitCompletion`'s parameter shape exactly (`completionImageUrls`, `beforePhotoUrls`, `artisanNotes`).
- **Database interaction**: `status: inProgress → submitted`, sets a 14-day `disputeWindowEndsAt` and (separately, via the auto-release scheduler) a 48-hour `autoReleaseAt`.
- **Completion status**: ✅.

## Bank/payout details ✅ (data collected; consumed correctly as of the newest code in this repository)
- **Entry point**: `/bank-details` (`bank_details_screen.dart`).
- **Workflow**: a fixed dropdown of 20 major Nigerian bank display names, account name, account number — written to `artisan_private/{uid}`.
- **Verified limitation**: the stored `bankName` is a display string, not a Paystack bank code — the most recent Cloud Functions work in this codebase (Part 8) added a static name-to-code lookup table specifically to bridge this gap, since Paystack's Transfer Recipient API requires the numeric code. That lookup table's accuracy for the newer fintech banks (Kuda, Moniepoint, Opay, PalmPay) was not verified against a live Paystack API call — flagged in Part 8 and Part 20.

## Business profile ✅
- **Purpose**: operate under a business name/registration instead of a personal one.
- **Entry point**: `/business-profile` (`business_profile_screen.dart`).
- **Workflow**: business name, registration number, business address, account type (individual/business) — writes into `artisans/{uid}`, the same public profile document search results read from.

## Portfolio ✅
- **Purpose**: showcase past work.
- **Entry point**: `/portfolio` (`portfolio_manager_screen.dart`).
- **Workflow**: two tabs — a flat photo gallery (`artisans.portfolioImageUrls`, add/remove/reorder, drag-to-reorder, capped, compressed client-side above an 800KB threshold) and a separate `portfolio_projects` collection for titled/described project entries.
- **Completion status**: ✅, no bugs found in this screen.

---

## Not found anywhere in the codebase for the artisan role
- A calendar/schedule view.
- Live location sharing or a map.
- An "interested" mechanic distinct from quoting.
- A rejected-application banner on the dashboard.
- Any automated response-time instrumentation feeding the trust score.
