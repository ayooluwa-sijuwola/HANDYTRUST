// Stage 8.1 — artisan presentation logic (lib/core/services/artisan_work_logic.dart).
// Every stage is derived from real job fields; fixtures are test-only.
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/artisan_work_logic.dart';
import 'package:handy_trust/models/job_model.dart';

JobModel j(
  String id,
  JobStatus status, {
  String? booking,
  AgreementStatus? agreement,
  String urgency = 'asap',
  SchedulingStatus? scheduling,
  List<DateTime> slots = const [],
  DateTime? appointment,
  int rework = 0,
  String? reworkResponse,
  DateTime? requestedAt,
  DateTime? autoReleaseAt,
  JobProgressStage? progress,
  String? cancellationRequest,
}) =>
    JobModel(
      id: id,
      customerId: 'c1',
      artisanId: 'a1',
      category: 'Plumbing',
      description: 'Fix leak',
      status: status,
      bookingStatus: booking,
      agreementStatus: agreement,
      urgency: urgency,
      schedulingStatus: scheduling,
      appointmentSlots: slots,
      confirmedAppointment: appointment,
      reworkCount: rework,
      reworkResponse: reworkResponse,
      bookingRequestedAt: requestedAt,
      autoReleaseAt: autoReleaseAt,
      progressStage: progress,
      cancellationRequestStatus: cancellationRequest,
      createdAt: DateTime(2026, 11, 1),
    );

void main() {
  group('isArtisanMode (F-11: active role decides, not role absence)', () {
    test('artisan in artisan mode', () => expect(ArtisanWorkLogic.isArtisanMode(isArtisan: true, activeRole: 'artisan'), isTrue));
    test('dual-role user in customer mode sees the customer app', () => expect(ArtisanWorkLogic.isArtisanMode(isArtisan: true, activeRole: 'customer'), isFalse));
    test('a customer who sets activeRole=artisan without the role does not get artisan UI',
        () => expect(ArtisanWorkLogic.isArtisanMode(isArtisan: false, activeRole: 'artisan'), isFalse));
  });

  group('stageOf mirrors the backend lifecycle', () {
    final cases = <String, (JobModel, ArtisanStage)>{
      'unconfirmed booking → request': (j('1', JobStatus.matched), ArtisanStage.request),
      'confirmed booking (matched) → agreement': (j('2', JobStatus.matched, booking: 'confirmed'), ArtisanStage.agreement),
      'inChat, customer drafting → agreement': (j('3', JobStatus.inChat, agreement: AgreementStatus.negotiating), ArtisanStage.agreement),
      'inChat, artisan to review → agreement': (j('4', JobStatus.inChat, agreement: AgreementStatus.pendingArtisanConfirmation), ArtisanStage.agreement),
      'scheduled job, agreed, not scheduled → schedule':
          (j('5', JobStatus.inChat, agreement: AgreementStatus.confirmed, urgency: 'scheduled'), ArtisanStage.schedule),
      'scheduled job, agreed and scheduled → awaiting payment': (
        j('6', JobStatus.inChat, agreement: AgreementStatus.confirmed, urgency: 'scheduled', scheduling: SchedulingStatus.scheduled),
        ArtisanStage.awaitingPayment
      ),
      'asap job, agreed → awaiting payment (no scheduling step)': (j('7', JobStatus.inChat, agreement: AgreementStatus.confirmed), ArtisanStage.awaitingPayment),
      'paymentPending → awaiting payment': (j('8', JobStatus.paymentPending), ArtisanStage.awaitingPayment),
      'escrowLocked → ready to start': (j('9', JobStatus.escrowLocked), ArtisanStage.readyToStart),
      'inProgress → working': (j('10', JobStatus.inProgress), ArtisanStage.working),
      'inProgress after a rework request → rework': (j('11', JobStatus.inProgress, rework: 1), ArtisanStage.rework),
      'submitted → in review': (j('12', JobStatus.submitted), ArtisanStage.inReview),
      'disputed → disputed': (j('13', JobStatus.disputed), ArtisanStage.disputed),
      'completed → completed': (j('14', JobStatus.completed), ArtisanStage.completed),
      'resolved → completed': (j('15', JobStatus.resolved), ArtisanStage.completed),
      'cancelled → closed': (j('16', JobStatus.cancelled), ArtisanStage.closed),
      'expired → closed': (j('17', JobStatus.expired), ArtisanStage.closed),
    };
    cases.forEach((name, c) => test(name, () => expect(ArtisanWorkLogic.stageOf(c.$1), c.$2)));
  });

  group('pipeline and history', () {
    final jobs = [
      j('r', JobStatus.matched),
      j('a', JobStatus.inChat, agreement: AgreementStatus.pendingArtisanConfirmation),
      j('s', JobStatus.inChat, agreement: AgreementStatus.confirmed, urgency: 'scheduled'),
      j('p', JobStatus.paymentPending),
      j('w1', JobStatus.escrowLocked),
      j('w2', JobStatus.inProgress),
      j('v', JobStatus.submitted),
      j('d', JobStatus.disputed),
      j('c', JobStatus.completed),
      j('x', JobStatus.cancelled),
    ];

    test('counts per column; disputed and history are not pipeline columns', () {
      final c = ArtisanWorkLogic.pipelineCounts(jobs);
      expect(c[ArtisanPipeline.requests], 1);
      expect(c[ArtisanPipeline.agreement], 2);
      expect(c[ArtisanPipeline.payment], 1);
      expect(c[ArtisanPipeline.working], 2);
      expect(c[ArtisanPipeline.inReview], 1);
    });

    test('active includes disputed; history is completed + closed', () {
      expect(jobs.where(ArtisanWorkLogic.isActive).map((e) => e.id), ['r', 'a', 's', 'p', 'w1', 'w2', 'v', 'd']);
      expect(jobs.where(ArtisanWorkLogic.isHistory).map((e) => e.id), ['c', 'x']);
    });

    test('My Jobs groups in pipeline order and drops empty groups', () {
      final g = ArtisanWorkLogic.groupForMyJobs(jobs);
      expect(g.map((e) => e.$1), ['Requests', 'Agreement', 'Awaiting payment', 'Working now', 'In review', 'Disputed']);
      expect(ArtisanWorkLogic.groupForMyJobs([j('v', JobStatus.submitted)]).map((e) => e.$1), ['In review']);
    });
  });

  group('work stepper (Booked · Agreed · Funded · Working · Submitted · Paid)', () {
    test('labels', () => expect(ArtisanWorkLogic.workStepLabels, ['Booked', 'Agreed', 'Funded', 'Working', 'Submitted', 'Paid']));
    test('index per stage; completed = all done', () {
      expect(ArtisanWorkLogic.workStep(j('1', JobStatus.matched)), 0);
      expect(ArtisanWorkLogic.workStep(j('2', JobStatus.inChat, agreement: AgreementStatus.negotiating)), 1);
      expect(ArtisanWorkLogic.workStep(j('3', JobStatus.paymentPending)), 2);
      expect(ArtisanWorkLogic.workStep(j('4', JobStatus.inProgress)), 3);
      expect(ArtisanWorkLogic.workStep(j('5', JobStatus.submitted)), 4);
      expect(ArtisanWorkLogic.workStep(j('6', JobStatus.completed)), 6);
    });
  });

  group('stage labels', () {
    test('agreement wording follows who acts next', () {
      expect(ArtisanWorkLogic.stageLabel(j('1', JobStatus.inChat, agreement: AgreementStatus.pendingArtisanConfirmation)), 'Review agreement');
      expect(ArtisanWorkLogic.stageLabel(j('2', JobStatus.inChat, agreement: AgreementStatus.changesRequested)), 'Changes requested');
      expect(ArtisanWorkLogic.stageLabel(j('3', JobStatus.inChat, agreement: AgreementStatus.negotiating)), 'Customer drafting');
      expect(ArtisanWorkLogic.stageLabel(j('4', JobStatus.matched, booking: 'confirmed')), 'Booking confirmed');
    });
    test('progress stage shows while working', () {
      expect(ArtisanWorkLogic.stageLabel(j('1', JobStatus.inProgress, progress: JobProgressStage.workStarted)), JobProgressStage.workStarted.label);
      expect(ArtisanWorkLogic.stageLabel(j('2', JobStatus.inProgress)), 'Working');
    });
    test('closed reasons', () {
      expect(ArtisanWorkLogic.stageLabel(j('1', JobStatus.cancelled)), 'Cancelled');
      expect(ArtisanWorkLogic.stageLabel(j('2', JobStatus.expired)), 'Expired');
      expect(ArtisanWorkLogic.stageLabel(j('3', JobStatus.resolved)), 'Resolved');
    });
  });

  group('deadlines (server windows only)', () {
    final t0 = DateTime(2026, 11, 5, 9);

    test('booking deadline = request time + bookingConfirmationHours', () {
      expect(ArtisanWorkLogic.bookingDeadline(j('1', JobStatus.matched, requestedAt: t0), 24), t0.add(const Duration(hours: 24)));
      expect(ArtisanWorkLogic.bookingDeadline(j('2', JobStatus.matched, requestedAt: t0), 6), t0.add(const Duration(hours: 6)));
      expect(ArtisanWorkLogic.bookingDeadline(j('3', JobStatus.inChat, requestedAt: t0), 24), isNull);
    });

    test('review end is the server autoReleaseAt, only while in review', () {
      final end = t0.add(const Duration(days: 14));
      expect(ArtisanWorkLogic.reviewEnds(j('1', JobStatus.submitted, autoReleaseAt: end)), end);
      expect(ArtisanWorkLogic.reviewEnds(j('2', JobStatus.inProgress, autoReleaseAt: end)), isNull);
    });

    test('remaining fraction and label', () {
      final end = t0.add(const Duration(hours: 24));
      expect(ArtisanWorkLogic.remainingFraction(t0, end, t0.add(const Duration(hours: 6))), closeTo(0.75, 1e-9));
      expect(ArtisanWorkLogic.remainingFraction(t0, end, end.add(const Duration(hours: 1))), 0);
      expect(ArtisanWorkLogic.remainingFraction(t0, t0, t0), 0);
      expect(ArtisanWorkLogic.remainingLabel(t0.add(const Duration(days: 11, hours: 3)), t0), '11 d');
      expect(ArtisanWorkLogic.remainingLabel(t0.add(const Duration(hours: 18)), t0), '18 h');
      expect(ArtisanWorkLogic.remainingLabel(t0.add(const Duration(minutes: 45)), t0), '45 min');
      expect(ArtisanWorkLogic.remainingLabel(t0.subtract(const Duration(minutes: 1)), t0), isNull);
    });
  });

  group('action queue', () {
    final t0 = DateTime(2026, 11, 5, 9);
    test('only real artisan actions, most urgent kind first, earliest deadline first', () {
      final q = ArtisanWorkLogic.actionQueue([
        j('dispute', JobStatus.disputed),
        j('start', JobStatus.escrowLocked),
        j('late', JobStatus.matched, requestedAt: t0.add(const Duration(hours: 3))),
        j('early', JobStatus.matched, requestedAt: t0),
        j('agree', JobStatus.inChat, agreement: AgreementStatus.pendingArtisanConfirmation),
        j('drafting', JobStatus.inChat, agreement: AgreementStatus.negotiating), // customer acts
        j('times', JobStatus.inChat, agreement: AgreementStatus.confirmed, urgency: 'scheduled'),
        j('proposed', JobStatus.inChat, agreement: AgreementStatus.confirmed, urgency: 'scheduled', slots: [t0]), // customer acts
        j('rework', JobStatus.inProgress, rework: 1),
        j('answered', JobStatus.inProgress, rework: 1, reworkResponse: 'Fixed'), // artisan already replied
        j('review', JobStatus.submitted), // customer acts
        j('pay', JobStatus.paymentPending), // customer acts
      ], bookingConfirmationHours: 24);
      expect(q.map((a) => a.job.id), ['early', 'late', 'agree', 'times', 'start', 'rework', 'dispute']);
      expect(q.first.kind, ArtisanActionKind.respondToBooking);
      expect(q.first.deadline, t0.add(const Duration(hours: 24)));
      expect(q.last.kind, ArtisanActionKind.respondToDispute);
    });
  });

  group('next appointment, progress, withdraw/cancel rules', () {
    final now = DateTime(2026, 11, 5, 9);
    test('nearest future appointment on an active job', () {
      final best = ArtisanWorkLogic.nextAppointment([
        j('past', JobStatus.escrowLocked, appointment: now.subtract(const Duration(hours: 1))),
        j('later', JobStatus.escrowLocked, appointment: now.add(const Duration(days: 3))),
        j('soon', JobStatus.paymentPending, appointment: now.add(const Duration(days: 1))),
        j('done', JobStatus.completed, appointment: now.add(const Duration(hours: 2))),
      ], now);
      expect(best?.id, 'soon');
      expect(ArtisanWorkLogic.nextAppointment([j('none', JobStatus.inProgress)], now), isNull);
    });

    test('progress steps forward through JobProgressStage and stops at the end', () {
      expect(ArtisanWorkLogic.nextProgress(null), JobProgressStage.values.first);
      expect(ArtisanWorkLogic.nextProgress(JobProgressStage.values[2]), JobProgressStage.values[3]);
      expect(ArtisanWorkLogic.nextProgress(JobProgressStage.values.last), isNull);
    });

    test('withdraw only before payment; paid cancellation only once funded and none pending', () {
      for (final s in [JobStatus.matched, JobStatus.inChat, JobStatus.paymentPending]) {
        expect(ArtisanWorkLogic.canWithdraw(j('w', s)), isTrue, reason: s.name);
      }
      for (final s in [JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted, JobStatus.disputed, JobStatus.completed]) {
        expect(ArtisanWorkLogic.canWithdraw(j('w', s)), isFalse, reason: s.name);
      }
      expect(ArtisanWorkLogic.canRequestPaidCancellation(j('c', JobStatus.escrowLocked)), isTrue);
      expect(ArtisanWorkLogic.canRequestPaidCancellation(j('c', JobStatus.inProgress)), isTrue);
      expect(ArtisanWorkLogic.canRequestPaidCancellation(j('c', JobStatus.inProgress, cancellationRequest: 'pending')), isFalse);
      expect(ArtisanWorkLogic.canRequestPaidCancellation(j('c', JobStatus.submitted)), isFalse);
    });
  });
}
