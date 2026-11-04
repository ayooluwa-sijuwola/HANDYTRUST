import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../utils/image_privacy.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const int _maxUploadBytes = 5 * 1024 * 1024;
  // storage.rules allows verification photos up to 10 MB (vs 5 MB for
  // everything else) since selfie/ID legibility matters more than for job
  // photos. The client check was previously stricter than the server rule,
  // causing a high-res but otherwise-valid photo to be rejected locally
  // before it ever reached Storage — one contributor to "uploads fail
  // intermittently."
  static const int _maxVerificationUploadBytes = 10 * 1024 * 1024;

  /// Upload a job image. The path includes [userId] so Storage rules can
  /// verify that only the uploader can write to their own sub-folder:
  ///   jobs/{jobId}/{userId}/[subfolder/]image_{index}.jpg
  ///
  /// [subfolder] can be 'before' or 'after' to separate arrival/completion
  /// photos within the same job. Defaults to empty (root of user folder).
  Future<String> uploadJobImageBytes({
    required String jobId,
    required String userId,
    required int index,
    required Uint8List bytes,
    String subfolder = '',
  }) async {
    // Stage 7.1 (F-2): strip GPS/EXIF from EVERY photo, whatever its size.
    bytes = await ImagePrivacy.sanitize(bytes);
    if (bytes.isEmpty) throw Exception('Image payload is empty.');
    if (bytes.lengthInBytes > _maxUploadBytes) {
      throw Exception('Image exceeds the 5 MB limit.');
    }

    final sub = subfolder.isEmpty ? '' : '$subfolder/';
    final path = 'jobs/$jobId/$userId/${sub}image_$index.jpg';
    final ref = _storage.ref(path);
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {'jobId': jobId, 'userId': userId, 'index': '$index'},
    );

    debugPrint('[StorageService] upload started: $path (${bytes.lengthInBytes} bytes)');
    final task = await ref.putData(bytes, metadata);
    final url = await _getDownloadUrlWithRetry(task.ref, path);
    debugPrint('[StorageService] upload completed: $path -> $url');
    return url;
  }

  /// Upload a profile photo.
  Future<String> uploadProfilePhoto({
    required String userId,
    required Uint8List bytes,
  }) async {
    // Stage 7.1 (F-2): strip GPS/EXIF from EVERY photo, whatever its size.
    bytes = await ImagePrivacy.sanitize(bytes);
    if (bytes.lengthInBytes > _maxUploadBytes) {
      throw Exception('Photo exceeds the 5 MB limit.');
    }
    final path = 'users/$userId/profile.jpg';
    final ref = _storage.ref(path);
    debugPrint('[StorageService] upload started: $path (${bytes.lengthInBytes} bytes)');
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await _getDownloadUrlWithRetry(task.ref, path);
    debugPrint('[StorageService] upload completed: $path -> $url');
    return url;
  }

  /// Upload a verification photo (selfie or government ID).
  /// Path: verifications/{userId}/{type}.jpg
  /// [type] is 'selfie' or 'id_front'.
  Future<String> uploadVerificationPhoto({
    required String userId,
    required String type,
    required Uint8List bytes,
  }) async {
    // Stage 7.1 (F-2): strip GPS/EXIF from EVERY photo, whatever its size.
    bytes = await ImagePrivacy.sanitize(bytes);
    if (bytes.isEmpty) {
      throw Exception('$type photo is empty — please retake it.');
    }
    if (bytes.lengthInBytes > _maxVerificationUploadBytes) {
      throw Exception('$type photo exceeds the 10 MB limit.');
    }
    final path = 'verifications/$userId/$type.jpg';
    final ref = _storage.ref(path);
    debugPrint('[StorageService] upload started: $path (${bytes.lengthInBytes} bytes)');
    final task = await ref.putData(
      bytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'userId': userId, 'type': type},
      ),
    );
    // putData() resolving success doesn't guarantee the object is
    // immediately readable — GCS can take a moment to propagate a
    // just-finalized object, and getDownloadURL() called right after can
    // throw [firebase_storage/object-not-found] even though the upload
    // genuinely succeeded. Retry with backoff before giving up.
    final url = await _getDownloadUrlWithRetry(task.ref, path);
    debugPrint('[StorageService] upload completed: $path -> $url');
    return url;
  }

  Future<String> _getDownloadUrlWithRetry(
    Reference ref,
    String path, {
    int attempts = 4,
  }) async {
    for (var i = 0; i < attempts; i++) {
      try {
        return await ref.getDownloadURL();
      } on FirebaseException catch (e) {
        final isLastAttempt = i == attempts - 1;
        if (e.code != 'object-not-found' || isLastAttempt) {
          debugPrint('[StorageService] getDownloadURL failed for $path: ${e.code}');
          rethrow;
        }
        debugPrint('[StorageService] getDownloadURL retry ${i + 1}/$attempts for $path (object-not-found, propagation delay)');
        await Future.delayed(Duration(milliseconds: 400 * (i + 1)));
      }
    }
    throw StateError('unreachable');
  }

  /// Upload an artisan portfolio image.
  /// Path: artisan_portfolio/{artisanId}/image_{index}.jpg
  Future<String> uploadPortfolioImage({
    required String artisanId,
    required int index,
    required Uint8List bytes,
  }) async {
    // Stage 7.1 (F-2): strip GPS/EXIF from EVERY photo, whatever its size.
    bytes = await ImagePrivacy.sanitize(bytes);
    if (bytes.lengthInBytes > _maxUploadBytes) {
      throw Exception('Image exceeds the 5 MB limit.');
    }
    final path = 'artisan_portfolio/$artisanId/image_$index.jpg';
    final ref = _storage.ref(path);
    debugPrint('[StorageService] upload started: $path (${bytes.lengthInBytes} bytes)');
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await _getDownloadUrlWithRetry(task.ref, path);
    debugPrint('[StorageService] upload completed: $path -> $url');
    return url;
  }

  /// Delete a portfolio image given its download URL.
  Future<void> deletePortfolioImage(String url) =>
      _storage.refFromURL(url).delete();

  /// Upload a dispute evidence photo.
  Future<String> uploadDisputeEvidence({
    required String disputeId,
    required String userId,
    required int index,
    required Uint8List bytes,
  }) async {
    // Stage 7.1 (F-2): strip GPS/EXIF from EVERY photo, whatever its size.
    bytes = await ImagePrivacy.sanitize(bytes);
    if (bytes.lengthInBytes > _maxUploadBytes) {
      throw Exception('Photo exceeds the 5 MB limit.');
    }
    final path = 'disputes/$disputeId/$userId/evidence_$index.jpg';
    final ref = _storage.ref(path);
    debugPrint('[StorageService] upload started: $path (${bytes.lengthInBytes} bytes)');
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await _getDownloadUrlWithRetry(task.ref, path);
    debugPrint('[StorageService] upload completed: $path -> $url');
    return url;
  }
}
