// Job posting: the error shown to the customer must reflect the real
// failure. A server refusal (permission-denied, e.g. deployed Firestore
// rules that do not accept jobs/{id}/private/location) must not be reported
// as a network problem; photo upload failures must not fail the job.
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/storage_service.dart';
import 'package:handy_trust/firebase/firestore/firestore_repository.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/providers/job_provider.dart';

class _FakeRepo implements FirestoreRepository {
  _FakeRepo({this.failWith});
  final Object? failWith;
  JobModel? written;

  @override
  String generateJobId() => 'job123';

  @override
  Future<void> createJob(JobModel job) async {
    if (failWith != null) throw failWith!;
    written = job;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStorage implements StorageService {
  _FakeStorage({this.failUploads = false});
  final bool failUploads;

  @override
  Future<String> uploadJobImageBytes({required String jobId, required String userId, required int index, required Uint8List bytes, String subfolder = ''}) async {
    if (failUploads) throw FirebaseException(plugin: 'firebase_storage', code: 'object-not-found');
    return 'https://example.test/$jobId/$index.jpg';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<JobRequestState> _submit(JobRequestNotifier n, {double? lat, double? lng, String? address}) async {
  await n.submitRequest(
    customerId: 'customer1',
    category: 'Plumbing',
    description: 'Leaking kitchen tap',
    images: [Uint8List.fromList([1, 2, 3])],
    customerLat: lat,
    customerLng: lng,
    customerAddress: address,
    budgetMin: 15000,
    budgetMax: 15000,
  );
  return n.state;
}

void main() {
  test('permission-denied is reported as a server refusal, not a network problem', () async {
    final n = JobRequestNotifier(_FakeRepo(failWith: FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')), _FakeStorage());
    final s = await _submit(n, lat: 6.4541, lng: 3.3947, address: '12 Adeola Odeku St, Victoria Island, Lagos');
    expect(s.success, isFalse);
    expect(s.error, contains('refused'));
    expect(s.error, contains('permission-denied'));
    expect(s.error!.toLowerCase(), isNot(contains('check your network')));
  });

  test('connectivity codes (unavailable, deadline-exceeded) mention the network', () async {
    for (final code in ['unavailable', 'deadline-exceeded']) {
      final n = JobRequestNotifier(_FakeRepo(failWith: FirebaseException(plugin: 'cloud_firestore', code: code)), _FakeStorage());
      final s = await _submit(n);
      expect(s.error, contains('Check your network'), reason: code);
    }
  });

  test('an expired session asks the customer to sign in again', () async {
    final n = JobRequestNotifier(_FakeRepo(failWith: FirebaseException(plugin: 'cloud_firestore', code: 'unauthenticated')), _FakeStorage());
    expect((await _submit(n)).error, contains('sign in again'));
  });

  test('an unexpected error is not blamed on the network', () async {
    final n = JobRequestNotifier(_FakeRepo(failWith: StateError('boom')), _FakeStorage());
    final s = await _submit(n);
    expect(s.success, isFalse);
    expect(s.error!.toLowerCase(), isNot(contains('network')));
  });

  test('a failed photo upload does not fail the job; it is counted', () async {
    final repo = _FakeRepo();
    final n = JobRequestNotifier(repo, _FakeStorage(failUploads: true));
    final s = await _submit(n, lat: 6.4541, lng: 3.3947);
    expect(s.success, isTrue);
    expect(s.createdJobId, 'job123');
    expect(s.failedImageCount, 1);
    expect(repo.written!.imageUrls, isEmpty);
  });

  test('success keeps the exact location on the model for createJob to split', () async {
    final repo = _FakeRepo();
    final n = JobRequestNotifier(repo, _FakeStorage());
    final s = await _submit(n, lat: 6.4541, lng: 3.3947, address: '12 Adeola Odeku St, Victoria Island, Lagos');
    expect(s.success, isTrue);
    expect(s.error, isNull);
    expect(repo.written!.customerLat, 6.4541);
    expect(repo.written!.customerAddress, contains('Adeola Odeku'));
    expect(repo.written!.imageUrls, hasLength(1));
  });
}
