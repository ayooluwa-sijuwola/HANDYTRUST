import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stage 8.2: whether the device currently reports any network connection.
/// Used only to explain stale data ("offline — showing saved messages");
/// Firestore keeps serving its cache either way. Fails open (assumes
/// online) if the platform plugin is unavailable.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  try {
    final c = Connectivity();
    yield _online(await c.checkConnectivity());
    yield* c.onConnectivityChanged.map(_online);
  } catch (e) {
    debugPrint('[connectivity] unavailable: $e');
    yield true;
  }
});

bool _online(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);
