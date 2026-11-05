// Stage 8.1 — artisan earnings figures come only from the artisan's own
// payment documents (no wallet, no invented totals).
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/artisan_earnings_summary.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/payment_model.dart';

PaymentModel pay(String id, String jobId, PaymentStatus s, double amount, {DateTime? releasedAt}) => PaymentModel(
      id: id,
      jobId: jobId,
      payerId: 'c1',
      artisanId: 'a1',
      amount: amount,
      totalCharged: amount * 1.05,
      status: s,
      releasedAt: releasedAt,
      createdAt: DateTime(2026, 6, 1),
    );

JobModel job(String id, JobStatus s) => JobModel(id: id, customerId: 'c1', artisanId: 'a1', category: 'Plumbing', description: 'x', status: s, createdAt: DateTime(2026));

void main() {
  final now = DateTime(2026, 11, 5);

  test('released totals by month, this month, escrow vs awaiting release', () {
    final payments = [
      pay('p1', 'j1', PaymentStatus.released, 40000, releasedAt: DateTime(2026, 11, 2)),
      pay('p2', 'j2', PaymentStatus.released, 25000, releasedAt: DateTime(2026, 10, 20)),
      pay('p3', 'j3', PaymentStatus.released, 99000, releasedAt: DateTime(2025, 1, 1)), // outside the 6-month window
      pay('p4', 'j4', PaymentStatus.escrowHeld, 30000),
      pay('p5', 'j5', PaymentStatus.releasing, 15000),
      pay('p6', 'j6', PaymentStatus.escrowHeld, 50000), // job submitted → awaiting release
      pay('p7', 'j7', PaymentStatus.refunded, 70000), // never counted
      pay('p8', 'j8', PaymentStatus.pending, 10000), // not funded yet
    ];
    final jobs = {
      'j4': job('j4', JobStatus.inProgress),
      'j5': job('j5', JobStatus.escrowLocked),
      'j6': job('j6', JobStatus.submitted),
    };
    final s = ArtisanEarningsSummary.of(payments, jobs, now);
    expect(s.months.length, 6);
    expect(s.months.first.month, 6);
    expect(s.months.last.month, 11);
    expect(s.months.last.total, 40000);
    expect(s.months[4].total, 25000);
    expect(s.releasedLastMonths, 65000);
    expect(s.releasedThisMonth, 40000);
    expect(s.releasedThisMonthJobs, 1);
    expect(s.inEscrow, 45000);
    expect(s.inEscrowJobs, 2);
    expect(s.awaitingRelease, 50000);
  });

  test('no payments → zeros, never placeholder figures', () {
    final s = ArtisanEarningsSummary.of(const [], const {}, now);
    expect(s.releasedLastMonths, 0);
    expect(s.inEscrow, 0);
    expect(s.awaitingRelease, 0);
    expect(s.months.every((m) => m.total == 0), isTrue);
  });

  test('year rollover in the month window', () {
    final s = ArtisanEarningsSummary.of(const [], const {}, DateTime(2026, 2, 10));
    expect(s.months.map((m) => '${m.year}-${m.month}'), ['2025-9', '2025-10', '2025-11', '2025-12', '2026-1', '2026-2']);
  });

  test('ledger is released payments only, newest first', () {
    final rows = ArtisanEarningsSummary.ledger([
      pay('old', 'j', PaymentStatus.released, 1, releasedAt: DateTime(2026, 9, 1)),
      pay('held', 'j', PaymentStatus.escrowHeld, 1),
      pay('new', 'j', PaymentStatus.released, 1, releasedAt: DateTime(2026, 11, 1)),
    ]);
    expect(rows.map((p) => p.id), ['new', 'old']);
  });

  test('payout labels mirror the server payoutStatus', () {
    expect(ArtisanEarningsSummary.payoutLabel('paid'), 'Paid');
    expect(ArtisanEarningsSummary.payoutLabel('processing'), 'Processing');
    expect(ArtisanEarningsSummary.payoutLabel('delayed'), 'Delayed');
    expect(ArtisanEarningsSummary.payoutLabel('on_hold'), 'On hold');
    expect(ArtisanEarningsSummary.payoutLabel(null), 'Released');
  });
}
