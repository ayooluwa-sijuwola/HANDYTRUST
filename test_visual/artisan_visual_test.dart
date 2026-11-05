// Stage 8.1 artisan visual QA (design/STAGE8_1_VISUAL_QA_REPORT.md).
//
// Renders every rebuilt artisan screen (the real widgets, not previews) in
// light and dark, at the approved preview size (390 pt wide, 1.5x — the
// same frame as test_visual/previews/goldens/ar*.png), plus a responsive
// sweep (320 / 360 / 430) that fails on any overflow or layout exception,
// and the 1024-px My Jobs board.
//   flutter test test_visual/artisan_visual_test.dart --update-goldens
//   flutter test test_visual/artisan_visual_test.dart
//
// TEST-ONLY fixture data, modelled on the approved previews. Every capture
// runs at a fixed instant (withClock) so countdowns, "20m ago" labels and
// dates are identical on every run.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/artisan_profile_service.dart';
import 'package:handy_trust/core/services/job_service.dart';
import 'package:handy_trust/models/artisan_model.dart';
import 'package:handy_trust/models/dispute_model.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/message_model.dart';
import 'package:handy_trust/models/notification_model.dart';
import 'package:handy_trust/models/payment_model.dart';
import 'package:handy_trust/models/portfolio_project_model.dart';
import 'package:handy_trust/models/quote_model.dart';
import 'package:handy_trust/models/user_model.dart';
import 'package:handy_trust/models/verification_model.dart';
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
import 'package:handy_trust/ui/artisan/artisan_shell.dart';
import 'package:handy_trust/ui/artisan/screens/artisan_inbox_screens.dart';
import 'package:handy_trust/ui/artisan/screens/artisan_registration_screen.dart';
import 'package:handy_trust/ui/artisan/screens/artisan_verification_screen.dart';
import 'package:handy_trust/ui/artisan/screens/business_profile_screen.dart';
import 'package:handy_trust/ui/artisan/screens/payout_account_screen.dart';
import 'package:handy_trust/ui/artisan/screens/portfolio_screen.dart';
import 'package:handy_trust/ui/artisan/screens/quote_composer_screen.dart';
import 'package:handy_trust/ui/artisan/screens/submit_work_screen.dart';
import 'package:handy_trust/ui/artisan/screens/work_order_screen.dart';
import 'package:handy_trust/ui/screens/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUser implements User {
  _FakeUser(this.uid);
  @override
  final String uid;
  @override
  String? get email => 'tunde@example.com';
  @override
  bool get isAnonymous => false;
  @override
  bool get emailVerified => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopJobService implements JobService {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class _FakeProfileService implements ArtisanProfileService {
  @override
  Future<ArtisanBankDetails> loadBankDetails(String uid) async =>
      const ArtisanBankDetails(bankName: 'Guaranty Trust Bank', accountName: 'Tunde Balogun', accountNumber: '0123456789');
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

final _now = DateTime(2026, 11, 5, 10, 14);
final _user = UserModel(uid: 'a1', name: 'Tunde Balogun', email: 'tunde@example.com', roles: const ['customer', 'artisan'], activeRole: 'artisan', createdAt: DateTime(2025, 3, 1));

ArtisanModel _artisanFor({bool fresh = false}) => ArtisanModel(
      uid: 'a1',
      name: fresh ? 'Kola Ade' : 'Tunde Balogun',
      createdAt: DateTime(2025, 3, 1),
      category: fresh ? 'Carpentry' : 'Plumbing',
      serviceAddress: '4 Ring Road, Bodija, Ibadan',
      skills: 'Pipe fitting, Leak repair, Water heaters, Drainage',
      bio: 'Licensed plumber with 9 years’ experience across Ibadan. Clean work, fair quotes, and I explain every fix before I start.',
      rating: fresh ? 0 : 4.8,
      totalRatings: fresh ? 0 : 37,
      completedJobs: fresh ? 0 : 41,
      trustScore: fresh ? 20 : 86,
      isAvailable: !fresh,
      verificationStatus: fresh ? 'pending' : 'id_verified',
      approvalStatus: fresh ? 'pending' : 'approved',
      serviceRadiusKm: 15,
    );

JobModel _job(String id, JobStatus status, String description,
        {double? agreed,
        String? booking,
        AgreementStatus? agreement,
        String urgency = 'asap',
        DateTime? requestedAt,
        DateTime? autoReleaseAt,
        DateTime? appointment,
        JobProgressStage? progress,
        int rework = 0,
        String? reworkReason,
        String artisanId = 'a1',
        String? scope,
        double? budgetMin,
        double? budgetMax}) =>
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
      agreementScope: scope,
      urgency: urgency,
      bookingRequestedAt: requestedAt,
      autoReleaseAt: autoReleaseAt,
      confirmedAppointment: appointment,
      progressStage: progress,
      reworkCount: rework,
      reworkReason: reworkReason,
      areaLabel: 'Bodija, Ibadan',
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      submittedAt: autoReleaseAt?.subtract(const Duration(days: 14)),
      createdAt: _now.subtract(const Duration(hours: 5)),
    );

final _request = _job('job0B8491', JobStatus.matched, 'Kitchen sink leak under the cabinet', agreed: 24500, requestedAt: _now.subtract(const Duration(hours: 6)));
final _agreement = _job('job4C1120', JobStatus.inChat, 'Replace bathroom water heater', agreed: 42000, agreement: AgreementStatus.pendingArtisanConfirmation,
    scope: 'Remove the old 30L heater, install the customer-supplied 50L heater, pressure-test all joints.');
final _funded = _job('job7C2210', JobStatus.escrowLocked, 'Install outdoor tap', agreed: 12000, agreement: AgreementStatus.confirmed, appointment: _now.add(const Duration(days: 2, hours: 3)));
final _working = _job('job9A0012', JobStatus.inProgress, 'Repipe guest bathroom', agreed: 85000, agreement: AgreementStatus.confirmed, progress: JobProgressStage.workStarted,
    scope: 'Replace all copper supply lines in the guest bathroom with PEX; reconnect basin, WC and shower.');
final _review = _job('job5D3301', JobStatus.submitted, 'Unblock main drain', agreed: 32000, agreement: AgreementStatus.confirmed, autoReleaseAt: _now.add(const Duration(days: 11, hours: 4)));
final _rework = _job('job2E7781', JobStatus.inProgress, 'Fix leaking shower head', agreed: 9500, agreement: AgreementStatus.confirmed, rework: 1, reworkReason: 'Still dripping slightly when the tap is off.');
final _disputed = _job('job6F4410', JobStatus.disputed, 'Toilet cistern replacement', agreed: 28000, agreement: AgreementStatus.confirmed);
final _done = _job('job1A9900', JobStatus.completed, 'Fix leaking shower head', agreed: 24500, agreement: AgreementStatus.confirmed);
final _activeJobs = [_request, _agreement, _funded, _working, _review, _rework, _disputed, _done];

final _openJobs = [
  _job('open1', JobStatus.requested, 'Burst pipe in the kitchen wall', artisanId: '', budgetMin: 20000, budgetMax: 30000),
  _job('open2', JobStatus.requested, 'Install a new kitchen sink and mixer', artisanId: '', urgency: 'scheduled', budgetMin: 30000, budgetMax: 45000),
  _job('open3', JobStatus.requested, 'Water pump not building pressure', artisanId: '', budgetMin: 12000, budgetMax: 18000),
];

PaymentModel _pay(String id, String jobId, PaymentStatus s, double amount, {int monthsAgo = 0}) => PaymentModel(
      id: id,
      jobId: jobId,
      payerId: 'c1',
      artisanId: 'a1',
      amount: amount,
      totalCharged: amount * 1.05,
      status: s,
      releasedAt: s == PaymentStatus.released ? DateTime(_now.year, _now.month - monthsAgo, 3) : null,
      createdAt: DateTime(_now.year, _now.month - monthsAgo, 1),
    );

final _payments = [
  _pay('p1', 'job1A9900', PaymentStatus.released, 24500),
  _pay('p2', 'x2', PaymentStatus.released, 60500),
  _pay('p3', 'x3', PaymentStatus.released, 32000),
  _pay('p4', 'x4', PaymentStatus.released, 95000, monthsAgo: 1),
  _pay('p5', 'x5', PaymentStatus.released, 120000, monthsAgo: 2),
  _pay('p6', 'x6', PaymentStatus.released, 78000, monthsAgo: 3),
  _pay('p7', 'x7', PaymentStatus.released, 101000, monthsAgo: 4),
  _pay('p8', 'job9A0012', PaymentStatus.escrowHeld, 85000),
  _pay('p9', 'job5D3301', PaymentStatus.escrowHeld, 32000),
];

final _notifications = [
  NotificationModel(id: 'n1', userId: 'a1', type: 'booking_requested', title: 'New booking request', body: 'A customer wants to book you for “Kitchen sink leak”.', jobId: 'job0B8491', createdAt: _now.subtract(const Duration(minutes: 20))),
  NotificationModel(id: 'n2', userId: 'a1', type: 'escrow_funded', title: 'Escrow funded', body: '₦12,000 is held in escrow for “Install outdoor tap”.', jobId: 'job7C2210', createdAt: _now.subtract(const Duration(hours: 3))),
  NotificationModel(id: 'n3', userId: 'a1', type: 'payment_released', title: 'Payment released', body: '₦24,500 was released for “Fix leaking shower head”.', jobId: 'job1A9900', isRead: true, createdAt: _now.subtract(const Duration(days: 1))),
];

final _messages = [
  MessageModel(id: 'm1', jobId: 'job9A0012', senderId: 'c1', receiverId: 'a1', text: 'Good morning! Will you need the water switched off before you arrive?', isRead: true, createdAt: _now.subtract(const Duration(minutes: 40))),
  MessageModel(id: 'm2', jobId: 'job9A0012', senderId: 'a1', receiverId: 'c1', text: 'Yes please, the main valve by the gate. I’ll be there at 9.', isRead: true, createdAt: _now.subtract(const Duration(minutes: 35))),
];

List<Override> _overrides({
  bool fresh = false,
  bool loading = false,
  bool error = false,
}) {
  final js = (fresh ? const <JobModel>[] : _activeJobs);
  final byId = {for (final j in [..._activeJobs, ..._openJobs]) j.id: j};
  Stream<List<JobModel>> jobStream() {
    if (loading) return StreamController<List<JobModel>>().stream;
    if (error) return Stream.error(StateError('unavailable'));
    return Stream.value(js);
  }

  return [
    authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(_FakeUser('a1'))),
    currentUserProfileProvider.overrideWith((ref) => Stream.value(_user)),
    isAdminProvider.overrideWith((ref) => Stream.value(false)),
    platformConfigProvider.overrideWithValue(const PlatformConfig()),
    artisanProfileProvider.overrideWith((ref, id) => Stream.value(_artisanFor(fresh: fresh))),
    artisanJobsProvider.overrideWith((ref, id) => jobStream()),
    artisanPaymentsProvider.overrideWith((ref, id) => Stream.value(fresh ? const <PaymentModel>[] : _payments)),
    artisanPayoutReadyProvider.overrideWith((ref, id) => Stream.value(!fresh)),
    verificationStatusProvider.overrideWith((ref, id) => Stream.value(fresh
        ? const VerificationModel(uid: 'a1', selfieUrl: 's', governmentIdUrl: 'g', status: VerificationStatus.pending)
        : const VerificationModel(uid: 'a1', selfieUrl: 's', governmentIdUrl: 'g', status: VerificationStatus.approved))),
    portfolioProjectsProvider.overrideWith((ref, id) => Stream.value(const <PortfolioProjectModel>[])),
    portfolioViewCountProvider.overrideWith((ref, id) => Stream.value(fresh ? 0 : 214)),
    messagesUnreadCountProvider.overrideWith((ref, id) => Stream.value(2)),
    unreadNotificationCountProvider.overrideWith((ref) => Stream.value(fresh ? 1 : 3)),
    userNotificationsProvider.overrideWith((ref) => Stream.value(_notifications)),
    openJobsFeedProvider.overrideWith((ref, cat) => Stream.value(_openJobs)),
    artisanQuoteForJobProvider.overrideWith((ref, key) => Stream<QuoteModel?>.value(null)),
    jobStreamProvider.overrideWith((ref, id) => Stream.value(byId[id])),
    jobPrivateLocationProvider.overrideWith((ref, id) => Stream.value({'customerAddress': '12 Awolowo Avenue, Bodija, Ibadan'})),
    disputeForJobProvider.overrideWith((ref, id) => Stream.value(DisputeModel(
          id: 'd1',
          jobId: id,
          raisedBy: 'c1',
          againstUserId: 'a1',
          reason: 'The cistern still runs constantly after the replacement.',
          createdAt: _now.subtract(const Duration(days: 1)),
        ))),
    chatUnreadCountProvider.overrideWith((ref, key) => Stream.value(key.jobId == _working.id ? 1 : 0)),
    lastMessageProvider.overrideWith((ref, key) => Stream.value(key.jobId == _working.id ? _messages.first : null)),
    messagesStreamProvider.overrideWith((ref, key) => Stream.value(_messages)),
    escrowNotifierProvider.overrideWith((ref) => EscrowNotifier(_NoopJobService(), 'a1')),
    artisanProfileServiceProvider.overrideWithValue(_FakeProfileService()),
  ];
}

Future<void> _loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final f in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(f['asset'] as String).then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }
}

/// One rebuilt screen and the approved preview it is compared with.
class _Shot {
  const _Shot(this.name, this.preview, this.height, this.builder, {this.fresh = false, this.loading = false, this.error = false, this.tap});
  final String name;
  final String preview; // test_visual/previews/goldens/<preview>_<theme>.png
  final double height;
  final Widget Function() builder;
  final bool fresh;
  final bool loading;
  final bool error;
  final String? tap; // text to tap before capture (e.g. a tab)
}

final _shots = <_Shot>[
  _Shot('home', 'ar01_home', 1520, () => const ArtisanShell()),
  _Shot('home_new_artisan', 'ar01n_home_new_artisan', 1100, () => const ArtisanShell(), fresh: true),
  _Shot('find_work', 'ar02_find_work', 1300, () => const ArtisanShell(initialTab: ArtisanTab.findWork)),
  _Shot('quote_composer', 'ar02b_quote_composer', 1300, () => QuoteComposerScreen(job: _openJobs.first, artisanId: 'a1')),
  _Shot('my_quotes', 'ar02q_my_quotes', 900, () => const ArtisanShell(initialTab: ArtisanTab.findWork), tap: 'My quotes'),
  _Shot('my_jobs', 'ar03_my_jobs', 1600, () => const ArtisanShell(initialTab: ArtisanTab.myJobs)),
  _Shot('booking_request', 'ar03r_booking_request', 1100, () => WorkOrderScreen(job: _request)),
  _Shot('work_order', 'ar04_work_order', 1300, () => WorkOrderScreen(job: _working)),
  _Shot('agreement', 'ar04a_agreement', 1200, () => WorkOrderScreen(job: _agreement), tap: 'Agreement'),
  _Shot('submit_work', 'ar05_submit_work', 1100, () => SubmitWorkScreen(jobId: _working.id)),
  _Shot('in_review', 'ar05r_in_review', 1200, () => WorkOrderScreen(job: _review)),
  _Shot('rework', 'ar06_rework', 1300, () => WorkOrderScreen(job: _rework)),
  _Shot('dispute', 'ar07_dispute', 1200, () => WorkOrderScreen(job: _disputed)),
  _Shot('earnings', 'ar08_earnings', 1500, () => const ArtisanShell(initialTab: ArtisanTab.earnings)),
  _Shot('payout_account', 'ar08p_payout_account', 1000, () => const PayoutAccountScreen()),
  _Shot('profile', 'ar09_profile', 1600, () => const ArtisanShell(initialTab: ArtisanTab.profile)),
  _Shot('business_profile', 'ar09b_business_profile', 1200, () => const BusinessProfileScreen()),
  _Shot('verification', 'ar09v_verification', 1000, () => const ArtisanVerificationScreen(), fresh: true),
  _Shot('portfolio', 'ar10_portfolio', 900, () => const PortfolioScreen()),
  _Shot('portfolio_project', 'ar10e_portfolio_project', 1200, () => const PortfolioProjectScreen(artisanId: 'a1')),
  _Shot('notifications', 'ar11_notifications', 900, () => const ArtisanNotificationsScreen()),
  _Shot('messages', 'ar12_messages', 900, () => const ArtisanMessagesScreen()),
  _Shot('chat', 'ar12c_chat', 900, () => ChatScreen(jobId: _working.id, otherUserId: 'c1')),
  _Shot('loading', 'ar13_loading', 844, () => const ArtisanShell(initialTab: ArtisanTab.myJobs), loading: true),
  _Shot('error', 'ar13e_error', 844, () => const ArtisanShell(initialTab: ArtisanTab.myJobs), error: true),
  _Shot('registration', 'au06_artisan_registration', 1300, () => const ArtisanRegistrationScreen()),
];

Future<void> _pumpShot(WidgetTester tester, _Shot s, {required bool dark}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(fresh: s.fresh, loading: s.loading, error: s.error),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, useMaterial3: true),
      home: s.builder(),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (s.tap != null) {
    await tester.tap(find.text(s.tap!).first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

void _frame(WidgetTester tester, Size logical, double dpr) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = logical * dpr;
  tester.view.padding = FakeViewPadding(top: 47 * dpr, bottom: 34 * dpr);
  tester.view.viewPadding = FakeViewPadding(top: 47 * dpr, bottom: 34 * dpr);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
    await _loadFonts();
  });

  // Responsive sweep: every rebuilt screen, both themes, small to large
  // phones. Fails on any overflow / layout exception.
  const sizes = [Size(320, 568), Size(360, 780), Size(430, 932)];
  for (final s in _shots) {
    for (final dark in [false, true]) {
      for (final size in sizes) {
        testWidgets('layout ${s.name} ${dark ? 'dark' : 'light'} @ ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
          _frame(tester, size, 2);
          await withClock(Clock.fixed(_now), () => _pumpShot(tester, s, dark: dark));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  // Captures at the approved preview frame (390 pt, 1.5x).
  for (final s in _shots) {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('${s.name}_$theme (approved: ${s.preview}_$theme)', (tester) async {
        _frame(tester, Size(390, s.height), 1.5);
        await withClock(Clock.fixed(_now), () => _pumpShot(tester, s, dark: dark));
        expect(tester.takeException(), isNull);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/artisan/${s.name}_$theme.png'));
      });
    }
  }

  // Tablet: My Jobs becomes a pipeline board at >= 900 px.
  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('my_jobs_tablet_$theme (approved: ar03t_my_jobs_tablet_$theme)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1024, 740);
      addTearDown(tester.view.reset);
      await withClock(Clock.fixed(_now), () => _pumpShot(tester, _Shot('my_jobs_tablet', 'ar03t_my_jobs_tablet', 740, () => const ArtisanShell(initialTab: ArtisanTab.myJobs)), dark: dark));
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/artisan/my_jobs_tablet_$theme.png'));
    });
  }
}
