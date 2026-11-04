import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/portfolio_project_model.dart';
import '../utils/safe_firestore.dart';
import 'storage_service.dart';

/// Single write layer for artisan portfolio data (`artisans.portfolioImageUrls`)
/// and portfolio view analytics (`portfolio_analytics/{artisanId}`).
/// Mirrors the precedent set by QuoteService/DisputeService: a dedicated
/// service owns writes to its own collection scope, while JobService remains
/// the sole writer for `/jobs`.
class PortfolioService {
  final FirebaseFirestore _db;
  final StorageService _storage;

  PortfolioService(this._db, this._storage);

  static const int maxImages = 10;

  DocumentReference<Map<String, dynamic>> _artisanRef(String artisanId) =>
      _db.collection('artisans').doc(artisanId);

  Future<void> addImage({
    required String artisanId,
    required Uint8List bytes,
  }) async {
    final snapshot = await _artisanRef(artisanId).get();
    final current =
        List<String>.from(snapshot.data()?['portfolioImageUrls'] ?? []);
    if (current.length >= maxImages) {
      throw Exception('Portfolio is limited to $maxImages photos.');
    }
    final url = await _storage.uploadPortfolioImage(
      artisanId: artisanId,
      index: DateTime.now().millisecondsSinceEpoch,
      bytes: bytes,
    );
    await _artisanRef(artisanId).update({
      'portfolioImageUrls': FieldValue.arrayUnion([url]),
    });
  }

  Future<void> removeImage({
    required String artisanId,
    required String url,
  }) async {
    await _artisanRef(artisanId).update({
      'portfolioImageUrls': FieldValue.arrayRemove([url]),
    });
    try {
      await _storage.deletePortfolioImage(url);
    } catch (_) {
      // Storage object may already be gone — Firestore is the source of truth.
    }
  }

  Future<void> reorder({
    required String artisanId,
    required List<String> orderedUrls,
  }) =>
      _artisanRef(artisanId).update({'portfolioImageUrls': orderedUrls});

  Future<void> recordView(String artisanId) =>
      _db.collection('portfolio_analytics').doc(artisanId).set({
        'viewCount': FieldValue.increment(1),
        'lastViewedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Stream<int> watchViewCount(String artisanId) => _db
      .collection('portfolio_analytics')
      .doc(artisanId)
      .snapshots()
      .map((doc) => (doc.data()?['viewCount'] as num?)?.toInt() ?? 0);

  /// Upload an image to Storage and return its download URL without touching
  /// the artisan doc's portfolioImageUrls. Used by [PortfolioProjectScreen]
  /// which manages image lists on the project document instead.
  Future<String> addImageAndGetUrl({
    required String artisanId,
    required Uint8List bytes,
  }) =>
      _storage.uploadPortfolioImage(
        artisanId: artisanId,
        index: DateTime.now().millisecondsSinceEpoch,
        bytes: bytes,
      );

  // ─── Portfolio Projects ───────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _projects =>
      _db.collection('portfolio_projects');

  Future<void> createProject({
    required String artisanId,
    required String title,
    required String description,
    required String category,
    List<String> imageUrls = const [],
  }) async {
    final ref = _projects.doc();
    await ref.set({
      'id': ref.id,
      'artisanId': artisanId,
      'title': title,
      'description': description,
      'category': category,
      'imageUrls': imageUrls,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateProject({
    required String projectId,
    String? title,
    String? description,
    String? category,
    List<String>? imageUrls,
  }) async {
    final updates = <String, dynamic>{
      'title': ?title,
      'description': ?description,
      'category': ?category,
      'imageUrls': ?imageUrls,
    };
    if (updates.isEmpty) return;
    await _projects.doc(projectId).update(updates);
  }

  Future<void> deleteProject(String projectId) =>
      _projects.doc(projectId).delete();

  Stream<List<PortfolioProjectModel>> watchProjects(String artisanId) =>
      safeStream(
        _projects
            .where('artisanId', isEqualTo: artisanId)
            .orderBy('createdAt', descending: true),
        (d) => PortfolioProjectModel.fromJson({...d.data(), 'id': d.id}),
        debugLabel: 'portfolioProjects:$artisanId',
      );
}
