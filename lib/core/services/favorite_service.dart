import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages artisan favorites for a customer.
/// Favorites are stored at `users/{uid}/favorites/{artisanId}` — the
/// document ID is the artisanId, enforcing one document per artisan per user.
class FavoriteService {
  final FirebaseFirestore _db;

  FavoriteService(this._db);

  CollectionReference<Map<String, dynamic>> _favCol(String userId) =>
      _db.collection('users').doc(userId).collection('favorites');

  Future<void> addFavorite(String userId, String artisanId) =>
      _favCol(userId).doc(artisanId).set({
        'artisanId': artisanId,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> removeFavorite(String userId, String artisanId) =>
      _favCol(userId).doc(artisanId).delete();

  Future<void> toggleFavorite(String userId, String artisanId) async {
    final ref = _favCol(userId).doc(artisanId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
    } else {
      await ref.set({
        'artisanId': artisanId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Stream of artisan IDs the user has favorited.
  Stream<Set<String>> watchFavoriteIds(String userId) =>
      _favCol(userId).snapshots().map(
            (snap) => snap.docs.map((d) => d.id).toSet(),
          );
}
