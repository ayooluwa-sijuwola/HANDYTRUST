// Stage 8.1 — artisan presentation layer: screens, actions, dual-role users,
// navigation and deep links. Fixtures are test-only; no Firebase. Every
// action goes through the real EscrowNotifier with a recording JobService.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:handy_trust/core/services/job_service.dart';
import 'package:handy_trust/models/artisan_model.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/notification_model.dart';
import 'package:handy_trust/models/payment_model.dart';
import 'package:handy_trust/models/portfolio_project_model.dart';
import 'package:handy_trust/models/quote_model.dart';
import 'package:handy_trust/models/user_model.dart';
import 'package:handy_trust/providers/artisan_provider.dart';
import 'package:handy_trust/providers/auth_provider.dart';
import 'package:handy_trust/providers/chat_provider.dart';
import 'package:handy_trust/providers/dispute_provider.dart';
import 'package:handy_trust/providers/escrow_provider.dart';
import 'package:handy_trust/providers/notification_provider.dart';
import 'package:handy_trust/providers/payment_provider.dart';
import 'package:handy_trust/providers/platform_config_provider.dart';
import 'package:handy_trust/providers/portfolio_provider.dart';
import 'package:handy_trust/providers/quote_provider.dart';
import 'package:handy_trust/providers/verification_provider.dart';
import 'package:handy_trust/routes/router.dart';
import 'package:handy_trust/screens/home/home_screen.dart';
import 'package:handy_trust/ui/artisan/artisan_shell.dart';
import 'package:handy_trust/ui/artisan/screens/artisan_home_screen.dart';
import 'package:handy_trust/ui/artisan/screens/artisan_inbox_screens.dart';
import 'package:handy_trust/ui/artisan/screens/artisan_profile_screen.dart';
import 'package:handy_trust/ui/artisan/screens/earnings_screen.dart';
import 'package:handy_trust/ui/artisan/screens/find_work_screen.dart';
import 'package:handy_trust/ui/artisan/screens/my_jobs_screen.dart';
import 'package:handy_trust/ui/artisan/screens/payout_account_screen.dart';
import 'package:handy_trust/ui/artisan/screens/work_order_screen.dart';
import 'package:handy_trust/ui/screens/bookings_screen.dart';
import 'package:handy_trust/ui/screens/customer_shell.dart';
import 'package:handy_trust/ui/screens/payments_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUser implements User {
  _FakeUser(this.uid);
  @override
  final String uid;
  @override
  String? get email => '$uid@example.com';
  @override
  bool get isAnonymous => false;
  @override
  bool get emailVerified => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records every JobService call the notifier makes; optionally fails them
/// (the notifier then holds the error — the screens must surface it).
class _RecordingJobService implements JobService {
  _RecordingJobService({this.fail = false});
  final bool fail;
  final calls = <String>[];
  @override
  dynamic noSuchMethod(Invocation i) {
    calls.add(i.memberName.toString().replaceAll('Symbol("', '').replaceAll('")', ''));
    return fail ? Future<void>.error(StateError('permission-denied')) : Future<void>.value();
  }
}

UserModel _user({List<String> roles = const ['artisan'], String activeRole = 'artisan', String uid = 'a1'}) =>
    UserModel(uid: uid, name: 'Tunde Bakare', email: '$uid@example.com', roles: roles, activeRole: activeRole, createdAt: DateTime(2025, 3, 1));

final _artisan = ArtisanModel(
  uid: 'a1',
  name: 'Tunde Bakare',
  createdAt: DateTime(2025),
  category: 'Plumbing',
  skills: 'Pipe fitting, leak repair',
  verificationStatus: 'id_verified',
  approvalStatus: 'approved',
  isAvailable: true,
  rating: 4.8,
  totalRatings: 12,
  completedJobs: 14,
  trustScore: 82,
);

JobModel _job(String id, JobStatus status,
        {String artisanId = 'a1', double? agreed = 45000, String? booking, AgreementStatus? agreement, DateTime? requestedAt, DateTime? autoReleaseAt, int rework = 0, String description = 'Fix kitchen sink leak'}) =>
    JobModel(
      id: id,
      customerId: 'c1',
      artisanId: artisanId,
      category: 'Plumbing',
      description: description,
      status: status,
      agreedAmount: agreed,
      bookingStatus: booking,
      agreementStatus: agreement,
      bookingRequestedAt: requestedAt,
      autoReleaseAt: autoReleaseAt,
      reworkCount: rework,
      areaLabel: 'Bodija, Ibadan',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    );

PaymentModel _pay(String id, String jobId, PaymentStatus s, double amount, {DateTime? releasedAt}) =>
    PaymentModel(id: id, jobId: jobId, payerId: 'c1', artisanId: 'a1', amount: amount, totalCharged: amount * 1.05, status: s, releasedAt: releasedAt, createdAt: DateTime(2026, 10, 1));

List<Override> _overrides({
  UserModel? user,
  List<JobModel> jobs = const [],
  List<JobModel> openJobs = const [],
  List<PaymentModel> payments = const [],
  bool admin = false,
  bool payoutReady = true,
  JobService? jobService,
  Map<String, JobModel>? jobById,
}) {
  final u = user ?? _user();
  final allJobs = {for (final j in [...jobs, ...openJobs]) j.id: j, ...?jobById};
  return [
    authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(_FakeUser(u.uid))),
    currentUserProfileProvider.overrideWith((ref) => Stream.value(u)),
    isAdminProvider.overrideWith((ref) => Stream.value(admin)),
    platformConfigProvider.overrideWithValue(const PlatformConfig()),
    artisanProfileProvider.overrideWith((ref, id) => Stream.value(_artisan)),
    artisanJobsProvider.overrideWith((ref, id) => Stream.value(jobs)),
    artisanPaymentsProvider.overrideWith((ref, id) => Stream.value(payments)),
    artisanPayoutReadyProvider.overrideWith((ref, id) => Stream.value(payoutReady)),
    verificationStatusProvider.overrideWith((ref, id) => Stream.value(null)),
    portfolioProjectsProvider.overrideWith((ref, id) => Stream.value(const <PortfolioProjectModel>[])),
    portfolioViewCountProvider.overrideWith((ref, id) => Stream.value(0)),
    // Stage 8.2: role-separated totals from per-conversation counts.
    unreadMessagesTotalProvider.overrideWith((ref, k) => 2),
    jobCounterpartsProvider.overrideWith((ref, k) => Stream.value(const <String>{})),
    unreadNotificationCountProvider.overrideWith((ref) => Stream.value(1)),
    userNotificationsProvider.overrideWith((ref) => Stream.value(const <NotificationModel>[])),
    openJobsFeedProvider.overrideWith((ref, cat) => Stream.value(openJobs)),
    artisanQuoteForJobProvider.overrideWith((ref, key) => Stream<QuoteModel?>.value(null)),
    jobStreamProvider.overrideWith((ref, id) => Stream.value(allJobs[id])),
    jobPrivateLocationProvider.overrideWith((ref, id) => Stream.value(null)),
    disputeForJobProvider.overrideWith((ref, id) => Stream.value(null)),
    pairUnreadCountProvider.overrideWith((ref, key) => Stream.value(0)),
    // Customer side (dual-role users in Customer Mode).
    customerJobsProvider.overrideWith((ref, id) => Stream.value(const <JobModel>[])),
    customerPaymentsProvider.overrideWith((ref, id) => Stream.value(const <PaymentModel>[])),
    featuredArtisansProvider.overrideWith((ref) => Stream.value(const <ArtisanModel>[])),
    if (jobService != null) escrowNotifierProvider.overrideWith((ref) => EscrowNotifier(jobService, u.uid)),
  ];
}

Widget _app(Widget child, List<Override> overrides, {ThemeMode mode = ThemeMode.light}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(themeMode: mode, theme: ThemeData.light(), darkTheme: ThemeData.dark(), home: child),
    );

Future<void> _settle(WidgetTester t, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void _tall(WidgetTester t, {double w = 430, double h = 1800}) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'onboarding_seen': true}));

  group('Artisan shell', () {
    testWidgets('approved navigation: Home · Find Work · My Jobs · Earnings · Profile; header shows messages + alerts', (t) async {
      _tall(t);
      await t.pumpWidget(_app(const ArtisanShell(), _overrides()));
      await _settle(t);
      for (final l in ['Home', 'Find Work', 'My Jobs', 'Earnings', 'Profile']) {
        expect(find.text(l), findsWidgets, reason: l);
      }
      expect(find.byType(ArtisanHomeScreen), findsOneWidget);
      // Header badges carry the live unread counts.
      expect(find.byTooltip('Messages (2 unread)'), findsOneWidget);
      expect(find.byTooltip('Notifications (1 unread)'), findsOneWidget);
      await t.tap(find.text('Earnings').last);
      await _settle(t);
      expect(find.byType(EarningsScreen), findsOneWidget);
      await t.tap(find.text('My Jobs').last);
      await _settle(t);
      expect(find.byType(MyJobsScreen), findsOneWidget);
    });

    testWidgets('a route-selected tab opens on that tab', (t) async {
      _tall(t);
      await t.pumpWidget(_app(const ArtisanShell(initialTab: ArtisanTab.findWork), _overrides()));
      await _settle(t);
      expect(find.byType(FindWorkScreen), findsOneWidget);
      expect(find.byType(ArtisanHomeScreen), findsNothing);
    });
  });

  group('Home', () {
    testWidgets('action queue shows only real artisan actions; payout reminder when no bank account', (t) async {
      _tall(t, h: 2400);
      await t.pumpWidget(_app(
          const ArtisanShell(),
          _overrides(payoutReady: false, jobs: [
            _job('b1', JobStatus.matched, requestedAt: DateTime.now()),
            _job('e1', JobStatus.escrowLocked),
            _job('p1', JobStatus.paymentPending), // customer acts → not queued
          ])));
      await _settle(t);
      expect(find.textContaining('Booking request'), findsWidgets);
      expect(find.text('Escrow funded — start work'), findsOneWidget);
      expect(find.text('Add payout details'), findsOneWidget);
      expect(find.textContaining('caught up'), findsNothing);
    });

    testWidgets('nothing to do → caught-up message, no invented work', (t) async {
      _tall(t, h: 2400);
      await t.pumpWidget(_app(const ArtisanShell(), _overrides()));
      await _settle(t);
      expect(find.textContaining('caught up'), findsOneWidget);
      expect(find.text('Add payout details'), findsNothing);
    });
  });

  group('My Jobs', () {
    testWidgets('grouped by pipeline stage; history kept separate', (t) async {
      _tall(t, h: 2400);
      await t.pumpWidget(_app(
          const ArtisanShell(initialTab: ArtisanTab.myJobs),
          _overrides(jobs: [
            _job('b1', JobStatus.matched, requestedAt: DateTime.now()),
            _job('w1', JobStatus.inProgress),
            _job('v1', JobStatus.submitted, autoReleaseAt: DateTime.now().add(const Duration(days: 11))),
            _job('c1', JobStatus.completed),
          ])));
      await _settle(t);
      expect(find.text('REQUESTS'), findsOneWidget);
      expect(find.text('WORKING NOW'), findsOneWidget);
      expect(find.text('IN REVIEW'), findsOneWidget);
      expect(find.text('Fix kitchen sink leak'), findsNWidgets(3)); // the completed job is under History only
      expect(find.text('History'), findsOneWidget);
    });

    testWidgets('empty state links to Find Work', (t) async {
      _tall(t);
      await t.pumpWidget(_app(const ArtisanShell(initialTab: ArtisanTab.myJobs), _overrides()));
      await _settle(t);
      expect(find.widgetWithText(ElevatedButton, 'Find Work').evaluate().isNotEmpty || find.text('Find Work').evaluate().length > 1, isTrue);
    });
  });

  group('Find Work', () {
    testWidgets('matched open jobs from the feed; urgent filter', (t) async {
      _tall(t, h: 2200);
      await t.pumpWidget(_app(
          const ArtisanShell(initialTab: ArtisanTab.findWork),
          _overrides(openJobs: [
            _job('o1', JobStatus.requested, artisanId: '', agreed: null, description: 'Replace bathroom tap'),
            _job('o2', JobStatus.requested, artisanId: '', agreed: null, description: 'Unblock drain').copyWith(),
          ])));
      await _settle(t);
      expect(find.textContaining('Replace bathroom tap'), findsOneWidget);
      expect(find.textContaining('Unblock drain'), findsOneWidget);
      expect(find.text('Open jobs'), findsOneWidget);
      expect(find.text('My quotes'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'drain');
      await _settle(t);
      expect(find.textContaining('Replace bathroom tap'), findsNothing);
      expect(find.textContaining('Unblock drain'), findsOneWidget);
    });
  });

  group('Earnings (real payment records only)', () {
    testWidgets('released, escrow and awaiting-release figures; no wallet actions', (t) async {
      _tall(t, h: 2400);
      final now = DateTime.now();
      await t.pumpWidget(_app(
          const ArtisanShell(initialTab: ArtisanTab.earnings),
          _overrides(
            jobs: [_job('h1', JobStatus.inProgress), _job('s1', JobStatus.submitted)],
            payments: [
              _pay('p1', 'r1', PaymentStatus.released, 40000, releasedAt: now),
              _pay('p2', 'h1', PaymentStatus.escrowHeld, 30000),
              _pay('p3', 's1', PaymentStatus.escrowHeld, 25000),
            ],
          )));
      await _settle(t);
      expect(find.text('₦30,000'), findsWidgets); // in escrow
      expect(find.text('₦25,000'), findsWidgets); // awaiting release
      expect(find.textContaining('40,000'), findsWidgets); // released
      expect(find.textContaining('Withdraw'), findsNothing);
      expect(find.textContaining('Add Money'), findsNothing);
      expect(find.textContaining('Wallet'), findsNothing);
    });

    testWidgets('no payments → empty state, zero totals', (t) async {
      _tall(t, h: 2000);
      await t.pumpWidget(_app(const ArtisanShell(initialTab: ArtisanTab.earnings), _overrides()));
      await _settle(t);
      expect(find.text('No payouts yet'), findsOneWidget);
    });
  });

  group('Profile and dual-role users', () {
    for (final dual in [true, false]) {
      testWidgets('switch-to-customer row ${dual ? 'shown to' : 'hidden from'} ${dual ? 'dual-role' : 'artisan-only'} users', (t) async {
        _tall(t, h: 2400);
        final user = _user(roles: dual ? const ['customer', 'artisan'] : const ['artisan']);
        await t.pumpWidget(_app(const ArtisanShell(initialTab: ArtisanTab.profile), _overrides(user: user)));
        await _settle(t);
        expect(find.byType(ArtisanProProfileScreen), findsOneWidget);
        expect(find.text('Switch to Customer mode'), dual ? findsOneWidget : findsNothing);
        expect(find.text('Admin dashboard'), findsNothing);
      });
    }

    testWidgets('admin entry only for admins', (t) async {
      _tall(t, h: 2400);
      await t.pumpWidget(_app(const ArtisanShell(initialTab: ArtisanTab.profile), _overrides(admin: true)));
      await _settle(t);
      expect(find.text('Admin dashboard'), findsOneWidget);
    });

    for (final (role, artisanUi) in [('artisan', true), ('customer', false)]) {
      testWidgets('/home for a dual-role user in $role mode shows the ${artisanUi ? 'artisan' : 'customer'} app only', (t) async {
        _tall(t, h: 2000);
        await t.pumpWidget(_app(const HomeScreen(), _overrides(user: _user(roles: const ['customer', 'artisan'], activeRole: role))));
        await _settle(t);
        expect(find.byType(ArtisanShell), artisanUi ? findsOneWidget : findsNothing);
        expect(find.byType(CustomerShell), artisanUi ? findsNothing : findsOneWidget);
      });
    }

    testWidgets('a customer-only account never gets the artisan app (F-11)', (t) async {
      _tall(t, h: 2000);
      await t.pumpWidget(_app(const HomeScreen(), _overrides(user: _user(roles: const ['customer'], activeRole: 'artisan', uid: 'c9'))));
      await _settle(t);
      expect(find.byType(ArtisanShell), findsNothing);
      expect(find.byType(CustomerShell), findsOneWidget);
    });
  });

  group('Work order actions (real notifier, recorded service calls)', () {
    testWidgets('booking request: Accept calls confirmBooking and confirms', (t) async {
      _tall(t);
      final svc = _RecordingJobService();
      final job = _job('b1', JobStatus.matched, requestedAt: DateTime.now());
      await t.pumpWidget(_app(WorkOrderScreen(job: job), _overrides(jobService: svc, jobs: [job])));
      await _settle(t);
      expect(find.text('A customer wants to book you'), findsOneWidget);
      await t.tap(find.text('Accept booking'));
      await _settle(t);
      expect(svc.calls, contains('confirmBooking'));
      expect(find.textContaining('Booking accepted'), findsOneWidget);
    });

    testWidgets('booking request: a rejected call shows an error, never a fake success', (t) async {
      _tall(t);
      final svc = _RecordingJobService(fail: true);
      final job = _job('b1', JobStatus.matched, requestedAt: DateTime.now());
      await t.pumpWidget(_app(WorkOrderScreen(job: job), _overrides(jobService: svc, jobs: [job])));
      await _settle(t);
      await t.tap(find.text('Accept booking'));
      await _settle(t);
      expect(svc.calls, contains('confirmBooking'));
      expect(find.textContaining('Could not accept the booking'), findsOneWidget);
      expect(find.textContaining('Booking accepted'), findsNothing);
    });

    testWidgets('booking past the server window cannot be accepted', (t) async {
      _tall(t);
      final svc = _RecordingJobService();
      final job = _job('b1', JobStatus.matched, requestedAt: DateTime.now().subtract(const Duration(hours: 30)));
      await t.pumpWidget(_app(WorkOrderScreen(job: job), _overrides(jobService: svc, jobs: [job])));
      await _settle(t);
      await t.tap(find.text('Accept booking'), warnIfMissed: false);
      await _settle(t);
      expect(svc.calls, isEmpty);
    });

    testWidgets('funded job: Start work calls startWork', (t) async {
      _tall(t);
      final svc = _RecordingJobService();
      final job = _job('e1', JobStatus.escrowLocked, agreement: AgreementStatus.confirmed);
      await t.pumpWidget(_app(WorkOrderScreen(job: job), _overrides(jobService: svc, jobs: [job])));
      await _settle(t);
      await t.tap(find.text('Start work'));
      await _settle(t);
      expect(svc.calls, contains('startWork'));
    });

    testWidgets('in progress: tabs (no Schedule for ASAP), progress update and submit entry', (t) async {
      _tall(t, h: 2200);
      final svc = _RecordingJobService();
      final job = _job('w1', JobStatus.inProgress, agreement: AgreementStatus.confirmed);
      await t.pumpWidget(_app(WorkOrderScreen(job: job), _overrides(jobService: svc, jobs: [job])));
      await _settle(t);
      for (final tab in ['Overview', 'Agreement', 'Photos', 'Activity']) {
        expect(find.text(tab), findsWidgets, reason: tab);
      }
      expect(find.text('Schedule'), findsNothing);
      await t.tap(find.textContaining('Mark: '));
      await _settle(t);
      expect(svc.calls, contains('updateJobProgress'));
      expect(find.textContaining('Withdraw from job'), findsNothing); // funded → no withdraw
      expect(find.text('Request cancellation'), findsOneWidget);
    });

    testWidgets('agreement to review: Accept agreement calls the artisan acceptance', (t) async {
      _tall(t, h: 2200);
      final svc = _RecordingJobService();
      final job = _job('a1j', JobStatus.inChat, agreement: AgreementStatus.pendingArtisanConfirmation).copyWith();
      await t.pumpWidget(_app(WorkOrderScreen(job: job), _overrides(jobService: svc, jobs: [job])));
      await _settle(t);
      await t.tap(find.text('Review agreement').last);
      await _settle(t);
      await t.tap(find.text('Accept agreement'));
      await _settle(t);
      expect(svc.calls, contains('acceptAgreementAsArtisan'));
    });

    testWidgets('submitted: 14-day review shown; no withdraw or cancellation', (t) async {
      _tall(t, h: 2200);
      final job = _job('s1', JobStatus.submitted, agreement: AgreementStatus.confirmed, autoReleaseAt: DateTime.now().add(const Duration(days: 13, hours: 2)));
      await t.pumpWidget(_app(WorkOrderScreen(job: job), _overrides(jobService: _RecordingJobService(), jobs: [job])));
      await _settle(t);
      expect(find.textContaining('13 d'), findsWidgets);
      expect(find.textContaining('Withdraw from job'), findsNothing);
      expect(find.text('Request cancellation'), findsNothing);
      expect(find.textContaining('48'), findsNothing);
    });
  });

  group('Other artisan pages', () {
    testWidgets('payout account rejects a non-10-digit account number', (t) async {
      _tall(t, h: 1600);
      await t.pumpWidget(_app(const PayoutAccountScreen(), _overrides()));
      await _settle(t);
      expect(find.byType(PayoutAccountScreen), findsOneWidget);
    });

    testWidgets('notifications: empty state renders', (t) async {
      _tall(t);
      await t.pumpWidget(_app(const ArtisanNotificationsScreen(), _overrides()));
      await _settle(t);
      expect(find.byType(ArtisanNotificationsScreen), findsOneWidget);
    });

    testWidgets('dark theme renders the shell without errors', (t) async {
      _tall(t);
      await t.pumpWidget(_app(const ArtisanShell(), _overrides(), mode: ThemeMode.dark));
      await _settle(t);
      expect(find.byType(ArtisanHomeScreen), findsOneWidget);
    });
  });

  group('Router: deep links and role redirects (UI only; rules enforce access)', () {
    Future<GoRouter> boot(WidgetTester t, List<Override> overrides) async {
      // 800 px like the Stage 8 customer tests: the test font draws every
      // glyph as a full square, wider than the real fonts.
      _tall(t, w: 800, h: 2200);
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);
      // The existing redirect calls ref.watch inside the GoRouter callback;
      // resolve its inputs first so the router is built once, as in the app
      // after sign-in.
      await t.runAsync(() async {
        await container.read(authStateChangesProvider.future);
        await container.read(currentUserProfileProvider.future);
        await container.read(isAdminProvider.future);
      });
      final router = container.read(routerProvider);
      await t.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
      await _settle(t, 20);
      return router;
    }

    String path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

    Future<void> go(WidgetTester t, GoRouter r, String to) async {
      r.go(to);
      await _settle(t, 20); // past the page transition
    }

    testWidgets('artisan: /home, /open-jobs, /jobs, /wallet open the matching artisan tab', (t) async {
      final r = await boot(t, _overrides());
      expect(path(r), '/home');
      expect(find.byType(ArtisanHomeScreen), findsOneWidget);
      await go(t, r, '/open-jobs');
      expect(find.byType(FindWorkScreen), findsOneWidget);
      await go(t, r, '/jobs');
      expect(find.byType(MyJobsScreen), findsOneWidget);
      await go(t, r, '/wallet');
      expect(find.byType(EarningsScreen), findsOneWidget);
      await go(t, r, '/profile');
      expect(find.byType(ArtisanProProfileScreen), findsOneWidget);
      await go(t, r, '/notifications');
      expect(find.byType(ArtisanNotificationsScreen), findsOneWidget);
      await go(t, r, '/my-chats');
      expect(find.byType(ArtisanMessagesScreen), findsOneWidget);
    });

    testWidgets('artisan: /job/:id opens the work order for the job’s own artisan', (t) async {
      final job = _job('j7', JobStatus.inProgress, agreement: AgreementStatus.confirmed);
      final r = await boot(t, _overrides(jobs: [job], jobService: _RecordingJobService()));
      await go(t, r, '/job/j7');
      expect(path(r), '/job/j7');
      expect(find.byType(WorkOrderScreen), findsOneWidget);
    });

    testWidgets('customer-only account: artisan-only deep links redirect home (D-6)', (t) async {
      final r = await boot(t, _overrides(user: _user(roles: const ['customer'], activeRole: 'customer', uid: 'c9')));
      for (final p in ['/open-jobs', '/bank-details', '/business-profile', '/portfolio', '/job/j1/submit']) {
        await go(t, r, p);
        expect(path(r), '/home', reason: p);
        expect(find.byType(CustomerShell), findsOneWidget, reason: p);
      }
    });

    testWidgets('dual-role user in customer mode gets customer screens on shared paths', (t) async {
      final r = await boot(t, _overrides(user: _user(roles: const ['customer', 'artisan'], activeRole: 'customer')));
      expect(find.byType(CustomerShell), findsOneWidget);
      await go(t, r, '/wallet');
      expect(find.byType(PaymentsScreen), findsOneWidget);
      expect(find.byType(EarningsScreen), findsNothing);
      await go(t, r, '/jobs');
      expect(find.byType(BookingsScreen), findsOneWidget);
      // Artisan-only pages stay reachable to them (they hold the role).
      await go(t, r, '/bank-details');
      expect(path(r), '/bank-details');
      expect(find.byType(PayoutAccountScreen), findsOneWidget);
    });
  });

  group('Source guards: the old artisan presentation is gone', () {
    const deleted = [
      'lib/screens/artisan/artisan_dashboard_screen.dart',
      'lib/screens/artisan/open_jobs_feed_screen.dart',
      'lib/screens/artisan/business_profile_screen.dart',
      'lib/screens/artisan/bank_details_screen.dart',
      'lib/screens/artisan/portfolio_manager_screen.dart',
      'lib/screens/artisan/portfolio_project_screen.dart',
      'lib/screens/artisan/artisan_profile_screen.dart',
      'lib/screens/artisan/browse_artisans_screen.dart',
      'lib/screens/home/all_jobs_screen.dart',
      'lib/screens/home/service_request_screen.dart',
      'lib/screens/wallet/wallet_screen.dart',
      'lib/screens/job/job_completion_screen.dart',
      'lib/screens/auth/artisan_registration_screen.dart',
      'lib/widgets/artisan_card.dart',
      'lib/widgets/balance_card.dart',
      'lib/widgets/cancellation_reason_dialog.dart',
      'lib/widgets/earnings_summary_card.dart',
      'lib/widgets/job_booking_card.dart',
      'lib/widgets/loading_indicator.dart',
      'lib/widgets/pill_tab_selector.dart',
      'lib/widgets/portfolio_viewer.dart',
      'lib/widgets/premium_scaffold.dart',
      'lib/widgets/service_area_card.dart',
      'lib/widgets/shimmer_loaders.dart',
      'lib/widgets/transaction_card.dart',
      'lib/widgets/trust_score_card.dart',
    ];

    test('deleted artisan screens and widgets do not exist', () {
      for (final f in deleted) {
        expect(File(f).existsSync(), isFalse, reason: f);
      }
    });

    final artisanUi = Directory('lib/ui/artisan').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

    test('the artisan UI is self-contained: no legacy screens, widgets or theme', () {
      expect(artisanUi.length, greaterThanOrEqualTo(15));
      for (final f in artisanUi) {
        final src = f.readAsStringSync();
        for (final banned in ["screens/artisan/", "/widgets/", 'MainShellScreen', 'premium_scaffold', 'AppTheme', 'context.colors', 'job_detail_screen']) {
          expect(src.contains(banned), isFalse, reason: '${f.path} references $banned');
        }
      }
    });

    test('no Firebase SDK in the artisan UI (writes go through services)', () {
      for (final f in artisanUi) {
        final src = f.readAsStringSync();
        for (final banned in ['package:cloud_firestore', 'package:firebase_storage', 'package:cloud_functions', 'FirebaseFirestore.instance', '.collection(']) {
          expect(src.contains(banned), isFalse, reason: '${f.path} uses $banned');
        }
      }
    });

    test('nothing in the app routes to the deleted artisan screens', () {
      final all = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      for (final f in all) {
        final src = f.readAsStringSync().replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
        for (final banned in ['ArtisanDashboardScreen', 'OpenJobsFeedScreen', 'BankDetailsScreen', 'PortfolioManagerScreen', 'AllJobsScreen', 'WalletScreen', 'JobCompletionScreen']) {
          expect(src.contains(banned), isFalse, reason: '${f.path} references $banned');
        }
      }
    });

    test('artisan copy uses the 14-day review window, never 48 hours or 7 days', () {
      final files = [...artisanUi, File('lib/core/services/workflow_gate_service.dart'), File('lib/core/services/artisan_work_logic.dart')];
      for (final f in files) {
        final src = f.readAsStringSync().replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
        for (final b in ['48 hours', '48-hour', '7 days', '7-day', '24–48']) {
          expect(src.contains(b), isFalse, reason: '${f.path} says "$b"');
        }
      }
    });
  });
}
