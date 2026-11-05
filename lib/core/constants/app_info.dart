/// Verified application facts shown on the About screen (Stage 8.2).
/// [version] and [build] must equal `pubspec.yaml`'s `version:`; a test
/// (test/settings_test.dart) fails if they drift apart.
abstract final class AppInfo {
  static const name = 'HandyTrust';
  static const version = '1.0.0';
  static const build = '1';
  static const tagline = 'Find verified artisans and pay safely through escrow.';
}
