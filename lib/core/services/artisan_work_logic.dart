import '../../models/job_model.dart';
import 'workflow_gate_service.dart';

/// Where a job sits in the artisan's work, derived only from existing job
/// fields. The order mirrors the backend lifecycle: booking request →
/// agreement (customer drafts, artisan reviews) → scheduling (scheduled
/// jobs only) → customer funds escrow → work → submission → 14-day review.
enum ArtisanStage {
  request,
  agreement,
  schedule,
  awaitingPayment,
  readyToStart,
  working,
  rework,
  inReview,
  disputed,
  completed,
  closed,
}

/// Pipeline columns on Home and My Jobs.
enum ArtisanPipeline { requests, agreement, payment, working, inReview }

/// A "needs your action" entry on the artisan Home queue.
enum ArtisanActionKind { respondToBooking, reviewAgreement, proposeTimes, startWork, respondToRework, respondToDispute }

class ArtisanAction {
  const ArtisanAction(this.kind, this.job, {this.deadline});
  final ArtisanActionKind kind;
  final JobModel job;

  /// Hard deadline, when the backend enforces one (booking requests).
  final DateTime? deadline;
}

/// Pure presentation logic for the artisan UI (Stage 8.1). No Firestore,
/// no BuildContext — tested in test/artisan_work_logic_test.dart.
abstract final class ArtisanWorkLogic {
  /// F-11: artisan mode is the user's active role, not "has no customer
  /// role". Dual-role users in Artisan Mode see artisan work only.
  static bool isArtisanMode({required bool isArtisan, required String activeRole}) => isArtisan && activeRole == 'artisan';

  static ArtisanStage stageOf(JobModel j) {
    switch (j.status) {
      case JobStatus.matched:
        return j.awaitingArtisanConfirmation ? ArtisanStage.request : ArtisanStage.agreement;
      case JobStatus.inChat:
        if (WorkflowGateService.isAgreementRequired(j)) return ArtisanStage.agreement;
        if (WorkflowGateService.isSchedulingRequired(j)) return ArtisanStage.schedule;
        return ArtisanStage.awaitingPayment;
      case JobStatus.paymentPending:
        return ArtisanStage.awaitingPayment;
      case JobStatus.escrowLocked:
        return ArtisanStage.readyToStart;
      case JobStatus.inProgress:
        return j.reworkCount > 0 ? ArtisanStage.rework : ArtisanStage.working;
      case JobStatus.submitted:
        return ArtisanStage.inReview;
      case JobStatus.disputed:
        return ArtisanStage.disputed;
      case JobStatus.completed:
      case JobStatus.resolved:
        return ArtisanStage.completed;
      case JobStatus.requested:
      case JobStatus.cancelled:
      case JobStatus.expired:
        return ArtisanStage.closed;
    }
  }

  static ArtisanPipeline? pipelineOf(JobModel j) => switch (stageOf(j)) {
        ArtisanStage.request => ArtisanPipeline.requests,
        ArtisanStage.agreement || ArtisanStage.schedule => ArtisanPipeline.agreement,
        ArtisanStage.awaitingPayment => ArtisanPipeline.payment,
        ArtisanStage.readyToStart || ArtisanStage.working || ArtisanStage.rework => ArtisanPipeline.working,
        ArtisanStage.inReview => ArtisanPipeline.inReview,
        _ => null,
      };

  static Map<ArtisanPipeline, int> pipelineCounts(Iterable<JobModel> jobs) {
    final counts = {for (final p in ArtisanPipeline.values) p: 0};
    for (final j in jobs) {
      final p = pipelineOf(j);
      if (p != null) counts[p] = counts[p]! + 1;
    }
    return counts;
  }

  static String pipelineLabel(ArtisanPipeline p) => switch (p) {
        ArtisanPipeline.requests => 'Requests',
        ArtisanPipeline.agreement => 'Agreement',
        ArtisanPipeline.payment => 'Awaiting payment',
        ArtisanPipeline.working => 'Working',
        ArtisanPipeline.inReview => 'In review',
      };

  static bool isActive(JobModel j) => pipelineOf(j) != null || stageOf(j) == ArtisanStage.disputed;

  /// Work-order stepper: Booked · Agreed · Funded · Working · Submitted ·
  /// Paid. Returns the index of the current step; 6 = everything done.
  static int workStep(JobModel j) => switch (stageOf(j)) {
        ArtisanStage.request => 0,
        ArtisanStage.agreement || ArtisanStage.schedule => 1,
        ArtisanStage.awaitingPayment => 2,
        ArtisanStage.readyToStart || ArtisanStage.working || ArtisanStage.rework => 3,
        ArtisanStage.inReview || ArtisanStage.disputed => 4,
        ArtisanStage.completed => 6,
        ArtisanStage.closed => 0,
      };

  static const workStepLabels = ['Booked', 'Agreed', 'Funded', 'Working', 'Submitted', 'Paid'];

  /// Short stage chip text.
  static String stageLabel(JobModel j) => switch (stageOf(j)) {
        ArtisanStage.request => 'Booking request',
        ArtisanStage.agreement => switch (j.agreementStatus) {
            AgreementStatus.pendingArtisanConfirmation => 'Review agreement',
            AgreementStatus.changesRequested => 'Changes requested',
            _ => j.status == JobStatus.matched ? 'Booking confirmed' : 'Customer drafting',
          },
        ArtisanStage.schedule => j.appointmentSlots.isEmpty ? 'Propose times' : 'Times proposed',
        ArtisanStage.awaitingPayment => 'Awaiting payment',
        ArtisanStage.readyToStart => 'Funded · ready',
        ArtisanStage.working => j.progressStage?.label ?? 'Working',
        ArtisanStage.rework => 'Rework requested',
        ArtisanStage.inReview => 'In customer review',
        ArtisanStage.disputed => 'Disputed',
        ArtisanStage.completed => j.status == JobStatus.resolved ? 'Resolved' : 'Completed',
        ArtisanStage.closed => switch (j.status) {
            JobStatus.cancelled => 'Cancelled',
            JobStatus.expired => 'Expired',
            _ => 'Closed',
          },
      };

  /// Booking-response deadline: request time + the server-configured window
  /// (`bookingConfirmationHours`, default 24 h). The server reopens the job
  /// after it.
  static DateTime? bookingDeadline(JobModel j, int confirmationHours) {
    if (stageOf(j) != ArtisanStage.request) return null;
    final at = j.bookingRequestedAt ?? j.matchedAt;
    return at?.add(Duration(hours: confirmationHours));
  }

  /// Review end = the server's auto-release time (14-day window).
  static DateTime? reviewEnds(JobModel j) => stageOf(j) == ArtisanStage.inReview ? j.autoReleaseAt : null;

  /// Fraction of a window still remaining, for countdown rings.
  static double remainingFraction(DateTime start, DateTime end, DateTime now) {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (end.difference(now).inSeconds / total).clamp(0.0, 1.0);
  }

  /// "18 h", "45 min", "11 d" — or null once passed.
  static String? remainingLabel(DateTime end, DateTime now) {
    final d = end.difference(now);
    if (d.isNegative) return null;
    if (d.inDays >= 2) return '${d.inDays} d';
    if (d.inHours >= 1) return '${d.inHours} h';
    return '${d.inMinutes.clamp(1, 59)} min';
  }

  /// The artisan's action queue, most urgent first.
  static List<ArtisanAction> actionQueue(Iterable<JobModel> jobs, {required int bookingConfirmationHours}) {
    final out = <ArtisanAction>[];
    for (final j in jobs) {
      switch (stageOf(j)) {
        case ArtisanStage.request:
          out.add(ArtisanAction(ArtisanActionKind.respondToBooking, j, deadline: bookingDeadline(j, bookingConfirmationHours)));
        case ArtisanStage.agreement when j.agreementStatus == AgreementStatus.pendingArtisanConfirmation:
          out.add(ArtisanAction(ArtisanActionKind.reviewAgreement, j));
        case ArtisanStage.schedule when j.appointmentSlots.isEmpty:
          out.add(ArtisanAction(ArtisanActionKind.proposeTimes, j));
        case ArtisanStage.readyToStart:
          out.add(ArtisanAction(ArtisanActionKind.startWork, j));
        case ArtisanStage.rework when j.reworkResponse == null:
          out.add(ArtisanAction(ArtisanActionKind.respondToRework, j));
        case ArtisanStage.disputed:
          out.add(ArtisanAction(ArtisanActionKind.respondToDispute, j));
        default:
          break;
      }
    }
    const order = ArtisanActionKind.values;
    out.sort((a, b) {
      final k = order.indexOf(a.kind).compareTo(order.indexOf(b.kind));
      if (k != 0) return k;
      final ad = a.deadline, bd = b.deadline;
      if (ad != null && bd != null) return ad.compareTo(bd);
      return 0;
    });
    return out;
  }

  /// Next confirmed appointment among active jobs.
  static JobModel? nextAppointment(Iterable<JobModel> jobs, DateTime now) {
    JobModel? best;
    for (final j in jobs) {
      final at = j.confirmedAppointment;
      if (at == null || at.isBefore(now) || !isActive(j)) continue;
      if (best == null || at.isBefore(best.confirmedAppointment!)) best = j;
    }
    return best;
  }

  /// Jobs grouped for My Jobs, in pipeline order; empty groups dropped.
  static List<(String, List<JobModel>)> groupForMyJobs(Iterable<JobModel> jobs) {
    final groups = <String, List<JobModel>>{
      'Requests': [],
      'Agreement': [],
      'Awaiting payment': [],
      'Working now': [],
      'In review': [],
      'Disputed': [],
    };
    for (final j in jobs) {
      final s = stageOf(j);
      final key = switch (s) {
        ArtisanStage.request => 'Requests',
        ArtisanStage.agreement || ArtisanStage.schedule => 'Agreement',
        ArtisanStage.awaitingPayment => 'Awaiting payment',
        ArtisanStage.readyToStart || ArtisanStage.working || ArtisanStage.rework => 'Working now',
        ArtisanStage.inReview => 'In review',
        ArtisanStage.disputed => 'Disputed',
        _ => null,
      };
      if (key != null) groups[key]!.add(j);
    }
    return [for (final e in groups.entries) if (e.value.isNotEmpty) (e.key, e.value)];
  }

  static bool isHistory(JobModel j) {
    final s = stageOf(j);
    return s == ArtisanStage.completed || s == ArtisanStage.closed;
  }

  /// Next progress stage after [current], or null at the end.
  static JobProgressStage? nextProgress(JobProgressStage? current) {
    const all = JobProgressStage.values;
    if (current == null) return all.first;
    final i = all.indexOf(current);
    return i + 1 < all.length ? all[i + 1] : null;
  }

  /// Artisan-side decline/withdraw (before payment) vs paid-cancellation
  /// request (after funding), matching the existing job detail rules.
  static bool canWithdraw(JobModel j) {
    final s = stageOf(j);
    return s == ArtisanStage.request || s == ArtisanStage.agreement || s == ArtisanStage.schedule || s == ArtisanStage.awaitingPayment;
  }

  static bool canRequestPaidCancellation(JobModel j) =>
      (j.status == JobStatus.escrowLocked || j.status == JobStatus.inProgress) && !j.hasPendingCancellationRequest;

  static const artisanReasons = ['Unavailable on requested date', 'Too far from location', 'Outside my expertise', 'Other'];
}
