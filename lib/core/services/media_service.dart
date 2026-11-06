import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../models/media_ref.dart';

/// RumptyCloud staging media client (synthetic test media only).
///
/// Every step goes through Firebase (functions/media.js):
///   requestMediaUpload → (proxy) uploadMediaContent | (presigned) PUT →
///   confirmMediaUpload → getMediaUrl → deleteMedia.
/// No RumptyCloud credential exists in the app; read URLs live in memory
/// only; success is reported only after the server has verified the stored
/// object.

/// Calls a Cloud Function. Seam for tests.
abstract class MediaBackend {
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data, {Duration timeout});
}

class FirebaseMediaBackend implements MediaBackend {
  FirebaseMediaBackend(this._functions);
  final FirebaseFunctions _functions;

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data, {Duration timeout = const Duration(seconds: 60)}) async {
    final r = await _functions.httpsCallable(name, options: HttpsCallableOptions(timeout: timeout)).call(data);
    return Map<String, dynamic>.from(r.data as Map);
  }
}

/// Sends bytes to a presigned URL (presigned mode only). Seam for tests.
abstract class MediaUploader {
  Future<void> put(Uri url, Map<String, String> headers, Uint8List bytes, {void Function(int sent, int total)? onProgress});
}

class DioMediaUploader implements MediaUploader {
  DioMediaUploader([Dio? dio]) : _dio = dio ?? Dio();
  final Dio _dio;

  @override
  Future<void> put(Uri url, Map<String, String> headers, Uint8List bytes, {void Function(int sent, int total)? onProgress}) async {
    await _dio.putUri<void>(
      url,
      data: Stream<List<int>>.value(bytes),
      onSendProgress: onProgress,
      options: Options(
        headers: headers,
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (s) => s != null && s >= 200 && s < 300,
      ),
    );
  }
}

enum MediaFailureKind { notSignedIn, notAllowed, invalidFile, rejected, limitReached, expired, notReady, notConfigured, notFound, offline, timeout, unavailable, unknown }

class MediaFailure implements Exception {
  const MediaFailure(this.kind, this.message, {this.reason});
  final MediaFailureKind kind;

  /// Safe to show to the user.
  final String message;

  /// Server rejection reason (e.g. checksum_mismatch), when given.
  final String? reason;

  @override
  String toString() => 'MediaFailure($kind${reason == null ? '' : ', $reason'})';
}

enum MediaUploadStage { hashing, requesting, uploading, verifying, done }

class MediaUploadProgress {
  const MediaUploadProgress(this.stage, {this.fraction});
  final MediaUploadStage stage;

  /// 0–1 while bytes are sent to a presigned URL; null when unknown.
  final double? fraction;
}

class MediaDeleteResult {
  const MediaDeleteResult(this.status, {required this.retryScheduled});
  final String status;
  final bool retryScheduled;

  /// True only once the server confirms the object is gone.
  bool get deleted => status == 'deleted';
}

class MediaService {
  MediaService(this._backend, this._uploader, {required String? Function() currentUid, DateTime Function()? now})
      : _currentUid = currentUid,
        _now = now ?? DateTime.now;

  final MediaBackend _backend;
  final MediaUploader _uploader;
  final String? Function() _currentUid;
  final DateTime Function() _now;
  final Map<String, MediaUrl> _urls = {};

  static const Set<String> stagingKinds = {'test-avatar', 'test-portfolio', 'test-thumb'};
  static const Set<String> imageTypes = {'image/jpeg', 'image/png', 'image/webp'};

  static String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

  void _requireSignedIn() {
    if (_currentUid() == null) throw const MediaFailure(MediaFailureKind.notSignedIn, 'Please sign in again.');
  }

  /// Forget temporary URLs (call on sign-out / account change).
  void clearCache() => _urls.clear();

  /// Uploads [bytes] and returns the media id once the SERVER has verified
  /// the stored object. On any failure after the request, the pending
  /// record is released (best effort) so a retry starts clean.
  Future<String> upload({
    required String kind,
    required String mimeType,
    required Uint8List bytes,
    void Function(MediaUploadProgress p)? onProgress,
  }) async {
    _requireSignedIn();
    if (!stagingKinds.contains(kind)) throw const MediaFailure(MediaFailureKind.invalidFile, 'This media type is not available.');
    if (!imageTypes.contains(mimeType)) throw const MediaFailure(MediaFailureKind.invalidFile, 'Only JPEG, PNG and WebP images are accepted.');
    if (bytes.isEmpty) throw const MediaFailure(MediaFailureKind.invalidFile, 'The file is empty.');

    onProgress?.call(const MediaUploadProgress(MediaUploadStage.hashing));
    final digest = sha256Hex(bytes);
    onProgress?.call(const MediaUploadProgress(MediaUploadStage.requesting));
    final req = await _guard(() => _backend.call('requestMediaUpload', {'kind': kind, 'mimeType': mimeType, 'sizeBytes': bytes.length, 'sha256': digest}));
    final mediaId = req['mediaId'] as String;
    try {
      onProgress?.call(const MediaUploadProgress(MediaUploadStage.uploading, fraction: 0));
      if (req['mode'] == 'presigned') {
        final up = Map<String, dynamic>.from(req['upload'] as Map);
        final expiresAt = DateTime.fromMillisecondsSinceEpoch((req['expiresAt'] as num).toInt());
        if (!expiresAt.isAfter(_now())) throw const MediaFailure(MediaFailureKind.expired, 'The upload link expired. Please try again.');
        await _guardHttp(() => _uploader.put(
              Uri.parse(up['url'] as String),
              Map<String, String>.from(up['headers'] as Map),
              bytes,
              onProgress: (sent, total) => onProgress?.call(MediaUploadProgress(MediaUploadStage.uploading, fraction: total > 0 ? sent / total : null)),
            ));
      } else {
        await _guard(() => _backend.call('uploadMediaContent', {'mediaId': mediaId, 'dataBase64': base64Encode(bytes)}, timeout: const Duration(seconds: 120)));
      }
      onProgress?.call(const MediaUploadProgress(MediaUploadStage.verifying));
      final c = await _guard(() => _backend.call('confirmMediaUpload', {'mediaId': mediaId}, timeout: const Duration(seconds: 120)));
      if (c['status'] != 'verified') throw const MediaFailure(MediaFailureKind.unknown, 'The upload could not be verified.');
      onProgress?.call(const MediaUploadProgress(MediaUploadStage.done, fraction: 1));
      return mediaId;
    } on MediaFailure {
      await _releaseQuietly(mediaId);
      rethrow;
    }
  }

  Future<void> _releaseQuietly(String mediaId) async {
    try {
      await _backend.call('deleteMedia', {'mediaId': mediaId});
    } catch (_) {
      // The server expires abandoned uploads itself (15 minutes).
    }
  }

  /// A temporary read URL (cached in memory until shortly before expiry).
  Future<MediaUrl> readUrl(String mediaId, {bool forceRefresh = false}) async {
    _requireSignedIn();
    final cached = _urls[mediaId];
    if (!forceRefresh && cached != null && cached.usableAt(_now())) return cached;
    final r = await _guard(() => _backend.call('getMediaUrl', {'mediaId': mediaId}));
    final url = MediaUrl(url: r['url'] as String, expiresAt: DateTime.fromMillisecondsSinceEpoch((r['expiresAt'] as num).toInt()));
    _urls[mediaId] = url;
    return url;
  }

  /// Requests deletion. [MediaDeleteResult.deleted] is true only when the
  /// server confirmed the object is gone; otherwise it is retried later.
  Future<MediaDeleteResult> delete(String mediaId) async {
    _requireSignedIn();
    _urls.remove(mediaId);
    final r = await _guard(() => _backend.call('deleteMedia', {'mediaId': mediaId}));
    return MediaDeleteResult(r['status'] as String? ?? 'unknown', retryScheduled: r['retryScheduled'] == true);
  }

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MediaFailure {
      rethrow;
    } on FirebaseFunctionsException catch (e) {
      throw mapFunctionsError(e.code, e.message, e.details);
    } on TimeoutException {
      throw const MediaFailure(MediaFailureKind.timeout, 'The request timed out. Check your connection and try again.');
    }
  }

  Future<void> _guardHttp(Future<void> Function() op) async {
    try {
      await op();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// Maps a callable error to a user-safe failure.
  static MediaFailure mapFunctionsError(String code, String? message, Object? details) {
    final reason = details is Map ? details['reason'] as String? : null;
    final msg = message ?? '';
    switch (code) {
      case 'unauthenticated':
        return const MediaFailure(MediaFailureKind.notSignedIn, 'Please sign in again.');
      case 'permission-denied':
        return MediaFailure(MediaFailureKind.notAllowed, msg.isEmpty ? 'You are not allowed to do this.' : msg);
      case 'invalid-argument':
        return reason != null
            ? MediaFailure(MediaFailureKind.rejected, _rejectionText(reason), reason: reason)
            : MediaFailure(MediaFailureKind.invalidFile, msg.isEmpty ? 'This file cannot be uploaded.' : msg);
      case 'resource-exhausted':
        return MediaFailure(MediaFailureKind.limitReached, 'Upload limit reached. Please try again later.', reason: reason);
      case 'not-found':
        return const MediaFailure(MediaFailureKind.notFound, 'This media no longer exists.');
      case 'failed-precondition':
        if (msg.contains('not configured')) return const MediaFailure(MediaFailureKind.notConfigured, 'Media storage is not configured on this server.');
        if (msg.contains('expired')) return MediaFailure(MediaFailureKind.expired, msg);
        return MediaFailure(MediaFailureKind.notReady, msg.isEmpty ? 'This media is not ready.' : msg);
      case 'unavailable':
        return const MediaFailure(MediaFailureKind.unavailable, 'Media storage is unavailable. Check your connection and try again.');
      case 'deadline-exceeded':
        return const MediaFailure(MediaFailureKind.timeout, 'The request timed out. Please try again.');
      default:
        return const MediaFailure(MediaFailureKind.unknown, 'Something went wrong. Please try again.');
    }
  }

  static MediaFailure mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
        return const MediaFailure(MediaFailureKind.offline, 'You appear to be offline. Please try again.');
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const MediaFailure(MediaFailureKind.timeout, 'The upload timed out. Please try again.');
      case DioExceptionType.badResponse:
        return const MediaFailure(MediaFailureKind.expired, 'The storage service refused the upload (the link may have expired). Please try again.');
      default:
        return const MediaFailure(MediaFailureKind.unknown, 'The upload failed. Please try again.');
    }
  }

  static String _rejectionText(String reason) => switch (reason) {
        'checksum_mismatch' => 'The file changed during upload. Please try again.',
        'size_mismatch' => 'The file size did not match. Please try again.',
        'type_mismatch' => 'The file is not the image type it claims to be.',
        'unrecognised_format' => 'This is not a JPEG, PNG or WebP image.',
        'truncated_or_trailing_data' => 'The image is incomplete or has extra data attached.',
        'dimensions_too_large' => 'The image dimensions are too large.',
        'thumbnail_too_large' => 'Thumbnails must be at most 512 × 512 pixels.',
        _ => 'The file was rejected.',
      };
}
