import 'package:cloud_firestore/cloud_firestore.dart';

/// A media record (`media/{id}`) as the owner may read it. Written only by
/// Cloud Functions (functions/media.js); the client never changes it.
/// Holds no URL: read URLs are short-lived and requested on demand.
class MediaRef {
  const MediaRef({
    required this.id,
    required this.ownerUid,
    required this.kind,
    required this.status,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.createdAt,
    this.rejectedReason,
  });

  final String id;
  final String ownerUid;
  final String kind;

  /// pending · uploading · uploaded · verifying · verified · deleting ·
  /// deleted · rejected · expired · delete_failed
  final String status;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final DateTime? createdAt;
  final String? rejectedReason;

  bool get isVerified => status == 'verified';
  bool get isGone => const {'deleted', 'expired', 'rejected'}.contains(status);
  bool get isDeletionPending => status == 'deleting' || status == 'delete_failed';

  factory MediaRef.fromFirestore(String id, Map<String, dynamic> d) => MediaRef(
        id: id,
        ownerUid: d['ownerUid'] as String? ?? '',
        kind: d['kind'] as String? ?? '',
        status: d['status'] as String? ?? 'unknown',
        mimeType: d['mimeType'] as String? ?? '',
        sizeBytes: (d['sizeBytes'] as num?)?.toInt() ?? 0,
        width: (d['width'] as num?)?.toInt(),
        height: (d['height'] as num?)?.toInt(),
        createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null,
        rejectedReason: d['rejectedReason'] as String?,
      );
}

/// A temporary read URL. Kept in memory only, never persisted.
class MediaUrl {
  const MediaUrl({required this.url, required this.expiresAt});
  final String url;
  final DateTime expiresAt;
  bool usableAt(DateTime now) => expiresAt.difference(now) > const Duration(seconds: 30);
}
