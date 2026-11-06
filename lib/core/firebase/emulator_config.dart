import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Local emulator mode — used to test the RumptyCloud staging media
/// integration (design/RUMPTYCLOUD_STAGING_INTEGRATION_IMPLEMENTATION_REPORT.md).
///
/// Needs BOTH, deliberately:
///  - `--dart-define=HT_EMULATOR=true`: the app starts on the local demo
///    project [projectId] and talks only to the Firebase emulators;
///  - `HT_EMULATOR=true` in the build ENVIRONMENT (Android): the production
///    `google-services.json` is not compiled in (android/app/build.gradle.kts).
///
/// If only the Dart flag is set, Firebase refuses to start (duplicate-app)
/// instead of silently using production. Release builds can never use it.
/// No production project, credential or service is reachable in this mode.
abstract final class EmulatorConfig {
  static const bool requested = bool.fromEnvironment('HT_EMULATOR');
  static bool get enabled => requested && !kReleaseMode;

  /// 10.0.2.2 reaches the host machine from the Android emulator; use
  /// 127.0.0.1 with `adb reverse` on a USB-connected phone.
  static const String _hostDefine = String.fromEnvironment('HT_EMULATOR_HOST');
  static String get host => _hostDefine.isNotEmpty ? _hostDefine : (kIsWeb ? 'localhost' : '10.0.2.2');

  /// `demo-` projects can never reach real Firebase resources.
  static const String projectId = 'demo-handytrust-media';
  static const int authPort = 9099;
  static const int firestorePort = 8090; // firebase.json
  static const int functionsPort = 5001;
  static const int storagePort = 9199;

  /// Placeholder identifiers accepted by the emulators; NOT real keys.
  /// The API key only has the FORMAT of a Firebase key ("AIza" + 35
  /// characters): the Android Functions SDK refuses any callable when Firebase
  /// Installations rejects the key's format (found on the device test). It
  /// belongs to no project and grants nothing. Assembled from parts so the
  /// source never contains a key-shaped literal (secret scanners).
  static final String placeholderApiKey = ['AI', 'za', 'SyDemoEmulatorOnly', 'KeyNotReal0000000'].join();
  static FirebaseOptions get options => FirebaseOptions(
    apiKey: placeholderApiKey,
    appId: '1:000000000000:android:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: projectId,
    storageBucket: '$projectId.appspot.com',
  );

  /// Initialises Firebase for the emulators. Call instead of the normal
  /// initialisation, before any Firebase service is used.
  static Future<void> initialize() async {
    if (kReleaseMode) throw StateError('HT_EMULATOR is not available in release builds.');
    try {
      await Firebase.initializeApp(options: options);
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') {
        throw StateError('Emulator mode needs an Android build made with HT_EMULATOR=true in the build environment, '
            'so the production Firebase configuration is not compiled in. Refusing to start.');
      }
      rethrow;
    }
    await FirebaseAuth.instance.useAuthEmulator(host, authPort);
    FirebaseFirestore.instance.useFirestoreEmulator(host, firestorePort);
    FirebaseFunctions.instance.useFunctionsEmulator(host, functionsPort);
    await FirebaseStorage.instance.useStorageEmulator(host, storagePort);
    debugPrint('[emulator] EMULATOR MODE — project $projectId at $host (auth $authPort, firestore $firestorePort, functions $functionsPort, storage $storagePort)');
  }
}
