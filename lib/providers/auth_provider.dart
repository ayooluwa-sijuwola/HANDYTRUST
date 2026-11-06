import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/services/auth_service.dart';
import '../core/services/profile_service.dart';
import '../models/user_model.dart';

class AuthState {
  final bool isLoading;
  final String? error;

  const AuthState({this.isLoading = false, this.error});

  AuthState copyWith({bool? isLoading, String? error}) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._authService, {Future<void> Function()? beforeSignOut})
      : _beforeSignOut = beforeSignOut,
        super(const AuthState());

  final IAuthService _authService;

  /// Stage 8.2: work that must run while still signed in (removing this
  /// device's push registration). Never blocks sign-out on failure.
  final Future<void> Function()? _beforeSignOut;

  Future<bool> signUp({
    required String email,
    required String password,
    required UserModel profile,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _authService.createAccount(
        email: email,
        password: password,
        profile: profile,
      );
      state = state.copyWith(isLoading: false);
      return true;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: AuthService.friendlyError(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Something went wrong. Please try again.');
      return false;
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _authService.signIn(email: email, password: password);
      state = state.copyWith(isLoading: false);
      return true;
    } on FirebaseAuthException catch (e) {
      if (_signedInAs(email)) {
        // Native sign-in actually succeeded despite this exception (some
        // firebase_auth plugin versions throw a spurious decode error
        // post-success). Navigation is driven independently by
        // authStateChangesProvider/the router redirect, which already sees
        // the real signed-in user — reporting failure here would show
        // "Something went wrong" while the app navigates to Home anyway.
        state = state.copyWith(isLoading: false);
        return true;
      }
      state = state.copyWith(
        isLoading: false,
        error: AuthService.friendlyError(e),
      );
      return false;
    } catch (e) {
      if (_signedInAs(email)) {
        state = state.copyWith(isLoading: false);
        return true;
      }
      state = state.copyWith(isLoading: false, error: 'Something went wrong. Please try again.');
      return false;
    }
  }

  bool _signedInAs(String attemptedEmail) =>
      _authService.currentUser?.email?.toLowerCase() ==
      attemptedEmail.trim().toLowerCase();

  /// P0 remediation (design/P0_REMEDIATION_PLAN.md §6.3): previously
  /// `void`-returning, catching FirebaseAuthException internally without
  /// rethrowing — the caller (ForgotPasswordScreen) had no way to tell a
  /// real failure (rate-limited, network error, etc.) from success, so it
  /// showed "Check your inbox" regardless. Now matches the same
  /// return-bool-and-read-.error convention [signIn]/[signUp] already use.
  ///
  /// `user-not-found` is deliberately treated as success (not surfaced as
  /// an error) — Firebase Auth's own privacy-preserving behavior for
  /// password reset is to not reveal whether an account exists, and this
  /// notifier must not undermine that by showing a different UI state for
  /// a nonexistent account than for a real one.
  Future<bool> sendPasswordReset(String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _authService.sendPasswordReset(email);
      state = state.copyWith(isLoading: false);
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        state = state.copyWith(isLoading: false);
        return true;
      }
      state = state.copyWith(isLoading: false, error: AuthService.friendlyError(e));
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Something went wrong. Please try again.');
      return false;
    }
  }

  Future<void> resendVerificationEmail() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _authService.sendEmailVerification();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Could not send verification email.');
    }
  }

  /// Upper bound on [_beforeSignOut] (Stage 8.2 F-5): sign-out never waits
  /// longer than this for push clean-up, even if a platform call hangs.
  static const beforeSignOutTimeout = Duration(seconds: 8);

  Future<void> signOut() async {
    final hook = _beforeSignOut;
    if (hook != null) {
      try {
        await hook().timeout(beforeSignOutTimeout);
      } catch (_) {
        // Sign-out must always proceed (failure or timeout).
      }
    }
    await _authService.signOut();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final profileServiceProvider = Provider<ProfileService>((ref) => ProfileService());

/// Stage 8.2: runs just before sign-out (overridden at the app root with
/// the push-device cleanup). No-op by default (tests, other entry points).
final beforeSignOutProvider = Provider<Future<void> Function()>((ref) => () async {});

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.watch(authServiceProvider), beforeSignOut: () => ref.read(beforeSignOutProvider)()),
);

final authStateChangesProvider = StreamProvider<User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

/// Reactive stream of the signed-in user's Firestore profile.
/// Replaces the old FutureProvider — updates live when profile changes.
final currentUserProfileProvider = StreamProvider<UserModel?>((ref) {
  final authAsync = ref.watch(authStateChangesProvider);
  final firebaseUser = authAsync.asData?.value;

  if (firebaseUser == null || firebaseUser.isAnonymous) {
    debugPrint('[currentUserProfileProvider] no authenticated user');
    // Stream.empty() closes without emitting — a StreamProvider built on it
    // never leaves AsyncLoading. Emit an explicit null so signed-out callers
    // correctly observe AsyncData(null) instead of spinning forever.
    return Stream.value(null);
  }

  debugPrint('[currentUserProfileProvider] streaming profile uid=${firebaseUser.uid}');
  return ref.watch(authServiceProvider).userProfileStream(firebaseUser.uid);
});

/// Legacy alias so existing screens that reference currentUserProvider still compile.
/// Migrate call sites to currentUserProfileProvider over time.
final currentUserProvider = currentUserProfileProvider;

/// Whether the signed-in user is an admin per Firestore security rules —
/// checks the SAME source of truth the rules use (exists(/admins/{uid})),
/// not UserModel.roles, which is a separate field nothing currently sets.
/// This is the only correct way to gate admin-only UI: any gate based on a
/// different field can desync from what the rules actually allow, causing
/// admin-wide queries to come back PERMISSION_DENIED even though the screen
/// itself was reachable.
final isAdminProvider = StreamProvider<bool>((ref) {
  final firebaseUser = ref.watch(authStateChangesProvider).asData?.value;
  if (firebaseUser == null) return Stream.value(false);
  // A non-admin's read of their own (non-existent) /admins/{uid} doc is
  // denied by rules, not just empty — that's a stream error, not a "false"
  // snapshot. Swallow it to false rather than showing a scary "Error
  // checking admin access" for the overwhelmingly common non-admin case.
  return FirebaseFirestore.instance
      .collection('admins')
      .doc(firebaseUser.uid)
      .snapshots()
      .map((snap) => snap.exists)
      .transform(
        StreamTransformer<bool, bool>.fromHandlers(
          handleError: (Object e, StackTrace st, sink) {
            debugPrint('[isAdminProvider] stream error swallowed to false: $e');
            sink.add(false);
          },
        ),
      );
});
