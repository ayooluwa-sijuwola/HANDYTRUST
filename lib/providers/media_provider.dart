import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/media_service.dart';
import '../models/media_ref.dart';
import 'auth_provider.dart';

/// RumptyCloud staging media (synthetic test media only; emulator mode).
final mediaServiceProvider = Provider<MediaService>((ref) {
  final service = MediaService(
    FirebaseMediaBackend(FirebaseFunctions.instance),
    DioMediaUploader(),
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
  );
  // Temporary URLs never outlive the account that requested them.
  ref.listen(authStateChangesProvider, (_, _) => service.clearCache());
  return service;
});

/// The signed-in user's media records (owner-readable per firestore.rules).
final myMediaProvider = StreamProvider.autoDispose<List<MediaRef>>((ref) {
  final uid = ref.watch(authStateChangesProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const <MediaRef>[]);
  return FirebaseFirestore.instance
      .collection('media')
      .where('ownerUid', isEqualTo: uid)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map((d) => MediaRef.fromFirestore(d.id, d.data())).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0))));
});

/// A temporary read URL for one verified media item.
final mediaUrlProvider = FutureProvider.autoDispose.family<MediaUrl, String>(
  (ref, mediaId) => ref.watch(mediaServiceProvider).readUrl(mediaId),
);
