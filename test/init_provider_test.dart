// Regression tests for the Safari/iOS-reliability fix in
// lib/providers/init_provider.dart — see
// design/V2_IOS_SAFARI_RELIABILITY_REPORT.md for the full root-cause
// writeup. Pure-Dart, no Firebase/widget tree involved, matching this
// repo's existing test convention (test extracted logic directly).
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:handy_trust/providers/init_provider.dart';

void main() {
  group('waitForInitialAuthState — the Safari "infinite spinner" fix', () {
    test('resolves immediately when the stream emits right away (the ordinary case)', () async {
      final stream = Stream<User?>.value(null); // "definitely signed out"
      await expectLater(
        waitForInitialAuthState(stream, timeout: const Duration(milliseconds: 200)),
        completes,
      );
    });

    test(
        'throws a TimeoutException — not hangs forever — when the stream never emits within the timeout '
        '(this is the exact failure mode: a browser/network condition stalls Firebase Auth persistence '
        'restoration, and the old code had no bound on this at all)', () async {
      final controller = StreamController<User?>(); // never emits, never closes
      addTearDown(controller.close);

      await expectLater(
        waitForInitialAuthState(controller.stream, timeout: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a short timeout does not fire once the stream has already emitted (no false-positive timeout after success)',
        () async {
      final controller = StreamController<User?>();
      addTearDown(controller.close);

      final future = waitForInitialAuthState(controller.stream, timeout: const Duration(milliseconds: 300));
      controller.add(null);

      await expectLater(future, completes);
    });

    test('propagates a genuine stream error (e.g. a real Firebase Auth exception) rather than swallowing it',
        () async {
      final controller = StreamController<User?>();
      addTearDown(controller.close);

      final future = waitForInitialAuthState(controller.stream, timeout: const Duration(milliseconds: 300));
      controller.addError(Exception('simulated Firebase Auth error'));

      await expectLater(future, throwsA(isA<Exception>()));
    });

    test('does not consume/disrupt a broadcast stream for other listeners (authStateChangesProvider keeps working)',
        () async {
      final controller = StreamController<User?>.broadcast();
      addTearDown(controller.close);

      final otherListenerEvents = <User?>[];
      final subscription = controller.stream.listen(otherListenerEvents.add);
      addTearDown(subscription.cancel);

      final future = waitForInitialAuthState(controller.stream, timeout: const Duration(milliseconds: 300));
      controller.add(null);
      await future;

      // Give the other listener's microtask a turn to receive the same event.
      await Future<void>.delayed(Duration.zero);
      expect(otherListenerEvents, [null]);
    });
  });
}
