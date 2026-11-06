import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:handy_trust/firebase_options.dart';

import 'emulator_config.dart';

Future<void> initializeFirebase() async {
  // main() already calls this before runApp(); firebaseInitializationProvider
  // calls it again inside the widget tree. Guard against re-initializing,
  // which would otherwise throw [core/duplicate-app] on the second call.
  if (Firebase.apps.isNotEmpty) {
    debugPrint('[firebase_initializer] Firebase already initialized — skipping');
    return;
  }

  // Local emulator mode (opt-in, never in release builds): demo project +
  // local emulators only. See emulator_config.dart.
  if (EmulatorConfig.requested) {
    await EmulatorConfig.initialize();
    return;
  }

  final options = DefaultFirebaseOptions.currentPlatform;
  debugPrint('[firebase_initializer] Initializing Firebase. options summary: apiKey=${options.apiKey.isNotEmpty}, appId=${options.appId.isNotEmpty}, projectId=${options.projectId.isNotEmpty}');
  try {
    final hasValidOptions = options.apiKey.isNotEmpty && options.appId.isNotEmpty && options.projectId.isNotEmpty;
    if (hasValidOptions) {
      debugPrint('[firebase_initializer] Using DefaultFirebaseOptions for initializeApp');
      await Firebase.initializeApp(
        options: options,
      );
    } else {
      debugPrint('[firebase_initializer] DefaultFirebaseOptions appear empty; calling Firebase.initializeApp() to use native config');
      await Firebase.initializeApp();
    }

    debugPrint('[firebase_initializer] Firebase.initializeApp completed');

    // Ensure Firebase Auth is ready by accessing current user
    final currentUser = FirebaseAuth.instance.currentUser;
    debugPrint('[firebase_initializer] Firebase Auth ready. Current user: ${currentUser?.uid ?? "none"}');
  } catch (e, st) {
    debugPrint('[firebase_initializer] Firebase.initializeApp ERROR: $e');
    debugPrint(st.toString());
    rethrow;
  }
}
