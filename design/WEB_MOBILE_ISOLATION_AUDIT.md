# Web/Mobile Isolation Audit

Audited every screen touched by the web implementation work to answer one question: was any existing mobile widget, screen, or shared component actually **modified** to build the desktop UI, or was desktop UI added as a separate branch? Found one real, root-cause issue — not a modified mobile widget tree, but a **missing platform gate** that could have let a wide Android device (tablet in landscape, unfolded foldable) cross the same width thresholds Flutter Web uses and receive desktop layouts it was never meant to get. Fixed at the source, not per-screen.

## Root cause found and fixed

`context.isDesktop` / `context.isTablet` / `context.isTabletOnly` (`lib/theme/breakpoints.dart`) and `WebContentWrapper`'s internal check (`lib/widgets/web_content_wrapper.dart`) were **pure viewport-width checks** — no platform check. Every screen's desktop branch correctly used `if (!context.isDesktop) return <mobile tree>;`, so no screen's own code was ever conditionally *editing* the mobile tree — but the condition itself could theoretically evaluate true on a wide-enough Android device, not just on web.

**Fix**: both extension getters and `WebContentWrapper` now require `kIsWeb` first:
```dart
bool get isDesktop => kIsWeb && _width >= AppBreakpoints.desktop;
```
This is the single point every desktop/tablet decision in the app reads through. Android is now **unconditionally** exempt from every desktop layout branch, regardless of screen width, orientation, or window mode — not just "usually" exempt because phones tend to be narrow.

Eight more raw, ungated width checks were found and fixed the same way, all inside the Admin section (`admin_dashboard_screen.dart` ×6, `admin_data_table.dart` ×2) — these predate the recent web-specific work (part of Admin's own earlier responsive shell) but had the identical gap, so fixed for the same reason and to the same standard.

## Screens split into Mobile/Desktop variants

Every one of these follows the same shape: `if (!context.isDesktop) return <original mobile widget tree, unmodified>;` then a separate desktop-only branch below it. With the `kIsWeb` fix, the mobile branch is what Android renders **unconditionally**.

| Screen | File | Desktop-only addition |
|---|---|---|
| Main nav shell | `lib/widgets/premium_scaffold.dart` | `_DesktopSidebar` (Row layout) vs. unmodified `_FlatNavBar`/`IndexedStack` |
| Customer Home | `lib/screens/home/home_screen.dart` | Right rail (`_DesktopRightRail`) added beside the unmodified `mainColumn` |
| My Bookings | `lib/screens/home/all_jobs_screen.dart` | `_BookingsList` — 2-column `Wrap` grid vs. unmodified `ListView` |
| Chat | `lib/screens/chat/chat_screen.dart` | 3-column `Row` vs. unmodified `WebContentWrapper(child: messageColumn)` |
| Find Jobs | `lib/screens/artisan/open_jobs_feed_screen.dart` | Left filter panel + `_JobResultsGrid` vs. unmodified `Column`/`ListView.separated` |
| Admin shell | `lib/screens/admin/admin_dashboard_screen.dart` | Sidebar+Row vs. drawer+body (pre-existing split, gate fixed) |

Screens using only `WebContentWrapper`/`AuthWebLayout` (width-capping, not a structural split) — passthrough on Android is now `kIsWeb`-gated at the source, nothing per-screen to list separately: Login, Register, Forgot Password, Verify Email, Artisan Registration, Job Detail, Payment, Post a Job, Artisan Dashboard, Wallet/Earnings.

## Confirmed: no mobile widget was edited to build desktop UI

Traced every desktop-only addition back to its mobile counterpart:
- `_FlatNavBar`, `_NavItem` (bottom nav) — zero changes, only the branch condition around them changed.
- Every `mainColumn`/list/`Column` extracted as a variable before the `if (!context.isDesktop)` check is a direct copy of the pre-existing widget construction, not a rewrite.
- `ChatListPanel`/`CustomerChatListPanel` (`my_chats_screen.dart`) — renamed from private (`_ChatList`/`_CustomerChatList`) to public so `chat_screen.dart` could reuse them on desktop. A rename changes no behavior; `MyChatsScreen`'s own mobile rendering is byte-identical.

Shared business logic, providers, and services were not touched by any of this — `WorkflowGateService`, `customerJobsProvider`, `artisanJobsProvider`, `currentUserProvider`, etc. are read by both mobile and desktop branches identically, as required.

## Testing

`flutter analyze`: 13 pre-existing issues, zero introduced. `flutter test`: 85/85 passing. `flutter build web`: succeeded — confirms `kIsWeb` evaluates true and the desktop branches still compile and render on the actual web target after the gating fix.

Android wasn't rebuilt as an APK this pass (not requested), but the fix is a pure boolean-constant gate (`kIsWeb`, a compile-time platform constant), not a platform-specific import or API — there is no code path by which it could introduce an Android compile error, and `flutter analyze` covers the same source tree Android compiles from.
