import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/firebase/firebase_initializer.dart';
import 'auth_provider.dart';

/// Default timeout for [waitForInitialAuthState] — deliberately generous so
/// a normal, working but slow network/device never trips it (see that
/// function's doc comment for the failure mode this guards against).
const kAuthResolutionTimeout = Duration(seconds: 20);

/// Pure, unit-testable core of the fix: waits for the first value (or
/// error) on [authStateChanges], or throws a [TimeoutException] if none
/// arrives within [timeout]. Extracted from [authResolutionProvider] so it
/// can be exercised directly with a fake/controllable stream in
/// test/init_provider_test.dart, without needing to override a
/// Riverpod-provided concrete AuthService (which — like AuthNotifier before
/// the P0-3 fix — has eager Firebase field initializers that make it
/// unconstructable in a plain unit test).
Future<void> waitForInitialAuthState(
  Stream<User?> authStateChanges, {
  Duration timeout = kAuthResolutionTimeout,
}) {
  return authStateChanges.first.timeout(
    timeout,
    onTimeout: () {
      throw TimeoutException(
          'Auth state did not resolve within ${timeout.inSeconds} seconds — Firebase Auth may be unable to restore your session (e.g. a browser blocking local storage).');
    },
  );
}

final firebaseInitializationProvider = FutureProvider<void>((ref) async {
  debugPrint('[init_provider] starting Firebase initialization');
  try {
    await initializeFirebase().timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TimeoutException('Firebase initialization timed out after 30 seconds');
      },
    );
    debugPrint('[init_provider] Firebase initialization completed successfully');
  } catch (e, st) {
    debugPrint('[init_provider] Firebase initialization failed: $e');
    debugPrint(st.toString());
    rethrow;
  }
});

/// Gates on the FIRST emission of [authStateChangesProvider] — i.e. "has
/// Firebase Auth finished restoring (or definitively not finding) a
/// persisted session at least once" — with a bounded timeout.
///
/// Root cause this closes (design/V2_IOS_SAFARI_RELIABILITY_REPORT.md):
/// `Firebase.initializeApp()` completing (the check `firebaseInitializationProvider`
/// already guards) is a SEPARATE async step from Firebase Auth's own
/// persisted-session restoration — the latter has its own network/storage
/// round-trip (reading IndexedDB, potentially refreshing a token) with no
/// timeout of its own anywhere in this app. Previously, if that step never
/// resolved (e.g. IndexedDB blocked/slow in a Safari private-browsing or
/// storage-partitioned context), `authStateChangesProvider` stayed
/// `AsyncLoading` forever, the router's `redirect` callback's
/// `if (authAsync.isLoading) return null;` never let the user leave `/`,
/// and `SplashScreen` spun forever with no failure state and no retry —
/// exactly the "Initializing -> infinite spinner" failure mode.
///
/// Only gates the FIRST value: does not use `Stream.timeout()` on the
/// underlying stream directly, since that would incorrectly fire on any
/// later >20s gap between genuine auth state changes (normal — sessions
/// often go unchanged for far longer than 20s). `.first` subscribes once,
/// independently of the long-lived `authStateChangesProvider` subscription
/// used everywhere else in the app (Firebase's `authStateChanges()` is a
/// broadcast stream, so a second listener is safe and does not consume or
/// disrupt events for the first).
///
/// 20 seconds is deliberately generous — long enough that a normal, working
/// but slow network/device never trips it, per the explicit instruction not
/// to paper over real backend problems with an arbitrarily tiny timeout.
final authResolutionProvider = FutureProvider<void>((ref) async {
  final authService = ref.watch(authServiceProvider);
  debugPrint('[init_provider] waiting for initial auth-state resolution');
  try {
    await waitForInitialAuthState(authService.authStateChanges());
    debugPrint('[init_provider] initial auth-state resolution completed');
  } catch (e, st) {
    debugPrint('[init_provider] auth-state resolution failed: $e');
    debugPrint(st.toString());
    rethrow;
  }
});
