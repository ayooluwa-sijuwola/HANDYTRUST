import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/job_service.dart';
import 'package:handy_trust/core/services/workflow_gate_service.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/quote_model.dart';
import 'package:handy_trust/models/user_model.dart';
import 'package:handy_trust/providers/platform_config_provider.dart';

// Stage 5 (design/REMEDIATION_STAGE5_REPORT_2026-11-03.md): booking
// confirmation, rework, expiry, suspension modes — client mirrors of the
// server rules (the server remains the authority).
void main() {
  JobModel job(JobStatus status, {String? booking, int rework = 0, String? reworkResponse}) => JobModel(
        id: 'job-1',
        customerId: 'customer-1',
        artisanId: 'artisan-1',
        category: 'Plumbing',
        description: 'Fix a leaking pipe',
        status: status,
        createdAt: DateTime(2026, 1, 1),
        bookingStatus: booking,
        reworkCount: rework,
        reworkResponse: reworkResponse,
      );

  group('Booking confirmation (D7)', () {
    test('a new match awaits the artisan; only the artisan can confirm it', () {
      final j = job(JobStatus.matched, booking: 'awaitingArtisan');
      expect(j.awaitingArtisanConfirmation, isTrue);
      expect(JobService.canConfirmBooking(j, 'artisan-1'), isTrue);
      expect(JobService.canConfirmBooking(j, 'customer-1'), isFalse);
      expect(JobService.canConfirmBooking(j, 'other'), isFalse);
    });

    test('artisan is offered Accept Booking; customer waits', () {
      final j = job(JobStatus.matched, booking: 'awaitingArtisan');
      final a = WorkflowGateService.describeStep(j, viewerIsCustomer: false);
      expect(a.primaryAction, WorkflowAction.confirmBooking);
      final c = WorkflowGateService.describeStep(j, viewerIsCustomer: true);
      expect(c.primaryAction, WorkflowAction.none);
      expect(c.waitingOn, WorkflowActor.artisan);
    });

    test('a confirmed (migrated legacy) match keeps Continue Negotiation for the customer', () {
      final j = job(JobStatus.matched, booking: 'confirmed');
      expect(j.awaitingArtisanConfirmation, isFalse);
      expect(WorkflowGateService.describeStep(j, viewerIsCustomer: true).primaryAction, WorkflowAction.continueNegotiation);
    });
  });

  group('Rework (D4)', () {
    test('one request, by the customer, on submitted work', () {
      expect(JobService.canRequestRework(job(JobStatus.submitted), 'customer-1'), isTrue);
      expect(JobService.canRequestRework(job(JobStatus.submitted), 'artisan-1'), isFalse);
      expect(JobService.canRequestRework(job(JobStatus.submitted, rework: 1), 'customer-1'), isFalse);
      expect(JobService.canRequestRework(job(JobStatus.completed), 'customer-1'), isFalse);
    });

    test('the artisan may respond once', () {
      expect(JobService.canRespondToRework(job(JobStatus.inProgress, rework: 1), 'artisan-1'), isTrue);
      expect(JobService.canRespondToRework(job(JobStatus.inProgress, rework: 1, reworkResponse: 'ok'), 'artisan-1'), isFalse);
      expect(JobService.canRespondToRework(job(JobStatus.inProgress, rework: 1), 'customer-1'), isFalse);
    });

    test('rework is the only path back from submitted; completed stays terminal', () {
      expect(JobService.isValidTransition(JobStatus.submitted, JobStatus.inProgress), isTrue);
      expect(JobService.allowedTransitions[JobStatus.completed], isEmpty);
    });

    test('artisan sees Resubmit Work after a rework request', () {
      final s = WorkflowGateService.describeStep(job(JobStatus.inProgress, rework: 1), viewerIsCustomer: false);
      expect(s.primaryAction, WorkflowAction.submitCompletion);
      expect(s.primaryLabel, 'Resubmit Work');
    });
  });

  group('Expiry (D5)', () {
    test('expired is a terminal, closed status', () {
      expect(JobStatus.fromString('expired'), JobStatus.expired);
      expect(JobStatus.expired.isTerminal, isTrue);
      expect(WorkflowGateService.describeStep(job(JobStatus.expired), viewerIsCustomer: true).phase, 'Closed');
    });

    test('expired quotes parse as expired, not pending', () {
      final q = QuoteModel.fromJson({'id': 'a', 'jobId': 'j', 'artisanId': 'a', 'amount': 10000, 'status': 'expired'});
      expect(q.status, QuoteStatus.expired);
    });

    test('quote validity display check (48 h default)', () {
      const c = PlatformConfig();
      final now = DateTime(2026, 11, 3, 12);
      expect(c.quoteIsValid(now.subtract(const Duration(hours: 47)), now: now), isTrue);
      expect(c.quoteIsValid(now.subtract(const Duration(hours: 49)), now: now), isFalse);
      expect(c.quoteIsValid(null, now: now), isFalse);
    });
  });

  group('Suspension modes (D9)', () {
    UserModel user(String status, [String? type]) => UserModel.fromJson({
          'uid': 'u', 'name': 'User', 'accountStatus': status, 'suspensionType': ?type,
        });

    test('administrative / verification → restricted existing-jobs mode', () {
      expect(user('suspended', 'administrative').hasRestrictedSuspension, isTrue);
      expect(user('suspended', 'verification').hasRestrictedSuspension, isTrue);
      expect(user('suspended', 'verification').hasFreezingSuspension, isFalse);
    });

    test('fraud / safety / security / unclassified → freezing (fails closed)', () {
      for (final t in ['fraud', 'safety', 'security', null]) {
        expect(user('suspended', t).hasFreezingSuspension, isTrue, reason: '$t');
      }
    });

    test('active users are neither', () {
      expect(user('active').hasFreezingSuspension, isFalse);
      expect(user('active').hasRestrictedSuspension, isFalse);
    });
  });

  test('JobModel parses the Stage 5 lifecycle fields', () {
    final j = JobModel.fromJson({
      'id': 'j1', 'customerId': 'c', 'status': 'matched', 'bookingStatus': 'awaitingArtisan',
      'reworkCount': 1, 'reworkReason': 'fix it', 'reopenCount': 2, 'reopenReason': 'booking_expired',
    });
    expect(j.bookingStatus, 'awaitingArtisan');
    expect(j.reworkCount, 1);
    expect(j.reopenCount, 2);
    expect(j.reopenReason, 'booking_expired');
  });
}
