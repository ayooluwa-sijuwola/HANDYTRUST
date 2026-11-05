// Stage 8.2 — screens and flows: Settings (destinations, back navigation,
// security/password, notification preference, deletion request, mode
// switch), Support Centre, About, customer My Chats, chat read receipts,
// push registration and tap routing (logic level), admin dashboard, and the
// real app router (deep links, role and admin redirects).
// Fixtures are test-only; no Firebase. Push DELIVERY is not testable here
// and is not claimed (see design/STAGE8_2_NOTIFICATION_AUDIT.md).
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:handy_trust/core/services/admin_service.dart';
import 'package:handy_trust/core/services/auth_service.dart';
import 'package:handy_trust/core/services/chat_service.dart';
import 'package:handy_trust/core/services/profile_service.dart';
import 'package:handy_trust/core/services/support_ticket_service.dart';
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
import 'package:handy_trust/providers/payment_provider.dart';
import 'package:handy_trust/providers/platform_config_provider.dart';
import 'package:handy_trust/providers/quote_provider.dart';
import 'package:handy_trust/providers/review_provider.dart';
import 'package:handy_trust/providers/support_ticket_provider.dart';
import 'package:handy_trust/providers/verification_provider.dart';
import 'package:handy_trust/routes/router.dart';
import 'package:handy_trust/ui/admin/admin_finance_compliance.dart';
import 'package:handy_trust/ui/admin/admin_operations.dart';
import 'package:handy_trust/ui/admin/admin_overview.dart';
import 'package:handy_trust/ui/screens/chat_screen.dart';
import 'package:handy_trust/ui/screens/customer_shell.dart';
import 'package:handy_trust/ui/screens/messages_screen.dart';
import 'package:handy_trust/ui/settings/help_screens.dart';
import 'package:handy_trust/ui/settings/settings_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Fakes ──────────────────────────────────────────────────────────────────

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

/// Records every call; [failWith] makes calls throw.
class _Recorder {
  final calls = <String, List<Object?>>{};
  void add(String name, Object? args) => (calls[name] ??= []).add(args);
  int count(String name) => calls[name]?.length ?? 0;
}

class _FakeProfile implements ProfileService {
  _FakeProfile(this.r);
  final _Recorder r;
  @override
  Future<void> updatePassword({required String currentPassword, required String newPassword}) async {
    if (currentPassword == 'wrong') throw FirebaseAuthException(code: 'wrong-password');
    r.add('updatePassword', [currentPassword, newPassword]);
  }

  @override
  Future<void> requestAccountDeletion(String uid, {String? reason}) async => r.add('requestAccountDeletion', [uid, reason]);
  @override
  Future<void> setActiveRole(String uid, String role) async => r.add('setActiveRole', [uid, role]);
  @override
  Future<void> updateName(String uid, String name) async => r.add('updateName', [uid, name]);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class _FakeAuth implements AuthService {
  _FakeAuth(this.r);
  final _Recorder r;
  @override
  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async => r.add('updateUserProfile', [uid, data]);
  @override
  Future<void> sendPasswordReset(String email) async => r.add('sendPasswordReset', email);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class _FakeTickets implements SupportTicketService {
  _FakeTickets(this.r);
  final _Recorder r;
  @override
  Future<void> createTicket({required String userId, required String userName, required String subject, required String message}) async => r.add('createTicket', [userId, subject, message]);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class _FakeChat implements ChatService {
  _FakeChat(this.r);
  final _Recorder r;
  @override
  Future<void> markAllAsRead(String jobId, {required String viewerId, String? otherPartyId}) async => r.add('markAllAsRead', [jobId, viewerId, otherPartyId]);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class _FakeAdmin implements AdminService {
  _FakeAdmin(this.r);
  final _Recorder r;
  @override
  Future<void> resolveAlert(String alertId, {required String adminId}) async => r.add('resolveAlert', alertId);
  @override
  Future<void> deleteJob(JobModel job, {required String adminId}) async => r.add('deleteJob', job.id);
  @override
  Future<HeldFunds?> heldFunds(String jobId) async => const HeldFunds(26250, 25000);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class _FakePush implements PushPlatform {
  final r = _Recorder();
  final opened = StreamController<String>.broadcast();
  final refresh = StreamController<String>.broadcast();
  String? launchPayload;
  String? initial;
  void Function(String?)? localTap;
  @override
  Future<void> requestPermission() async => r.add('requestPermission', null);
  @override
  Future<String?> getToken() async => 'tok';
  @override
  Future<void> deleteToken() async => r.add('deleteToken', null);
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Future<String?> initialMessageDestination() async {
    r.add('initial', null);
    return initial;
  }

  @override
  Stream<String> get openedAppDestinations => opened.stream;
  @override
  String? takeLocalLaunchPayload() {
    final p = launchPayload;
    launchPayload = null;
    return p;
  }

  @override
  set onLocalTap(void Function(String? payload)? handler) => localTap = handler;
  @override
  void startForegroundListener(bool Function() enabled) => r.add('foreground', null);
  @override
  Future<void> saveToken(String uid, String token) async => r.add('saveToken', [uid, token]);
  @override
  Future<void> removeToken(String uid) async => r.add('removeToken', uid);
}

// ─── Fixtures ───────────────────────────────────────────────────────────────

final _t = DateTime(2026, 11, 5, 9);
UserModel _user({String uid = 'c1', List<String> roles = const ['customer'], String role = 'customer', bool notifications = true, bool deletion = false}) =>
    UserModel(uid: uid, name: 'Daniel Ade', email: '$uid@example.com', roles: roles, activeRole: role, notificationsEnabled: notifications, accountDeletionRequested: deletion, createdAt: DateTime(2025, 2, 1));

ArtisanModel _artisan(String uid, String name) => ArtisanModel(uid: uid, name: name, createdAt: DateTime(2025), category: 'Plumbing', approvalStatus: 'approved', isAvailable: true);

JobModel _job(String id, JobStatus s, {String artisan = '', String customer = 'c1', String? paymentReference, DateTime? escrowLockedAt}) => JobModel(
      id: id,
      customerId: customer,
      artisanId: artisan,
      category: 'Plumbing',
      description: 'Fix $id',
      status: s,
      agreedAmount: 25000,
      paymentReference: paymentReference,
      escrowLockedAt: escrowLockedAt,
      createdAt: _t.subtract(const Duration(days: 1)),
    );

MessageModel _msg(String id, String from, String to, {bool read = false, bool pending = false, int minute = 0}) =>
    MessageModel(id: id, jobId: 'j1', senderId: from, receiverId: to, text: 'Message $id', isRead: read, isPending: pending, createdAt: _t.add(Duration(minutes: minute)));

List<Override> _base({UserModel? user, _Recorder? rec, bool admin = false, PushPlatform? push}) {
  final u = user ?? _user();
  final r = rec ?? _Recorder();
  return [
    authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(_FakeUser(u.uid))),
    currentUserProfileProvider.overrideWith((ref) => Stream.value(u)),
    isAdminProvider.overrideWith((ref) => Stream.value(admin)),
    platformConfigProvider.overrideWithValue(const PlatformConfig()),
    profileServiceProvider.overrideWithValue(_FakeProfile(r)),
    authServiceProvider.overrideWithValue(_FakeAuth(r)),
    supportTicketServiceProvider.overrideWithValue(_FakeTickets(r)),
    userTicketsProvider.overrideWith((ref, id) => Stream.value([
          SupportTicketModel(id: 't1', userId: u.uid, userName: u.name, subject: 'Payment not showing', message: 'I paid but it is not showing.', status: 'resolved', adminResponse: 'Fixed on our side.', createdAt: _t),
        ])),
    unreadNotificationCountProvider.overrideWith((ref) => Stream.value(0)),
    userNotificationsProvider.overrideWith((ref) => Stream.value(const <NotificationModel>[])),
    pushPlatformProvider.overrideWithValue(push ?? _FakePush()),
    isOnlineProvider.overrideWith((ref) => Stream.value(true)),
  ];
}

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

void _size(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Minimal GoRouter around the screens under test.
Widget _routed(List<Override> overrides, String initial, List<RouteBase> routes) => ProviderScope(
      key: UniqueKey(), // a fresh scope per pump, so changed overrides apply
      overrides: overrides,
      child: MaterialApp.router(routerConfig: GoRouter(initialLocation: initial, routes: routes)),
    );

final _settingsRoutes = <RouteBase>[
  GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen(), routes: [
    GoRoute(path: 'personal', builder: (_, _) => const PersonalInfoScreen()),
    GoRoute(path: 'notifications', builder: (_, _) => const NotificationPreferencesScreen()),
    GoRoute(path: 'security', builder: (_, _) => const SecurityScreen()),
  ]),
  GoRoute(path: '/support', builder: (_, _) => const SupportCentreScreen()),
  GoRoute(path: '/about', builder: (_, _) => const AboutHandyTrustScreen()),
  GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
  GoRoute(path: '/profile', builder: (_, _) => const Text('PROFILE')),
  GoRoute(path: '/notifications', builder: (_, _) => const Text('NOTIFICATIONS')),
  GoRoute(path: '/wallet', builder: (_, _) => const Text('WALLET')),
  GoRoute(path: '/jobs', builder: (_, _) => const Text('JOBS')),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'onboarding_seen': true}));

  group('Settings: every option opens its own destination, Back returns', () {
    final cases = <(String, Type)>[
      ('Personal information', PersonalInfoScreen),
      ('Security and password', SecurityScreen),
      ('Notification preferences', NotificationPreferencesScreen),
      ('Support Centre', SupportCentreScreen),
      ('About HandyTrust', AboutHandyTrustScreen),
    ];
    for (final (label, type) in cases) {
      testWidgets('$label → $type → back to Settings', (t) async {
        _size(t, 430, 1400);
        await t.pumpWidget(_routed(_base(), '/settings', _settingsRoutes));
        await _settle(t);
        await t.tap(find.text(label));
        await _settle(t);
        expect(find.byType(type), findsOneWidget);
        await t.tap(find.byTooltip('Back').hitTestable().last);
        await _settle(t);
        expect(find.byType(SettingsScreen), findsOneWidget);
      });
    }

    testWidgets('dual-role user can switch mode; deletion request uses the approved wording', (t) async {
      _size(t, 430, 1400);
      final r = _Recorder();
      await t.pumpWidget(_routed(_base(user: _user(roles: const ['customer', 'artisan']), rec: r), '/settings', _settingsRoutes));
      await _settle(t);
      expect(find.text('Active mode'), findsOneWidget);
      await t.tap(find.text('Active mode'));
      await _settle(t);
      await t.tap(find.text('Switch'));
      await _settle(t);
      expect(r.calls['setActiveRole']!.single, ['c1', 'artisan']);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('account deletion: U-1 copy, request recorded; no "7 days" promise', (t) async {
      _size(t, 430, 1400);
      final r = _Recorder();
      await t.pumpWidget(_routed(_base(rec: r), '/settings', _settingsRoutes));
      await _settle(t);
      await t.tap(find.text('Request account deletion'));
      await _settle(t);
      expect(find.textContaining('An administrator will review your request. Your job history, payments and reviews are kept.'), findsOneWidget);
      expect(find.textContaining('7 days'), findsNothing);
      await t.tap(find.text('Submit request'));
      await _settle(t);
      expect(r.count('requestAccountDeletion'), 1);
    });

    testWidgets('pending deletion offers cancellation instead', (t) async {
      _size(t, 430, 1400);
      await t.pumpWidget(_routed(_base(user: _user(deletion: true)), '/settings', _settingsRoutes));
      await _settle(t);
      expect(find.text('Cancel deletion request'), findsOneWidget);
      expect(find.text('Request account deletion'), findsNothing);
    });
  });

  group('Security and password', () {
    Future<_Recorder> open(WidgetTester t) async {
      _size(t, 430, 1600);
      final r = _Recorder();
      await t.pumpWidget(_routed(_base(rec: r), '/settings/security', _settingsRoutes));
      await _settle(t);
      return r;
    }

    Future<void> fill(WidgetTester t, String current, String next, String confirm) async {
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), current);
      await t.enterText(fields.at(1), next);
      await t.enterText(fields.at(2), confirm);
      await t.tap(find.text('Update password'));
      await _settle(t);
    }

    testWidgets('policy is enforced for the new password (8+, uppercase, number)', (t) async {
      final r = await open(t);
      await fill(t, 'Current1', 'short', 'short');
      expect(find.text('Password must be at least 8 characters'), findsOneWidget);
      await fill(t, 'Current1', 'longenough1', 'longenough1');
      expect(find.text('Include at least one uppercase letter'), findsOneWidget);
      expect(r.count('updatePassword'), 0);
    });

    testWidgets('confirmation must match; success re-authenticates and confirms', (t) async {
      final r = await open(t);
      await fill(t, 'Current1', 'Valid1234', 'Valid12345');
      expect(find.text('Passwords don’t match'), findsOneWidget);
      await fill(t, 'Current1', 'Valid1234', 'Valid1234');
      expect(r.calls['updatePassword']!.single, ['Current1', 'Valid1234']);
      expect(find.text('Password changed'), findsOneWidget);
    });

    testWidgets('wrong current password shows a clear error, not a success', (t) async {
      await open(t);
      await fill(t, 'wrong', 'Valid1234', 'Valid1234');
      expect(find.text('Your current password is incorrect.'), findsOneWidget);
      expect(find.text('Password changed'), findsNothing);
    });

    testWidgets('visibility toggle and Firebase-hosted reset link', (t) async {
      final r = await open(t);
      expect(find.byTooltip('Show password'), findsNWidgets(3));
      await t.tap(find.byTooltip('Show password').first);
      await _settle(t, 2);
      expect(find.byTooltip('Hide password'), findsOneWidget);
      await t.tap(find.text('Email me a reset link'));
      await _settle(t);
      expect(r.calls['sendPasswordReset']!.single, 'c1@example.com');
    });
  });

  testWidgets('Notification preferences: writes users.notificationsEnabled', (t) async {
    _size(t, 430, 1200);
    final r = _Recorder();
    await t.pumpWidget(_routed(_base(rec: r), '/settings/notifications', _settingsRoutes));
    await _settle(t);
    await t.tap(find.byType(Switch));
    await _settle(t);
    expect(r.calls['updateUserProfile']!.single, ['c1', {'notificationsEnabled': false}]);
  });

  group('Support Centre and About', () {
    testWidgets('FAQ uses the live fee and booking window; ticket is sent; replies show', (t) async {
      _size(t, 430, 2600);
      final r = _Recorder();
      await t.pumpWidget(_routed([..._base(rec: r), platformConfigProvider.overrideWithValue(const PlatformConfig(platformFeePercent: 7, bookingConfirmationHours: 12))], '/support', _settingsRoutes));
      await _settle(t);
      await t.tap(find.text('Payments'));
      await _settle(t);
      expect(find.textContaining('7% platform fee'), findsOneWidget);
      await t.tap(find.text('Jobs and bookings'));
      await _settle(t);
      expect(find.textContaining('12 hours'), findsOneWidget);
      expect(find.text('Fixed on our side.'), findsOneWidget);
      await t.tap(find.text('Send ticket'));
      await _settle(t);
      expect(r.count('createTicket'), 0); // validation
      await t.enterText(find.byType(TextFormField).at(0), 'Refund question');
      await t.enterText(find.byType(TextFormField).at(1), 'My refund has not arrived yet.');
      await t.tap(find.text('Send ticket'));
      await _settle(t);
      expect(r.calls['createTicket']!.single, ['c1', 'Refund question', 'My refund has not arrived yet.']);
    });

    testWidgets('help topic links open their real destinations', (t) async {
      _size(t, 430, 2600);
      await t.pumpWidget(_routed(_base(), '/support', _settingsRoutes));
      await _settle(t);
      await t.tap(find.text('Payments'));
      await _settle(t);
      await t.tap(find.text('View payments'));
      await _settle(t);
      expect(find.text('WALLET'), findsOneWidget);
    });

    testWidgets('About shows the real version and no invented claims or placeholder links', (t) async {
      _size(t, 430, 1600);
      await t.pumpWidget(_routed(_base(), '/about', _settingsRoutes));
      await _settle(t);
      expect(find.text('Version 1.0.0 (build 1)'), findsOneWidget);
      expect(find.text('Terms of Service'), findsNothing);
      for (final f in Directory('lib/ui').listSync(recursive: true).whereType<File>()) {
        final src = f.readAsStringSync();
        for (final bad in ['example.com/terms', 'handytrust.example.com', 'Super Administrator', 'within 48 hours', 'within 7 days']) {
          expect(src.contains(bad), isFalse, reason: '${f.path} contains "$bad"');
        }
      }
    });
  });

  group('Customer My Chats', () {
    final jobs = [_job('j1', JobStatus.inProgress, artisan: 'a1'), _job('j2', JobStatus.requested)];
    List<Override> chats({Object? error, bool online = true}) => [
          ..._base(),
          customerJobsProvider.overrideWith((ref, id) => error == null ? Stream.value(jobs) : Stream.error(error)),
          jobCounterpartsProvider.overrideWith((ref, k) => Stream.value(k.jobId == 'j2' ? {'a2', 'a3'} : <String>{})),
          lastMessageProvider.overrideWith((ref, k) => Stream.value(k.otherPartyId == 'a3' ? null : _msg('m${k.otherPartyId}', k.otherPartyId, 'c1', minute: k.otherPartyId == 'a2' ? 30 : 5))),
          pairUnreadCountProvider.overrideWith((ref, k) => Stream.value(k.otherPartyId == 'a2' ? 2 : 0)),
          artisanProfileProvider.overrideWith((ref, id) => Stream.value(_artisan(id, {'a1': 'Funke Adeyemi', 'a2': 'Kola Ade', 'a3': 'Tunde Bello'}[id] ?? id))),
          isOnlineProvider.overrideWith((ref) => Stream.value(online)),
        ];
    final routes = <RouteBase>[
      GoRoute(path: '/my-chats', builder: (_, _) => const CustomerMessagesScreen()),
      GoRoute(path: '/chat/:id', builder: (_, s) => Text('CHAT ${s.pathParameters['id']} WITH ${s.uri.queryParameters['with']}')),
      GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
      GoRoute(path: '/request', builder: (_, _) => const Text('POST')),
    ];

    testWidgets('lists real conversations, newest first, with per-conversation unread', (t) async {
      _size(t, 430, 1400);
      await t.pumpWidget(_routed(chats(), '/my-chats', routes));
      await _settle(t);
      expect(find.text('Kola Ade'), findsOneWidget); // pre-booking, open job
      expect(find.text('Tunde Bello'), findsOneWidget);
      expect(find.text('Funke Adeyemi'), findsOneWidget); // booked job
      expect(find.text('No messages yet'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Kola Ade.*2 unread')), findsOneWidget);
      expect(t.getTopLeft(find.text('Kola Ade')).dy, lessThan(t.getTopLeft(find.text('Funke Adeyemi')).dy));
    });

    testWidgets('Unread filter and search; tapping opens that exact conversation', (t) async {
      _size(t, 430, 1400);
      await t.pumpWidget(_routed(chats(), '/my-chats', routes));
      await _settle(t);
      await t.tap(find.text('Unread'));
      await _settle(t);
      expect(find.text('Funke Adeyemi'), findsNothing);
      expect(find.text('Kola Ade'), findsOneWidget);
      await t.tap(find.text('All'));
      await t.enterText(find.byType(TextField), 'funke');
      await _settle(t);
      expect(find.text('Kola Ade'), findsNothing);
      await t.tap(find.text('Funke Adeyemi'));
      await _settle(t);
      expect(find.text('CHAT j1 WITH a1'), findsOneWidget);
    });

    testWidgets('offline banner, error and empty states', (t) async {
      _size(t, 430, 1400);
      await t.pumpWidget(_routed(chats(online: false), '/my-chats', routes));
      await _settle(t);
      expect(find.textContaining('You’re offline'), findsOneWidget);
      await t.pumpWidget(_routed(chats(error: StateError('x')), '/my-chats', routes));
      await _settle(t);
      expect(find.textContaining('couldn’t load your chats'), findsOneWidget);
      await t.pumpWidget(_routed([..._base(), customerJobsProvider.overrideWith((ref, id) => Stream.value(const <JobModel>[]))], '/my-chats', routes));
      await _settle(t);
      expect(find.text('No chats yet'), findsOneWidget);
    });
  });

  group('Chat read receipts', () {
    List<Override> chat(_Recorder r) => [
          ..._base(),
          jobStreamProvider.overrideWith((ref, id) => Stream.value(_job('j1', JobStatus.inChat, artisan: 'a1'))),
          artisanProfileProvider.overrideWith((ref, id) => Stream.value(_artisan(id, 'Funke Adeyemi'))),
          chatServiceProvider.overrideWithValue(_FakeChat(r)),
          messagesStreamProvider.overrideWith((ref, k) => Stream.value([
                _msg('m1', 'c1', 'a1', read: true, minute: 1),
                _msg('m2', 'c1', 'a1', minute: 2),
                _msg('m3', 'c1', 'a1', pending: true, minute: 3),
                _msg('m4', 'a1', 'c1', minute: 4),
              ])),
        ];

    testWidgets('Sending / Sent / Read are shown truthfully; opening marks only this conversation read', (t) async {
      _size(t, 430, 1600);
      final r = _Recorder();
      await t.pumpWidget(ProviderScope(overrides: chat(r), child: const MaterialApp(home: ChatScreen(jobId: 'j1', otherUserId: 'a1'))));
      await _settle(t);
      expect(find.byTooltip('Read'), findsOneWidget);
      expect(find.byTooltip('Sent'), findsOneWidget);
      expect(find.byTooltip('Sending'), findsOneWidget);
      expect(find.byTooltip('Delivered'), findsNothing);
      expect(r.calls['markAllAsRead'], isNotEmpty);
      expect(r.calls['markAllAsRead']!.last, ['j1', 'c1', 'a1']);
    });

    testWidgets('no read receipt is written while the app is in the background', (t) async {
      _size(t, 430, 1600);
      final r = _Recorder();
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await t.pumpWidget(ProviderScope(overrides: chat(r), child: const MaterialApp(home: ChatScreen(jobId: 'j1', otherUserId: 'a1'))));
      await _settle(t);
      expect(r.count('markAllAsRead'), 0);
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await _settle(t, 3);
      expect(r.calls['markAllAsRead']!.last, ['j1', 'c1', 'a1']);
    });
  });

  group('Push registration and tap routing (logic level; delivery not claimed)', () {
    Future<(_FakePush, List<String>, StreamController<User?>, StreamController<UserModel?>)> boot(WidgetTester t) async {
      final push = _FakePush()..initial = '/chat/j9';
      final opened = <String>[];
      final auth = StreamController<User?>.broadcast();
      final profile = StreamController<UserModel?>.broadcast();
      await t.pumpWidget(ProviderScope(
        overrides: [
          ..._base(push: push),
          authStateChangesProvider.overrideWith((ref) => auth.stream),
          currentUserProfileProvider.overrideWith((ref) => profile.stream),
          pushNavigatorProvider.overrideWithValue(opened.add),
        ],
        child: Consumer(builder: (c, ref, _) {
          ref.watch(notificationInitProvider);
          return const MaterialApp(home: SizedBox());
        }),
      ));
      return (push, opened, auth, profile);
    }

    testWidgets('signed in with push on: permission requested and token saved', (t) async {
      final (push, _, auth, profile) = await boot(t);
      auth.add(_FakeUser('u1'));
      await _settle(t, 2);
      profile.add(_user(uid: 'u1'));
      await _settle(t, 4);
      expect(push.r.count('requestPermission'), 1);
      expect(push.r.calls['saveToken']!.single, ['u1', 'tok']);
    });

    testWidgets('push turned off: device token invalidated and stored token removed', (t) async {
      final (push, _, auth, profile) = await boot(t);
      auth.add(_FakeUser('u1'));
      profile.add(_user(uid: 'u1', notifications: false));
      await _settle(t, 4);
      expect(push.r.count('deleteToken'), 1);
      expect(push.r.calls['removeToken']!.single, 'u1');
      expect(push.r.count('saveToken'), 0);
    });

    testWidgets('sign-out invalidates this device’s token (account switch)', (t) async {
      final (push, _, auth, profile) = await boot(t);
      auth.add(_FakeUser('u1'));
      profile.add(_user(uid: 'u1'));
      await _settle(t, 4);
      auth.add(null);
      profile.add(null);
      await _settle(t, 4);
      expect(push.r.count('deleteToken'), 1);
    });

    testWidgets('taps navigate once each (no duplicate listeners across rebuilds); launch tap handled once', (t) async {
      final (push, opened, auth, profile) = await boot(t);
      for (var i = 0; i < 3; i++) {
        auth.add(_FakeUser('u1'));
        profile.add(_user(uid: 'u1', notifications: i.isEven));
        await _settle(t, 2);
      }
      push.opened.add('/chat/j1');
      await _settle(t, 2);
      push.localTap?.call('/job/j2');
      push.localTap?.call('https://evil.example');
      await _settle(t, 2);
      expect(opened.where((r) => r == '/chat/j1').length, 1);
      expect(opened.where((r) => r == '/chat/j9').length, 1); // terminated-launch tap, once
      expect(opened, contains('/job/j2'));
      expect(opened, contains('/notifications')); // unsafe payload contained
      expect(push.r.count('initial'), 1);
    });
  });

  group('Admin (rebuilt)', () {
    final jobs = [
      _job('jReq', JobStatus.requested),
      _job('jFunded', JobStatus.inProgress, artisan: 'a1', paymentReference: 'ref1', escrowLockedAt: _t),
      _job('jDone', JobStatus.completed, artisan: 'a1', paymentReference: 'ref2'),
    ];
    List<Override> admin(_Recorder r) => [
          ..._base(user: _user(uid: 'adm', roles: const ['customer']), admin: true),
          adminServiceProvider.overrideWithValue(_FakeAdmin(r)),
          adminTotalsProvider.overrideWith((ref) async => const AdminTotals(users: 1284, artisans: 312, jobs: 3, admins: 2)),
          adminUsersProvider.overrideWith((ref) => Stream.value([_user(uid: 'c1'), _user(uid: 'a1', roles: const ['artisan'], role: 'artisan')])),
          adminJobsProvider.overrideWith((ref) => Stream.value(jobs)),
          adminArtisansProvider.overrideWith((ref) => Stream.value([_artisan('a1', 'Kola Ade')])),
          adminPendingArtisansProvider.overrideWith((ref) => Stream.value([_artisan('a2', 'New Artisan')])),
          adminDeletionRequestsProvider.overrideWith((ref) => Stream.value(const <Map<String, dynamic>>[])),
          adminAlertsProvider.overrideWith((ref) => Stream.value([
                {'id': 'al1', 'type': 'chargeback_after_payout', 'jobId': 'jDone', 'resolved': false},
                {'id': 'al2', 'type': 'brand_new_type', 'resolved': false},
              ])),
          adminPaymentsProvider.overrideWith((ref) => Stream.value([PaymentModel(id: 'p1', jobId: 'jFunded', payerId: 'c1', artisanId: 'a1', amount: 25000, totalCharged: 26250, status: PaymentStatus.escrowHeld, createdAt: _t)])),
          adminDisputesProvider.overrideWith((ref) => Stream.value(const <DisputeModel>[])),
          adminVerificationsProvider.overrideWith((ref) => Stream.value(const <VerificationModel>[])),
          adminAuditLogsProvider.overrideWith((ref) => Stream.value([AdminAuditLogModel(id: 'l1', action: AdminAction.adminOverride, actionId: 'payoutFrozen', adminId: 'adm', targetId: 'jFunded', targetType: 'job', timestamp: _t, metadata: const {'reason': 'Chargeback under investigation'})])),
          adminPeopleNamesProvider.overrideWith((ref, k) async => {'c1': 'Daniel Ade', 'a1': 'Kola Ade', 'adm': 'Ada Admin'}),
          adminFinanceProvider.overrideWith((ref, k) => Stream.value(k == FinanceKind.chargebacks
              ? [FinanceRecord(k, 'CB-1', {'status': 'open', 'chargedAmountKobo': 2625000, 'jobId': 'jFunded', 'payoutStateAtOpen': 'in_escrow'})]
              : const <FinanceRecord>[])),
          pendingVerificationsProvider.overrideWith((ref) => Stream.value(const <VerificationModel>[])),
          openDisputesProvider.overrideWith((ref) => Stream.value(const <DisputeModel>[])),
          allTicketsProvider.overrideWith((ref) => Stream.value(const <SupportTicketModel>[])),
          allReviewsProvider.overrideWith((ref) => Stream.value(const <ReviewModel>[])),
          jobQuotesProvider.overrideWith((ref, id) => Stream.value(const <QuoteModel>[])),
          jobPrivateLocationProvider.overrideWith((ref, id) => Stream.value(null)),
          jobStreamProvider.overrideWith((ref, id) => Stream.value(jobs.where((j) => j.id == id).firstOrNull)),
          artisanProfileProvider.overrideWith((ref, id) => Stream.value(_artisan(id, 'Kola Ade'))),
        ];

    Future<GoRouter> boot(WidgetTester t, List<Override> overrides, {double w = 1440, double h = 1000}) async {
      _size(t, w, h);
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);
      await t.runAsync(() async {
        await container.read(authStateChangesProvider.future);
        await container.read(currentUserProfileProvider.future);
        await container.read(isAdminProvider.future);
      });
      final router = container.read(routerProvider);
      await t.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
      await _settle(t, 12);
      return router;
    }

    Future<void> go(WidgetTester t, GoRouter r, String p) async {
      r.go(p);
      await _settle(t, 12);
    }

    testWidgets('every admin section has its own URL (deep links), incl. new /admin/finance', (t) async {
      final r = await boot(t, admin(_Recorder()));
      final expected = <String, Type>{
        '/admin/dashboard': AdminDashboardSection,
        '/admin/analytics': AdminAnalyticsSection,
        '/admin/jobs': AdminJobsSection,
        '/admin/finance': AdminFinanceSection,
        '/admin/audit-logs': AdminAuditLogsSection,
        '/admin/settings': AdminSettingsSection,
      };
      for (final e in expected.entries) {
        await go(t, r, e.key);
        expect(r.routerDelegate.currentConfiguration.uri.path, e.key);
        expect(find.byType(e.value), findsOneWidget, reason: e.key);
        expect(t.takeException(), isNull, reason: e.key);
      }
    });

    testWidgets('dashboard shows genuine totals and labelled alerts with raw ids', (t) async {
      final r = await boot(t, admin(_Recorder()));
      await go(t, r, '/admin/dashboard');
      expect(find.text('1284'), findsOneWidget); // count() total, not the 2 loaded users
      expect(find.text('312'), findsOneWidget);
      expect(find.text('₦26.3k'), findsOneWidget); // held in escrow (charged amount)
      expect(find.text('Chargeback opened after payout'), findsOneWidget);
      expect(find.text('chargeback_after_payout'), findsOneWidget);
      expect(find.text('Unrecognised alert'), findsOneWidget);
      expect(find.text('brand_new_type'), findsOneWidget);
      expect(find.text('View in Finance'), findsNothing);
    });

    testWidgets('resolving an alert goes through AdminService', (t) async {
      final rec = _Recorder();
      final r = await boot(t, admin(rec));
      await go(t, r, '/admin/dashboard');
      await t.tap(find.text('Resolve').first);
      await _settle(t, 4);
      expect(rec.calls['resolveAlert'], isNotEmpty);
    });

    testWidgets('F-1: delete only offered for unfunded jobs; funded jobs keep their record', (t) async {
      final rec = _Recorder();
      final r = await boot(t, admin(rec));
      await go(t, r, '/admin/jobs?focus=jFunded');
      expect(find.text('Deletion unavailable'), findsOneWidget);
      expect(find.text('Delete job request'), findsNothing);
      await t.tap(find.text('Fix jReq').first);
      await _settle(t, 4);
      expect(find.text('Delete job request'), findsOneWidget);
      await t.tap(find.text('Delete job request'));
      await _settle(t, 4);
      await t.tap(find.text('Delete job request').last);
      await _settle(t, 4);
      expect(rec.calls['deleteJob'], ['jReq']);
    });

    testWidgets('finance is read-only and payout freeze is display-only', (t) async {
      final r = await boot(t, admin(_Recorder()));
      await go(t, r, '/admin/finance');
      expect(find.textContaining('Read-only.'), findsOneWidget);
      for (final action in ['Close chargeback', 'Freeze payout', 'Set investigation', 'Unfreeze']) {
        expect(find.textContaining(action), findsNothing, reason: action);
      }
      await t.tap(find.text('CB-1'));
      await _settle(t, 6);
      expect(find.text('Payouts not frozen'), findsOneWidget);
    });

    testWidgets('audit log shows the recorded server action, not "admin override"', (t) async {
      final r = await boot(t, admin(_Recorder()));
      await go(t, r, '/admin/audit-logs');
      expect(find.text('Payout frozen'), findsOneWidget);
      expect(find.textContaining('Admin override'), findsNothing);
      expect(find.text('Chargeback under investigation'), findsOneWidget);
    });

    testWidgets('settings: role label is "Administrator" (F-3)', (t) async {
      final r = await boot(t, admin(_Recorder()));
      await go(t, r, '/admin/settings');
      expect(find.text('Administrator'), findsOneWidget);
      expect(find.textContaining('Super'), findsNothing);
    });

    for (final (w, h, label) in [(1440.0, 1000.0, 'desktop'), (900.0, 1100.0, 'tablet'), (390.0, 1400.0, 'phone')]) {
      testWidgets('dashboard, jobs and finance lay out on $label', (t) async {
        final r = await boot(t, admin(_Recorder()), w: w, h: h);
        for (final p in ['/admin/dashboard', '/admin/jobs', '/admin/finance', '/admin/users']) {
          await go(t, r, p);
          expect(t.takeException(), isNull, reason: '$label $p');
        }
      });
    }

    testWidgets('non-admins are sent home from /admin (UI gate; rules enforce access)', (t) async {
      final r = await boot(t, [
        ...admin(_Recorder()),
        isAdminProvider.overrideWith((ref) => Stream.value(false)),
        customerJobsProvider.overrideWith((ref, id) => Stream.value(const <JobModel>[])),
        customerPaymentsProvider.overrideWith((ref, id) => Stream.value(const <PaymentModel>[])),
        featuredArtisansProvider.overrideWith((ref) => Stream.value(const <ArtisanModel>[])),
      ]);
      await go(t, r, '/admin/finance');
      expect(r.routerDelegate.currentConfiguration.uri.path, '/home');
      expect(find.byType(CustomerShell), findsOneWidget);
    });
  });

  group('App router: Settings, Support, About and My Chats deep links', () {
    testWidgets('each path opens its own screen', (t) async {
      _size(t, 800, 1600);
      final container = ProviderContainer(overrides: [
        ..._base(),
        customerJobsProvider.overrideWith((ref, id) => Stream.value(const <JobModel>[])),
      ]);
      addTearDown(container.dispose);
      await t.runAsync(() async {
        await container.read(authStateChangesProvider.future);
        await container.read(currentUserProfileProvider.future);
      });
      final router = container.read(routerProvider);
      await t.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
      await _settle(t, 10);
      for (final (path, type) in <(String, Type)>[
        ('/settings', SettingsScreen),
        ('/settings/personal', PersonalInfoScreen),
        ('/settings/notifications', NotificationPreferencesScreen),
        ('/settings/security', SecurityScreen),
        ('/support', SupportCentreScreen),
        ('/about', AboutHandyTrustScreen),
        ('/my-chats', CustomerMessagesScreen),
      ]) {
        router.go(path);
        await _settle(t, 12);
        expect(find.byType(type), findsOneWidget, reason: path);
      }
    });
  });

  group('Source guards (Stage 8.2)', () {
    test('old admin, settings, support and chat-list presentation is gone', () {
      for (final f in [
        'lib/screens/admin/admin_dashboard_screen.dart',
        'lib/screens/admin/admin_sidebar.dart',
        'lib/screens/admin/admin_widgets.dart',
        'lib/screens/admin/admin_data_table.dart',
        'lib/screens/admin/admin_charts.dart',
        'lib/screens/admin/admin_palette.dart',
        'lib/screens/admin/admin_finance_dialogs.dart',
        'lib/screens/settings/settings_screen.dart',
        'lib/screens/support/contact_support_screen.dart',
        'lib/screens/support/about_screen.dart',
        'lib/screens/chat/my_chats_screen.dart',
        'lib/widgets/app_snackbars.dart',
        'lib/widgets/job_status_badge.dart',
        'lib/widgets/notification_bell.dart',
      ]) {
        expect(File(f).existsSync(), isFalse, reason: f);
      }
    });

    test('no client collection-group message queries remain (denied by the rules)', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync().replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
        expect(src.contains("collectionGroup('messages')"), isFalse, reason: f.path);
      }
    });

    test('profile and settings rows never route every option to the Settings hub', () {
      final profile = File('lib/ui/screens/profile_screen.dart').readAsStringSync();
      for (final title in ['Account Information', 'Security & Password', 'Notification Settings']) {
        final line = profile.split('\n').firstWhere((l) => l.contains("title: '$title'"));
        expect(line.contains("context.push('/settings')"), isFalse, reason: title);
      }
    });
  });
}
