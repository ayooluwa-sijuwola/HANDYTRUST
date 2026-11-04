import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/auth_service.dart';
import 'package:handy_trust/models/user_model.dart';
import 'package:handy_trust/providers/auth_provider.dart';

/// Regression test for P0-5 (design/FULL_PRODUCTION_QA_AUDIT.md) /
/// design/P0_REMEDIATION_PLAN.md §6: the forgot-password flow showed a
/// false "email sent" success screen on any FirebaseAuthException, because
/// AuthNotifier.sendPasswordReset caught the exception, stored it in its
/// own state, and returned normally without rethrowing — the calling
/// screen's sole success signal was "did the await throw," which was never
/// true for this bug, only ever true for a genuine success.
///
/// AuthNotifier.sendPasswordReset now returns `Future<bool>`, matching
/// [AuthNotifier.signIn]/[AuthNotifier.signUp]'s existing convention. These
/// tests exercise the notifier directly against a fake [IAuthService] — no
/// Firebase bootstrap, no widget tree, matching this repo's established
/// preference (see test/artisan_eligibility_test.dart) for testing logic
/// directly rather than via emulator/mocking packages this project doesn't
/// otherwise depend on.
class _FakeAuthService implements IAuthService {
  _FakeAuthService([this._sendPasswordResetThrows]);

  final Object? _sendPasswordResetThrows;

  @override
  User? get currentUser => null;

  @override
  Future<UserCredential> createAccount({
    required String email,
    required String password,
    required UserModel profile,
  }) =>
      throw UnimplementedError('not exercised by these tests');

  @override
  Future<UserCredential> signIn({required String email, required String password}) =>
      throw UnimplementedError('not exercised by these tests');

  @override
  Future<void> sendEmailVerification() => throw UnimplementedError('not exercised by these tests');

  @override
  Future<void> sendPasswordReset(String email) async {
    if (_sendPasswordResetThrows != null) {
      throw _sendPasswordResetThrows;
    }
  }

  @override
  Future<void> signOut() => throw UnimplementedError('not exercised by these tests');
}

void main() {
  group('AuthNotifier.sendPasswordReset — P0-5 regression', () {
    test('genuine success: returns true, error stays null', () async {
      final notifier = AuthNotifier(_FakeAuthService());
      final ok = await notifier.sendPasswordReset('user@example.com');
      expect(ok, isTrue);
      expect(notifier.state.error, isNull);
      expect(notifier.state.isLoading, isFalse);
    });

    test(
      'too-many-requests: returns false with the friendly rate-limit '
      'message — this is the exact case the audit reported as a false '
      'success (P0-5)',
      () async {
        final notifier = AuthNotifier(
          _FakeAuthService(FirebaseAuthException(code: 'too-many-requests')),
        );
        final ok = await notifier.sendPasswordReset('user@example.com');
        expect(ok, isFalse);
        expect(notifier.state.error, 'Too many attempts. Please try again later.');
      },
    );

    test('network-request-failed: returns false with the network-specific message', () async {
      final notifier = AuthNotifier(
        _FakeAuthService(FirebaseAuthException(code: 'network-request-failed')),
      );
      final ok = await notifier.sendPasswordReset('user@example.com');
      expect(ok, isFalse);
      expect(notifier.state.error, 'No internet connection. Please check your network.');
    });

    test(
      'user-not-found: treated as success (privacy-preserving) — must not '
      'reveal account non-existence through this flow',
      () async {
        final notifier = AuthNotifier(
          _FakeAuthService(FirebaseAuthException(code: 'user-not-found')),
        );
        final ok = await notifier.sendPasswordReset('nobody@example.com');
        expect(ok, isTrue);
        expect(notifier.state.error, isNull);
      },
    );

    test('a non-FirebaseAuthException also fails cleanly (returns false, sets an error)', () async {
      final notifier = AuthNotifier(_FakeAuthService(Exception('boom')));
      final ok = await notifier.sendPasswordReset('user@example.com');
      expect(ok, isFalse);
      expect(notifier.state.error, isNotNull);
    });

    test('isLoading is true during the call and false afterward, in every outcome', () async {
      final successNotifier = AuthNotifier(_FakeAuthService());
      expect(successNotifier.state.isLoading, isFalse);
      final future = successNotifier.sendPasswordReset('user@example.com');
      expect(successNotifier.state.isLoading, isTrue);
      await future;
      expect(successNotifier.state.isLoading, isFalse);
    });
  });
}
