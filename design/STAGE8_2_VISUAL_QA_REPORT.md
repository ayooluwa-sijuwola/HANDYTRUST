# Stage 8.2 — visual QA report

## 1. Method

- **Harness:** `test_visual/stage8_2_visual_test.dart` renders the real widgets with the app's fonts, a fixed clock (5 Nov 2026 10:14) and test-only fixture data.
- **Responsive sweep:**
  - admin screens at 390 / 768 / 1024 / 1440 px;
  - phone screens at 320 / 360 / 430 px;
  - light and dark;
  - fails on any overflow or layout exception.
- **Goldens:** 20 screens × 2 themes = 40, in `test_visual/goldens/stage8_2/`.
- **References:** the approved previews from Stage 8.1:
  - admin `ad01`–`ad16`;
  - `cu01_settings`, `cu02_support`, `cu09_about`;
  - dialogs `dl01`–`dl05`.

  The customer chat list had no approved design and was purpose-built in the same design system.

## 2. Results

| Suite | Result |
|---|---|
| Stage 8.2 sweep (146) + goldens (40) | **186 / 186** |
| Whole visual suite (Stage 8, approved previews, artisan, Stage 8.2) | **654 / 654** |
| Unchanged earlier goldens | All except 4, all intended: `profile_{light,dark}` (role-correct "Messages with artisans"), `artisan/messages_{light,dark}` (search hint) |

## 3. Captured screens

- **Admin:**
  - dashboard on desktop, tablet and phone;
  - analytics, users (detail open), artisans, jobs (detail open), disputes, support, deletions;
  - finance (chargeback detail with read-only payout-freeze status), audit logs, settings.
- **Settings and help:** hub, personal information, notification preferences, security and password, Support Centre (Payments topic open), About.
- **Customer:** My Chats.

## 4. Defects found by review and fixed

| Defect | Where | Fix |
|---|---|---|
| Brand text and search placeholder overflowed in narrow layouts | Admin sidebar / top bar | Flexible text with ellipsis |
| Alert type ID and the Analytics link drawn in fonts the app doesn't bundle (`monospace`, default button font) | Dashboard | Design-system typography; `AdminLink` |
| Disputed job showed Escrow "Not funded" | Job detail | Funded state includes disputed/completed jobs and `escrowLockedAt` |
| Status pills truncated ("In prog…") with the detail panel open | Jobs table | Wider column, two-line pills |
| Settings sub-page Back closed the wrong page | Test harness finding | Top-most Back used; behaviour verified |

## 5. Deviations from the approved previews (deliberate)

1. **Settings** is a hub with separate pages instead of one page with dialogs, as Stage 8.2 §D requires. The visual language (grouped cards, icon rows) is kept.
2. **About** has no *Terms of Service* or *Privacy Policy* rows. Their URLs were placeholders (`handytrust.example.com`) and no real documents exist. Licences and Support links replace them.
3. **Admin dashboard trends:**
   - the preview's "+6% vs last week" badges are replaced by verifiable notes ("N joined in the last 7 days (previous 7: M)");
   - totals come from count() queries;
   - figures from the 200-record samples say so;
   - an *Administrators* tile was added (real count).
4. **"View in Finance"** links on chargeback alerts are omitted (U-2 not approved). Those alerts offer *Resolve*.
5. **Payout freeze:** status shown read-only (Q-5). The approved preview's *Freeze payout* dialog (`ad13b`) is **not** implemented, because Stage 8.2 limits payout freeze to read-only display.
6. **Disputes:** a single *Resolve dispute* action (release / full refund / split) replaces the old separate *Dismiss* entry point. Same server call, same options.
7. **Customer My Chats** was purpose-built; there was no Stitch reference.

## 6. Limits

- Widget-test rendering, not a device. Keyboard insets, system pickers and notification banners were not visually verified.
- Network images are placeholders in fixtures.
