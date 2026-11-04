import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/favorite_service.dart';
import '../models/artisan_model.dart';

final favoriteServiceProvider = Provider<FavoriteService>((ref) {
  return FavoriteService(FirebaseFirestore.instance);
});

/// Stream of the current user's favorited artisan IDs.
final favoriteIdsProvider =
    StreamProvider.family<Set<String>, String>((ref, userId) {
  return ref.watch(favoriteServiceProvider).watchFavoriteIds(userId);
});

/// Stream of full artisan profiles for the current user's favorites.
/// Fetches each profile individually — fine for typical favorite-list sizes (<30).
final favoriteArtisansProvider =
    StreamProvider.family<List<ArtisanModel>, String>((ref, userId) async* {
  await for (final ids in ref.read(favoriteServiceProvider).watchFavoriteIds(userId)) {
    if (ids.isEmpty) {
      yield [];
      continue;
    }
    final db = FirebaseFirestore.instance;
    final snaps = await Future.wait(
      ids.map((id) => db.collection('artisans').doc(id).get()),
    );
    yield snaps
        .where((s) => s.exists)
        .map((s) => ArtisanModel.fromJson({...s.data()!, 'uid': s.id}))
        .toList()
      ..sort((a, b) => b.trustScore.compareTo(a.trustScore));
  }
});
