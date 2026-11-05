// Stage 8 visual QA harness (design/STAGE8_VISUAL_QA_REPORT.md).
//
// Renders every Stitch-designed screen in light and dark at the pixel size
// of its reference image and writes the screenshot to
// test_visual/goldens/. Run:
//   flutter test test_visual --update-goldens   (capture)
//   flutter test test_visual                    (regression compare)
// ignore_for_file: invalid_use_of_visible_for_testing_member
// (test_visual/ is a test directory run explicitly; not part of lib/.)
//
// Fixture data below is TEST-ONLY and mirrors the reference content so the
// screenshots are comparable; it is never used by the app.
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/paystack_service.dart';
import 'package:handy_trust/models/artisan_model.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/message_model.dart';
import 'package:handy_trust/models/notification_model.dart';
import 'package:handy_trust/models/payment_model.dart';
import 'package:handy_trust/models/quote_model.dart';
import 'package:handy_trust/models/review_model.dart';
import 'package:handy_trust/models/user_model.dart';
import 'package:handy_trust/models/verification_model.dart';
import 'package:handy_trust/providers/artisan_provider.dart';
import 'package:handy_trust/providers/auth_provider.dart';
import 'package:handy_trust/providers/chat_provider.dart';
import 'package:handy_trust/providers/escrow_provider.dart';
import 'package:handy_trust/providers/favorites_provider.dart';
import 'package:handy_trust/providers/notification_provider.dart';
import 'package:handy_trust/providers/payment_provider.dart';
import 'package:handy_trust/providers/paystack_provider.dart';
import 'package:handy_trust/providers/platform_config_provider.dart';
import 'package:handy_trust/providers/portfolio_provider.dart';
import 'package:handy_trust/providers/quote_provider.dart';
import 'package:handy_trust/providers/review_provider.dart';
import 'package:handy_trust/providers/verification_provider.dart';
import 'package:handy_trust/ui/screens/artisan_profile_screen.dart';
import 'package:handy_trust/ui/screens/chat_screen.dart';
import 'package:handy_trust/ui/screens/confirm_pay_screen.dart';
import 'package:handy_trust/ui/screens/customer_shell.dart';
import 'package:handy_trust/ui/screens/notifications_screen.dart';
import 'package:handy_trust/ui/screens/onboarding_screen.dart';
import 'package:handy_trust/ui/screens/post_job_screen.dart';
import 'package:handy_trust/ui/screens/verification_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUser implements User {
  @override
  String get uid => 'cust1';
  @override
  String? get email => 'daniel@example.com';
  @override
  bool get isAnonymous => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Fixed (reference "Today, Oct 24") so screenshots are reproducible.
final _now = DateTime(2026, 10, 24, 10, 14);

ArtisanModel _artisan(String uid, String name, String category, double rating, int jobs) => ArtisanModel(
      uid: uid,
      name: name,
      createdAt: DateTime(2025, 1, 1),
      category: category,
      serviceAddress: 'Bodija, Ibadan',
      rating: rating,
      totalRatings: 42,
      totalJobs: jobs + 4,
      completedJobs: jobs,
      trustScore: 92,
      isAvailable: true,
      verificationStatus: 'id_verified',
      approvalStatus: 'approved',
      bio: 'Certified master electrician specializing in residential wiring, solar inverter setups, and electrical fault troubleshooting across Ibadan.',
      skills: 'Wiring & conduit piping, Fault repair & diagnostics, Inverter & backup setup',
    );

final _artisans = [
  _artisan('art1', 'Emeka Okafor', 'Electrical', 4.9, 128),
  _artisan('art2', 'Funke Adeyemi', 'Painting', 4.8, 94),
  _artisan('art3', 'Tunde Balogun', 'Plumbing', 4.9, 211),
];
final _byId = {for (final a in _artisans) a.uid: a};

final _user = UserModel(uid: 'cust1', name: 'Daniel R.', email: 'daniel@example.com', location: 'Bodija, Ibadan', roles: const ['customer'], activeRole: 'customer', createdAt: DateTime(2025, 1, 1));

final _jobs = [
  JobModel(
    id: 'job8402',
    customerId: 'cust1',
    artisanId: 'art2',
    category: 'Painting',
    description: 'Repaint living room',
    status: JobStatus.inProgress,
    agreedAmount: 85000,
    areaLabel: 'Bodija, Ibadan',
    createdAt: _now.subtract(const Duration(days: 2)),
  ),
  JobModel(
    id: 'job9110',
    customerId: 'cust1',
    artisanId: '',
    category: 'Electrical',
    description: 'Fix kitchen socket',
    status: JobStatus.requested,
    budgetMin: 12000,
    budgetMax: 12000,
    areaLabel: 'Ring Road, Ibadan',
    createdAt: _now.subtract(const Duration(days: 1)),
  ),
];

final _payJob = JobModel(
  id: 'job8491',
  customerId: 'cust1',
  artisanId: 'art2',
  category: 'Painting',
  description: 'Repaint living room',
  status: JobStatus.inChat,
  agreedAmount: 85000,
  agreementStatus: AgreementStatus.confirmed,
  areaLabel: 'Bodija, Ibadan',
  urgency: 'asap',
  createdAt: _now,
);

final _payments = [
  PaymentModel(id: 'p1', jobId: 'job8402', payerId: 'cust1', artisanId: 'art2', amount: 85000, platformFee: 4250, totalCharged: 89250, status: PaymentStatus.escrowHeld, createdAt: _now),
  PaymentModel(id: 'p2', jobId: 'old1', payerId: 'cust1', artisanId: 'art3', amount: 12000, platformFee: 600, totalCharged: 12600, status: PaymentStatus.released, createdAt: _now.subtract(const Duration(days: 9))),
];

final _notifications = [
  NotificationModel(id: 'n1', userId: 'cust1', type: 'job_status_update', title: 'Booking Confirmed', body: 'Funke Adeyemi confirmed your booking for "Repaint living room".', isRead: false, jobId: 'job8402', createdAt: _now.subtract(const Duration(minutes: 10))),
  NotificationModel(id: 'n2', userId: 'cust1', type: 'job_status_update', title: '₦85,000 secured in escrow', body: 'Your payment is held safely in escrow for Repaint living room.', isRead: false, jobId: 'job8402', createdAt: _now.subtract(const Duration(hours: 2))),
  NotificationModel(id: 'n3', userId: 'cust1', type: 'payout_completed', title: 'Payment released to Tunde', body: '₦12,000 released for "Fix ceiling fan" completion.', isRead: true, jobId: 'old1', createdAt: _now.subtract(const Duration(days: 2))),
];

final _messages = [
  MessageModel(id: 'm1', jobId: 'job8402', senderId: 'cust1', receiverId: 'art2', text: 'Good morning Funke, we decided on the Warm Olive and Soft Off-White for the living room.', isRead: true, createdAt: _now.subtract(const Duration(minutes: 30))),
  MessageModel(id: 'm2', jobId: 'job8402', senderId: 'art2', receiverId: 'cust1', text: 'Good morning! Perfect choice. Can I come by tomorrow at 9:00 AM to start prepping the walls?', isRead: true, createdAt: _now.subtract(const Duration(minutes: 28))),
  MessageModel(id: 'm3', jobId: 'job8402', senderId: 'cust1', receiverId: 'art2', text: 'Yes, tomorrow 9:00 AM works perfectly. The paint cans are already on-site.', isRead: true, createdAt: _now.subtract(const Duration(minutes: 26))),
];

List<Override> _overrides({CustomerTab tab = CustomerTab.discovery}) => [
      authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(_FakeUser())),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(_user)),
      isAdminProvider.overrideWith((ref) => Stream.value(false)),
      unreadNotificationCountProvider.overrideWith((ref) => Stream.value(2)),
      featuredArtisansProvider.overrideWith((ref) => Stream.value(_artisans)),
      customerJobsProvider.overrideWith((ref, uid) => Stream.value(_jobs)),
      artisanProfileProvider.overrideWith((ref, id) => Stream.value(_byId[id])),
      jobQuotesProvider.overrideWith((ref, id) => Stream.value(const <QuoteModel>[])),
      customerPaymentsProvider.overrideWith((ref, uid) => Stream.value(_payments)),
      userNotificationsProvider.overrideWith((ref) => Stream.value(_notifications)),
      artisanReviewListProvider.overrideWith((ref, id) => Stream.value([
            ReviewModel(id: 'r1', jobId: 'j1', customerId: 'c', artisanId: id, rating: 5, comment: 'Fixed our inverter setup quickly and cleanly. Kept the wiring neat and explained maintenance tips thoroughly!', createdAt: _now.subtract(const Duration(days: 2))),
            ReviewModel(id: 'r2', jobId: 'j2', customerId: 'c', artisanId: id, rating: 5, comment: 'Diagnosed the short circuit that two other electricians missed in less than 30 minutes.', createdAt: _now.subtract(const Duration(days: 7))),
          ])),
      portfolioProjectsProvider.overrideWith((ref, id) => Stream.value(const [])),
      favoriteIdsProvider.overrideWith((ref, uid) => Stream.value(const <String>{})),
      jobStreamProvider.overrideWith((ref, id) => Stream.value(id == _payJob.id ? _payJob : _jobs.first)),
      paymentBreakdownProvider.overrideWith((ref, id) async =>
          const PaymentBreakdown(serviceAmount: 85000, platformFee: 4250, totalCharged: 89250, platformFeePercent: 5)),
      messagesStreamProvider.overrideWith((ref, key) => Stream.value(_messages)),
      verificationStatusProvider.overrideWith((ref, uid) => Stream.value(const VerificationModel(uid: 'cust1', selfieUrl: 's', governmentIdUrl: 'g', status: VerificationStatus.pending))),
      platformConfigProvider.overrideWithValue(const PlatformConfig()),
      customerTabProvider.overrideWith((ref) => tab),
    ];

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

/// (screen key, reference image, reference pixel width, height, builder)
class _Shot {
  const _Shot(this.name, this.ref, this.width, this.height, this.builder, {this.tab = CustomerTab.discovery});
  final String name;
  final int ref;
  final int width;
  final int height;
  final Widget Function() builder;
  final CustomerTab tab;
}

final _shots = <_Shot>[
  _Shot('discovery_dark', 8, 390, 1340, () => const CustomerShell()),
  _Shot('discovery_light', 15, 512, 1600, () => const CustomerShell()),
  _Shot('artisan_profile_dark', 2, 539, 1600, () => const ArtisanProfileScreen(artisanId: 'art1')),
  _Shot('artisan_profile_light', 16, 515, 1485, () => const ArtisanProfileScreen(artisanId: 'art1')),
  _Shot('post_job_dark', 3, 602, 1600, () => const PostJobScreen()),
  _Shot('post_job_light', 17, 515, 1386, () => const PostJobScreen()),
  _Shot('bookings_dark', 4, 612, 1600, () => const CustomerShell(), tab: CustomerTab.bookings),
  _Shot('bookings_light', 19, 561, 1600, () => const CustomerShell(), tab: CustomerTab.bookings),
  _Shot('payments_dark', 5, 540, 1600, () => const CustomerShell(), tab: CustomerTab.wallet),
  _Shot('payments_light', 21, 597, 1600, () => const CustomerShell(), tab: CustomerTab.wallet),
  _Shot('profile_dark', 6, 424, 1600, () => const CustomerShell(), tab: CustomerTab.profile),
  _Shot('profile_light', 22, 467, 1600, () => const CustomerShell(), tab: CustomerTab.profile),
  _Shot('verification_dark', 7, 574, 1600, () => const VerificationScreen()),
  _Shot('verification_light', 23, 651, 1600, () => const VerificationScreen()),
  _Shot('confirm_pay_dark', 10, 495, 1600, () => const ConfirmPayScreen(jobId: 'job8491')),
  _Shot('confirm_pay_light', 18, 706, 1600, () => const ConfirmPayScreen(jobId: 'job8491')),
  _Shot('chat_dark', 11, 554, 1600, () => const ChatScreen(jobId: 'job8402', otherUserId: 'art2')),
  _Shot('chat_light', 20, 506, 1600, () => const ChatScreen(jobId: 'job8402', otherUserId: 'art2')),
  _Shot('notifications_dark', 12, 615, 1600, () => const NotificationsScreen()),
  _Shot('notifications_light', 24, 706, 1600, () => const NotificationsScreen()),
  _Shot('onboarding_dark', 13, 490, 1050, () => const OnboardingScreen()),
  _Shot('onboarding_light', 14, 706, 1600, () => const OnboardingScreen()),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
    await _loadFonts();
  });

  // Responsive sweep: every designed screen, both themes, small to large
  // phones. Fails on any overflow / layout exception.
  const sizes = [Size(320, 568), Size(360, 780), Size(430, 932)];
  for (final s in _shots) {
    for (final size in sizes) {
      testWidgets('layout ${s.name} @ ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = size * 2;
        tester.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
        tester.view.viewPadding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
        addTearDown(tester.view.reset);
        final dark = s.name.endsWith('_dark');
        await tester.pumpWidget(ProviderScope(
          overrides: _overrides(tab: s.tab),
          child: MaterialApp(
            theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, useMaterial3: true),
            home: s.builder(),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final s in _shots) {
    testWidgets('${s.name} (reference #${s.ref})', (tester) async {
      final dpr = s.width / 390.0;
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = Size(s.width.toDouble(), s.height.toDouble());
      tester.view.padding = FakeViewPadding(top: 47 * dpr, bottom: 34 * dpr);
      tester.view.viewPadding = FakeViewPadding(top: 47 * dpr, bottom: 34 * dpr);
      addTearDown(tester.view.reset);
      final dark = s.name.endsWith('_dark');
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(tab: s.tab),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, useMaterial3: true),
          home: s.builder(),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Asset images decode asynchronously in widget tests: precache, then repaint.
      await tester.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          await precacheImage((e.widget as Image).image, e);
        }
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${s.name}.png'));
    });
  }
}
