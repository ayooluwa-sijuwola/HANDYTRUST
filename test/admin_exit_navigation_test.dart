import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/models/user_model.dart';

/// Unit tests for the "Exit Admin Panel / Back to App" navigation feature.
///
/// Scope, stated plainly, same standing disclosure as this repo's other
/// test files: _BackToAppButton's own onTap is a single line
/// (`context.go('/home')`) with no decision logic of its own — that's the
/// point of reusing router.dart's existing redirect rather than writing a
/// second, parallel "which dashboard for this user" decision. There is
/// nothing GoRouter-specific to unit test without a router test harness,
/// which this repo doesn't have (same class of gap as the rules-emulator
/// disclosures elsewhere).
///
/// What IS genuinely testable, and tested below, is the precondition the
/// reused redirect depends on: router.dart's dual-role gate is
///   profile.hasBothRoles && path == '/home' && activeRole not already
///   'customer'/'artisan' => redirect to /role-select
/// An admin tapping "Back to App" lands on exactly this same check, for
/// exactly their own profile — these tests confirm UserModel's role fields
/// behave the way that check assumes, for every role shape an admin
/// account can actually have.
UserModel _user({
  List<String> roles = const ['customer'],
  String? activeRole,
}) =>
    UserModel.fromJson({
      'uid': 'admin1',
      'name': 'Ada',
      'roles': roles,
      'activeRole': ?activeRole,
    });

/// Mirrors router.dart's own `hasExplicitRole` local exactly.
bool _hasExplicitRole(UserModel u) =>
    u.activeRole == 'customer' || u.activeRole == 'artisan';

void main() {
  group('Back to App — role-based destination (reuses router.dart, no duplicate logic)', () {
    test('single-role customer admin: not dual-role, no /role-select detour possible', () {
      final admin = _user(roles: const ['customer']);
      expect(admin.hasBothRoles, isFalse);
      expect(admin.isCustomer, isTrue);
      expect(admin.isArtisan, isFalse);
    });

    test('single-role artisan admin: not dual-role, no /role-select detour possible', () {
      final admin = _user(roles: const ['artisan']);
      expect(admin.hasBothRoles, isFalse);
      expect(admin.isArtisan, isTrue);
      expect(admin.isCustomer, isFalse);
    });

    test('dual-role admin loaded from Firestore always has an explicit '
        'activeRole — UserModel.fromJson defaults it to roles.first when '
        'absent, so hasExplicitRole (router.dart\'s own /role-select gate) '
        'is true and "Back to App" lands straight on /home, no detour', () {
      final admin = _user(roles: const ['customer', 'artisan']);
      expect(admin.hasBothRoles, isTrue);
      expect(admin.activeRole, isNotEmpty);
      expect(_hasExplicitRole(admin), isTrue,
          reason: 'fromJson defaults activeRole to roles.first — this is '
              'the actual current behavior, not an assumption');
    });

    test('dual-role admin with an explicit, already-chosen activeRole: '
        'hasExplicitRole is true, "Back to App" goes straight to /home', () {
      final admin = _user(roles: const ['customer', 'artisan'], activeRole: 'artisan');
      expect(admin.hasBothRoles, isTrue);
      expect(_hasExplicitRole(admin), isTrue);
    });

    test('dual-role admin with a malformed/non-role activeRole value '
        '(a data-integrity edge case, not reachable via fromJson\'s own '
        'default): router.dart\'s existing safety net still catches it — '
        'hasExplicitRole is false, so the existing /role-select redirect '
        'fires instead of leaving the admin on a broken or blank '
        'dashboard. This is the existing logic working correctly, not '
        'new behavior added for this feature.', () {
      final admin = UserModel(uid: 'admin1', name: 'Ada', roles: const ['customer', 'artisan'], activeRole: '');
      expect(admin.hasBothRoles, isTrue);
      expect(_hasExplicitRole(admin), isFalse);
    });
  });

  group('Back to App — admin permissions unaffected (requirement 2)', () {
    // "Do not remove admin permissions" is satisfied by construction:
    // _BackToAppButton's onTap makes zero Firestore or Auth calls (see
    // admin_dashboard_screen.dart) — pure navigation. isAdminProvider's
    // underlying admins/{uid} document is never touched by this feature,
    // so there is no permission state for this test to catch regressing —
    // documented here rather than faked as a runtime assertion against
    // code that intentionally does not exist.
    test('UserModel carries no admin-permission field that navigation '
        'could plausibly mutate — admin status lives entirely in the '
        'separate admins/{uid} collection, untouched by this feature', () {
      final admin = _user(roles: const ['customer', 'artisan']);
      // Sanity: confirms the model this feature reads has no adminOverride/
      // isAdmin-shaped field an accidental future edit could wire a write
      // to by mistake.
      expect(admin.toJson().containsKey('isAdmin'), isFalse);
    });
  });
}
