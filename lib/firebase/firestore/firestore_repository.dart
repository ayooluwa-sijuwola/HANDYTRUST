import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/firestore_service.dart';
import '../../core/utils/geo.dart';
import '../../models/job_model.dart';
import 'collections.dart';

class FirestoreRepository {
  FirestoreRepository(this._service);

  final FirestoreService _service;

  String generateJobId() {
    return _service.collection(Collections.jobs).doc().id;
  }

  /// Stage 6 (P-K, policy D9): the job document carries only a coarse area
  /// (~1 km, for distance matching); the exact address and coordinates go to
  /// `jobs/{id}/private/location` in the same batch — readable only by the
  /// customer, admins, and the assigned artisan once the booking is confirmed.
  Future<void> createJob(JobModel job) async {
    final ref = _service.collection(Collections.jobs).doc(job.id);
    final data = job.toJson()
      ..remove('customerLat')
      ..remove('customerLng')
      ..remove('customerAddress');
    final exact = <String, dynamic>{
      'customerLat': ?job.customerLat,
      'customerLng': ?job.customerLng,
      'customerAddress': ?job.customerAddress,
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.set(ref, {
      ...data,
      ...?Geo.coarseArea(job.customerLat, job.customerLng, job.customerAddress),
      // Seed consistency fields so every doc has them from creation.
      // JobService.updateJobStatus will increment updateVersion on each mutation.
      'updateVersion': 0,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
      'lastUpdatedBy': 'customer',
    });
    if (exact.isNotEmpty) {
      batch.set(ref.collection('private').doc('location'), exact);
    }
    await batch.commit();
  }

  Stream<List<JobModel>> watchCustomerJobs(String customerId) {
    return _service
        .collection(Collections.jobs)
        .where('customerId', isEqualTo: customerId)
        .snapshots()
        .map((snapshot) {
          final jobs = snapshot.docs
              .map((doc) => JobModel.fromJson({...doc.data(), 'id': doc.id}))
              .toList();
          jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return jobs;
        });
  }
}
