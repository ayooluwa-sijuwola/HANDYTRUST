# HandyTrust — Screens Without an Approved Design

Date: 2026-11-04 · Companion to `STAGE8_COMPLETE_SCREEN_INVENTORY.md`

**The gap:**
- **Approved Stitch references** cover only 12 customer screens. They were implemented in Stage 8.
- **No approved design:** the other **48 live screens** (42 NEW + 6 SHARED) and **40 of the 47 overlays**, plus the approved new Finance section.

**What's ready:**
- For every one of them, a **proposed design is rendered** in both themes (`design/stage8_1_previews/`), or the screen reuses a rendered pattern (marked "reuses").
- **Nothing below may be implemented until you approve the previews.**

## 1. Screens needing approval (48 + 1 new section)

| ID | Screen | Role | Proposed design (preview) | Coverage |
|---|---|---|---|---|
| SY-01 | App initialisation | all | reuses `au00_splash` | reuses |
| SY-02 | Startup error | all | `au00b_startup_error` | rendered |
| SY-03 | Splash | all | `au00_splash` | rendered |
| SY-04 | Route not found | all | `sy01_not_found` | rendered (new copy) |
| SY-05 | Cannot open directly | all | `sy02_cannot_open_directly` | rendered |
| AU-01 | Sign In (+ error, loading) | all | `au01_login`, `au01b_login_error`, `au01c_login_loading` | rendered |
| AU-02 | Sign Up (+ validation / server errors) | all | `au02_register`, `au02b_register_errors` | rendered |
| AU-03 | Password recovery (+ link sent) | all | `au03_forgot_password`, `au03b_reset_link_sent` | rendered |
| AU-04 | Verify email | all | `au04_verify_email` | rendered |
| AU-05 | Role selection | dual role | `au05_role_select` | rendered |
| AU-06 | Artisan registration | artisan | `au06_artisan_registration` | rendered |
| AU-07 | Suspended | all | `au07_suspended` | rendered |
| CU-05 | Choose an artisan | customer | `cu06_matched_artisans` | rendered |
| CU-06 | Secure booking | customer | `cu05_secure_booking` | rendered |
| CU-09 | Paystack checkout frame | customer | `cu10_payment_checkout` | rendered (Paystack page itself is third-party) |
| CU-10 | Payment result (3 states) | customer | `cu08_payment_result`, `cu08b_payment_not_completed`, `cu08c_payment_verifying` | rendered |
| CU-12 | Saved artisans | customer | `cu07_favorites` | rendered |
| CU-13 | Raise dispute | customer | `cu03_dispute` | rendered |
| CU-14 | Leave a review | customer | `cu04_review` | rendered |
| SH-01 | Job detail (customer + artisan) | shared | `ar04_job_detail`, `cu12_job_detail_customer_quotes`, `ar04c_propose_slots` | rendered |
| SH-03 | Chat list | shared | `ar12_messages` | rendered |
| SH-06 | Settings | shared | `cu01_settings` | rendered |
| SH-07 | Help & Support | shared | `cu02_support` | rendered |
| SH-08 | About | shared | `cu09_about` | rendered |
| SH-10 | Portfolio viewer | shared | `sh01_portfolio_viewer` | rendered |
| AR-00 | Artisan shell / 5-item nav | artisan | shown in AR tab previews | rendered |
| AR-01 | Artisan home (+ trust sheet) | artisan | `ar01_home`, `ar01b_trust_score_sheet` | rendered |
| AR-02 | Find Work (+ quote sheet) | artisan | `ar02_find_work`, `ar02b_quote_sheet` | rendered |
| AR-03 | My Jobs | artisan | `ar03_my_jobs` | rendered |
| AR-04 | Work submission | artisan | `ar05_submit_work` | rendered |
| AR-05 | Earnings | artisan | `ar06_earnings` | rendered |
| AR-06 | Business profile | artisan | `ar07_business_profile` | rendered |
| AR-07 | Payout details | artisan | `ar08_payout_details` | rendered |
| AR-08 | Portfolio manager | artisan | `ar09_portfolio` | rendered |
| AR-09 | Portfolio project editor | artisan | `ar10_portfolio_project` | rendered |
| AD-00 | Admin shell, search, notifications | admin | all AD previews, `ad14_search`, `ad15_notifications` | rendered |
| AD-01 | Dashboard (desktop + mobile) | admin | `ad01_dashboard_desktop`, `ad01_dashboard_mobile` | rendered |
| AD-02 | Users (+ delete dialog) | admin | `ad02_users`, `ad16_delete_user_dialog` | rendered |
| AD-03 | Artisans | admin | `ad03_artisans_pending` | rendered |
| AD-04 | Jobs | admin | `ad05_jobs` | rendered |
| AD-05 | Verifications | admin | `ad04_verifications` | rendered |
| AD-06 | Disputes (+ settlement) | admin | `ad06_disputes_settlement` | rendered |
| AD-07 | Reviews | admin | `ad07_reviews` | rendered |
| AD-08 | Support tickets | admin | `ad08_support` | rendered |
| AD-09 | Deletion requests | admin | `ad09_deletions` | rendered |
| AD-10 | Audit logs | admin | `ad10_audit_logs` | rendered |
| AD-11 | Analytics | admin | `ad11_analytics` | rendered |
| AD-12 | Admin settings | admin | `ad12_settings` | rendered |
| AD-13 | **Finance** (approved new) + payout freeze | admin | `ad13_finance`, `ad13b_payout_freeze` | rendered |

**Coverage:** 47 of the 49 have a dedicated render. SY-01 reuses the splash design, and AR-00's nav appears in every artisan tab preview.

## 2. Overlays needing approval (40)

The seven Stage 8 overlays (OV-01 to OV-06, plus OV-45 snackbars) are already in the design system. Of the 40: 17 are rendered, 22 reuse a rendered pattern, and 1 is system UI.

**Rendered (17):**

| Overlay | Preview |
|---|---|
| Quote sheet | `ar02b` |
| Trust-score sheet | `ar01b` |
| Edit name | `dl01` |
| Change email | `dl02` |
| Change password | `dl03` |
| Account deletion | `dl04` |
| Switch mode | `dl05` |
| Cancel job reason | `dl06` |
| Request changes | `dl07` |
| Themed date picker | `dl08` |
| Admin search | `ad14` |
| Admin notifications | `ad15` |
| Settlement | `ad06` |
| Delete user | `ad16` |
| Respond & resolve ticket | panel in `ad08` |
| Admin job detail | panel in `ad05` |
| Portfolio viewer push | `sh01` |

The payout-freeze dialog (`ad13b`) is rendered too; it's the approved new exposure, so it isn't counted in the 40.

**Reuse a rendered pattern (22), so no separate render is needed:**

| Pattern | Overlays |
|---|---|
| Dialog card (`dl01` / `ad16`) | edit username; cancel deletion; remove photo; sign out; approve/reject artisan; beta tester; suspend/reactivate; delete review; delete job |
| Reason dialog (`ad13b`) | refund / retry refund / retry payout; reject verification |
| Option cards (`dl05`) | suspension type |
| Image zoom (`sh01`) | verification images; dispute evidence |
| Detail panel / sheet (`ad02`, `ad05`) | user contact details; user activity; data-table row sheet |
| `dl06` / `dl07` / `dl08` | rework request; paid cancellation; time picker; secure-booking date picker |
| Chart chip menu | chart period |

**System UI, not restyled:** the camera and gallery pickers (the sheets that launch them are themed).

## 3. Requested but not present: decisions needed

| Item | Status | Your decision |
|---|---|---|
| Transaction details | Not in the app; proposed sheet rendered (`cu11_transaction_detail`), existing `PaymentModel` fields only | Approve / reject the new sheet |
| Notification details | Not in the app; the destination screen serves as the detail | Confirm "no separate screen" or ask for one |
| Privacy settings | Not a separate screen; the existing controls are grouped in Settings | Confirm grouping |
| In-app password reset | Not in the app; Firebase-hosted page | Q-2 in the design spec (architectural) |
| Styled not-found page | Framework default today; proposed `sy01` (new copy, adds a router `errorBuilder`) | Approve |
| "Contact support" on Suspended | Proposed addition; route already permitted while suspended | Approve |
| Payout banner on artisan Home | Proposed placement of the existing Earnings payout-readiness banner (same provider) | Approve |

## 4. Screens that still need designs after this preview round

**None, if you approve the previews as rendered.**

**Remaining blockers are decisions, not designs:** Q-1 to Q-6 (design spec §11) and the §3 items above.

**Provisional assets that need originals from you:**

| Provisional element | What it is now | What's needed |
|---|---|---|
| Heading font | Plus Jakarta Sans, my closest match | The Stitch font name |
| Onboarding hero | Cropped from the screenshot | The original photo |
| Photo tiles in previews | Placeholders | None: the app shows real user photos |
