# HandyTrust — Stage 8 Implementation Progress

Date: 2026-11-04
Branch: `stage-8-ui-replacement`, created from `stage-7.3-verified-baseline` @ `7e16eb1`
Status: **implementation complete. All work is uncommitted, nothing has been pushed and nothing has been deployed.**

| Step | Work | Status |
|---|---|---|
| 0 | Recovery point: branch `stage-7.3-verified-baseline`, baseline commit `7e16eb1` (344 files), secret scan clean, `work_sphere_ai/` excluded (`.git/info/exclude`), `node_modules/` and `.firebase/` added to `.gitignore`, tests run. Work branch `stage-8-ui-replacement` | ✅ Done (not pushed) |
| 1 | Reference verification: 25 images checked individually and by SHA-256; #25 = #21 confirmed; #1 degraded confirmed; dark/light pairs differ in layout (17–32 % similar). Copied to `design/stitch_reference/` | ✅ Done |
| 2 | Design system (`lib/ui/theme/ht_theme.dart`): dark and light palettes sampled from pixels; type scale recalibrated to the reference density; spacing and radius constants; `context.ht` picks the palette from `Theme` brightness. Fonts bundled: Plus Jakarta Sans (OFL) for headings, static Inter for body | ✅ Done |
| 3 | Components (`lib/ui/components/`): background glow, app/screen headers, primary/secondary/small buttons, chips, segmented tabs, status/verified pills, cards, info banner, stat tile, section header, menu row, avatar, lifecycle stepper, form fields, loading/empty/error views, snackbar, confirmation sheet, floating bottom nav, formatting helpers | ✅ Done |
| 4 | Customer shell + bottom nav (Discovery · Bookings · Payments · Profile) | ✅ Done |
| 5 | Discovery | ✅ Done |
| 6 | Artisan Profile | ✅ Done |
| 7 | Post a Job (step 1) | ✅ Done |
| 8 | My Bookings (actions driven by the state machine; Approve & Release only in `submitted`) | ✅ Done |
| 9 | Confirm & Pay: server breakdown, single Paystack option, **demo payment route removed** | ✅ Done |
| 10 | Chat | ✅ Done |
| 11 | Payments: the Wallet design adapted to genuine payment history (deviation D-01) | ✅ Done |
| 12 | Profile: dark-mode toggle, Artisan Mode switch, admin entry for admins only | ✅ Done |
| 13 | Identity Verification | ✅ Done |
| 14 | Notifications | ✅ Done |
| 15 | Onboarding: new public `/onboarding` route, shown once | ✅ Done |
| 16 | Router: 11 routes repointed, `/onboarding` added, `/demo-payment` removed, `_RoleAware` keeps artisan `/wallet` and `/jobs` | ✅ Done |
| 17 | Obsolete UI deleted: 9 screens, 2 demo files, 3 empty directories | ✅ Done |
| 18 | Presentation logic extracted to tested classes (`CustomerBookingLogic`, `PaymentSummary`, `NotificationCategories`, `HtFormat`, `LocationService`) | ✅ Done |
| 19 | Tests: `test/stage8_ui_test.dart` (19 functional, logic and source-guard tests) and `test_visual/` (22 golden captures + 66 responsive-layout tests) | ✅ Done |
| 20 | Visual QA: golden renders at each reference size, side-by-side images, measured similarity (`design/stage8_visual_qa/`) | ✅ Done |
| 21 | Full regression (Flutter, analyzer, Functions on Node 22, rules, Storage, e2e, visual) | ✅ Done (see completion report §9) |
| 22 | Deliverable documents (5) | ✅ Done |
| — | Retained artisan, admin, auth, job-detail, dispute, review, settings and support screens: **not redesigned** (no references) | ⏸ Awaiting designs |
| — | Stage 8 commit / push / deploy | ⛔ **Not done. Requires your explicit approval** |

## Defects found and fixed during Stage 8 (by the visual and responsive harness)

| Defect | Fix |
|---|---|
| Chat decided the viewer's role before auth had resolved, so a customer could be treated as the artisan | Chat waits for `authStateChangesProvider` and shows a loader until then |
| Notifications (dark) header overflow on narrow widths | `Flexible` title |
| Bookings (light) secondary-button label overflow at 320 px | Flexible label with ellipsis |
| Notifications (light) "Unread alerts" overflow at 320 px | Ellipsis; counter circle reduced |
| Onboarding flag could load after auth and redirect too early | Splash waits while the flag is `null` |
| Section-header title wrapped with free space beside it (Flexible + Spacer splitting the width) | Title and badge grouped in one `Expanded` |
| 8 pre-existing `use_build_context_synchronously` infos in the retained Settings dialogs (already guarded by `State.mounted`) | Guards switched to `context.mounted`; same behaviour, analyzer clean |
| Type and component scale about 20 % larger than the references | Type scale and component sizes recalibrated |
