import '../../models/job_model.dart';
import 'workflow_gate_service.dart';

/// Tabs on the customer Bookings screen (references 4, 19). "Drafts" from
/// the reference is omitted: the backend has no draft jobs.
enum BookingTab { active, completed, disputed }

/// The one action a booking card offers the customer, decided only from
/// the server state machine (WorkflowGateService / JobService).
enum CustomerBookingAction { approveAndRelease, payIntoEscrow, openChat, reviewQuotes, viewDetails }

/// Stage 8: pure presentation logic for customer bookings, kept out of the
/// widgets so it is unit-tested (test/stage8_ui_logic_test.dart).
abstract final class CustomerBookingLogic {
  static const fundedStatuses = {JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted};

  static BookingTab tabFor(JobStatus s) => switch (s) {
        JobStatus.disputed => BookingTab.disputed,
        JobStatus.completed || JobStatus.resolved || JobStatus.cancelled || JobStatus.expired => BookingTab.completed,
        _ => BookingTab.active,
      };

  static Map<BookingTab, List<JobModel>> group(List<JobModel> jobs) {
    final out = {for (final t in BookingTab.values) t: <JobModel>[]};
    for (final j in jobs) {
      out[tabFor(j.status)]!.add(j);
    }
    return out;
  }

  /// True when escrow holds the customer's payment for this job.
  static bool isFunded(JobModel j) => fundedStatuses.contains(j.status);

  /// Index into Funded / In Progress / Verified / Released.
  static int lifecycleIndex(JobStatus s) => switch (s) {
        JobStatus.escrowLocked => 0,
        JobStatus.inProgress => 1,
        JobStatus.submitted => 2,
        JobStatus.completed => 3,
        _ => 0,
      };

  static CustomerBookingAction actionFor(JobModel job, String customerId) {
    if (job.status == JobStatus.submitted) return CustomerBookingAction.approveAndRelease;
    if (WorkflowGateService.isReadyForPayment(job) && WorkflowGateService.canPay(job, customerId)) {
      return CustomerBookingAction.payIntoEscrow;
    }
    if (job.status == JobStatus.paymentPending && WorkflowGateService.canPay(job, customerId)) {
      return CustomerBookingAction.payIntoEscrow;
    }
    if (job.status == JobStatus.inChat) return CustomerBookingAction.openChat;
    if (job.status == JobStatus.requested) return CustomerBookingAction.reviewQuotes;
    return CustomerBookingAction.viewDetails;
  }

  /// Short status text for an unfunded/closed booking card.
  static String statusLabel(JobModel j) => switch (j.status) {
        JobStatus.requested => 'Open for quotes',
        JobStatus.matched => 'Awaiting artisan response',
        JobStatus.inChat => WorkflowGateService.isReadyForPayment(j) ? 'Ready for payment' : 'Agreeing terms',
        JobStatus.paymentPending => 'Payment in progress',
        JobStatus.escrowLocked => 'In escrow',
        JobStatus.inProgress => 'In progress',
        JobStatus.submitted => 'Awaiting your approval',
        JobStatus.completed => 'Completed',
        JobStatus.disputed => 'Disputed',
        JobStatus.resolved => 'Resolved',
        JobStatus.cancelled => 'Cancelled',
        JobStatus.expired => 'Expired',
      };
}
