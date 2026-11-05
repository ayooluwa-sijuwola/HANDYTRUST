# HandyTrust — Stage 8 Screen Inventory (definitive)

Date: 2026-11-04 · Branch: `stage-8-ui-replacement` (uncommitted) · Baseline: `stage-7.3-verified-baseline` @ `7e16eb1`

**Source of truth:** the 25 Stitch screenshots uploaded in this conversation. They are stored in the repo as `design/stitch_reference/1.png` … `25.png`, numbered in upload order.

**How each image was checked:**
- **Opened individually** at full resolution.
- **SHA-256 hash** compared across all images.
- **Pixel-level comparison** against its pair, using `test_visual/compare_references.py` and the Stage 8 PIL audit.

---

## 1. Verification of the previous (Phase A) findings

| Earlier claim | Verified against the files | Result |
|---|---|---|
| #25 duplicates #21 | Identical SHA-256 (`841d71eac306…`) and identical size (597×1600) | **Confirmed.** One screen, counted once |
| #1 is a broken rendering | 390×1159. Same layout as #8/#9, but the badges are unstyled, the buttons are plain and there are no avatar circles; 89–90 % grayscale similarity to #8/#9 | **Confirmed.** Used as a layout cross-check only, not as a target |
| Two themes, dark (1–13) and light (14–25) | Every image sampled. Dark backgrounds are `#10150D` / `#07090A`; light backgrounds are `#F9FAF4`. #6 contains an "Obsidian Dark Mode" toggle | **Confirmed** |
| Dark/light pairs are theme swaps of each other | Pair similarity is only 17–32 % in grayscale. Wallet, Bookings, Notifications, Profile, Chat and Pay differ in **content and layout**, not just colour | **Corrected.** They aren't simple swaps; per-theme layout differences were implemented where backend data supports them (§4) |
| 11 customer screen categories | Confirmed: Onboarding, Discovery, Artisan Profile, Post a Job (step 1), Bookings, Confirm & Pay, Chat, Wallet, Profile, Identity Verification, Notifications | **Confirmed** |
| #8 vs #9 are the same Discovery screen | Same design at different widths (390 vs 510). The chip order differs (Electrical first vs Plumbing first) | Confirmed. #8 is the primary dark target |
| Canvas exports | #13 (1600×1280) and #16/#17 (1600×1485/1386) are presentation canvases containing a phone frame | Each phone area was cropped before comparison (crop boxes in `compare_references.py`) |

No image is artisan-only or admin-only. **All 25 are customer-facing**, apart from the role-switch and admin-entry controls inside Profile.

---

## 2. Image-by-image inventory

**Key:**
- **C** = customer · **A** = artisan · **Ad** = admin · **P** = public (signed out).
- **"Backend available"** = what the verified Stage 7.3 system actually supports.

| # | File (px) | Theme | Screen | Role | Purpose | Main components | Navigation | Backend available | Ambiguities / missing |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `1.png` 390×1159 | Dark | Discovery (degraded) | C | Same as #8 | Unstyled badges and buttons | Same as #8 | Same as #8 | Broken export; **not a target** |
| 2 | `2.png` 539×1600 | Dark | Artisan profile | C | Inspect an artisan before booking | Back/share header, ringed avatar + online dot, verified pill, 3 stat tiles, About, Services & Rates, Client Reviews (42), escrow note, sticky "Starting from ₦8,000 / Book" | ← Discovery · → booking request | `artisanProfileProvider`, reviews, portfolio, favourites, `acceptArtisan` / secure booking | **No rates, starting price or years of experience in `ArtisanModel`.** "ID & Biometrics Verified" isn't supported (photo ID + selfie with admin review only) |
| 3 | `3.png` 602×1600 | Dark | Post a Job, step 1 of 3 | C | Describe a job | Photo picker, Job title, Category, Description (132/500), Location + Change, Estimated Budget (NGN), escrow note, "Find Artisans →" | → matched artisans | `jobRequestNotifierProvider.submitRequest`, `platformConfigProvider.minJobValue`, `ImagePrivacy` | **`JobModel` has no title.** Budget is min/max. **Steps 2–3 aren't designed** |
| 4 | `4.png` 612×1600 | Dark | My Bookings | C | Track bookings | Tabs Active/Completed/Drafts, funded card (escrow amount, 4-stage lifecycle, chat, "Approve & Release"), awaiting card, "Funds safely locked" note, bottom nav | → Chat · Job detail · Pay | `customerJobsProvider`, `jobQuotesProvider`, `confirmComplete`, `WorkflowGateService` | **No drafts in the backend.** The design shows Release while "In Progress", but the server only allows it once the job is `submitted` |
| 5 | `5.png` 540×1600 | Dark | Escrow Wallet | C | Money overview | Personal/Vaults toggle, available balance ₦42,500, locked ₦85,000, Add Money/Withdraw, SafeVault, contracts (milestone 2 of 3, 48 h auto-release), transactions | → Inspect Job | `customerPaymentsProvider`, `customerJobsProvider` (no wallet) | **No stored-value wallet, Add Money, Withdraw, vaults, milestones or 48 h release** |
| 6 | `6.png` 424×1600 | Dark | Profile & Trust | C (+Ad entry) | Account hub | Avatar, BVN & ID pills, 3 stats, security tier, menu, **Obsidian Dark Mode toggle**, Admin Dashboard card, sign out | → Jobs, Chats, Settings, Support, About, Admin | `currentUserProvider`, `isAdminProvider`, `themeProvider`, `uploadAvatar`, `signOut` | **BVN, tiers, "Client Trust 5.0" and FaceID/2FA don't exist** |
| 7 | `7.png` 574×1600 | Dark | Identity verification | C/A | Submit ID | Session/tier pills, shield illustration, checklist (NIN, selfie, review), privacy card, Continue, help | → Support | `verificationServiceProvider.submit`, `storageServiceProvider.uploadVerificationPhoto`, `verificationStatusProvider` | **Header copy error ("Job Scope & Category").** NIN and tiers aren't supported. Verification is an **artisan** workflow |
| 8 | `8.png` 390×1340 | Dark | Discovery | C | Find artisans | Greeting, "Find **Trusted Experts** for Your Home", search, category chips, featured cards (avatar, verified, rating, jobs, "FROM ₦…", View), bottom nav | → Artisan profile · Notifications | `featuredArtisansProvider`, `ServiceCategories.all` | **"FROM ₦…" has no data source** |
| 9 | `9.png` 510×1600 | Dark | Discovery (wide) | C | As #8 | As #8, chips reordered | As #8 | As #8 | Chip order conflicts with #8; #8 was used |
| 10 | `10.png` 495×1600 | Dark | Confirm & Pay | C | Pay agreed amount into escrow | Escrow banner, job card, Service ₦85,000 + "SafeVault Escrow Fee ₦1,500" = ₦86,500, sources (Wallet/Card/Bank Transfer), guarantee, 3-step lifecycle, "Pay ₦86,500 Securely" | → Paystack checkout | `getPaymentBreakdown`, `initPayment`, `initializePaystackTransaction`, `verifyPayment`, webview | **The ₦1,500 fee contradicts the approved 5 %. No wallet source, no saved cards, no dedicated accounts** |
| 11 | `11.png` 554×1600 | Dark | Chat | C↔A | Job conversation | Header (escrow active, phone, amount pill), job strip, SafeGuard card, bubbles, image message, quick actions, composer | → Job detail | `chatNotifierProvider`, `messagesStreamProvider`, `markAllAsRead`, image upload, price proposal | **No phone calls, location pins or "Confirm arrival" automation** |
| 12 | `12.png` 615×1600 | Dark | Notifications | C | Alerts | Filters All/Escrow & Pay/Jobs/Security, SafeVault banner, Today/Earlier groups with chips, settings link | → linked job · Settings | `userNotificationsProvider`, `markRead`, `markAllRead`, `safeNotificationRoute` | **Header copy error ("Chat Conversation").** No security-event notifications exist |
| 13 | `13.png` 1600×1280 canvas | Dark | Onboarding slide 1 | P | First run | Logo, "Hire Trusted Hands, **Pay With Confidence.**", subtitle, 3-dot pager, Get Started, Skip | → Register · Login | Local seen-flag only | **No design or copy for slides 2–3** |
| 14 | `14.png` 706×1600 | Light | Onboarding slide 1 | P | As #13 | Photo hero, "NIN VERIFIED" pill, "Smart Escrow Vault" card, "12,400+ Vetted Artisans", logo pill, headline, 4-dot pager, buttons | As #13 | As #13 | **No photo file was supplied.** "12,400+" is fabricated; NIN isn't supported; 4 dots vs 3 |
| 15 | `15.png` 512×1600 | Light | Discovery | C | As #8 | As #8, plus a duplicate "Discovery" top bar, "Top Rated" chip, "Starting at", escrow banner | As #8 | As #8 | **Double header** is an artefact. No sort-by-rating exists |
| 16 | `16.png` 1600×1485 canvas | Light | Artisan profile | C | As #2 | As #2, plus bookmark, "Services / STARTING RATES", "Recent Reviews All (96)" | As #2 | As #2 | Review count differs from #2 (42 vs 96); rates aren't supported |
| 17 | `17.png` 1600×1386 canvas | Light | Post a Job, step 1 | C | As #3 | As #3, plus a dashed photo box and a "Fixed quote" chip | As #3 | As #3 | As #3 |
| 18 | `18.png` 706×1600 | Light | Confirm & Pay | C | As #10 | "Milestone 1 of 1", "Escrow protection fee (1.7 %) ₦1,500", Wallet ₦124,000 / Mastercard ••••4092 / Bank Transfer, compliance footer | As #10 | As #10 | **Fee, milestone, saved card and wallet conflicts.** CBN/NDPR footer is unsupported |
| 19 | `19.png` 561×1600 | Light | My Bookings | C | As #4 | Tabs Active/Completed/Drafts/**Disputed**, protection banner, funded card, open job with "3 bids in" / View Bids, "Need another repair? Post Job" | As #4 | As #4, plus `jobQuotesProvider` | Drafts as #4 |
| 20 | `20.png` 506×1600 | Light | Artisan Direct Chat | C↔A | As #11 | Active escrow order card, date chip, bubbles, receipt card, Preparation Checklist, "Release 20 % Deposit", "Share Exact Gate Code" | As #11 | As #11 | **No 20 % deposit (single release), receipts or checklists.** "CBN-licensed trustee escrow" is unsupported |
| 21 | `21.png` 597×1600 | Light | Wallet | C | As #5 | Balance card (Tier-3), lock pill, Add Money/Withdraw, compliance strip, 3 quick tiles, transactions, protection card | As #5 | As #5 | As #5 |
| 22 | `22.png` 467×1600 | Light | Profile | C (+A, +Ad) | As #6 | Trust tier pill, avatar, location, ID verified, SCORE 98.4 % / PROTECTION ₦250k, menu, **Artisan Mode toggle**, Admin Dashboard (Partner), log out | As #6 | As #6, plus `setActiveRole` | **98.4 % and ₦250k are fabricated; no customer trust score exists** |
| 23 | `23.png` 651×1600 | Light | Verify Your Identity | C/A | As #7 | As #7 with the correct title, plus "Real-Time NIMC Gateway: Connected" | As #7 | As #7 | **There's no NIMC integration** |
| 24 | `24.png` 706×1600 | Light | Notifications | C | As #12 | "2 Unread alerts", filters All/Escrow/Orders, 4 items, privacy card | As #12 | As #12 | Filter set differs from #12 |
| 25 | `25.png` 597×1600 | Light | Wallet | C | — | — | — | — | **Byte-identical duplicate of #21** |

---

## 3. Navigation (as implemented)

**Customer bottom navigation:**
- Order: **Discovery · Bookings · Payments · Profile**.
- It's the floating pill bar from the references.
- "Wallet" is renamed **Payments** (see completion report, D-01).

**Flows from the references, wired to existing routes:**
- **Onboarding** (`/onboarding`) → *Get Started* → `/register` · *Skip* → `/login`. Shown once.
- **Discovery** (tab):
  - artisan card → `/artisan/:uid` → *Book* → `/secure-booking/:artisanId`;
  - with a job in context, *Book* → `acceptArtisan` → `/chat/:jobId`;
  - bell → `/notifications`.
- **Post a Job** (`/request`) → *Find Artisans* → `/artisans/:jobId` (retained matched-artisan list).
- **Bookings** (tab and `/jobs`):
  - card → `/job/:id`;
  - chat → `/chat/:id`;
  - *Pay into Escrow* → `/payment/:id`;
  - *Approve & Release* → confirmation sheet → `confirmComplete`;
  - *Post Job* → `/request`.
- **Confirm & Pay** (`/payment/:jobId`) → `/payment/:jobId/webview` (retained Paystack webview) → server verification.
- **Payments** (tab and `/wallet` for customers) → *Inspect Job* / transaction → `/job/:id`.
- **Profile** (tab and `/profile`):
  - My Jobs → `/jobs`; My Chats → `/my-chats`;
  - Account, Security and Notification settings → `/settings`;
  - Support → `/support`; About → `/about`;
  - Verification → `/verification`; Earnings → `/wallet` (artisan); Admin → `/admin` (admins only).
- **Notifications** → `safeNotificationRoute` (allow-listed routes only) · settings → `/settings`.

---

## 4. Theme variants: layout differences implemented

There's one screen per category with two palettes. Where the dark and light references differ in layout, the theme selects the variant, but only for elements that have real data behind them.

| Screen | Dark-only (from the dark reference) | Light-only (from the light reference) |
|---|---|---|
| Onboarding | Gradient background, 34 pt headline | Photo hero card with "Smart Escrow Vault", 30 pt headline |
| Post a Job | "Step 1 of 3 · Job Details" | "PROGRESS · Step 1 of 3" |
| Chat | "HandyTrust SafeGuard Active" banner | "Active Escrow Order" card (funded jobs only); sender name above incoming bubbles |
| Bookings, Notifications | Reference header styles | Reference header styles (incl. "Unread alerts" counter) |

---

## 5. Missing screens (no uploaded design)

**Status key:**
- **Retained** = the existing screen still works and is routed.
- **Needs design** = it requires an approved Stitch design before it can be replaced.

No new visual system was invented for any of these.

| Area | Existing screen(s) (retained) | Route | Status |
|---|---|---|---|
| Authentication and recovery | `auth/login_screen`, `register_screen`, `verify_email_screen`, `forgot_password_screen`, `role_selection_screen`, `artisan_registration_screen`, `suspended_screen`, `splash_screen` | `/login`, `/register`, `/verify-email`, `/forgot-password`, `/role-select`, `/register/artisan`, `/suspended`, `/` | Retained · needs design |
| Remaining job-posting steps (2–3) | `artisan/artisan_list_screen` (matched artisans), `artisan/secure_booking_screen` | `/artisans/:jobId`, `/secure-booking/:artisanId` | Retained · needs design |
| Job details (status, agreement, schedule, cancellation, rework) | `job/job_detail_screen` (2,518 lines) | `/job/:jobId` | Retained · needs design |
| Quote review ("View Bids") | Quotes inbox inside `job_detail_screen` | `/job/:jobId` | Retained · needs design |
| Payment results | `payment/payment_webview_screen` (checkout + server verification) | `/payment/:jobId/webview` | Retained · needs design |
| Reviews | `review/review_screen` | `/review/:jobId` | Retained · needs design |
| Disputes | `dispute/dispute_screen` | `/dispute/:jobId` | Retained · needs design |
| Work submission | `job/job_completion_screen` | `/job/:jobId/submit` | Retained · needs design |
| Artisan dashboard and workflows | `artisan/artisan_dashboard_screen`, `open_jobs_feed_screen`, `business_profile_screen`, `bank_details_screen`, `portfolio_manager_screen`, `portfolio_project_screen`, `home/all_jobs_screen` (artisan jobs), `wallet/wallet_screen` (artisan earnings) | `/home` (artisan), `/open-jobs`, `/business-profile`, `/bank-details`, `/portfolio`, `/portfolio-project`, `/jobs`, `/wallet` (artisan) | Retained · needs design |
| Admin dashboard and financial operations | `admin/admin_dashboard_screen` (+ charts, tables, finance dialogs, sidebar) | `/admin` | Retained · needs design |
| Settings and support | `settings/settings_screen`, `support/contact_support_screen`, `support/about_screen` | `/settings`, `/support`, `/about` | Retained · needs design |
| Favourites, chat list | `artisan/favorites_screen`, `chat/my_chats_screen` | `/favorites`, `/my-chats` | Retained · needs design |
| Empty, loading, error states and dialogs | New `HtLoadingView`, `HtEmptyView`, `HtErrorView`, `htConfirm` and `htSnack` built from reference styling | — | Implemented in the design language, but there's **no reference image** for them |

Retained screens keep the previous theme (`AppTheme` / `context.colors`), so they look different from the new screens. This is listed in the completion report as an outstanding issue.
