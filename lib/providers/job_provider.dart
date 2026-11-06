import 'dart:async' show TimeoutException;
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/storage_service.dart';
import '../core/services/firestore_service.dart';
import '../firebase/firestore/firestore_repository.dart';
import '../models/job_model.dart';

class JobRequestState {
  final bool isSubmitting;
  final String? error;
  final String? createdJobId;
  /// Number of attached photos that failed to upload — the job is still
  /// created successfully with whichever photos made it through, but this
  /// must be surfaced to the customer rather than silently dropped.
  final int failedImageCount;

  const JobRequestState({
    this.isSubmitting = false,
    this.error,
    this.createdJobId,
    this.failedImageCount = 0,
  });

  bool get success => createdJobId != null;

  JobRequestState copyWith({
    bool? isSubmitting,
    String? error,
    String? createdJobId,
    int? failedImageCount,
  }) =>
      JobRequestState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: error,
        createdJobId: createdJobId ?? this.createdJobId,
        failedImageCount: failedImageCount ?? this.failedImageCount,
      );
}

class JobRequestNotifier extends StateNotifier<JobRequestState> {
  final FirestoreRepository _repository;
  final StorageService _storageService;

  JobRequestNotifier(this._repository, this._storageService)
      : super(const JobRequestState());

  Future<void> submitRequest({
    required String customerId,
    required String category,
    required String description,
    required List<Uint8List> images,
    double? customerLat,
    double? customerLng,
    String? customerAddress,
    double? budgetMin,
    double? budgetMax,
    String urgency = 'asap',
    DateTime? scheduledDate,
    Map<String, dynamic>? aiSuggestion,
  }) async {
    state = const JobRequestState(isSubmitting: true);

    try {
      final jobId = _repository.generateJobId();
      debugPrint('[JobRequest] submission started: jobId=$jobId, images=${images.length}');

      // Pass userId so Storage path matches rules: jobs/{jobId}/{userId}/...
      // Each upload is caught individually — Future.wait would otherwise
      // abort the WHOLE submission (and lose every successfully-uploaded
      // photo too) if even one of several images failed transiently. The
      // job is still created with whichever photos made it through; the
      // customer doesn't lose their work over one flaky upload, but the
      // failure is logged and counted (not silently dropped).
      debugPrint('[JobRequest] image upload started: jobId=$jobId');
      final uploadResults = await Future.wait(
        images.asMap().entries.map((e) async {
          try {
            return await _storageService.uploadJobImageBytes(
              jobId: jobId,
              userId: customerId,
              index: e.key,
              bytes: e.value,
            );
          } catch (err) {
            debugPrint('[JobRequest] image ${e.key} upload failed for jobId=$jobId: $err');
            return null;
          }
        }),
      );
      final urls = uploadResults.whereType<String>().toList();
      final failedCount = uploadResults.length - urls.length;
      debugPrint('[JobRequest] image upload completed: jobId=$jobId, '
          'succeeded=${urls.length}, failed=$failedCount');

      final job = JobModel(
        id: jobId,
        customerId: customerId,
        category: category,
        description: description,
        imageUrls: urls,
        status: JobStatus.requested,
        customerLat: customerLat,
        customerLng: customerLng,
        customerAddress: customerAddress,
        budgetMin: budgetMin,
        budgetMax: budgetMax,
        urgency: urgency,
        scheduledDate: scheduledDate,
        createdAt: DateTime.now(),
        aiSuggestion: aiSuggestion,
      );

      debugPrint('[JobRequest] firestore write started: jobId=$jobId');
      await _repository.createJob(job);
      debugPrint('[JobRequest] firestore write completed: jobId=$jobId');
      state = JobRequestState(createdJobId: jobId, failedImageCount: failedCount);
    } on FirebaseException catch (e) {
      // Keep the real cause in the device log (plugin + code), and only
      // blame the network when the error actually is a connectivity one.
      debugPrint('[JobRequest] submission failed: ${e.plugin}/${e.code}: ${e.message}');
      state = JobRequestState(error: jobSubmitErrorMessage(e.code));
    } on TimeoutException catch (e) {
      debugPrint('[JobRequest] submission failed: timeout: $e');
      state = JobRequestState(error: jobSubmitErrorMessage('deadline-exceeded'));
    } catch (e) {
      debugPrint('[JobRequest] submission failed: ${e.runtimeType}: $e');
      state = JobRequestState(error: jobSubmitErrorMessage('unknown'));
    }
  }
}

/// What the customer sees when a job could not be saved, by Firebase error
/// code. Only connectivity codes mention the network: a server refusal
/// (e.g. `permission-denied`, when the deployed Firestore rules do not
/// accept the job) must not be reported as a connection problem.
String jobSubmitErrorMessage(String code) => switch (code) {
      'unavailable' || 'deadline-exceeded' || 'network-request-failed' =>
        'No connection to HandyTrust. Check your network and try again.',
      'unauthenticated' => 'Your session has expired. Please sign in again.',
      'permission-denied' =>
        'The server refused to save this job. This is not a network problem; please contact support. (permission-denied)',
      'resource-exhausted' => 'Too many requests right now. Please wait a moment and try again.',
      'unknown' => 'Something went wrong while saving your job. Please try again.',
      _ => 'Something went wrong while saving your job. Please try again. ($code)',
    };

final jobRequestNotifierProvider =
    StateNotifierProvider<JobRequestNotifier, JobRequestState>(
  (ref) => JobRequestNotifier(
    FirestoreRepository(FirestoreService()),
    StorageService(),
  ),
);
