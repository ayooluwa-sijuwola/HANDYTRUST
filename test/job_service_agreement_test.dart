import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/errors/job_exceptions.dart';
import 'package:handy_trust/core/services/job_service.dart';
import 'package:handy_trust/models/job_model.dart';

/// Unit tests for the "Negotiation Completed / Agreement Confirmation"
/// checkpoint's validation logic.
///
/// Scope, stated plainly: these test the PURE predicates
/// (JobService.canConfirmAgreement / canRespondToAgreement / canInitPayment)
/// that both the real JobService transactional methods and this test file
/// call — there is one copy of this logic, not a production copy and a
/// tested copy. They do NOT exercise Firestore itself (no transaction, no
/// audit log, no actual write) and do NOT test firestore.rules — this repo
/// has no Firestore emulator / rules-unit-testing setup, so the
/// server-enforced mirror of these same checks (firestore.rules' three new
/// agreement update rules, and the tightened agreedAmount/paymentPending
/// rules) is unverified by automated tests. That's a real gap, flagged
/// here rather than silently glossed over — see the implementation report
/// for the recommended follow-up.
void main() {
  JobModel job({
    JobStatus status = JobStatus.inChat,
    String customerId = 'customer-1',
    String artisanId = 'artisan-1',
    AgreementStatus? agreementStatus,
    bool confirmedByCustomer = false,
    bool confirmedByArtisan = false,
    String urgency = 'asap',
    SchedulingStatus? schedulingStatus,
  }) {
    return JobModel(
      id: 'job-1',
      customerId: customerId,
      artisanId: artisanId,
      category: 'Plumbing',
      description: 'Fix a leaking pipe',
      status: status,
      createdAt: DateTime(2026, 1, 1),
      agreementStatus: agreementStatus,
      agreementConfirmedByCustomer: confirmedByCustomer,
      agreementConfirmedByArtisan: confirmedByArtisan,
      urgency: urgency,
      schedulingStatus: schedulingStatus,
    );
  }

  group('canConfirmAgreement — customer confirms terms', () {
    test('VALID: inChat, accepted quote, correct customer, negotiating', () {
      final j = job(agreementStatus: AgreementStatus.negotiating);
      expect(JobService.canConfirmAgreement(j, 'customer-1'), isTrue);
    });

    test('VALID: null agreementStatus treated the same as negotiating', () {
      final j = job(agreementStatus: null);
      expect(JobService.canConfirmAgreement(j, 'customer-1'), isTrue);
    });

    test('VALID: re-confirming after artisan requested changes', () {
      final j = job(agreementStatus: AgreementStatus.changesRequested);
      expect(JobService.canConfirmAgreement(j, 'customer-1'), isTrue);
    });

    test('INVALID: no accepted quote (artisanId empty)', () {
      final j = job(artisanId: '', agreementStatus: AgreementStatus.negotiating);
      expect(JobService.canConfirmAgreement(j, 'customer-1'), isFalse);
    });

    test('INVALID: caller is not the job\'s customer', () {
      final j = job(agreementStatus: AgreementStatus.negotiating);
      expect(JobService.canConfirmAgreement(j, 'some-other-uid'), isFalse);
    });

    test('INVALID: caller is the artisan, not the customer', () {
      final j = job(agreementStatus: AgreementStatus.negotiating);
      expect(JobService.canConfirmAgreement(j, 'artisan-1'), isFalse);
    });

    test('INVALID: job not inChat (e.g. still matched)', () {
      final j = job(status: JobStatus.matched, agreementStatus: AgreementStatus.negotiating);
      expect(JobService.canConfirmAgreement(j, 'customer-1'), isFalse);
    });

    test('INVALID: already pending artisan confirmation (no double-confirm)', () {
      final j = job(agreementStatus: AgreementStatus.pendingArtisanConfirmation);
      expect(JobService.canConfirmAgreement(j, 'customer-1'), isFalse);
    });

    test('INVALID: already confirmed — locked terms cannot be re-submitted', () {
      final j = job(agreementStatus: AgreementStatus.confirmed);
      expect(JobService.canConfirmAgreement(j, 'customer-1'), isFalse);
    });
  });

  group('canRespondToAgreement — artisan accepts or requests changes', () {
    test('VALID: correct matched artisan, pending their confirmation', () {
      final j = job(agreementStatus: AgreementStatus.pendingArtisanConfirmation);
      expect(JobService.canRespondToAgreement(j, 'artisan-1'), isTrue);
    });

    test('INVALID: a different artisan — not selected for this job', () {
      final j = job(agreementStatus: AgreementStatus.pendingArtisanConfirmation);
      expect(JobService.canRespondToAgreement(j, 'some-other-artisan'), isFalse);
    });

    test('INVALID: the customer, not the artisan', () {
      final j = job(agreementStatus: AgreementStatus.pendingArtisanConfirmation);
      expect(JobService.canRespondToAgreement(j, 'customer-1'), isFalse);
    });

    test('INVALID: not yet pending — customer hasn\'t confirmed yet', () {
      final j = job(agreementStatus: AgreementStatus.negotiating);
      expect(JobService.canRespondToAgreement(j, 'artisan-1'), isFalse);
    });

    test('INVALID: already confirmed — nothing left to accept', () {
      final j = job(agreementStatus: AgreementStatus.confirmed);
      expect(JobService.canRespondToAgreement(j, 'artisan-1'), isFalse);
    });

    test('INVALID: job not inChat', () {
      final j = job(
        status: JobStatus.escrowLocked,
        agreementStatus: AgreementStatus.pendingArtisanConfirmation,
      );
      expect(JobService.canRespondToAgreement(j, 'artisan-1'), isFalse);
    });
  });

  group('canInitPayment — escrow payment gated on a confirmed agreement', () {
    test('VALID: agreement confirmed, correct customer, valid transition', () {
      final j = job(agreementStatus: AgreementStatus.confirmed);
      expect(JobService.canInitPayment(j, 'customer-1'), isTrue);
    });

    test('INVALID: agreement only pending, not yet confirmed', () {
      final j = job(agreementStatus: AgreementStatus.pendingArtisanConfirmation);
      expect(JobService.canInitPayment(j, 'customer-1'), isFalse);
    });

    test('INVALID: agreement still negotiating', () {
      final j = job(agreementStatus: AgreementStatus.negotiating);
      expect(JobService.canInitPayment(j, 'customer-1'), isFalse);
    });

    test('INVALID: legacy job with no agreementStatus at all', () {
      final j = job(agreementStatus: null);
      expect(JobService.canInitPayment(j, 'customer-1'), isFalse);
    });

    test('INVALID: caller is the artisan, not the customer', () {
      final j = job(agreementStatus: AgreementStatus.confirmed);
      expect(JobService.canInitPayment(j, 'artisan-1'), isFalse);
    });

    test('INVALID: job status cannot structurally reach paymentPending', () {
      final j = job(status: JobStatus.matched, agreementStatus: AgreementStatus.confirmed);
      expect(JobService.canInitPayment(j, 'customer-1'), isFalse);
    });
  });

  group('canInitPayment — scheduling gate (new: Task 2, workflow consistency pass)', () {
    test('VALID: asap job — scheduling not required, exempt regardless of schedulingStatus', () {
      final j = job(
        agreementStatus: AgreementStatus.confirmed,
        urgency: 'asap',
        schedulingStatus: null,
      );
      expect(JobService.canInitPayment(j, 'customer-1'), isTrue);
    });

    test('VALID: scheduled job, agreement confirmed, schedule confirmed', () {
      final j = job(
        agreementStatus: AgreementStatus.confirmed,
        urgency: 'scheduled',
        schedulingStatus: SchedulingStatus.scheduled,
      );
      expect(JobService.canInitPayment(j, 'customer-1'), isTrue);
    });

    test('INVALID: scheduled job, agreement confirmed, but not yet scheduled', () {
      final j = job(
        agreementStatus: AgreementStatus.confirmed,
        urgency: 'scheduled',
        schedulingStatus: SchedulingStatus.awaitingSchedule,
      );
      expect(JobService.canInitPayment(j, 'customer-1'), isFalse);
    });

    test('INVALID: scheduled job, agreement confirmed, schedulingStatus never set (defaults to awaitingSchedule)', () {
      final j = job(
        agreementStatus: AgreementStatus.confirmed,
        urgency: 'scheduled',
        schedulingStatus: null,
      );
      expect(JobService.canInitPayment(j, 'customer-1'), isFalse);
    });

    test('INVALID: scheduled job, schedule confirmed, but agreement not confirmed yet', () {
      final j = job(
        agreementStatus: AgreementStatus.pendingArtisanConfirmation,
        urgency: 'scheduled',
        schedulingStatus: SchedulingStatus.scheduled,
      );
      expect(JobService.canInitPayment(j, 'customer-1'), isFalse);
    });
  });

  group('JobModel.schedulingSatisfied', () {
    test('asap job is always satisfied, even with no schedulingStatus', () {
      final j = job(urgency: 'asap', schedulingStatus: null);
      expect(j.schedulingSatisfied, isTrue);
    });

    test('scheduled job is unsatisfied until schedulingStatus == scheduled', () {
      final j = job(urgency: 'scheduled', schedulingStatus: SchedulingStatus.awaitingSchedule);
      expect(j.schedulingSatisfied, isFalse);
    });

    test('scheduled job is satisfied once schedulingStatus == scheduled', () {
      final j = job(urgency: 'scheduled', schedulingStatus: SchedulingStatus.scheduled);
      expect(j.schedulingSatisfied, isTrue);
    });
  });

  group('SchedulingStatus round-trip (regression guard)', () {
    test('SchedulingStatus round-trips through fromString correctly', () {
      for (final s in SchedulingStatus.values) {
        expect(SchedulingStatus.fromString(s.name), s);
      }
    });

    test('SchedulingStatus.fromString defaults unknown values to awaitingSchedule', () {
      expect(SchedulingStatus.fromString('garbage'), SchedulingStatus.awaitingSchedule);
    });
  });

  group('State machine unaffected by this feature (regression guard)', () {
    test('inChat → paymentPending is still structurally valid at the enum level', () {
      expect(JobService.isValidTransition(JobStatus.inChat, JobStatus.paymentPending), isTrue);
    });

    test('AgreementStatus round-trips through fromString correctly', () {
      for (final s in AgreementStatus.values) {
        expect(AgreementStatus.fromString(s.name), s);
      }
    });

    test('AgreementStatus.fromString defaults unknown values to negotiating', () {
      expect(AgreementStatus.fromString('garbage'), AgreementStatus.negotiating);
    });
  });

  // Escrow auto-release timing bug (design/ESCROW_TIMING_AUDIT.md): the
  // Cloud Functions auto-release cron only ever matches status ==
  // 'submitted', so autoReleaseAt must be set there — not at escrowLocked,
  // where it could (and did) expire before the job was even eligible to
  // be matched by the cron, releasing funds within an hour of a late
  // submission while the customer-facing countdown claimed 14 days left.
  group('Escrow release timing (money states)', () {
    test('releaseWindow is the single 14-day duration both the UI countdown '
        'and the auto-release cron are meant to agree on', () {
      expect(JobService.releaseWindow, const Duration(days: 14));
    });

    test('escrowLocked does NOT set autoReleaseAt — regression guard against '
        'the lock-time write that caused the timing bug', () {
      final milestones = JobService.timestampsForStatus(JobStatus.escrowLocked);
      expect(milestones.containsKey('autoReleaseAt'), isFalse);
    });

    test('escrowLocked still stamps escrowLockedAt', () {
      final milestones = JobService.timestampsForStatus(JobStatus.escrowLocked);
      expect(milestones.containsKey('escrowLockedAt'), isTrue);
    });

    // Stage 2 (HT-005) replaced the two previous tests here, which asserted
    // that the CLIENT computed autoReleaseAt/disputeWindowEndsAt from
    // DateTime.now() — i.e. from the artisan's own device clock, which is
    // exactly the vulnerability (an artisan could shorten the customer's
    // review window). Both fields are now server-owned (onJobCompleted sets
    // them from the server-stamped submittedAt; _releaseEscrow re-checks).
    test('submitted does NOT write the review-window timers — they are '
        'server-owned (HT-005)', () {
      final milestones = JobService.timestampsForStatus(JobStatus.submitted);
      expect(milestones.containsKey('autoReleaseAt'), isFalse);
      expect(milestones.containsKey('disputeWindowEndsAt'), isFalse);
    });

    test('submitted stamps submittedAt with a server timestamp (the review '
        'window anchor), never a client clock value', () {
      final milestones = JobService.timestampsForStatus(JobStatus.submitted);
      expect(milestones.keys, ['submittedAt']);
      expect(milestones['submittedAt'], isA<FieldValue>());
    });

    test('manual confirmation (completed) does not touch autoReleaseAt or '
        'disputeWindowEndsAt — confirmComplete/timestampsForStatus(completed) '
        'only stamps completedAt', () {
      final milestones = JobService.timestampsForStatus(JobStatus.completed);
      expect(milestones.containsKey('completedAt'), isTrue);
      expect(milestones.containsKey('autoReleaseAt'), isFalse);
      expect(milestones.containsKey('disputeWindowEndsAt'), isFalse);
    });

    test('dispute-window start: submitted → disputed is still a valid '
        'transition — raising a dispute moves status off "submitted", which '
        'is what actually removes a job from the auto-release cron\'s query '
        '(status == "submitted"), not any explicit field clearing', () {
      expect(JobService.isValidTransition(JobStatus.submitted, JobStatus.disputed), isTrue);
    });

    test('submitted → completed (manual confirmation) is still valid', () {
      expect(JobService.isValidTransition(JobStatus.submitted, JobStatus.completed), isTrue);
    });

    test('full escrow lock → work → submission chain is structurally valid', () {
      expect(JobService.isValidTransition(JobStatus.paymentPending, JobStatus.escrowLocked), isTrue);
      expect(JobService.isValidTransition(JobStatus.escrowLocked, JobStatus.inProgress), isTrue);
      expect(JobService.isValidTransition(JobStatus.inProgress, JobStatus.submitted), isTrue);
    });
  });

  // Payout idempotency (Phase 12.5 — design/PAYOUT_RACE_CONDITION_AUDIT.md).
  //
  // Scope, stated plainly: the actual fix (JobService.confirmComplete and
  // functions/index.js's _releaseEscrow both keying escrow_releases by a
  // fixed jobId and checking existence inside a Firestore transaction,
  // plus processEscrowRelease's atomic pending->processing claim) is real
  // Firestore-transaction and Cloud-Functions behavior that cannot be
  // exercised by a pure Dart unit test — this repo has no Firestore
  // emulator, same standing gap the agreement-checkpoint tests above
  // already state. What IS genuinely unit-testable, and tested below, is
  // the first layer of defense that exists independently of the
  // transaction fix: the state machine itself structurally forbids a job
  // from reaching 'completed' a second time, and 'submitted' → 'completed'
  // remains the only legitimate way to get there. "Concurrent release" and
  // "automatic release vs. manual release racing" specifically need
  // emulator-based integration tests — flagged as the recommended
  // follow-up, not faked here.
  group('Payout idempotency — state machine guards (Phase 12.5)', () {
    test('already-paid job: completed has no valid outbound transitions at all — '
        'a second confirmComplete/auto-release attempt cannot move it anywhere, '
        'let alone back through completed', () {
      expect(JobService.allowedTransitions[JobStatus.completed], isEmpty);
    });

    test('duplicate release attempt: completed → completed is not a valid transition', () {
      expect(JobService.isValidTransition(JobStatus.completed, JobStatus.completed), isFalse);
    });

    test('manual completion release: submitted → completed is the one legitimate path', () {
      expect(JobService.isValidTransition(JobStatus.submitted, JobStatus.completed), isTrue);
    });

    test('a job cannot be released from any status other than submitted — '
        'e.g. escrowLocked or inProgress → completed are both invalid, '
        'matching _releaseEscrow\'s post-fix transactional precondition', () {
      expect(JobService.isValidTransition(JobStatus.escrowLocked, JobStatus.completed), isFalse);
      expect(JobService.isValidTransition(JobStatus.inProgress, JobStatus.completed), isFalse);
    });

    test('JobStateConflictException (thrown by confirmComplete when a release '
        'document already exists for the job) carries a clear, actionable message', () {
      const e = JobStateConflictException('This job has already been released for payout.');
      expect(e.toString(), contains('already been released'));
    });
  });

  // Policy D2 (Stage 2): a funded job can't be cancelled by either party —
  // only a request for admin review, mirrored by firestore.rules.
  group('canRequestPaidCancellation — paid-job cancellation requires admin review', () {
    JobModel withRequest(JobStatus status, {String? requestStatus}) => JobModel(
          id: 'job-1',
          customerId: 'customer-1',
          artisanId: 'artisan-1',
          category: 'Plumbing',
          description: 'Fix a leaking pipe',
          status: status,
          createdAt: DateTime(2026, 1, 1),
          cancellationRequestStatus: requestStatus,
        );

    test('customer and artisan may request while escrowLocked or inProgress', () {
      for (final status in [JobStatus.escrowLocked, JobStatus.inProgress]) {
        expect(JobService.canRequestPaidCancellation(withRequest(status), 'customer-1'), isTrue);
        expect(JobService.canRequestPaidCancellation(withRequest(status), 'artisan-1'), isTrue);
      }
    });

    test('a stranger may not request', () {
      expect(JobService.canRequestPaidCancellation(withRequest(JobStatus.escrowLocked), 'stranger'), isFalse);
    });

    test('a second request while one is pending is refused', () {
      final j = withRequest(JobStatus.inProgress, requestStatus: 'pending');
      expect(j.hasPendingCancellationRequest, isTrue);
      expect(JobService.canRequestPaidCancellation(j, 'customer-1'), isFalse);
      expect(JobService.canRequestPaidCancellation(j, 'artisan-1'), isFalse);
    });

    test('not available outside funded pre-submission states (unfunded jobs cancel directly; '
        'submitted work goes through disputes)', () {
      for (final status in JobStatus.values.where(
          (s) => s != JobStatus.escrowLocked && s != JobStatus.inProgress)) {
        expect(JobService.canRequestPaidCancellation(withRequest(status), 'customer-1'), isFalse,
            reason: status.name);
      }
    });

    test('cancellation-request fields round-trip through JobModel.fromJson', () {
      final j = JobModel.fromJson({
        'id': 'job-1',
        'customerId': 'c',
        'status': 'escrowLocked',
        'cancellationRequestStatus': 'pending',
        'cancellationRequestedBy': 'c',
        'cancellationRequestReason': 'Other',
        'cancellationRequestedAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
      });
      expect(j.hasPendingCancellationRequest, isTrue);
      expect(j.cancellationRequestedBy, 'c');
      expect(j.cancellationRequestReason, 'Other');
      expect(j.cancellationRequestedAt, DateTime(2026, 11, 1));
    });
  });
}
