import '../../models/job_model.dart';
import 'job_service.dart';

/// Single source of truth for "what phase is this job in, who's it
/// waiting on, and what's the next action" — the exact decisions
/// job_detail_screen.dart and chat_screen.dart were each computing
/// independently before this file existed (chat re-derived its own
/// agreementStatus == confirmed check; job detail had the same check
/// duplicated across its inChat branches). One drifting out of sync with
/// the other was a real risk, not a hypothetical one.
///
/// This does NOT replace or re-implement JobService's security-authoritative
/// predicates (canConfirmAgreement / canRespondToAgreement / canInitPayment)
/// — canPay below calls JobService.canInitPayment directly rather than
/// re-deriving the same condition a second way. Firestore rules remain the
/// actual server-side enforcement regardless of what this class says; this
/// class (like JobService's predicates) is a client-side convenience that
/// mirrors the same rules, not a second authority.
///
/// Deliberately pure — no Firestore reads, no BuildContext, no ref. Screens
/// still own the actual onPressed execution (navigation, provider calls)
/// via [WorkflowStep.primaryAction]; this class only decides whether that
/// action is available and what to call it, not how to perform it.
abstract final class WorkflowGateService {
  /// Whether payment can start right now for [actorId]. Delegates to
  /// [JobService.canInitPayment] — not re-derived here.
  static bool canPay(JobModel job, String actorId) =>
      JobService.canInitPayment(job, actorId);

  /// True while the job is inChat and the two-party agreement checkpoint
  /// hasn't been confirmed yet — the condition that previously lived
  /// separately in both chat_screen.dart's app-bar check and job_detail's
  /// inChat branch.
  static bool isAgreementRequired(JobModel job) =>
      job.status == JobStatus.inChat &&
      job.agreementStatus != AgreementStatus.confirmed;

  /// True once the agreement is confirmed but (for jobs that need one) a
  /// schedule still isn't. 'asap' jobs are never in this state — they have
  /// nothing to schedule (see [JobModel.schedulingSatisfied]).
  static bool isSchedulingRequired(JobModel job) =>
      job.status == JobStatus.inChat &&
      job.agreementStatus == AgreementStatus.confirmed &&
      !job.schedulingSatisfied;

  /// True once both the agreement and (if applicable) scheduling are
  /// satisfied — the job is ready for the customer to pay, even if they
  /// haven't yet. Distinct from [canPay], which additionally checks the
  /// caller's identity/role — this is "is the job ready," not "can this
  /// specific actor do it right now."
  static bool isReadyForPayment(JobModel job) =>
      job.status == JobStatus.inChat &&
      job.agreementStatus == AgreementStatus.confirmed &&
      job.schedulingSatisfied;

  /// Full descriptive step for the current status, from [viewerIsCustomer]'s
  /// point of view — what job_detail_screen.dart's action-buttons area (and
  /// any future screen that needs the same decision) renders from. Covers
  /// every non-terminal status, including the three inChat sub-phases
  /// (negotiating / awaiting schedule / ready for payment) that collapse
  /// into a single JobStatus.inChat value.
  static WorkflowStep describeStep(JobModel job, {required bool viewerIsCustomer}) {
    switch (job.status) {
      case JobStatus.requested:
        return WorkflowStep(
          phase: 'Job Requested',
          description: viewerIsCustomer
              ? "Waiting for artisans to respond. You'll be notified as quotes come in."
              : "This job is still open. You can submit a quote for it from the Open Jobs Feed.",
          waitingOn: viewerIsCustomer ? WorkflowActor.artisan : null,
          primaryAction: viewerIsCustomer
              ? WorkflowAction.none
              : WorkflowAction.browseOpenJobs,
          primaryLabel: viewerIsCustomer ? null : 'Browse Open Jobs',
        );

      // Stage 5 (D7): a match is a booking REQUEST until the artisan
      // confirms it (within the server-configured window, default 24 h).
      // Declining / not answering reopens the job server-side.
      case JobStatus.matched when job.awaitingArtisanConfirmation:
        return WorkflowStep(
          phase: 'Awaiting Artisan Confirmation',
          description: viewerIsCustomer
              ? "Booking request sent. The artisan has 24 hours to confirm it — if they decline or don't respond, your job reopens for other artisans."
              : 'A customer wants to book you. Accept to start agreeing the details, or decline so they can book someone else. Unanswered requests expire after 24 hours.',
          waitingOn: viewerIsCustomer ? WorkflowActor.artisan : null,
          primaryAction: viewerIsCustomer ? WorkflowAction.none : WorkflowAction.confirmBooking,
          primaryLabel: viewerIsCustomer ? null : 'Accept Booking',
        );

      case JobStatus.matched:
        return WorkflowStep(
          phase: 'Quote Accepted',
          description: viewerIsCustomer
              ? "You've hired this artisan. Start a conversation to agree on the details before confirming the job."
              : "The customer accepted your quote. They'll start a conversation with you to work out the details.",
          waitingOn: viewerIsCustomer ? null : WorkflowActor.customer,
          primaryAction: viewerIsCustomer
              ? WorkflowAction.continueNegotiation
              : WorkflowAction.none,
          primaryLabel: viewerIsCustomer ? 'Continue Negotiation' : null,
        );

      case JobStatus.inChat:
        if (isAgreementRequired(job)) {
          // _AgreementSection above already renders the full confirm/
          // accept/request-changes UI for every one of these sub-phases —
          // this step exists so OTHER surfaces (chat's gate, a future
          // screen) can ask "is there anything to show here" without
          // duplicating _AgreementSection's own state logic, not to
          // replace that section's UI.
          return WorkflowStep(
            phase: 'Negotiation',
            description: 'Confirm the job terms before proceeding to payment.',
            waitingOn: null,
            primaryAction: WorkflowAction.none,
          );
        }
        if (isSchedulingRequired(job)) {
          return WorkflowStep(
            phase: 'Awaiting Schedule',
            description: viewerIsCustomer
                ? 'The agreement is confirmed. Propose or confirm an appointment time before payment — this job needs a scheduled visit.'
                : 'Propose an appointment time — the customer needs to confirm one before they can pay into escrow.',
            waitingOn: null,
            primaryAction: WorkflowAction.none,
          );
        }
        // isReadyForPayment(job) — the only remaining inChat case.
        return WorkflowStep(
          phase: 'Agreement Confirmed',
          description:
              'Both of you have agreed on the terms. Fund escrow to let the artisan begin work — your payment stays protected until you confirm completion.',
          waitingOn: viewerIsCustomer ? null : WorkflowActor.customer,
          primaryAction: viewerIsCustomer ? WorkflowAction.payIntoEscrow : WorkflowAction.none,
          primaryLabel: viewerIsCustomer ? 'Pay Into Escrow' : null,
        );

      // Stage 3 (HT-009): previously no action at all here, so a customer
      // who closed or failed checkout was stranded. They can now resume
      // (the payment screen skips the status write and the server refuses
      // a second charge if the first actually succeeded); an unpaid
      // checkout also expires server-side after the configured window.
      case JobStatus.paymentPending:
        return WorkflowStep(
          phase: 'Awaiting Payment',
          description: viewerIsCustomer
              ? "Your payment hasn't been confirmed yet. If you closed or couldn't finish the checkout, resume it below. If you've just paid, this page updates automatically."
              : "Waiting for the customer to complete payment into escrow. Don't start work until payment is confirmed.",
          waitingOn: viewerIsCustomer ? WorkflowActor.system : WorkflowActor.customer,
          primaryAction: viewerIsCustomer ? WorkflowAction.payIntoEscrow : WorkflowAction.none,
          primaryLabel: viewerIsCustomer ? 'Resume Payment' : null,
        );

      case JobStatus.escrowLocked:
        return WorkflowStep(
          phase: 'Payment Complete',
          description: viewerIsCustomer
              ? 'Your payment is held securely in escrow. The artisan will begin work shortly.'
              : "The customer's payment is locked in escrow — you're clear to start.",
          waitingOn: viewerIsCustomer ? WorkflowActor.artisan : null,
          primaryAction: viewerIsCustomer ? WorkflowAction.none : WorkflowAction.startJob,
          primaryLabel: viewerIsCustomer ? null : 'Start Job',
        );

      case JobStatus.inProgress when job.reworkCount > 0:
        return WorkflowStep(
          phase: 'Rework Requested',
          description: viewerIsCustomer
              ? 'You asked for changes. The artisan will resubmit the work, and a new 14-day review period starts then.'
              : 'The customer asked for changes (see below). Fix the issues, then submit the work again.',
          waitingOn: viewerIsCustomer ? WorkflowActor.artisan : null,
          primaryAction: viewerIsCustomer ? WorkflowAction.none : WorkflowAction.submitCompletion,
          primaryLabel: viewerIsCustomer ? null : 'Resubmit Work',
        );

      case JobStatus.inProgress:
        return WorkflowStep(
          phase: 'Job In Progress',
          description: viewerIsCustomer
              ? "The artisan is working on your job. You'll be notified as soon as they submit it for your review."
              : 'Once the work is done, submit photos for the customer to review.',
          waitingOn: viewerIsCustomer ? WorkflowActor.artisan : null,
          primaryAction: viewerIsCustomer ? WorkflowAction.none : WorkflowAction.submitCompletion,
          primaryLabel: viewerIsCustomer ? null : 'Submit Completion',
        );

      case JobStatus.submitted:
        return WorkflowStep(
          phase: viewerIsCustomer ? 'Work Submitted' : 'Submitted',
          description: viewerIsCustomer
              ? 'The artisan says the job is done. Review their photos and confirm to release payment — or raise a dispute if something is wrong.'
              : "Waiting for the customer to confirm your work. If they don't respond, payment releases automatically after 48 hours.",
          waitingOn: viewerIsCustomer ? null : WorkflowActor.customer,
          // Customer has two real actions here (confirm or dispute) — a
          // single primaryAction can't express both, so job_detail_screen
          // keeps rendering them explicitly rather than through this step;
          // this branch exists mainly for consistent phase/waitingOn text.
          primaryAction: WorkflowAction.none,
        );

      case JobStatus.completed:
      case JobStatus.disputed:
      case JobStatus.resolved:
      case JobStatus.cancelled:
      case JobStatus.expired:
        return const WorkflowStep(
          phase: 'Closed',
          description: '',
          waitingOn: null,
          primaryAction: WorkflowAction.none,
        );
    }
  }
}

enum WorkflowActor { customer, artisan, system }

enum WorkflowAction {
  none,
  browseOpenJobs,
  continueNegotiation,
  payIntoEscrow,
  startJob,
  submitCompletion,
  /// Stage 5: artisan accepts a booking request (matched -> inChat).
  confirmBooking,
}

class WorkflowStep {
  final String phase;
  final String description;
  final WorkflowActor? waitingOn;
  final WorkflowAction primaryAction;
  final String? primaryLabel;

  const WorkflowStep({
    required this.phase,
    required this.description,
    required this.waitingOn,
    required this.primaryAction,
    this.primaryLabel,
  });
}
