import '../../models/job_model.dart';
import '../../models/payment_model.dart';

/// One month of released payouts (bars on the Earnings screen).
class MonthTotal {
  const MonthTotal(this.year, this.month, this.total);
  final int year;
  final int month;
  final double total;
}

/// Earnings figures for the artisan, computed only from the artisan's own
/// payment documents (`artisanPaymentsProvider`) and their jobs. `amount`
/// is the agreed service price the artisan receives in full; the 5%
/// platform fee is paid by the customer on top and never counted here.
class ArtisanEarningsSummary {
  const ArtisanEarningsSummary({
    required this.releasedLastMonths,
    required this.releasedThisMonth,
    required this.releasedThisMonthJobs,
    required this.inEscrow,
    required this.inEscrowJobs,
    required this.awaitingRelease,
    required this.months,
  });

  /// Released over the [months] window shown in the bars.
  final double releasedLastMonths;
  final double releasedThisMonth;
  final int releasedThisMonthJobs;

  /// Funded and held for jobs that aren't in customer review yet.
  final double inEscrow;
  final int inEscrowJobs;

  /// Held for jobs submitted and in the 14-day review.
  final double awaitingRelease;
  final List<MonthTotal> months;

  static bool isReleased(PaymentModel p) => p.status == PaymentStatus.released;

  static bool isHeld(PaymentModel p) => p.status == PaymentStatus.escrowHeld || p.status == PaymentStatus.releasing;

  static ArtisanEarningsSummary of(List<PaymentModel> payments, Map<String, JobModel> jobsById, DateTime now, {int monthCount = 6}) {
    final months = <MonthTotal>[];
    for (var i = monthCount - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i);
      months.add(MonthTotal(d.year, d.month, 0));
    }
    var thisMonth = 0.0;
    var thisMonthJobs = 0;
    var held = 0.0;
    var heldJobs = 0;
    var awaiting = 0.0;
    for (final p in payments) {
      if (isReleased(p)) {
        final at = p.releasedAt ?? p.paidAt ?? p.createdAt;
        final idx = months.indexWhere((m) => m.year == at.year && m.month == at.month);
        if (idx >= 0) months[idx] = MonthTotal(months[idx].year, months[idx].month, months[idx].total + p.amount);
        if (at.year == now.year && at.month == now.month) {
          thisMonth += p.amount;
          thisMonthJobs++;
        }
      } else if (isHeld(p)) {
        final job = jobsById[p.jobId];
        if (job != null && job.status == JobStatus.submitted) {
          awaiting += p.amount;
        } else {
          held += p.amount;
          heldJobs++;
        }
      }
    }
    return ArtisanEarningsSummary(
      releasedLastMonths: months.fold(0, (s, m) => s + m.total),
      releasedThisMonth: thisMonth,
      releasedThisMonthJobs: thisMonthJobs,
      inEscrow: held,
      inEscrowJobs: heldJobs,
      awaitingRelease: awaiting,
      months: months,
    );
  }

  /// Ledger rows: released payments, newest first.
  static List<PaymentModel> ledger(List<PaymentModel> payments) {
    final rows = payments.where(isReleased).toList()
      ..sort((a, b) => (b.releasedAt ?? b.createdAt).compareTo(a.releasedAt ?? a.createdAt));
    return rows;
  }

  /// Payout transfer status mirrored on the job by the server
  /// (`processing`, `paid`, `delayed`, `on_hold`).
  static String payoutLabel(String? payoutStatus) => switch (payoutStatus) {
        'paid' => 'Paid',
        'processing' => 'Processing',
        'delayed' => 'Delayed',
        'on_hold' => 'On hold',
        _ => 'Released',
      };
}
