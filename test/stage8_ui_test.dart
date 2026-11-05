// Stage 8 — UI replacement: presentation logic, safety guards and screen
// behaviour (design/STAGE8_COMPLETION_REPORT.md). Fixtures are test-only.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/customer_booking_logic.dart';
import 'package:handy_trust/core/services/notification_category.dart';
import 'package:handy_trust/core/services/payment_summary.dart';
import 'package:handy_trust/core/services/paystack_service.dart';
import 'package:handy_trust/models/artisan_model.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/notification_model.dart';
import 'package:handy_trust/models/payment_model.dart';
import 'package:handy_trust/models/quote_model.dart';
import 'package:handy_trust/models/user_model.dart';
import 'package:handy_trust/providers/artisan_provider.dart';
import 'package:handy_trust/providers/auth_provider.dart';
import 'package:handy_trust/providers/escrow_provider.dart';
import 'package:handy_trust/providers/notification_provider.dart';
import 'package:handy_trust/providers/payment_provider.dart';
import 'package:handy_trust/providers/paystack_provider.dart';
import 'package:handy_trust/providers/quote_provider.dart';
import 'package:handy_trust/ui/components/ht_components.dart';
import 'package:handy_trust/ui/components/ht_format.dart';
import 'package:handy_trust/ui/screens/bookings_screen.dart';
import 'package:handy_trust/ui/screens/confirm_pay_screen.dart';
import 'package:handy_trust/ui/screens/discovery_screen.dart';
import 'package:handy_trust/ui/screens/notifications_screen.dart';
import 'package:handy_trust/ui/screens/payments_screen.dart';
import 'package:handy_trust/ui/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUser implements User {
  _FakeUser(this.uid);
  @override
  final String uid;
  @override
  String? get email => 'c@example.com';
  @override
  bool get isAnonymous => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

JobModel _job(String id, JobStatus status, {double? agreed, String artisanId = 'a1', AgreementStatus? agreement}) => JobModel(
      id: id,
      customerId: 'c1',
      artisanId: artisanId,
      category: 'Painting',
      description: 'Repaint living room',
      status: status,
      agreedAmount: agreed,
      agreementStatus: agreement,
      urgency: 'asap',
      createdAt: DateTime(2026, 11, 1),
    );

PaymentModel _pay(String id, PaymentStatus s, double total) =>
    PaymentModel(id: id, jobId: 'j', payerId: 'c1', artisanId: 'a1', amount: total / 1.05, totalCharged: total, status: s, createdAt: DateTime(2026, 11, 1));

final _artisan = ArtisanModel(uid: 'a1', name: 'Funke Adeyemi', createdAt: DateTime(2025), category: 'Painting', verificationStatus: 'id_verified', approvalStatus: 'approved');

Widget _app(Widget child, List<Override> overrides) => ProviderScope(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(_FakeUser('c1'))),
        unreadNotificationCountProvider.overrideWith((ref) => Stream.value(0)),
        artisanProfileProvider.overrideWith((ref, id) => Stream.value(_artisan)),
        jobQuotesProvider.overrideWith((ref, id) => Stream.value(const <QuoteModel>[])),
        ...overrides,
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CustomerBookingLogic (server state machine → one action)', () {
    test('Approve & Release only when the artisan has submitted the work', () {
      for (final s in JobStatus.values) {
        final a = CustomerBookingLogic.actionFor(_job('j', s, agreed: 85000), 'c1');
        expect(a == CustomerBookingAction.approveAndRelease, s == JobStatus.submitted, reason: s.name);
      }
    });

    test('Pay into escrow only when the agreement is confirmed and the viewer is the customer', () {
      final ready = _job('j', JobStatus.inChat, agreed: 85000, agreement: AgreementStatus.confirmed);
      expect(CustomerBookingLogic.actionFor(ready, 'c1'), CustomerBookingAction.payIntoEscrow);
      expect(CustomerBookingLogic.actionFor(ready, 'someone-else'), isNot(CustomerBookingAction.payIntoEscrow));
      final negotiating = _job('j', JobStatus.inChat, agreed: 85000, agreement: AgreementStatus.negotiating);
      expect(CustomerBookingLogic.actionFor(negotiating, 'c1'), CustomerBookingAction.openChat);
    });

    test('tabs: disputed separate; closed jobs under Completed; no Drafts', () {
      final g = CustomerBookingLogic.group([
        _job('1', JobStatus.requested),
        _job('2', JobStatus.inProgress),
        _job('3', JobStatus.completed),
        _job('4', JobStatus.cancelled),
        _job('5', JobStatus.disputed),
      ]);
      expect(g[BookingTab.active]!.map((j) => j.id), ['1', '2']);
      expect(g[BookingTab.completed]!.map((j) => j.id), ['3', '4']);
      expect(g[BookingTab.disputed]!.map((j) => j.id), ['5']);
      expect(BookingTab.values.map((t) => t.name), isNot(contains('drafts')));
    });

    test('lifecycle: funded → in progress → verified → released', () {
      expect([JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted, JobStatus.completed].map(CustomerBookingLogic.lifecycleIndex), [0, 1, 2, 3]);
    });
  });

  group('PaymentSummary (no wallet: only real payment records)', () {
    test('held / released / refunded totals use the charged amount', () {
      final s = PaymentSummary.of([
        _pay('1', PaymentStatus.escrowHeld, 89250),
        _pay('2', PaymentStatus.released, 12600),
        _pay('3', PaymentStatus.refunded, 5250),
        _pay('4', PaymentStatus.abandoned, 9999),
      ]);
      expect(s.heldInEscrow, 89250);
      expect(s.released, 12600);
      expect(s.refunded, 5250);
      expect(s.heldCount, 1);
    });
  });

  group('NotificationCategories', () {
    NotificationModel n(String type, String title) => NotificationModel(id: 'x', userId: 'u', type: type, title: title, body: '', createdAt: DateTime(2026));
    test('payout / escrow / refund → Escrow & Pay; quotes and chat → Jobs; verification → Account', () {
      expect(NotificationCategories.of(n('payout_completed', 'Payment Sent')), NotificationCategory.escrow);
      expect(NotificationCategories.of(n('job_status_update', 'Refund Processed')), NotificationCategory.escrow);
      expect(NotificationCategories.of(n('quote_received', 'New Quote')), NotificationCategory.jobs);
      expect(NotificationCategories.of(n('job_status_update', 'Verification approved')), NotificationCategory.account);
    });
  });

  group('HtFormat', () {
    test('naira, initials, short reference, area never includes the street', () {
      expect(HtFormat.naira(89250), '₦89,250');
      expect(HtFormat.initials('Emeka Okafor'), 'EO');
      expect(HtFormat.bookingRef('abcDEF123456'), 'HT-123456');
      expect(HtFormat.area('12 Home Street, Bodija, Ibadan'), 'Bodija, Ibadan');
      expect(HtFormat.area('12 Home Street'), isNull);
    });
  });

  group('Source guards (whole new presentation layer)', () {
    final uiFiles = Directory('lib/ui').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

    test('new UI never talks to Firebase directly (providers/services only)', () {
      for (final f in uiFiles) {
        final src = f.readAsStringSync();
        for (final banned in ['FirebaseFirestore.instance', 'FirebaseFunctions.instance', 'FirebaseStorage.instance', ".collection('"]) {
          expect(src.contains(banned), isFalse, reason: '${f.path} uses $banned');
        }
      }
    });

    test('the demo/debug payment path is gone from the app', () {
      final all = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      for (final f in all) {
        final src = f.readAsStringSync();
        expect(src.contains("'/demo-payment"), isFalse, reason: f.path);
        expect(src.contains('DemoEscrowService('), isFalse, reason: f.path);
      }
      expect(File('lib/screens/payment/demo_escrow_screen.dart').existsSync(), isFalse);
    });

    test('no unsupported claims or wallet actions in the new screens', () {
      const banned = [
        'CBN', 'Multi-Sig', 'NIMC', 'BVN', 'NDPR', '99.8%', '12,400', 'Add Money', 'Withdraw', '20% Deposit',
        'Milestone 2', 'MILESTONE ESCROW', 'Biometric', '256-bit', '256-BIT', 'end-to-end', 'Tier-3', 'Tier 2',
      ];
      for (final f in uiFiles) {
        final src = f.readAsStringSync().replaceAll(RegExp(r'^\s*///.*$|^\s*//.*$', multiLine: true), '');
        // Stage 8.1: artisans really can withdraw a quote or withdraw from a
        // job (QuoteService.withdrawQuote, artisanWithdrawFromJob). There,
        // only wallet-style withdrawal wording is banned.
        final artisan = f.path.replaceAll(r'\', '/').contains('lib/ui/artisan/');
        for (final b in [
          for (final b in banned)
            if (!(artisan && b == 'Withdraw')) b,
          if (artisan) ...['Withdraw funds', 'Withdraw to', 'Withdraw earnings', 'Withdraw balance', 'Wallet balance', 'Available balance'],
        ]) {
          expect(src.contains(b), isFalse, reason: '${f.path} shows "$b"');
        }
      }
    });
  });

  group('Screens', () {
    testWidgets('Bookings: funded in-progress job offers View Details, not release', (t) async {
      await t.pumpWidget(_app(const BookingsScreen(), [
        customerJobsProvider.overrideWith((ref, uid) => Stream.value([_job('j1', JobStatus.inProgress, agreed: 85000)])),
      ]));
      await _settle(t);
      expect(find.text('Approve & Release Payment'), findsNothing);
      expect(find.text('View Details'), findsWidgets);
      expect(find.text('Stage 2 of 4'), findsOneWidget);
    });

    testWidgets('Bookings: submitted job offers Approve & Release', (t) async {
      await t.pumpWidget(_app(const BookingsScreen(), [
        customerJobsProvider.overrideWith((ref, uid) => Stream.value([_job('j1', JobStatus.submitted, agreed: 85000)])),
      ]));
      await _settle(t);
      expect(find.text('Approve & Release Payment'), findsOneWidget);
    });

    testWidgets('Payments: real escrow totals, no wallet balance, Add Money or Withdraw', (t) async {
      await t.pumpWidget(_app(const PaymentsScreen(), [
        customerJobsProvider.overrideWith((ref, uid) => Stream.value(const <JobModel>[])),
        customerPaymentsProvider.overrideWith((ref, uid) => Stream.value([_pay('p', PaymentStatus.escrowHeld, 89250)])),
      ]));
      await _settle(t);
      expect(find.textContaining('89,250'), findsWidgets);
      expect(find.textContaining('Add Money'), findsNothing);
      expect(find.textContaining('Withdraw'), findsNothing);
      expect(find.textContaining('not withdrawable'), findsOneWidget);
    });

    testWidgets('Confirm & Pay: server breakdown (5% fee), single Paystack method', (t) async {
      await t.pumpWidget(_app(const ConfirmPayScreen(jobId: 'j1'), [
        currentUserProfileProvider.overrideWith((ref) => Stream.value(UserModel(uid: 'c1', name: 'C', email: 'c@example.com', createdAt: DateTime(2025)))),
        jobStreamProvider.overrideWith((ref, id) => Stream.value(_job('j1', JobStatus.inChat, agreed: 85000, agreement: AgreementStatus.confirmed))),
        paymentBreakdownProvider.overrideWith((ref, id) async => const PaymentBreakdown(serviceAmount: 85000, platformFee: 4250, totalCharged: 89250, platformFeePercent: 5)),
      ]));
      await _settle(t);
      expect(find.text('Platform fee (5%)'), findsOneWidget);
      expect(find.text('₦4,250'), findsOneWidget);
      expect(find.text('Pay ₦89,250 Securely'), findsOneWidget);
      expect(find.textContaining('Wallet'), findsNothing);
    });

    testWidgets('Confirm & Pay: refuses before the agreement is confirmed', (t) async {
      await t.pumpWidget(_app(const ConfirmPayScreen(jobId: 'j1'), [
        currentUserProfileProvider.overrideWith((ref) => Stream.value(UserModel(uid: 'c1', name: 'C', createdAt: DateTime(2025)))),
        jobStreamProvider.overrideWith((ref, id) => Stream.value(_job('j1', JobStatus.inChat, agreed: 85000, agreement: AgreementStatus.negotiating))),
      ]));
      await _settle(t);
      expect(find.text('Not ready for payment yet'), findsOneWidget);
      expect(find.textContaining('Securely'), findsNothing);
    });

    for (final admin in [false, true]) {
      testWidgets('Profile: admin entry ${admin ? 'shown to' : 'hidden from'} ${admin ? 'admins' : 'customers'}; no role switch for single-role users', (t) async {
        t.view.physicalSize = const Size(800, 3200);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(_app(const ProfileScreen(), [
          currentUserProfileProvider.overrideWith((ref) => Stream.value(UserModel(uid: 'c1', name: 'Daniel R.', roles: const ['customer'], createdAt: DateTime(2025)))),
          isAdminProvider.overrideWith((ref) => Stream.value(admin)),
          customerJobsProvider.overrideWith((ref, uid) => Stream.value(const <JobModel>[])),
        ]));
        await _settle(t);
        expect(find.text('Admin Dashboard'), admin ? findsOneWidget : findsNothing);
        expect(find.text('Artisan Mode'), findsNothing);
        expect(find.text('Obsidian Dark Mode'), findsOneWidget);
      });
    }

    testWidgets('Discovery: category chip filters the real artisan list', (t) async {
      final electrician = ArtisanModel(uid: 'e', name: 'Emeka Okafor', createdAt: DateTime(2025), category: 'Electrical', verificationStatus: 'id_verified');
      final painter = ArtisanModel(uid: 'p', name: 'Funke Adeyemi', createdAt: DateTime(2025), category: 'Painting', verificationStatus: 'id_verified');
      await t.pumpWidget(_app(const DiscoveryScreen(), [
        currentUserProfileProvider.overrideWith((ref) => Stream.value(UserModel(uid: 'c1', name: 'Daniel', createdAt: DateTime(2025)))),
        featuredArtisansProvider.overrideWith((ref) => Stream.value([electrician, painter])),
      ]));
      await _settle(t);
      expect(find.text('Emeka Okafor'), findsOneWidget);
      expect(find.text('Funke Adeyemi'), findsOneWidget);
      await t.tap(find.widgetWithText(HtChip, 'Electrical'));
      await _settle(t);
      expect(find.text('Funke Adeyemi'), findsNothing);
      expect(find.text('Emeka Okafor'), findsOneWidget);
    });

    testWidgets('Notifications: filter tabs; mark-all disabled when nothing is unread', (t) async {
      await t.pumpWidget(_app(const NotificationsScreen(), [
        currentUserProfileProvider.overrideWith((ref) => Stream.value(UserModel(uid: 'c1', name: 'C', createdAt: DateTime(2025)))),
        userNotificationsProvider.overrideWith((ref) => Stream.value([
              NotificationModel(id: '1', userId: 'c1', type: 'payout_completed', title: 'Payment Sent', body: 'b', isRead: true, createdAt: DateTime(2026)),
              NotificationModel(id: '2', userId: 'c1', type: 'quote_received', title: 'New Quote', body: 'b', isRead: true, createdAt: DateTime(2026)),
            ])),
      ]));
      await _settle(t);
      expect(find.text('Payment Sent'), findsOneWidget);
      expect(find.text('New Quote'), findsOneWidget);
      await t.tap(find.text('Escrow & Pay'));
      await _settle(t);
      expect(find.text('New Quote'), findsNothing);
      final markAll = t.widget<TextButton>(find.ancestor(of: find.text('Mark all as read'), matching: find.byType(TextButton)));
      expect(markAll.onPressed, isNull);
    });
  });
}
