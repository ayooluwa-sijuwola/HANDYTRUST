import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/models/artisan_model.dart';

/// Unit tests for ArtisanModel.betaTester (design/BETA_TESTING_GUIDE.md).
///
/// Scope, stated plainly, same standing disclosure as the job-service tests:
/// these are pure model round-trip tests (fromJson/toJson/copyWith) — they
/// do NOT exercise firestore.rules' admin-only write restriction on this
/// field, which needs a Firestore emulator this repo doesn't have. What IS
/// tested is that the field itself defaults, serializes, and copies
/// correctly, since a wrong default here (e.g. defaulting to true) would be
/// a real security-relevant bug independent of the rules layer.
void main() {
  group('ArtisanModel.betaTester', () {
    test('defaults to false when absent from Firestore data — legacy '
        'artisan documents written before this field existed must never '
        'be silently treated as beta testers', () {
      final artisan = ArtisanModel.fromJson({'uid': 'a1', 'name': 'Ada'});
      expect(artisan.betaTester, isFalse);
    });

    test('round-trips true through fromJson/toJson', () {
      final artisan = ArtisanModel.fromJson({
        'uid': 'a1',
        'name': 'Ada',
        'betaTester': true,
      });
      expect(artisan.betaTester, isTrue);
      expect(artisan.toJson()['betaTester'], isTrue);
    });

    test('round-trips false through fromJson/toJson', () {
      final artisan = ArtisanModel.fromJson({
        'uid': 'a1',
        'name': 'Ada',
        'betaTester': false,
      });
      expect(artisan.betaTester, isFalse);
      expect(artisan.toJson()['betaTester'], isFalse);
    });

    test('copyWith(betaTester: true) flips it on without disturbing other fields', () {
      final base = ArtisanModel.fromJson({'uid': 'a1', 'name': 'Ada'});
      final updated = base.copyWith(betaTester: true);
      expect(updated.betaTester, isTrue);
      expect(updated.uid, base.uid);
      expect(updated.name, base.name);
    });

    test('copyWith() with no betaTester argument preserves the existing '
        'value instead of silently resetting it to the false default', () {
      final base = ArtisanModel.fromJson({
        'uid': 'a1',
        'name': 'Ada',
        'betaTester': true,
      });
      final updated = base.copyWith(bio: 'updated bio');
      expect(updated.betaTester, isTrue);
    });
  });
}
