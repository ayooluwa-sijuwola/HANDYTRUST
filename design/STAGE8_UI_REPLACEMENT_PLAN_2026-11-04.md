# HandyTrust — Stage 8 UI Replacement: Phases A–C (Reference Audit, Architecture Audit, Implementation Plan)

Date: 2026-11-04 · Status: **planning only**. No UI file was changed, deleted or created except this report. No backend, Firebase, Paystack or rules change. Nothing committed, pushed or deployed.

**Source of truth:** the 25 images uploaded in this conversation, numbered 1–25 in upload order. I examined each image individually, not by filename.

**Values marked "≈" are estimates** read from screenshots. They aren't source values; the Stitch export (HTML/Tailwind) would give exact ones.

---

## PHASE A — Reference audit

### A.1 Image-by-image inventory

Every image is a **customer-facing mobile screen**; no artisan-only or admin screen was uploaded.

The 25 images form **two parallel sets**: **Dark** (1–13) and **Light** (14–25). Image 6 (dark Profile) contains an **"Obsidian Dark Mode"** toggle, which is evidence that Dark and Light are the two themes of one app. Several screen pairs, however, differ in **layout and content**, not only in colour (see A.4).

| # | Theme | Screen (from the content) | Role | Purpose | Notes / flags |
|---|---|---|---|---|---|
| 1 | Dark | Discovery (home), variant D-a | Customer | Search, category chips, featured artisans, bottom nav | **Degraded render**: unstyled badges ("ID Verified" as plain text), "View Profile" dark buttons, no avatar circles. Appears to be a broken export of #8/#9. **Flag: confirm whether to ignore** |
| 2 | Dark | Artisan profile (Emeka Okafor) | Customer | Avatar ring + online dot, "ID & Biometrics Verified", 3 stat tiles, About, **Services & Rates**, Client Reviews (42), escrow note, sticky "Starting from ₦8,000 / Book Emeka →" | Back + share header |
| 3 | Dark | Post a Job, Step 1 of 3 ("Job Scope & Category") | Customer | Photo picker, Job title, Category, Description (132/500), Location + Change, Estimated Budget (NGN chip), escrow note, "Find Artisans →" | Steps 2 and 3 have **no design** |
| 4 | Dark | My Bookings | Customer | Tabs Active/Completed/Drafts; funded booking card (₦ held in escrow, 4-stage lifecycle, chat + "Approve & Release Payment"); second card "Awaiting artisan response / View Details"; "Funds safely locked" note; bottom nav (Bookings active) | "Vault Sync" pill |
| 5 | Dark | Escrow Wallet | Customer | Personal/Vaults(2) toggle; Available balance ₦42,500 + locked ₦85,000; Add Money / Withdraw; SafeVault Guarantee; Active Escrow Contracts (milestone 2 of 3, auto-release 48 h, Inspect Job); Recent Transactions | **Backend conflict** (A.6) |
| 6 | Dark | Profile & Trust | Customer (+ entry to Admin) | Avatar, BVN & ID verified, stats (jobs posted / escrow release / client trust), escrow security tier; menu (My Jobs, Messages & Quotes, Account, Payment & Payout Methods, Security & Biometrics, Notification Prefs, **Obsidian Dark Mode toggle**, Support & Escrow Mediation, About); **Admin Dashboard (Staff Access)** card; Sign out | QR + settings icons in header |
| 7 | Dark | Identity verification ("Safety Starts With Trust") | Customer & artisan | Encrypted-session / tier pills, shield illustration, Verification Checklist (NIN, selfie, review), privacy card, Continue, help link | **Header reads "Job Scope & Category"** (copy error in the design). **Flag** |
| 8 | Dark | Discovery, variant D-b (390 px wide) | Customer | Styled version: "Find **Trusted Experts** for Your Home", chips (Electrical selected first), cards with avatar + online dot, ID Verified badge, rating row, "FROM ₦…", lime "View" | — |
| 9 | Dark | Discovery, variant D-c (510 px wide) | Customer | Same design as #8; **chip order differs** (Plumbing, Electrical selected, Cleaning) | **Conflict** with #8 (chip order, width) |
| 10 | Dark | Confirm & Pay | Customer | Escrow Protection banner, job card (artisan, verified), **Service ₦85,000 + "SafeVault Escrow Fee ₦1,500" = ₦86,500**; Payment source (HandyTrust Wallet / Card / Bank Transfer); release guarantee; 3-step lifecycle; "Pay ₦86,500 Securely" | **Fee conflict** with the approved 5% policy (A.6) |
| 11 | Dark | Chat conversation | Customer ↔ artisan | Header (escrow active, phone, escrow amount pill), job strip, SafeGuard system card, bubbles (lime outgoing), image message with caption, quick actions ("Send location pin", "Confirm 9:00 AM arrival"), composer | — |
| 12 | Dark | Notifications | Customer | Filters All / Escrow & Pay / Jobs / Security; SafeVault banner; Today / Earlier groups with status chips; "Manage Notification Settings"; footer | **Header reads "Chat Conversation / Escrow Active"** (copy error). **Flag** |
| 13 | Dark | Onboarding slide 1 (in a device frame) | Public | Logo, "Hire Trusted Hands, **Pay With Confidence.**", subtitle, 3-dot pager, Get Started, Skip | No hero image (dark gradient only) |
| 14 | Light | Onboarding slide 1 | Public | **Photo hero** (artisan in workshop) + "NIN VERIFIED" pill + "Smart Escrow Vault" card + "12,400+ Vetted Artisans"; logo pill; headline; 4-dot pager; Get Started; Skip | **Needs the photo asset**; fabricated stat (A.6); 4 dots vs 3 in #13 |
| 15 | Light | Discovery | Customer | Same structure as #8, plus a top bar "Discovery" **above** the HandyTrust header (two headers), "Top Rated" chip, "Starting at", escrow banner, bottom nav | **Double header**, likely an artifact. **Flag** |
| 16 | Light | Artisan profile | Customer | Same as #2 with a bookmark button, simplified "Services / STARTING RATES" with icons, "Recent Reviews All (96)" | Review count differs from #2 (42) |
| 17 | Light | Post a Job, Step 1 of 3 | Customer | Same as #3 (dashed photo box, "Fixed quote" chip on budget) | — |
| 18 | Light | Confirm & Pay | Customer | "JOB & ESCROW MILESTONE / Milestone 1 of 1", **"Escrow protection fee (1.7%) ₦1,500"**, payment method list (HandyTrust Wallet ₦124,000, Mastercard ••••4092, Bank Transfer), compliance footer, Pay | **Fee and saved-card conflicts** (A.6) |
| 19 | Light | My Bookings | Customer | Tabs Active / Completed / Drafts / **Disputed**; protection banner; funded card (lifecycle, "Approve & Release Payment", chat, more); open-job card with **Budget Target / "3 bids in" / Review 3 offers / View Bids**; "Need another repair? Post Job" | More content than #4 |
| 20 | Light | Artisan Direct Chat | Customer ↔ artisan | Active-escrow header card, date chip, bubbles, **material receipt card**, **Preparation Checklist** images, quick actions "**Release 20% Deposit**", "Share Exact Gate Code", composer | Partial-release conflict (A.6) |
| 21 | Light | Wallet | Customer | Balance card (Tier-3 badge), escrow lock pill, Add Money / Withdraw, compliance strip, 3 quick tiles (Auto-Release / Linked Bank / Spend Log), Recent Transactions (3), protection card | Differs from #5 |
| 22 | Light | Profile | Customer (+ Artisan Mode + Admin) | Trust tier pill, photo avatar, location, ID verified, SCORE 98.4% Trust / PROTECTION ₦250k; menu (My Jobs 3 Active, My Chats, Account, Payment Methods, Security & Password, Notifications, Support, About v2.4.1, **Artisan Mode toggle**); **Admin Dashboard (Partner)**; Log Out | No dark-mode toggle (cf. #6) |
| 23 | Light | Verify Your Identity | Customer & artisan | Same as #7 with the correct title, plus "Real-Time NIMC Gateway: Connected" | — |
| 24 | Light | Notifications | Customer | "2 Unread alerts", filters All / Escrow / Orders; 4 items with chips; Notification Privacy card | Filters differ from #12 |
| 25 | Light | Wallet | Customer | **Pixel-identical duplicate of #21** | **Duplicate**: one screen, not two |

**Distinct screens represented:** 11.
1. Onboarding
2. Discovery
3. Artisan Profile
4. Post a Job (step 1)
5. My Bookings
6. Confirm & Pay
7. Chat
8. Wallet
9. Profile
10. Identity Verification
11. Notifications

These come in up to two theme variants each, plus the duplicate (#25) and the degraded Discovery render (#1).

### A.2 Navigation inferred from the images
- **Bottom navigation** (customer): Discovery · Bookings · Wallet · Profile. It's a floating rounded bar with a filled pill on the active item (#1, #4–6, #8, #9, #15, #19, #21, #22).
- **Onboarding** → Get Started / Skip → (auth: **no design**) → Discovery.
- **Discovery** → artisan card "View" → **Artisan Profile** → "Book Emeka" → (booking request / **no design**). Also: search and filter (**no design** for results).
- **Discovery** "Post a job" path → **Post a Job step 1** → "Find Artisans" → (steps 2–3, matched artisans: **no design**).
- **Bookings card** → chat icon → **Chat**; "View Details" / "View Bids" → (job detail / quote list: **no design**). "Approve & Release Payment" → confirmation (**no design**).
- **Confirm & Pay** is reached from an agreed booking (it shows the agreed amount) → Paystack checkout.
- **Profile** → My Jobs (= Bookings), Messages, Account, Payment Methods, Security, Notifications, Support, About (**no designs**), Admin Dashboard (**no design**), Artisan Mode toggle (role switch).
- **Bell icon** (Discovery, Bookings, Wallet, Profile headers) → **Notifications**.
- **Verification** is reachable from the profile verification badge or onboarding (inferred).

### A.3 Design system observed (all values ≈, estimated from screenshots)

| Token | Dark | Light |
|---|---|---|
| Page background | Near-black with olive tint ≈ `#0F130D`, radial olive glow at the top (≈ `#3A4520` → transparent) | Warm off-white ≈ `#F6F7F0`, pale-lime wash at the top (≈ `#E4ECC8`) |
| Card surface | ≈ `#191E15` – `#1E2419`, hairline border ≈ `rgba(255,255,255,0.06)` | White ≈ `#FFFFFF` / ≈ `#FBFCF7`, very soft shadow |
| Primary (CTA) | **Horizontal gradient** olive → lime ≈ `#8A9A4A` → `#C9DB80`, **dark text** ≈ `#1C2410`, soft lime glow | Gradient ≈ `#5E6E25` → `#A9BE58`, **white text** |
| Accent lime | ≈ `#C5D77C` (headline "Trusted Experts", active chip, links) | ≈ `#6E7F2A` text accent; chip fill ≈ `#DCE8A8` |
| Verified / success | Mint ≈ `#3ED6A0` on ≈ `#163A2C` pill | ≈ `#1E8A4C` on ≈ `#E2F5E9` pill |
| Escrow-locked / warning | Amber ≈ `#F2B33D` on ≈ `#3A3016` | ≈ `#B5532C` on ≈ `#FCE9DD` |
| Text | Primary ≈ `#F2F4EC`, secondary ≈ `#A4AA98` | Primary ≈ `#141712`, secondary ≈ `#6B7063` |
| Typography | Headlines: geometric sans, heavy (≈ 800), tight tracking. Closest candidates: **Plus Jakarta Sans** or Manrope. Body/labels: **Inter-like**. Section labels in letter-spaced caps (≈ 11–12 px, +1 px tracking) | Same families and scale |
| Type scale (≈ at 390 pt width) | Display 30–34 · screen title 26–30 · card title 18–20 · body 14–16 · caption 11–13 | same |
| Radii (≈) | Cards 24–28 · inputs 18–20 · buttons / chips / nav = fully rounded pills · icon tiles 12–16 · avatars circular with a 2 px lime ring | same |
| Elevation | Dark: no drop shadows, glow on the primary CTA and the active chip | Light: low soft shadows on cards (≈ 0 4 16 rgba(0,0,0,0.05)) |
| Spacing (≈) | 20–24 page gutter; 16 card padding (24 on hero cards); 12–16 between list rows; 24–32 between sections | same |
| Icons | **Outlined, rounded-stroke icons** (Material Symbols Rounded style) | same |
| Bottom nav | Floating bar, radius ≈ 32, inset 16 from the edges, active item in a filled pill (dark: lime icon on olive pill / lime pill with dark text; light: olive pill, white) | same |

**Fonts available in the project:** Inter (bundled in `assets/fonts/Inter`) and `google_fonts` (runtime download). **The heading font is not confirmed.** See D-3.

### A.4 Shared components (appear in 2+ screens)

| Component | Seen in |
|---|---|
| App header: shield logo tile + "HandyTrust" + search / bell (with dot) / avatar | 4, 5, 6, 15, 19, 21, 22 |
| Screen header: round back button + centred title + avatar/action | 3, 7, 10, 11, 12, 17, 18, 23, 24 |
| Floating pill bottom nav | 1, 4, 5, 6, 8, 9, 15, 19, 21, 22 |
| Gradient pill primary button (with arrow or shield) | 2, 3, 10, 13, 14, 16, 17, 18, 23 |
| Category / filter chips and segmented tabs (count badges) | 1, 4, 5, 8, 9, 12, 15, 19, 24 |
| Artisan card (initials avatar + online dot, name, trade · city, verified badge, rating / jobs / escrow row, "From ₦", View) | 1, 8, 9, 15 |
| Verified badge pill ("ID Verified" etc.) | 2, 4, 8–10, 15, 16, 18, 19, 22 |
| Escrow info banner (shield/lock icon + text) | 2–5, 10, 12, 15, 17–19, 21, 24 |
| Escrow lifecycle stepper (4-step / 3-step) | 4, 10, 19 |
| Stat tiles | 2, 6, 16, 22 |
| Settings menu row (icon tile, title, subtitle, trailing chevron/badge/toggle) | 6, 22 |
| Transaction row (icon tile, title, meta, signed amount, status caption) | 5, 21 |
| Notification item (icon tile, title, time, unread dot, status chip) | 12, 24 |
| Form field (label above, rounded filled input, trailing icon) | 3, 17 |
| Checklist row (icon, title, subtitle, state badge) | 7, 23 |
| Chat bubble / system card / image message / quick-action chips / composer | 11, 20 |

### A.5 Conflicts and ambiguities (decisions needed)
1. **Dark vs Light are not pure theme swaps.** Wallet (#5 vs #21), Bookings (#4 vs #19), Notifications (#12 vs #24), Profile (#6 vs #22), Chat (#11 vs #20) and Pay (#10 vs #18) differ in content and layout. → **D-1**
2. **Discovery variants:** #1 (degraded), #8 and #9 (chip order), #15 (double header). → **D-2**
3. **Copy errors in the designs:** #7 title "Job Scope & Category" on a verification screen; #12 header "Chat Conversation" on Notifications. → **D-2**
4. **Duplicate:** #25 = #21 (counted once).
5. **Onboarding:** 3 pager dots (#13) vs 4 (#14); #14 needs a hero photo. The image isn't supplied as a file; a cropped screenshot would be low resolution. → **D-4**

### A.6 Design features that conflict with the verified backend, approved policies or truthfulness

These can't be made functional without new backend, a policy change or false claims. The brief forbids fabricated data and weakening business rules, so **each needs a decision (D-5) before implementation.** I won't silently change or drop them.

| # | Design element | Images | Reality in the verified system | Options |
|---|---|---|---|---|
| F-1 | **Wallet with stored balance** ("Available Balance ₦42,500", **Add Money**, **Withdraw**, "Wallet top-up", "HandyTrust Wallet" as a payment source, Vaults) | 5, 10, 18, 21 | **No wallet or stored-value ledger exists.** Customers pay per job through Paystack into escrow. A stored-value wallet is new financial infrastructure and likely needs e-money/CBN licensing (Stage 7.3 §12) | (a) Keep the layout and show only real data: escrow-locked total, active escrow contracts, payment history; hide Add Money / Withdraw / wallet balance. (b) Build a wallet (new backend + legal approval: out of Stage 8 scope) |
| F-2 | **Fee "₦1,500 SafeVault Escrow Fee (1.7%)"** | 10, 18 | **Approved policy: 5% platform fee on top** (₦85,000 → ₦4,250, total ₦89,250) | Display server values from `getPaymentBreakdown` (labels kept, numbers real). **The fee policy itself must not change without your authorization** |
| F-3 | **Saved card "Mastercard ••••4092"; "Bank Transfer — dedicated single-use account"** | 10, 18 | Paystack checkout (card / bank / transfer channels inside Paystack); **no saved cards, no dedicated virtual accounts** | Show "Card / Bank / Transfer via Paystack" as one real option leading to checkout; omit saved-card rows |
| F-4 | **"Release 20% Deposit"**, "Milestone 2 of 3", milestone progress bars | 5, 20 | **Single release per job** (approved escrow model); review window **14 days**, not "48 h" | Show real single-stage status and the real auto-release date; omit partial release |
| F-5 | **Regulatory/security claims:** "CBN-Licensed Trustee Escrow", "Multi-Sig 256-Bit Escrow Vault", "cryptographically signed", "NDPR Compliant", "Instant NIBSS Settlement", "Real-Time NIMC Gateway Connected", "Zero storage of raw biometric scans", "end-to-end encrypted", "SMS alerts", "99.8% Approval Rate", "12,400+ Vetted Artisans" | 5, 7, 12, 14, 18, 21, 23, 24 | **None of these is true of the system today** (Stage 7.3 §12: escrow licensing unresolved; no NIMC/BVN integration; no SMS; no E2E encryption) | Publishing them is a **legal and consumer-protection risk**. Replace with accurate, approved copy supplied by you, keeping the same components and styling |
| F-6 | **NIN / BVN / "3D biometric" verification, tier levels (Tier 1/2/3, ₦250k/₦500k caps)** | 6, 7, 22, 23 | Verification = ID photo + selfie upload, **manual admin review**; no tiers or caps | Keep the checklist layout mapped to the real steps (upload ID, selfie, admin review status); omit tiers and caps |
| F-7 | **Customer trust score / "Client Trust 5.0" / "Security & Biometrics: FaceID, 2FA"** | 6, 22 | Trust score exists **only for artisans**; no 2FA or biometrics | Show real customer stats (jobs posted, completed); omit 2FA/FaceID claims |
| F-8 | **Artisan "Services & Rates" list, "Starting rate ₦8,000", "5 yrs experience"** | 1, 2, 8, 9, 15, 16 | **`ArtisanModel` has no services, rates, starting price or years of experience** | (a) Show available real fields only (rating, jobs, bio, skills). (b) Add optional artisan-editable fields (`services[]`, `startingRateNgn`, `yearsExperience`): model + rules + artisan edit screen (no design for the edit screen). Needs approval |
| F-9 | **Job title** field; single **Estimated Budget** | 3, 17 | `JobModel` has **no title**; budget is `budgetMin`/`budgetMax` | (b) Add optional `title` (model + create-rule allow-list) or (a) map to description; budget → min = max. Needs approval |
| F-10 | **Bookings "Drafts" tab** | 4, 19 | **No draft jobs** exist | Omit the tab, or add local drafts (new feature) |
| F-11 | **Chat: phone call, material receipt cards, preparation checklist, "Share Exact Gate Code", location pin** | 11, 20 | Text and image messages only; no calling | Keep text/image and real quick actions (agreement / schedule); omit unsupported ones |
| F-12 | **"Approve & Release Payment" shown while "In Progress"** | 4, 19 | Release is only allowed in `submitted` (state machine) | Render the button only in the state the server allows; other states show the correct action |
| F-13 | **Admin Dashboard entry labelled "Staff Access" / "Partner"** | 6, 22 | Admin = `admins/{uid}` | Show only to admins (router guard already enforces) |

### A.7 Workflows with no uploaded design (gap list — nothing will be invented)

**Customer:**
- login, register, verify email, forgot password, role selection, suspended screen;
- search results / browse-all artisans, favorites;
- **Post a Job steps 2–3** and matched-artisan list;
- booking request (after "Book Emeka");
- **Job Detail** (status, quotes inbox, agreement, schedule, cancellation, rework), quote review / "View Bids";
- payment webview and result;
- submit review, raise/view dispute, cancellation request;
- settings, account, support, about;
- all empty, loading, error and confirmation dialogs.

**Artisan (no artisan screens at all):**
- registration and onboarding, dashboard, open-jobs feed;
- quote submission/edit/withdraw;
- booking request confirm/decline (24 h), active jobs, work submission (before/after photos), rework;
- earnings and payouts, bank details;
- business profile and service area, portfolio;
- artisan side of chat and job detail.

**Admin (no admin screens at all):**
- dashboard, users and suspension (type), artisan verification, jobs, disputes and settlements;
- **chargebacks**, **platform losses**, refunds/settlements/payout monitoring, payout freezes;
- audit logs, reviews, support, deletions, analytics;
- configuration (read-only).

### A.8 Screen implementation matrix (designed screens)

| Screen | Images | Route (existing) | Replaces | Data sources (existing) | Decisions blocking |
|---|---|---|---|---|---|
| Onboarding | 13, 14 | `/` splash → new `/onboarding` (public) | `splash_screen` (logic kept) | none (static copy) | D-1, D-4, F-5 |
| Discovery | 8/9/15 (1 = reference only) | `/home` (customer tab 0) | `home_screen` `_CustomerHomeTab`, `browse_artisans_screen` | `featuredArtisansProvider`, `matchingProvider`, categories | D-1, D-2, F-8 |
| Artisan Profile | 2, 16 | `/artisan/:uid` | `artisan_profile_screen` | `artisanProfileProvider`, reviews, favorites, `escrowNotifierProvider` (direct hire) | F-8 |
| Post a Job (step 1) | 3, 17 | `/request` | `service_request_screen` | `jobRequestNotifierProvider`, AI, `platformConfigProvider`, `ImagePrivacy` | F-9; steps 2–3 gap |
| My Bookings | 4, 19 | `/jobs` (tab 1) | `all_jobs_screen` | `customerJobsProvider`, job status, escrow amounts | D-1, F-10, F-12 |
| Confirm & Pay | 10, 18 | `/payment/:jobId` | `payment_screen` (+ webview kept) | `getPaymentBreakdown`, `initializePaystackTransaction`, `verifyPayment` | F-1, F-2, F-3 |
| Chat | 11, 20 | `/chat/:jobId` | `chat_screen` | `chatNotifierProvider`, `messagesStreamProvider` | D-1, F-11 |
| Wallet | 5, 21 (25 dup) | `/wallet` (tab 2) | `wallet_screen` | `customerPaymentsProvider` (real payments only) | **F-1 (blocking)** |
| Profile | 6, 22 | `/profile` (tab 3) | `profile_screen` | `currentUserProfileProvider`, `isAdminProvider`, `themeProvider`, role switch | D-1, F-7 |
| Identity Verification | 7, 23 | `/verification` | `verification_upload_screen` | `verificationServiceProvider`, `StorageService` | F-5, F-6 |
| Notifications | 12, 24 | `/notifications` | `notifications_screen` | `userNotificationsProvider`, `safeNotificationRoute` | D-1 |

---

## PHASE B — Architecture audit

(Builds on Stage 7.3 §13–§14, re-checked against the designs.)

### B.1 Routes vs designs
- **Keep:** all 38 GoRouter paths and the central `redirect` guard (auth, email verification, suspended restricted mode, admin guard, dual-role). The designs fit the current tab shell (`MainShellScreen`):
  - customer tabs map to Discovery = Home, Bookings = Jobs, Wallet, Profile;
  - the artisan tab set has no design.
- **New route:** `/onboarding` (public, shown once; flag persisted locally). It doesn't change server state.
- **Remove:** `/demo-payment/:jobId`, together with `demo_escrow_screen.dart`, `demo_payment_provider.dart` and `demo_escrow_service.dart`, and the `kDebugMode` hand-off in `payment_screen`. Rules already refuse its writes (Stage 7.3 test).
- **`safeNotificationRoute` allow-list:** unchanged, because route paths are kept.

### B.2 Business logic embedded in screens (must be extracted first)

| File | What lives in the widget | Extraction target |
|---|---|---|
| `admin/admin_dashboard_screen.dart` (7,881 lines, 54 direct Firestore/Functions calls) | All admin queries and actions | `admin_*` services/providers (only when admin screens are designed) |
| `job/job_detail_screen.dart` (2,518 lines) | Per-status action selection (agreement, booking confirm/decline, cancel, rework, dispute window) | `JobActionsViewModel` (provider) reused by Bookings cards and future Job Detail |
| `home/all_jobs_screen.dart` | Filtering into active/completed | Provider (`bookingsTabsProvider`) |
| `artisan/browse_artisans_screen.dart` (2 direct calls) | Category query | `artisan_provider` |
| `artisan/bank_details_screen.dart` (4), `business_profile_screen.dart` (3), `artisan_dashboard_screen.dart` (3), `open_jobs_feed_screen.dart` (3), `verification_upload_screen.dart` (3), `auth/artisan_registration_screen.dart` (2), `review_screen.dart` (2), `job_completion_screen.dart` / `dispute_screen.dart` / `payment_screen.dart` / `payment_webview_screen.dart` (1 each) | Direct reads/writes | Corresponding services. **Only screens being replaced now are extracted now** |
| `settings/settings_screen.dart` | 8 `BuildContext`-after-`await` uses | New screens use `if (!context.mounted) return;` / ref-based navigation |

### B.3 Reusable without changing the designs
- **All services and providers** (data, actions, Paystack, notifications, storage + `ImagePrivacy`, matching).
- **Models**, plus the contract additions only if approved: F-8, F-9; and for later admin work, chargeback fields.
- **Behaviour-only helpers:** `WorkflowGateService` (status → allowed actions), `distance_matching`, `safeNotificationRoute`, `ServiceAreaCard` logic (GPS on tap; re-skinned), cancellation-reason validation.
- **No existing visual widget matches the designs.** The `lib/widgets` visuals (`artisan_card`, `job_booking_card`, `trust_score_card`, `pill_tab_selector`, `premium_scaffold`, ...) were built from the earlier screenshot batch and will be replaced by new design-system components.

### B.4 Obsolete UI files (to remove after their replacement is verified, never before)

| Group | Files |
|---|---|
| Theme | `lib/theme/app_colors.dart`, `app_design_system.dart`, `app_theme.dart` (replaced by new tokens + light/dark `ThemeData`). `breakpoints.dart` kept if still used |
| Widgets superseded by new components | `artisan_card`, `job_booking_card`, `balance_card`, `earnings_summary_card`, `transaction_card`, `trust_score_card`, `pill_tab_selector`, `premium_scaffold`, `auth_scaffold`, `shimmer_loaders`, `loading_indicator`, `app_snackbars`/`error_snackbar` (one replacement), `notification_bell`, `star_rating`, `user_avatar`, `review_tile`, `workflow_status_card`, `workflow_timeline`, `job_status_badge`, `web_content_wrapper` |
| Replaced screens (designed set) | The 11 files in the A.8 "Replaces" column |
| Demo path | `demo_escrow_screen.dart`, `demo_payment_provider.dart`, `demo_escrow_service.dart` |
| **Kept until designs exist** | Every artisan, admin, auth, job-detail, dispute, review, settings and support screen |

**Note:** "complete removal of the existing UI" can't be finished in this stage, because more than 30 screens have no design (A.7). Removing them would break working workflows. They stay, restyled only with the new theme tokens so the app is visually consistent, **unless you decide otherwise** (D-6).

### B.5 Dependencies and risks

| Risk | Mitigation |
|---|---|
| **Uncommitted baseline** (Stage 7.3) | **Commit or branch before any UI deletion** (your approval) |
| Fonts unconfirmed | D-3; bundle font files under `assets/fonts` (no runtime download for offline/privacy) |
| Hero photo and artisan imagery | D-4; real artisan photos come from `profileImageUrl`, otherwise the initials avatar (as in the designs) |
| Two themes double the work | D-1 |
| Fabricated or false copy | F-5, replaced only with your approved copy |
| Visual-test fonts | Golden tests must load real fonts (otherwise Flutter renders the Ahem test font) |
| No device for screenshots | Comparison via golden renders at reference sizes plus Chrome/Windows desktop runs; device checks stay a Stage 7.3 §11 item |

---

## PHASE C — Implementation plan (for approval)

### C.1 Decisions required before implementation

| ID | Decision | My recommendation |
|---|---|---|
| **D-1** | Dark and Light: one layout per screen with two colour themes (toggle in Profile, as in #6), or implement both layouts as drawn? | **One layout per screen, two themes.** Per screen, choose the layout variant that best matches real data: Wallet #21, Bookings #19, Notifications #24, Profile #22 (+ dark-mode toggle from #6), Chat #11, Pay #18. Dark tokens from 1–13, light tokens from 14–25 |
| **D-2** | Discovery: #8 (Electrical first) or #9 (Plumbing first); ignore #1; drop #15's duplicate top bar; fix the copy errors in #7 and #12 | #8 ordering = existing category order; ignore #1; single header; correct the titles |
| **D-3** | Heading font | Supply the Stitch export or font name; otherwise **Plus Jakarta Sans** (headings) + **Inter** (body), bundled, clearly marked as an estimate |
| **D-4** | Onboarding hero photo (#14) and dot count (3 or 4) | Supply the original image file; 3 slides need copy for slides 2–3 (no design) |
| **D-5** | F-1 … F-13 (A.6) | F-1 option (a); F-2 real server fee; F-3 single Paystack option; F-4 single release; **F-5 your approved copy**; F-6 real steps; F-7 real stats; F-8 option (b) only if you want rates shown; F-9 add optional `title`; F-10 omit Drafts; F-11 supported actions only; F-12 state-machine-driven; F-13 admin-only |
| **D-6** | Screens with no design (A.7) | Keep and restyle with the new tokens now; replace when designs arrive. **Do not invent new layouts** |
| **D-7** | Baseline commit | Commit or branch the Stage 7.3 state before Phase D (your action or approval) |

### C.2 Files

**Create (`lib/ui/`, new design system and screens):**
- `lib/ui/theme/ht_tokens.dart` — colour, spacing, radius and type tokens, light and dark; values from A.3, each marked ≈.
- `lib/ui/theme/ht_theme.dart` — `ThemeData` light and dark, wired to the existing `themeProvider`.
- `lib/ui/components/`:
  - `ht_app_header.dart`, `ht_screen_header.dart`, `ht_bottom_nav.dart`
  - `ht_primary_button.dart`, `ht_secondary_button.dart`
  - `ht_chip.dart`, `ht_segmented_tabs.dart`
  - `ht_artisan_card.dart`, `ht_verified_badge.dart`, `ht_escrow_banner.dart`, `ht_lifecycle_stepper.dart`
  - `ht_stat_tile.dart`, `ht_menu_row.dart`, `ht_transaction_row.dart`, `ht_notification_tile.dart`
  - `ht_form_field.dart`, `ht_checklist_row.dart`
  - `ht_chat_bubble.dart`, `ht_composer.dart`
  - `ht_avatar.dart` (initials + online dot + ring)
  - `ht_state_views.dart` (loading/empty/error in the design language)
- `lib/ui/screens/`: `onboarding_screen.dart`, `discovery_screen.dart`, `artisan_profile_screen.dart`, `post_job_screen.dart`, `bookings_screen.dart`, `confirm_pay_screen.dart`, `chat_screen.dart`, `wallet_screen.dart`, `profile_screen.dart`, `verification_screen.dart`, `notifications_screen.dart`.
- Providers/view-models (logic extracted, no new business rules):
  - `lib/providers/job_actions_provider.dart` (from `job_detail_screen` / `WorkflowGateService`)
  - `bookings_provider.dart`
  - `wallet_summary_provider.dart` (escrow totals from real payments)
  - `onboarding_provider.dart` (seen-flag)
- `assets/fonts/<HeadingFont>/` (after D-3); `assets/images/onboarding_hero.*` (after D-4).

**Modify:**
- `lib/routes/router.dart` — point the 11 routes to new screens, add `/onboarding`, remove `/demo-payment`, keep the guards.
- `MainShellScreen` usage (new bottom nav); `pubspec.yaml` (fonts/assets).
- Models only if D-5 approves F-8/F-9; then also `firestore.rules` create/update allow-lists **plus rules tests**. This is the only backend-adjacent change, and it is additive.

**Remove (only after each replacement passes its checks):** files in B.4.

### C.3 Implementation order (each step ends with tests + visual check)
0. Baseline commit/branch (D-7). Visual reference images copied into `test/visual/reference/` (needs your approval to store them in the repo).
1. Design system: tokens, theme, components, plus golden tests of each component in both themes.
2. App shell: bottom nav + headers; Discovery tab.
3. Artisan Profile.
4. Post a Job (step 1; steps 2–3 keep the existing flow restyled until designed).
5. My Bookings (state-machine-driven actions via `job_actions_provider`).
6. Confirm & Pay (real breakdown; Paystack checkout; demo path removed).
7. Chat.
8. Wallet (real escrow data only, per F-1).
9. Profile (+ theme toggle, role switch, admin entry for admins).
10. Identity Verification.
11. Notifications.
12. Onboarding.
13. Restyle the undesigned screens with tokens (D-6); remove obsolete widgets and theme files; run the full regression.

### C.4 How backend functionality is preserved
- No change to Cloud Functions, Firestore/Storage rules (except approved additive fields), Paystack integration, state machines or policies.
- New screens call **only existing providers and services**. No widget writes to Firestore directly (a new source-scan test, like the upload guard, fails if `FirebaseFirestore.instance` appears under `lib/ui/`).
- Actions are shown only when the server state machine allows them (`WorkflowGateService` / `job_actions_provider`).
- Money values always come from server documents (`getPaymentBreakdown`, payments, `payoutStatus`). No client-computed fees.
- Uploads keep going through `StorageService` / `ProfileService` (existing guard test).
- `BuildContext` is never used after `await` without `context.mounted` (analyzer must show no new `use_build_context_synchronously`).

### C.5 Visual comparison and regression tests
- **Golden render per screen** at each reference image's logical size (e.g. 390×844 viewport; the long screenshots rendered as full scroll extent), in both themes. Fixture data is **test-only** and mirrors the reference content (e.g. "Emeka Okafor"), never production data. Real fonts are loaded in tests.
- **Pixel-difference report:** a test script compares each golden with its reference PNG and outputs a diff image and a per-region score (header, cards, nav). Differences above threshold are fixed and the run repeated. **I'll report measured differences, not claim pixel perfection.** Reference screenshots include device chrome and status bars, which are masked.
- **Live check:** `flutter run -d chrome` / Windows at 390 px width with a headless screenshot, side by side with the reference.
- **Regression:** the full Stage 7.3 suite (Flutter 174, analyzer no new issues, Functions 266 on Node 22, rules 139, Storage 9, e2e 16) after every step. Plus new widget tests per screen for loading/empty/error states, role gating (admin card only for admins; artisan mode switch), and action gating (release button only in `submitted`).

**STOP — Phases A–C complete. No UI has been changed. Awaiting your approval of the plan and decisions D-1 … D-7 (incl. F-1 … F-13).**
