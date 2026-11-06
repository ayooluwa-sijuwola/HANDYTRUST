// RumptyCloud staging media — LIVE test of the APP's client code path:
// MediaService + DioMediaUploader against the real stack (Auth + Functions
// emulators of demo-handytrust-media, real staging bucket). Images are the
// synthetic fixtures; downloaded private bytes are decoded by Flutter's image
// codec and painted by an Image widget.
//
// Skipped unless RUMPTY_LIVE=1 and the emulators are running (see
// design/RUMPTYCLOUD_LIVE_STAGING_TEST_GUIDE.md). Never prints URLs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/media_service.dart';

const _project = 'demo-handytrust-media';
const _auth = 'http://127.0.0.1:9099';
const _functions = 'http://127.0.0.1:5001/$_project/us-central1';
const _firestore = 'http://127.0.0.1:8090/v1/projects/$_project/databases/(default)/documents';
final bool _live = Platform.environment['RUMPTY_LIVE'] == '1';

class _HttpCallableBackend implements MediaBackend {
  _HttpCallableBackend(this.token);
  final String token;
  final _dio = Dio();
  static const _codes = {
    'UNAUTHENTICATED': 'unauthenticated', 'PERMISSION_DENIED': 'permission-denied', 'INVALID_ARGUMENT': 'invalid-argument',
    'RESOURCE_EXHAUSTED': 'resource-exhausted', 'NOT_FOUND': 'not-found', 'FAILED_PRECONDITION': 'failed-precondition',
    'UNAVAILABLE': 'unavailable', 'DEADLINE_EXCEEDED': 'deadline-exceeded',
  };

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data, {Duration timeout = const Duration(seconds: 60)}) async {
    final r = await _dio.post<Map<String, dynamic>>('$_functions/$name',
        data: jsonEncode({'data': data}),
        options: Options(headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}, receiveTimeout: timeout, validateStatus: (_) => true));
    final body = r.data ?? const {};
    if (body['error'] is Map) {
      final e = body['error'] as Map;
      throw FirebaseFunctionsException(code: _codes[e['status']] ?? 'unknown', message: e['message'] as String? ?? '', details: e['details']);
    }
    return Map<String, dynamic>.from(body['result'] as Map);
  }
}

Future<(String uid, String token)> _user(String email) async {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  final body = {'email': email, 'password': 'synthetic-pass-123', 'returnSecureToken': true};
  final s = await dio.post<Map<String, dynamic>>('$_auth/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo', data: body);
  final uid = s.data!['localId'] as String;
  await dio.post<dynamic>('$_auth/identitytoolkit.googleapis.com/v1/projects/$_project/accounts:update',
      data: {'localId': uid, 'emailVerified': true}, options: Options(headers: {'Authorization': 'Bearer owner'}));
  final t = await dio.post<Map<String, dynamic>>('$_auth/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo', data: body);
  return (uid, t.data!['idToken'] as String);
}

Future<Map<String, dynamic>> _record(String mediaId) async {
  final r = await Dio().get<Map<String, dynamic>>('$_firestore/media/$mediaId', options: Options(headers: {'Authorization': 'Bearer owner'}));
  final f = r.data!['fields'] as Map<String, dynamic>;
  return f.map((k, v) => MapEntry(k, (v as Map).values.first));
}

void main() {
  final fixtures = {'JPEG': ('synthetic_64x48.jpg', 'image/jpeg', 64, 48), 'PNG': ('synthetic_64x48.png', 'image/png', 64, 48), 'WebP': ('synthetic_1x1.webp', 'image/webp', 1, 1)};

  testWidgets('app media client: upload, verify, read twice, display, refuse others, delete (live)', (tester) async {
    HttpOverrides.global = null; // real network for this test only
    final evidence = <String, Object?>{};
    await tester.runAsync(() async {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final (ownerUid, ownerToken) = await _user('live-app-owner-$stamp@example.test');
      final (_, otherToken) = await _user('live-app-other-$stamp@example.test');
      final owner = MediaService(_HttpCallableBackend(ownerToken), DioMediaUploader(), currentUid: () => ownerUid);
      final other = MediaService(_HttpCallableBackend(otherToken), DioMediaUploader(), currentUid: () => 'other');

      for (final MapEntry(key: label, value: (file, mime, w, h)) in fixtures.entries) {
        final bytes = File('functions/test/fixtures/media/$file').readAsBytesSync();
        final up = await owner.upload(kind: 'test-portfolio', mimeType: mime, bytes: Uint8List.fromList(bytes));
        final rec = await _record(up.mediaId);
        expect(rec['status'], 'verified', reason: label);
        expect(rec['verifiedSha256'], MediaService.sha256Hex(Uint8List.fromList(bytes)), reason: label);

        // Read twice: the second request bypasses the cache (a fresh signed link).
        final u1 = await owner.readUrl(up.mediaId);
        final u2 = await owner.readUrl(up.mediaId, forceRefresh: true);
        final got1 = (await Dio().get<List<int>>(u1.url, options: Options(responseType: ResponseType.bytes))).data!;
        final got2 = (await Dio().get<List<int>>(u2.url, options: Options(responseType: ResponseType.bytes))).data!;
        expect(got1, bytes, reason: '$label first read');
        expect(got2, bytes, reason: '$label refreshed read');

        // Decoded by Flutter's own image codec (what Image.network uses).
        final codec = await ui.instantiateImageCodec(Uint8List.fromList(got1));
        final frame = await codec.getNextFrame();
        expect((frame.image.width, frame.image.height), (w, h), reason: '$label decoded size');
        frame.image.dispose();

        // Another account cannot obtain a link.
        await expectLater(other.readUrl(up.mediaId), throwsA(isA<MediaFailure>().having((f) => f.kind, 'kind', MediaFailureKind.notFound)));

        final del = await owner.delete(up.mediaId);
        expect(del.deleted, isTrue, reason: '$label delete');
        await expectLater(owner.readUrl(up.mediaId, forceRefresh: true), throwsA(isA<MediaFailure>()));
        final after = await _record(up.mediaId);
        expect(after['status'], 'deleted');
        evidence[label] = {'mediaId': up.mediaId, 'mode': up.mode, 'objectKey': rec['objectKey'], 'sizeBytes': bytes.length, 'afterDelete': after['status']};
      }
      final dir = Platform.environment['RUMPTY_LIVE_REPORT_DIR'] ?? Directory.systemTemp.path;
      File('$dir/rumpty-live-app-$stamp.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(evidence));
      // ignore: avoid_print
      print('app live evidence: $dir/rumpty-live-app-$stamp.json');
    });

    // The same bytes painted by an Image widget.
    final png = File('functions/test/fixtures/media/synthetic_64x48.png').readAsBytesSync();
    await tester.pumpWidget(MaterialApp(home: Center(child: Image.memory(png, width: 64, height: 48, key: const Key('img')))));
    await tester.runAsync(() => precacheImage(MemoryImage(png), tester.element(find.byKey(const Key('img')))));
    await tester.pump();
    expect(find.byKey(const Key('img')), findsOneWidget);
  }, skip: !_live, timeout: const Timeout(Duration(minutes: 5)));
}
