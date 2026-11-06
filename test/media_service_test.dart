// RumptyCloud staging media — Flutter client tests (fakes only: no Firebase,
// no network). The server-side checks are covered by
// functions/test/media_offline.test.js.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/firebase/emulator_config.dart';
import 'package:handy_trust/core/services/media_service.dart';
import 'package:handy_trust/models/media_ref.dart';

class _Backend implements MediaBackend {
  final calls = <(String, Map<String, dynamic>)>[];
  final Map<String, Object Function(Map<String, dynamic>)> handlers = {};

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data, {Duration timeout = const Duration(seconds: 60)}) async {
    calls.add((name, data));
    final h = handlers[name];
    if (h == null) throw StateError('unexpected call $name');
    final r = h(data);
    if (r is Exception) throw r;
    return Map<String, dynamic>.from(r as Map);
  }

  List<String> get names => calls.map((c) => c.$1).toList();
}

class _Uploader implements MediaUploader {
  Uri? url;
  Map<String, String>? headers;
  Uint8List? bytes;
  Exception? fail;
  @override
  Future<void> put(Uri url, Map<String, String> headers, Uint8List bytes, {void Function(int sent, int total)? onProgress}) async {
    if (fail != null) throw fail!;
    this.url = url;
    this.headers = headers;
    this.bytes = bytes;
    onProgress?.call(bytes.length ~/ 2, bytes.length);
    onProgress?.call(bytes.length, bytes.length);
  }
}

FirebaseFunctionsException _fx(String code, [String message = 'x', Object? details]) => FirebaseFunctionsException(code: code, message: message, details: details);

void main() {
  final bytes = Uint8List.fromList(List<int>.generate(200, (i) => i % 251));
  var now = DateTime(2026, 11, 6, 12);
  late _Backend backend;
  late _Uploader uploader;
  late MediaService service;
  String? uid = 'u1';

  setUp(() {
    now = DateTime(2026, 11, 6, 12);
    uid = 'u1';
    backend = _Backend();
    uploader = _Uploader();
    service = MediaService(backend, uploader, currentUid: () => uid, now: () => now);
    backend.handlers['requestMediaUpload'] = (_) => {'mediaId': 'm1', 'mode': 'proxy', 'expiresAt': now.add(const Duration(minutes: 15)).millisecondsSinceEpoch};
    backend.handlers['uploadMediaContent'] = (_) => {'mediaId': 'm1', 'status': 'uploaded'};
    backend.handlers['confirmMediaUpload'] = (_) => {'mediaId': 'm1', 'status': 'verified'};
    backend.handlers['deleteMedia'] = (_) => {'mediaId': 'm1', 'status': 'deleted', 'retryScheduled': false};
  });

  test('SHA-256 is the real digest of the bytes', () {
    expect(MediaService.sha256Hex(Uint8List.fromList(utf8.encode('abc'))), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  group('upload', () {
    test('proxy: request → upload content → confirm; success only after the server verified', () async {
      final stages = <MediaUploadStage>[];
      final id = await service.upload(kind: 'test-portfolio', mimeType: 'image/png', bytes: bytes, onProgress: (p) => stages.add(p.stage));
      expect(id, 'm1');
      expect(backend.names, ['requestMediaUpload', 'uploadMediaContent', 'confirmMediaUpload']);
      final req = backend.calls.first.$2;
      expect(req, {'kind': 'test-portfolio', 'mimeType': 'image/png', 'sizeBytes': 200, 'sha256': MediaService.sha256Hex(bytes)});
      expect(base64Decode(backend.calls[1].$2['dataBase64'] as String), bytes);
      expect(stages, [MediaUploadStage.hashing, MediaUploadStage.requesting, MediaUploadStage.uploading, MediaUploadStage.verifying, MediaUploadStage.done]);
      expect(stages.last, MediaUploadStage.done);
    });

    test('presigned: bytes go to the returned URL with the signed headers; progress is reported', () async {
      backend.handlers['requestMediaUpload'] = (_) => {
            'mediaId': 'm1',
            'mode': 'presigned',
            'expiresAt': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
            'upload': {'method': 'PUT', 'url': 'https://s3.rumptycloud.com/b/k?X-Amz-Signature=s', 'headers': {'Content-Type': 'image/png', 'Content-Length': '200'}},
          };
      final fractions = <double?>[];
      await service.upload(kind: 'test-portfolio', mimeType: 'image/png', bytes: bytes, onProgress: (p) => p.stage == MediaUploadStage.uploading ? fractions.add(p.fraction) : null);
      expect(uploader.url.toString(), 'https://s3.rumptycloud.com/b/k?X-Amz-Signature=s');
      expect(uploader.headers, {'Content-Type': 'image/png', 'Content-Length': '200'});
      expect(uploader.bytes, bytes);
      expect(fractions, [0, 0.5, 1.0]);
      expect(backend.names, ['requestMediaUpload', 'confirmMediaUpload']);
    });

    test('an expired upload link fails before sending and releases the reservation', () async {
      backend.handlers['requestMediaUpload'] = (_) => {
            'mediaId': 'm1', 'mode': 'presigned', 'expiresAt': now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
            'upload': {'method': 'PUT', 'url': 'https://x', 'headers': <String, String>{}},
          };
      await expectLater(service.upload(kind: 'test-portfolio', mimeType: 'image/png', bytes: bytes), throwsA(isA<MediaFailure>().having((f) => f.kind, 'kind', MediaFailureKind.expired)));
      expect(uploader.url, isNull);
      expect(backend.names.last, 'deleteMedia');
    });

    test('a server rejection is surfaced with its reason, never as success, and the record is released', () async {
      backend.handlers['uploadMediaContent'] = (_) => _fx('invalid-argument', 'The file was rejected.', {'reason': 'checksum_mismatch'});
      final stages = <MediaUploadStage>[];
      await expectLater(
        service.upload(kind: 'test-portfolio', mimeType: 'image/png', bytes: bytes, onProgress: (p) => stages.add(p.stage)),
        throwsA(isA<MediaFailure>().having((f) => f.kind, 'kind', MediaFailureKind.rejected).having((f) => f.reason, 'reason', 'checksum_mismatch')),
      );
      expect(stages, isNot(contains(MediaUploadStage.done)));
      expect(backend.names, ['requestMediaUpload', 'uploadMediaContent', 'deleteMedia']);
    });

    test('a confirm that does not end in "verified" is a failure', () async {
      backend.handlers['confirmMediaUpload'] = (_) => {'mediaId': 'm1', 'status': 'pending'};
      await expectLater(service.upload(kind: 'test-portfolio', mimeType: 'image/png', bytes: bytes), throwsA(isA<MediaFailure>()));
      expect(backend.names.last, 'deleteMedia');
    });

    test('network failures on the presigned PUT map to offline / timeout / refused', () async {
      backend.handlers['requestMediaUpload'] = (_) => {
            'mediaId': 'm1', 'mode': 'presigned', 'expiresAt': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
            'upload': {'method': 'PUT', 'url': 'https://x', 'headers': <String, String>{}},
          };
      for (final (type, kind) in [
        (DioExceptionType.connectionError, MediaFailureKind.offline),
        (DioExceptionType.sendTimeout, MediaFailureKind.timeout),
        (DioExceptionType.badResponse, MediaFailureKind.expired),
      ]) {
        uploader.fail = DioException(requestOptions: RequestOptions(), type: type);
        await expectLater(service.upload(kind: 'test-portfolio', mimeType: 'image/png', bytes: bytes), throwsA(isA<MediaFailure>().having((f) => f.kind, 'kind', kind)));
      }
    });

    test('nothing is sent when signed out, or for a non-staging kind, a non-image type or an empty file', () async {
      uid = null;
      await expectLater(service.upload(kind: 'test-portfolio', mimeType: 'image/png', bytes: bytes), throwsA(isA<MediaFailure>().having((f) => f.kind, 'kind', MediaFailureKind.notSignedIn)));
      uid = 'u1';
      for (final (kind, mime, b) in [('avatar', 'image/png', bytes), ('identity-document', 'image/png', bytes), ('test-video', 'image/png', bytes), ('test-portfolio', 'video/mp4', bytes), ('test-portfolio', 'image/png', Uint8List(0))]) {
        await expectLater(service.upload(kind: kind, mimeType: mime, bytes: b), throwsA(isA<MediaFailure>().having((f) => f.kind, 'kind', MediaFailureKind.invalidFile)));
      }
      expect(backend.calls, isEmpty);
    });
  });

  test('callable errors map to user-safe failures', () {
    final cases = {
      'unauthenticated': MediaFailureKind.notSignedIn,
      'permission-denied': MediaFailureKind.notAllowed,
      'invalid-argument': MediaFailureKind.invalidFile,
      'resource-exhausted': MediaFailureKind.limitReached,
      'not-found': MediaFailureKind.notFound,
      'unavailable': MediaFailureKind.unavailable,
      'deadline-exceeded': MediaFailureKind.timeout,
      'internal': MediaFailureKind.unknown,
    };
    cases.forEach((code, kind) => expect(MediaService.mapFunctionsError(code, 'm', null).kind, kind, reason: code));
    expect(MediaService.mapFunctionsError('failed-precondition', 'Media storage is not configured.', null).kind, MediaFailureKind.notConfigured);
    expect(MediaService.mapFunctionsError('failed-precondition', 'This upload has expired. Please start again.', null).kind, MediaFailureKind.expired);
    expect(MediaService.mapFunctionsError('failed-precondition', 'The upload has not arrived yet.', null).kind, MediaFailureKind.notReady);
    final r = MediaService.mapFunctionsError('invalid-argument', 'x', {'reason': 'type_mismatch'});
    expect((r.kind, r.reason), (MediaFailureKind.rejected, 'type_mismatch'));
  });

  group('temporary read URLs (memory only)', () {
    test('cached until 30 s before expiry; forceRefresh and clearCache fetch again', () async {
      var n = 0;
      backend.handlers['getMediaUrl'] = (_) => {'url': 'https://signed/${++n}', 'expiresAt': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch};
      expect((await service.readUrl('m1')).url, 'https://signed/1');
      expect((await service.readUrl('m1')).url, 'https://signed/1');
      now = now.add(const Duration(minutes: 4, seconds: 31)); // < 30 s left
      expect((await service.readUrl('m1')).url, 'https://signed/2');
      expect((await service.readUrl('m1', forceRefresh: true)).url, 'https://signed/3');
      service.clearCache();
      expect((await service.readUrl('m1')).url, 'https://signed/4');
    });
    test('refused for another user surfaces as not found', () async {
      backend.handlers['getMediaUrl'] = (_) => _fx('not-found', 'Media not found.');
      await expectLater(service.readUrl('m1'), throwsA(isA<MediaFailure>().having((f) => f.kind, 'kind', MediaFailureKind.notFound)));
    });
  });

  group('delete', () {
    test('success only when the server confirms the object is gone', () async {
      expect((await service.delete('m1')).deleted, isTrue);
      backend.handlers['deleteMedia'] = (_) => {'mediaId': 'm1', 'status': 'deleting', 'retryScheduled': true};
      final r = await service.delete('m1');
      expect((r.deleted, r.retryScheduled, r.status), (false, true, 'deleting'));
      backend.handlers['deleteMedia'] = (_) => {'mediaId': 'm1', 'status': 'delete_failed', 'retryScheduled': false};
      expect((await service.delete('m1')).deleted, isFalse);
    });
    test('deleting drops the cached URL', () async {
      var n = 0;
      backend.handlers['getMediaUrl'] = (_) => {'url': 'https://signed/${++n}', 'expiresAt': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch};
      await service.readUrl('m1');
      await service.delete('m1');
      expect((await service.readUrl('m1')).url, 'https://signed/2');
    });
  });

  test('MediaRef parses the server record and holds no URL', () {
    final m = MediaRef.fromFirestore('m1', {
      'ownerUid': 'u1', 'kind': 'test-avatar', 'status': 'verified', 'mimeType': 'image/png', 'sizeBytes': 168, 'width': 64, 'height': 48,
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 6)), 'objectKey': 'staging/media/x.png',
    });
    expect((m.isVerified, m.isGone, m.width, m.sizeBytes), (true, false, 64, 168));
    expect(MediaRef.fromFirestore('m2', {'status': 'deleting'}).isDeletionPending, isTrue);
  });

  test('emulator mode is off unless explicitly requested, and uses a demo project only', () {
    expect(EmulatorConfig.requested, isFalse);
    expect(EmulatorConfig.enabled, isFalse);
    expect(EmulatorConfig.projectId, startsWith('demo-'));
    expect(EmulatorConfig.options.projectId, EmulatorConfig.projectId);
    expect(EmulatorConfig.options.apiKey, isNot(startsWith('AIza'))); // not a real API key
  });
}
