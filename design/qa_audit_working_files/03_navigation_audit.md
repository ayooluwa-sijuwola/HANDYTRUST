# Navigation/Routing Audit — HandyTrust (go_router 13.0.0)

Router config: lib/routes/router.dart (410 lines, read in full). All findings verified against current code, not stale v1-audit/16-navigation-map.md (claims /phone-login exists as dead code — screen no longer exists at all) or design/WEB_MOBILE_ISOLATION_AUDIT.md (accurate but missed one spot, see below).

## 1. Router structure
Single flat GoRoute list + one ShellRoute for /admin/* (AdminShell keeps sidebar mounted). initialLocation: '/' -> SplashScreen. One top-level redirect: (lines 86-164), re-run via refreshListenable: AuthChangeNotifier (lines 47-68) listening to authStateChangesProvider, currentUserProfileProvider, isAdminProvider. Gate order: auth-loading -> signed-out/anonymous -> email-unverified -> verified-user-on-auth-screen -> suspended -> admin-guard -> dual-role role-select. No role-based guard exists for customer-only/artisan-only routes at router level — role branching done screen-side (home_screen.dart:56). Deep-linking a customer to an artisan-only URL is not blocked by the router (gap, not new).

## 2. Redirect-loop analysis

**[P2] profile-null vs profile-loading not distinguished for suspend/role-select gates** (router.dart:128-134 suspend, :154-162 role-select) vs :142-147 admin check which DOES check isAdminAsync.isLoading.
`currentUserProfileProvider.asData?.value` is null both when profile doc doesn't exist AND while stream still resolving (cold start/refresh). During that window a suspended user's redirect condition is false, so they briefly land on /home before being bounced to /suspended. Not infinite loop, converges, but real timing gap. Repro: suspend a user's Firestore doc mid-session, have them refresh web app — brief flash of gated content before eviction.

**[P2] dual-role -> /role-select interstitial effectively unreachable — UserModel.activeRole can never be null.**
router.dart:154-162 vs user_model.dart:47,89:
```dart
activeRole = activeRole ?? (roles?.first ?? 'customer'),   // constructor
activeRole: json['activeRole'] as String? ?? roles.first,  // fromJson
```
Redirect trigger is `!hasExplicitRole` where hasExplicitRole = activeRole == 'customer' || 'artisan'. But activeRole always defaults to roles.first when Firestore lacks the field, and for hasBothRoles==true accounts roles only contains customer/artisan/admin, so roles.first is virtually always customer or artisan. No code path leaves activeRole null/other. So dual-role users never see the "which mode?" interstitial the redirect comment (149-153) says they should — feature described in code doesn't fire.

**No true infinite loop found.** Every adjacent redirect pair converges in <=2 evaluations. verify_email_screen.dart:33-48 deliberately avoids manual navigation, defers to redirect (good pattern).

## 3. Back-navigation / go vs push

No WillPopScope anywhere (migrated to PopScope — only 1 usage, demo_escrow_screen.dart:144, correctly disables back-gesture mid-payment). No misuse of context.go() where push() was intended — every go() is a genuine "commit" transition. Good pattern: job_completion_screen.dart:292-297 prefers context.pop(), falls back to context.go only if !context.canPop().

**[P1] FCM push-notification deep links use raw Navigator.pushNamed, not go_router — will fail, no named-route table exists.**
notification_provider.dart:107, :125:
```dart
Navigator.of(ctx).pushNamed(route);   // route = '/job/xyz' or '/chat/xyz'
```
main.dart:73-79 boots via MaterialApp.router(routerConfig: router) — no onGenerateRoute/named-routes table anywhere (confirmed via grep). Navigator.of(ctx) returns go_router's internally-managed Navigator (from declarative pages: list) which has no onGenerateRoute set. Calling .pushNamed() throws instead of navigating. Repro: tap push notification for job update while app backgrounded (onMessageOpenedApp, line 118-129) or cold-launch from notification tap (getInitialMessage, line 96-112) — deep link silently fails; the getInitialMessage case throw happens inside a postFrameCallback outside the try block, becomes uncaught Flutter framework error. Fix: ref.read(routerProvider).go(route) or expose context.push/go via router API. Core marketed feature (tap notification -> open job/chat) is broken.

## 4. Push+extra-only screens broken by direct/deep navigation (web refresh, bookmark)

**[P0] `/portfolio-project` crashes outright on any direct navigation — required cast on nullable extra.**
router.dart:383-392:
```dart
final extra = state.extra as Map<String, dynamic>? ?? {};
return PortfolioProjectScreen(
  artisanId: extra['artisanId'] as String,     // crash point
  existing: extra['existing'] as PortfolioProjectModel?,
);
```
PortfolioProjectScreen.artisanId is `required this.artisanId` (non-nullable String, portfolio_project_screen.dart:19). Zero path params — entire payload rides on extra. On Flutter Web refresh, bookmarked/typed URL, or browser back/forward restore, state.extra is null -> extra becomes {} -> extra['artisanId'] is null -> `null as String` throws `type 'Null' is not a subtype of type 'String'` synchronously during build(). Reachable in-app via portfolio_manager_screen.dart:238,325 using context.push('/portfolio-project', extra: {...}). Hard crash — the single most common Flutter Web failure mode.

**[P1] `/payment/:jobId/webview` loads empty/invalid URL and crashes in initState when reached directly.**
router.dart:258-268, payment_webview_screen.dart:39-54:
```dart
url: extra['url'] as String? ?? '',
...
..loadRequest(Uri.parse(widget.url));   // initState, no try/catch
```
On direct nav (extra==null), url defaults to ''. WebViewController.loadRequest requires absolute URI; empty string throws (platform-specific ArgumentError/PlatformException) synchronously in initState, uncaught. Even without throwing, dead blank WebView with no recovery — _retryAfterFailure (line 96) just calls context.pop(), a no-op/exits-app if this was first page in stack. Deep link/refresh into in-progress Paystack payment crashes or dead-ends.

**[P2] `/chat/:jobId` degrades silently (not a crash) on direct navigation.**
router.dart:227-237: otherUserId becomes '' on direct nav — chat screen attempts to resolve counterpart user with empty ID, broken-looking header, no crash.

**[P3 each] Lower severity, same pattern, degrade gracefully:** `/artisans/:jobId` (category/lat/lng default '' /null, router.dart:204-214), `/artisan/:uid` (jobId optional, :215-224), `/demo-payment/:jobId` (autoStart defaults false, benign, :248-257), `/open-jobs` (category defaults '', :393-399). Fix: encode as query params instead of extra.

## 5. Responsive/platform layout gating

Core mechanism sound and centrally enforced: lib/theme/breakpoints.dart:46,53,57 — isTablet/isTabletOnly/isDesktop all require `kIsWeb &&` before width check (tablet=700, desktop=1100, maxContentWidth=1120). WebContentWrapper (web_content_wrapper.dart:35) and MainShellScreen's sidebar-vs-bottom-bar branch (premium_scaffold.dart:73-74,102-108) both read through these getters — Android confirmed unconditionally exempt from desktop layouts at any width; Flutter Web confirmed to get sidebar/multi-column layouts at documented thresholds. admin_dashboard_screen.dart:282,405,515,559 and admin_data_table.dart:296,332 also correctly kIsWeb-gated.

**[P2] One raw, ungated width check missed — admin_data_table.dart:114.**
```dart
final narrow = MediaQuery.of(context).size.width < kAdminTableNarrowBreakpoint;  // 640, no kIsWeb
```
Decides table-vs-stacked-cards for every admin data grid (Users, Artisans, Jobs, Reviews, Support Tickets). Inverse bug direction: not gated, so on Android at width >= 640 (phone landscape, or larger devices), narrow is false and it falls through to flex-column desktop table layout (lines 142-216) instead of mobile card layout. Matches exactly the "wide Android gets desktop-only layout" pattern the audit is designed to catch — this one spot slipped through. Inconsistent with sibling AdminMasterDetail's `wide` flag (line 296,332) which IS kIsWeb-gated. Admin-only audience limits blast radius (route-guarded, not public).

## 6. Dead routes / broken call sites

**[P2] Dead route: `/favorites`.** router.dart:196-200 defines it, FavoritesScreen exists and works, feature is wired (artisan_profile_screen.dart:137 toggles favorite via FavoriteService). But NO navigation call site anywhere pushes/goes to /favorites (exhaustive grep). Users can save artisans but have no UI path to view saved list (short of typing URL on web).

**Effectively-dead route: `/role-select`** — see §2, unreachable in practice. No screen links to it directly either.

**No broken outbound call sites found.** All 85+ context.go/push string literals resolve to defined paths, including AdminSection.*.path references (single source of truth, admin_sidebar.dart:24-37).

Stale doc note: v1-audit/16-navigation-map.md:84 claims /phone-login is unroutable dead code — grepped, found nothing; screen deleted since that doc was written.

## 7. Tab-state preservation

**Confirmed good:** bottom-nav/sidebar tab switching preserves state via IndexedStack (premium_scaffold.dart:95,101), does not rebuild. home_screen.dart:57-72,75-90 constructs tabs as const widgets fed into IndexedStack — scroll position, form input, provider subscriptions all preserved across tab switches. No UX finding needed here.

## Summary by severity
- **P0:** `/portfolio-project` crashes on any direct/deep navigation (router.dart:383-392).
- **P1:** FCM notification deep links broken (notification_provider.dart:107,125 — wrong Navigator API for go_router app); `/payment/:jobId/webview` crashes/dead-ends on direct navigation (router.dart:258-268, payment_webview_screen.dart:53).
- **P2:** suspend/role-select gates don't distinguish profile-loading from profile-null (router.dart:128-134,154-162); dual-role role-select interstitial practically unreachable (user_model.dart:47,89); `/favorites` fully-built dead-end screen with no entry point (router.dart:196-200); ungated width check lets wide Android admin views render desktop data-table layout (admin_data_table.dart:114); `/chat/:jobId` degrades silently on direct nav (router.dart:227-237).
- **P3:** `/artisans/:jobId`, `/artisan/:uid`, `/demo-payment/:jobId`, `/open-jobs` lose extra payload on refresh but degrade gracefully.

All findings CODE-LEVEL ONLY, not executed/tested at runtime by this agent.
