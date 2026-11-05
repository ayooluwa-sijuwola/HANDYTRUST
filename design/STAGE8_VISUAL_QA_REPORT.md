# HandyTrust — Stage 8 Visual QA Report

Date: 2026-11-04 · Branch: `stage-8-ui-replacement` (uncommitted)

**Short version:** pixel-perfect output is **not** claimed. Every number below comes from comparing real application renders with the Stitch references. Where the two still differ, the difference is listed and explained.

## 1. Method

1. **Captured real screens.** `test_visual/stage8_visual_test.dart` renders the real Stage 8 screen widgets:
   - **Providers:** the real ones, overridden with test-only fixture data that mirrors each mock's sample content (Emeka Okafor, Funke Adeyemi, ₦85,000 and so on).
   - **Clock:** fixed at 2026-10-24 10:14, so dates and relative times are reproducible.
   - **Fonts:** the bundled ones (Plus Jakarta Sans and Inter), loaded from `FontManifest`, so nothing falls back to the Ahem test font.
   - **Images:** precached before capture.
   - **Size:** each screen is rendered at its reference's pixel size, with the device pixel ratio set to `width / 390`, so layout happens at the same 390 pt logical width.
2. **Compared with the references.** `test_visual/compare_references.py` does the comparison:
   - **Cropping:** the canvas exports (#13, #16, #17, #18) are cropped to the phone area first.
   - **Layout similarity:** 100 − mean absolute grayscale difference, at 130×340.
   - **Colour similarity:** 100 − mean absolute RGB difference after a heavy blur, at 40×100.
   - **Output:** a side-by-side PNG for each screen (reference left, implementation right), in `design/stage8_visual_qa/`.
3. **Responsive sweep.** Every designed screen is rendered in both themes at three sizes: 320×568 (small), 360×780 (typical Android) and 430×932 (large iPhone). The test fails on any overflow or layout exception.

Scores are approximate. Fixture text differs from the mock text, the mocks include device status bars, and unsupported elements were left out on purpose (§4), so 100 % is neither expected nor desirable.

## 2. Commands and results

```
flutter test test_visual --update-goldens   → 00:39 +88: All tests passed!
flutter test test_visual                    → 00:39 +88: All tests passed!   (re-run against the stored goldens)
python test_visual/compare_references.py design/stitch_reference design/stage8_visual_qa
```

- **88 tests:** 22 golden captures (11 screens × 2 themes) and 66 responsive-layout tests (22 × 3 sizes).
- **Goldens:** stored in `test_visual/goldens/`.
- **Side-by-side images:** stored in `design/stage8_visual_qa/` (22 files).

## 3. Similarity scores (final run)

| Screen | Ref | Layout % | Colour % | Ref | Layout % | Colour % |
|---|---|---|---|---|---|---|
| | **Dark** | | | **Light** | | |
| Discovery | #8 | 87.7 | 94.6 | #15 | 91.4 | 96.4 |
| Artisan Profile | #2 | 90.0 | 95.6 | #16 | 92.7 | 96.8 |
| Post a Job | #3 | 91.8 | 95.8 | #17 | 93.0 | 94.5 |
| My Bookings | #4 | 89.1 | 97.3 | #19 | 89.7 | 96.5 |
| Payments (Wallet) | #5 | 89.7 | 97.2 | #21 | 91.0 | 96.8 |
| Profile | #6 | 92.3 | 97.3 | #22 | 93.8 | 97.9 |
| Identity Verification | #7 | 90.7 | 95.8 | #23 | 90.7 | 94.0 |
| Confirm & Pay | #10 | 90.2 | 97.6 | #18 | 91.6 | 95.7 |
| Chat | #11 | 88.2 | 95.0 | #20 | 85.6 | 89.2 |
| Notifications | #12 | 93.4 | 97.6 | #24 | 92.9 | 98.2 |
| Onboarding | #13 | 86.3 | 94.6 | #14 | 86.1 | 95.2 |

- **Layout:** 85.6–93.8 % across all 22 renders.
- **Colour:** 89.2–98.2 %.
- **Starting point:** before recalibration, the first pass was about 20 % oversized in type and components.

## 4. Remaining differences

### 4.1 Intentional: features the backend doesn't support, or claims that can't be substantiated

These differences are deliberate, required by the Stage 8 rules, and **will not be "fixed"**:

| Screen | Reference element | Implementation |
|---|---|---|
| Discovery | "MILESTONE ESCROW GUARANTEED" pill; "FROM ₦8,000" prices; "100 % Escrow" | "ESCROW-PROTECTED PAYMENTS"; **no prices** (no data source); "Escrow" |
| Artisan Profile | "ID & Biometrics Verified"; Services & Rates; "Starting from ₦8,000"; years of experience | Real verification status only; **skills** with "Rates agreed per job"; Trust Score tile; no rates or experience |
| Post a Job | Job title field | Omitted (`JobModel` has no title); budget is a single amount (min = max) |
| Bookings | "Drafts" tab; Release button while In Progress | No Drafts tab; Release only when `submitted` |
| Payments (Wallet #5/#21) | Available balance, Add Money, Withdraw, Vaults, Tier-3, milestone progress, 48 h auto-release, "Wallet top-up", "Multi-Sig 256-Bit Escrow Vault" | **Held in escrow / released totals from real payments**, "not withdrawable" note, 4-stage lifecycle, **14-day** auto-release, real transactions only |
| Confirm & Pay | ₦1,500 "SafeVault/1.7 %" fee; Milestone 1 of 1; HandyTrust Wallet ₦124,000; Mastercard ••••4092; dedicated bank account; CBN/NDPR footer | **Server breakdown: 5 % platform fee** (₦85,000 → ₦4,250 → ₦89,250); one "Card, Bank or Transfer" Paystack option; no compliance claims |
| Chat | Phone button; "CBN-licensed trustee escrow"; receipt card; Preparation Checklist; "Release 20 % Deposit"; "Share Exact Gate Code"; location pin | Omitted; "Funds locked in HandyTrust escrow"; real chips only (agreement, schedule, pay) |
| Profile | BVN pill; Tier/₦250k protection; 98.4 % trust score; "Client Trust 5.0"; FaceID/2FA | Real stats (customer: posted/active/completed; artisan: jobs/rating/trust score); "Security & Password" |
| Verification | NIN, tier pills, "Encrypted session", "Real-Time NIMC Gateway: Connected", "Zero storage of raw biometrics" | Checklist mapped to the real steps (Government ID photo, selfie, review); accurate privacy text (owner + admin access, backed by rules) |
| Notifications | "Security" filter; SafeVault/NDPR copy | "Account" filter (real categories); neutral copy |
| Onboarding | "NIN VERIFIED" pill; "12,400+ Vetted Artisans"; "Funds released on milestone completion"; 3- or 4-dot pager | Omitted; "Funds released when you approve the work"; **single slide, no pager** (no copy exists for further slides) |

### 4.2 Interpretation and asset differences (unresolved, documented)

1. **Heading font.**
   - Plus Jakarta Sans is the closest match found; the original Stitch font isn't confirmed.
   - Letterforms differ slightly, most visibly on "HandyTrust" and the large headlines.
   - **Needs:** the Stitch export's font name.
2. **Onboarding hero (#14).**
   - The photo is a **stand-in crop of the screenshot itself** (`assets/images/stitch/onboarding_hero.jpg`, cropped to leave out the "NIN VERIFIED" pill).
   - It's low resolution and framed tighter than the reference.
   - **Needs:** the original image file.
3. **Light-set density.**
   - Several light references were exported from wider frames (506–706 px).
   - Their content is relatively smaller than the dark set's.
   - One type scale is used for both themes, so the light renders look slightly larger than their references.
4. **Discovery #8 vs #9.**
   - #8 (390 px) is the dark target.
   - #9 differs only in chip order and width.
5. **No preselected category chip.**
   - The references show "Electrical" selected.
   - The real screen opens unfiltered, so all artisans are shown.
   - Selecting a chip filters the live list (tested).
6. **Bottom-nav variants.**
   - The references vary the active-item style slightly between screens.
   - One consistent style was implemented: a filled lime pill.
7. **Chat (light) has the lowest score (85.6 / 89.2).**
   - **Content:** the reference has more messages, plus receipt and checklist cards, which are unsupported.
   - **Header:** the implementation shows the counterpart's name, "Escrow Active" and the amount pill instead of the generic "Artisan Direct Chat" title.
   - **Empty space:** a short fixture conversation leaves space above the bubbles (the list is anchored to the bottom, like a real chat).
8. **Device chrome.**
   - The references include the 9:41 status bar and home indicator.
   - The renders don't, because the system draws those.
9. **Retained screens (auth, job detail, artisan, admin, settings…).**
   - They have no references and still use the previous theme.
   - Moving between new and retained screens is visually inconsistent until designs arrive.

## 5. Responsive and overflow sweep

- **Coverage:** 66 tests (11 screens × 2 themes × 3 sizes). **All pass with no overflow or layout exceptions.**
- **Defects found and fixed by this sweep:**
  - Notifications (dark) header overflow.
  - Bookings (light) secondary-button label overflow at 320 px.
  - Notifications (light) "Unread alerts" overflow at 320 px.
  - Section-header title wrapping with free space beside it (Discovery "Featured Experts").
- **Scrolling:** long screens scroll under the floating bottom nav with a 104 px bottom inset, so the last item stays reachable.

## 6. Not yet done (requires hardware or an environment)

- **Physical devices:** no captures on Android or iOS phones; no device was available in this environment.
- **Live app in a browser or desktop shell:** no captures against the emulator stack.
- **What is verified:** the golden renders are the real widget tree with the real fonts and layout engine. Platform-specific text rendering and safe areas are still unverified.
