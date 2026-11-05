// Stage 8.2 visual QA (design/STAGE8_2_VISUAL_QA_REPORT.md): the rebuilt
// admin dashboard (desktop / tablet / phone), Settings pages, Support
// Centre, About and customer My Chats, in light and dark, with real fonts
// and a fixed clock. A responsive sweep fails on any overflow.
//   flutter test test_visual/stage8_2_visual_test.dart --update-goldens
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:handy_trust/models/admin_audit_log_model.dart';
import 'package:handy_trust/models/artisan_model.dart';
import 'package:handy_trust/models/dispute_model.dart';
import 'package:handy_trust/models/finance_record.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/message_model.dart';
import 'package:handy_trust/models/notification_model.dart';
import 'package:handy_trust/models/payment_model.dart';
import 'package:handy_trust/models/quote_model.dart';
import 'package:handy_trust/models/review_model.dart';
import 'package:handy_trust/models/support_ticket_model.dart';
import 'package:handy_trust/models/user_model.dart';
import 'package:handy_trust/models/verification_model.dart';
import 'package:handy_trust/providers/admin_provider.dart';
import 'package:handy_trust/providers/artisan_provider.dart';
import 'package:handy_trust/providers/auth_provider.dart';
import 'package:handy_trust/providers/chat_provider.dart';
import 'package:handy_trust/providers/connectivity_provider.dart';
import 'package:handy_trust/providers/dispute_provider.dart';
import 'package:handy_trust/providers/escrow_provider.dart';
import 'package:handy_trust/providers/notification_provider.dart';
import 'package:handy_trust/providers/platform_config_provider.dart';
import 'package:handy_trust/providers/quote_provider.dart';
import 'package:handy_trust/providers/review_provider.dart';
import 'package:handy_trust/providers/support_ticket_provider.dart';
import 'package:handy_trust/providers/verification_provider.dart';
import 'package:handy_trust/ui/admin/admin_finance_compliance.dart';
import 'package:handy_trust/ui/admin/admin_operations.dart';
import 'package:handy_trust/ui/admin/admin_overview.dart';
import 'package:handy_trust/ui/admin/admin_people.dart';
import 'package:handy_trust/ui/admin/admin_shell.dart';
import 'package:handy_trust/ui/screens/messages_screen.dart';
import 'package:handy_trust/ui/settings/help_screens.dart';
import 'package:handy_trust/ui/settings/settings_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUser implements User {
  _FakeUser(this.uid);
  @override
  final String uid;
  @override
  String? get email => 'ada@example.com';
  @override
  bool get isAnonymous => false;
  @override
  bool get emailVerified => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _now = DateTime(2026, 11, 5, 10, 14);
DateTime _ago({int d = 0, int h = 0, int m = 0}) => _now.subtract(Duration(days: d, hours: h, minutes: m));

UserModel _u(String uid, String name, {List<String> roles = const ['customer'], String role = 'customer', int joinedDaysAgo = 30, String? status}) => UserModel(
      uid: uid,
      name: name,
      email: '${name.split(' ').first.toLowerCase()}@example.com',
      username: name.split(' ').first.toLowerCase(),
      roles: roles,
      activeRole: role,
      accountStatus: status ?? 'active',
      suspensionType: status == 'suspended' ? 'administrative' : null,
      createdAt: _ago(d: joinedDaysAgo),
    );

final _me = _u('adm', 'Ada Okafor', roles: const ['customer', 'artisan'], role: 'customer', joinedDaysAgo: 400);
final _users = [
  _u('c1', 'Funke Adeyemi', joinedDaysAgo: 2),
  _u('a1', 'Tunde Balogun', roles: const ['artisan'], role: 'artisan', joinedDaysAgo: 40),
  _u('c2', 'Emeka Okafor', joinedDaysAgo: 9, status: 'suspended'),
  _u('a2', 'Aisha Bello', roles: const ['customer', 'artisan'], role: 'artisan', joinedDaysAgo: 4),
  _u('c3', 'Kunle Ade', joinedDaysAgo: 120),
];

ArtisanModel _a(String uid, String name, {String category = 'Plumbing', double rating = 4.7, int ratings = 21, double trust = 84, String approval = 'approved'}) => ArtisanModel(
      uid: uid,
      name: name,
      createdAt: _ago(d: 40),
      category: category,
      rating: rating,
      totalRatings: ratings,
      completedJobs: ratings + 3,
      trustScore: trust,
      isAvailable: true,
      approvalStatus: approval,
      verificationStatus: 'id_verified',
      responseTimeMinutes: 95,
      skills: 'Pipe fitting, leak repair, water heaters',
      bio: 'Nine years fixing plumbing across Ibadan.',
    );

JobModel _j(String id, JobStatus s, String desc, {String artisan = '', String customer = 'c1', double? amount, String category = 'Plumbing', int createdDaysAgo = 1, DateTime? escrow}) => JobModel(
      id: id,
      customerId: customer,
      artisanId: artisan,
      category: category,
      description: desc,
      status: s,
      agreedAmount: amount,
      escrowLockedAt: escrow,
      paymentReference: escrow == null ? null : 'ref_$id',
      areaLabel: 'Bodija, Ibadan',
      createdAt: _ago(d: createdDaysAgo),
    );

final _jobs = [
  _j('job0B8491', JobStatus.inProgress, 'Repaint living room', artisan: 'a1', amount: 85000, category: 'Painting', escrow: _ago(d: 3)),
  _j('job3A9115', JobStatus.disputed, 'Replace bathroom tap', artisan: 'a1', customer: 'c3', amount: 24500, escrow: _ago(d: 6)),
  _j('job5D7720', JobStatus.requested, 'Kitchen sink leak under the cabinet', createdDaysAgo: 0),
  _j('job7C2210', JobStatus.completed, 'Install outdoor tap', artisan: 'a2', amount: 32000, escrow: _ago(d: 12), createdDaysAgo: 14),
  _j('job9E1200', JobStatus.inChat, 'Wire a new socket', artisan: 'a2', category: 'Electrical', createdDaysAgo: 2),
  _j('job2F4410', JobStatus.requested, 'Fix wardrobe door', category: 'Carpentry', createdDaysAgo: 3),
];

List<Override> _overrides() => [
      authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(_FakeUser('adm'))),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(_me)),
      isAdminProvider.overrideWith((ref) => Stream.value(true)),
      platformConfigProvider.overrideWithValue(const PlatformConfig()),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      unreadNotificationCountProvider.overrideWith((ref) => Stream.value(0)),
      userNotificationsProvider.overrideWith((ref) => Stream.value(const <NotificationModel>[])),
      // Admin data
      adminTotalsProvider.overrideWith((ref) async => const AdminTotals(users: 1284, artisans: 312, jobs: 6, admins: 2)),
      adminUsersProvider.overrideWith((ref) => Stream.value(_users)),
      adminJobsProvider.overrideWith((ref) => Stream.value(_jobs)),
      adminArtisansProvider.overrideWith((ref) => Stream.value([_a('a1', 'Tunde Balogun'), _a('a2', 'Aisha Bello', category: 'Electrical', rating: 4.9, ratings: 34, trust: 91)])),
      adminPendingArtisansProvider.overrideWith((ref) => Stream.value([_a('a3', 'Kola Ade', category: 'Carpentry', approval: 'pending', ratings: 0, trust: 20)])),
      adminDeletionRequestsProvider.overrideWith((ref) => Stream.value([
            {'uid': 'c3', 'status': 'pending', 'reason': 'I no longer use the app', 'requestedAt': Timestamp.fromDate(_ago(d: 1))},
          ])),
      adminAlertsProvider.overrideWith((ref) => Stream.value([
            {'id': 'al1', 'type': 'refund_failed', 'refundId': 'RF-20931', 'jobId': 'job0B8491', 'resolved': false, 'createdAt': Timestamp.fromDate(_ago(h: 2))},
            {'id': 'al2', 'type': 'chargeback_after_payout', 'jobId': 'job7C2210', 'resolved': false, 'createdAt': Timestamp.fromDate(_ago(h: 5))},
            {'id': 'al3', 'type': 'refund_held_chargeback', 'jobId': 'job3A9115', 'resolved': false, 'createdAt': Timestamp.fromDate(_ago(d: 1))},
          ])),
      adminPaymentsProvider.overrideWith((ref) => Stream.value([
            PaymentModel(id: 'p1', jobId: 'job0B8491', payerId: 'c1', artisanId: 'a1', amount: 85000, totalCharged: 89250, status: PaymentStatus.escrowHeld, createdAt: _ago(d: 3)),
            PaymentModel(id: 'p2', jobId: 'job3A9115', payerId: 'c3', artisanId: 'a1', amount: 24500, totalCharged: 25725, status: PaymentStatus.escrowHeld, createdAt: _ago(d: 6)),
          ])),
      adminDisputesProvider.overrideWith((ref) => Stream.value([
            DisputeModel(id: 'd1', jobId: 'job3A9115', raisedBy: 'c3', againstUserId: 'a1', reason: 'The tap still drips after the replacement.', createdAt: _ago(d: 2)),
          ])),
      adminVerificationsProvider.overrideWith((ref) => Stream.value([
            const VerificationModel(uid: 'a1', selfieUrl: 's', governmentIdUrl: 'g', status: VerificationStatus.approved),
            const VerificationModel(uid: 'a2', selfieUrl: 's', governmentIdUrl: 'g', status: VerificationStatus.approved),
            const VerificationModel(uid: 'a4', selfieUrl: 's', governmentIdUrl: 'g', status: VerificationStatus.rejected),
          ])),
      adminAuditLogsProvider.overrideWith((ref) => Stream.value([
            AdminAuditLogModel(id: 'l1', action: AdminAction.adminOverride, actionId: 'disputeResolved', adminId: 'adm', targetId: 'job3A9115', targetType: 'job', timestamp: _ago(h: 1), metadata: const {'reason': 'Work partly completed'}),
            AdminAuditLogModel(id: 'l2', action: AdminAction.verificationApproved, actionId: 'verificationApproved', adminId: 'adm', targetId: 'a2', targetType: 'verification', timestamp: _ago(h: 3)),
            AdminAuditLogModel(id: 'l3', action: AdminAction.userSuspended, actionId: 'userSuspended', adminId: 'adm', targetId: 'c2', targetType: 'user', timestamp: _ago(d: 1)),
          ])),
      adminPeopleNamesProvider.overrideWith((ref, k) async => {for (final u in [..._users, _me]) u.uid: u.name}),
      adminFinanceProvider.overrideWith((ref, k) => Stream.value(switch (k) {
            FinanceKind.chargebacks => [
                FinanceRecord(k, 'CB-81273', {'status': 'open', 'chargedAmountKobo': 8925000, 'jobId': 'job0B8491', 'payoutStateAtOpen': 'paid_out', 'createdAt': Timestamp.fromDate(_ago(d: 2))}),
                FinanceRecord(k, 'CB-80911', {'status': 'open', 'investigationStatus': 'investigating', 'chargedAmountKobo': 2572500, 'jobId': 'job3A9115', 'payoutStateAtOpen': 'in_escrow', 'createdAt': Timestamp.fromDate(_ago(d: 5))}),
                FinanceRecord(k, 'CB-79002', {'status': 'closed', 'outcome': 'merchant_won', 'chargedAmountKobo': 4200000, 'jobId': 'job7C2210', 'payoutStateAtOpen': 'released', 'createdAt': Timestamp.fromDate(_ago(d: 14))}),
              ],
            FinanceKind.refunds => [FinanceRecord(k, 'RF-20931', {'status': 'failed', 'kind': 'charge_refund', 'amountKobo': 2572500, 'attempts': 2, 'jobId': 'job3A9115', 'createdAt': Timestamp.fromDate(_ago(d: 1))})],
            _ => const <FinanceRecord>[],
          })),
      pendingVerificationsProvider.overrideWith((ref) => Stream.value(const [VerificationModel(uid: 'a3', selfieUrl: '', governmentIdUrl: '', status: VerificationStatus.pending)])),
      openDisputesProvider.overrideWith((ref) => Stream.value([DisputeModel(id: 'd1', jobId: 'job3A9115', raisedBy: 'c3', againstUserId: 'a1', reason: 'x', createdAt: _ago(d: 2))])),
      allTicketsProvider.overrideWith((ref) => Stream.value([SupportTicketModel(id: 't9', userId: 'c1', userName: 'Funke Adeyemi', subject: 'Payment not showing', message: 'I paid but it does not show.', status: 'open', createdAt: _ago(h: 6))])),
      allReviewsProvider.overrideWith((ref) => Stream.value([ReviewModel(id: 'r1', jobId: 'job7C2210', customerId: 'c1', artisanId: 'a2', rating: 5, comment: 'Quick and tidy.', createdAt: _ago(d: 10))])),
      jobQuotesProvider.overrideWith((ref, id) => Stream.value(const <QuoteModel>[])),
      jobPrivateLocationProvider.overrideWith((ref, id) => Stream.value({'customerAddress': '12 Awolowo Avenue, Bodija, Ibadan'})),
      jobStreamProvider.overrideWith((ref, id) => Stream.value(_jobs.where((j) => j.id == id).firstOrNull)),
      artisanProfileProvider.overrideWith((ref, id) => Stream.value(_a(id, {'a1': 'Tunde Balogun', 'a2': 'Aisha Bello', 'a5': 'Kola Ade'}[id] ?? 'Artisan'))),
      // Settings / support
      userTicketsProvider.overrideWith((ref, id) => Stream.value([
            SupportTicketModel(id: 't1', userId: 'adm', userName: 'Ada', subject: 'Payment not showing', message: 'I paid for job #HT-0B8491 but it still says awaiting payment.', status: 'resolved', adminResponse: 'Thanks, it’s fixed on our side.', createdAt: _ago(d: 3)),
            SupportTicketModel(id: 't2', userId: 'adm', userName: 'Ada', subject: 'Change my phone number', message: 'Please update my number.', status: 'open', createdAt: _ago(d: 1)),
          ])),
      // Customer My Chats
      customerJobsProvider.overrideWith((ref, id) => Stream.value([
            _j('job0B8491', JobStatus.inProgress, 'Repaint living room', customer: 'adm', artisan: 'a1', amount: 85000, escrow: _ago(d: 3)),
            _j('job5D7720', JobStatus.requested, 'Kitchen sink leak under the cabinet', customer: 'adm'),
          ])),
      jobCounterpartsProvider.overrideWith((ref, k) => Stream.value(k.jobId == 'job5D7720' ? {'a2', 'a5'} : <String>{})),
      lastMessageProvider.overrideWith((ref, k) => Stream.value(switch (k.otherPartyId) {
            'a1' => MessageModel(id: 'm1', jobId: k.jobId, senderId: 'adm', receiverId: 'a1', text: 'Great, see you at 9.', isRead: true, createdAt: _ago(m: 40)),
            'a2' => MessageModel(id: 'm2', jobId: k.jobId, senderId: 'a2', receiverId: 'adm', text: 'I can come this afternoon to take a look.', createdAt: _ago(m: 12)),
            _ => null,
          })),
      pairUnreadCountProvider.overrideWith((ref, k) => Stream.value(k.otherPartyId == 'a2' ? 2 : 0)),
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

Widget _section(AdminSection s) => switch (s) {
      AdminSection.dashboard => const AdminDashboardSection(),
      AdminSection.analytics => const AdminAnalyticsSection(),
      AdminSection.users => const AdminUsersSection(),
      AdminSection.artisans => const AdminArtisansSection(),
      AdminSection.verifications => const AdminVerificationsSection(),
      AdminSection.jobs => const AdminJobsSection(),
      AdminSection.disputes => const AdminDisputesSection(),
      AdminSection.support => const AdminSupportSection(),
      AdminSection.reviews => const AdminReviewsSection(),
      AdminSection.deletions => const AdminDeletionsSection(),
      AdminSection.finance => const AdminFinanceSection(),
      AdminSection.auditLogs => const AdminAuditLogsSection(),
      AdminSection.settings => const AdminSettingsSection(),
    };

GoRouter _router(String initial) => GoRouter(initialLocation: initial, routes: [
      ShellRoute(builder: (_, _, child) => AdminShell(child: child), routes: [
        for (final s in AdminSection.values) GoRoute(path: s.path, builder: (_, _) => _section(s)),
      ]),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen(), routes: [
        GoRoute(path: 'personal', builder: (_, _) => const PersonalInfoScreen()),
        GoRoute(path: 'notifications', builder: (_, _) => const NotificationPreferencesScreen()),
        GoRoute(path: 'security', builder: (_, _) => const SecurityScreen()),
      ]),
      GoRoute(path: '/support', builder: (_, _) => const SupportCentreScreen()),
      GoRoute(path: '/about', builder: (_, _) => const AboutHandyTrustScreen()),
      GoRoute(path: '/my-chats', builder: (_, _) => const CustomerMessagesScreen()),
    ]);

class _Shot {
  const _Shot(this.name, this.path, this.size, {this.tap, this.dpr = 1.0});
  final String name;
  final String path;
  final Size size;
  final String? tap;
  final double dpr;
}

const _desktop = Size(1440, 900);
const _phone = Size(390, 844);

final _shots = <_Shot>[
  const _Shot('admin_dashboard_desktop', '/admin/dashboard', Size(1440, 1300)),
  const _Shot('admin_dashboard_tablet', '/admin/dashboard', Size(900, 1700)),
  const _Shot('admin_dashboard_phone', '/admin/dashboard', Size(390, 2400), dpr: 1.5),
  const _Shot('admin_analytics', '/admin/analytics', _desktop),
  const _Shot('admin_users', '/admin/users?focus=c2', _desktop),
  const _Shot('admin_artisans', '/admin/artisans', _desktop),
  const _Shot('admin_jobs', '/admin/jobs?focus=job3A9115', Size(1440, 1000)),
  const _Shot('admin_disputes', '/admin/disputes', _desktop),
  const _Shot('admin_support', '/admin/support', _desktop),
  const _Shot('admin_deletions', '/admin/deletions', _desktop),
  const _Shot('admin_finance', '/admin/finance', _desktop, tap: 'CB-80911'),
  const _Shot('admin_audit_logs', '/admin/audit-logs', _desktop),
  const _Shot('admin_settings', '/admin/settings', _desktop),
  const _Shot('settings', '/settings', Size(390, 1150), dpr: 1.5),
  const _Shot('settings_personal', '/settings/personal', _phone, dpr: 1.5),
  const _Shot('settings_notifications', '/settings/notifications', _phone, dpr: 1.5),
  const _Shot('settings_security', '/settings/security', Size(390, 1100), dpr: 1.5),
  const _Shot('support_centre', '/support', Size(390, 1700), dpr: 1.5, tap: 'Payments'),
  const _Shot('about', '/about', Size(390, 1150), dpr: 1.5),
  const _Shot('customer_my_chats', '/my-chats', _phone, dpr: 1.5),
];

Future<void> _pump(WidgetTester t, String path, {required bool dark, String? tap}) async {
  await withClock(Clock.fixed(_now), () async {
    await t.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: _overrides(),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, useMaterial3: true),
        routerConfig: _router(path),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    if (tap != null) {
      await t.tap(find.text(tap).first);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
    await _loadFonts();
  });

  // Responsive sweep: phone screens at 320/360/430, admin at 390/768/1024/1440.
  const phoneSizes = [Size(320, 640), Size(360, 780), Size(430, 932)];
  const adminSizes = [Size(390, 900), Size(768, 1024), Size(1024, 900), Size(1440, 900)];
  for (final s in _shots) {
    final isAdmin = s.path.startsWith('/admin');
    for (final dark in [false, true]) {
      for (final size in isAdmin ? adminSizes : phoneSizes) {
        testWidgets('layout ${s.name} ${dark ? 'dark' : 'light'} @ ${size.width.toInt()}', (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = size;
          addTearDown(t.view.reset);
          await _pump(t, s.path, dark: dark);
          expect(t.takeException(), isNull);
        });
      }
    }
  }

  for (final s in _shots) {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('${s.name}_$theme', (t) async {
        t.view.devicePixelRatio = s.dpr;
        t.view.physicalSize = s.size * s.dpr;
        addTearDown(t.view.reset);
        await _pump(t, s.path, dark: dark, tap: s.tap);
        expect(t.takeException(), isNull);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/stage8_2/${s.name}_$theme.png'));
      });
    }
  }
}
