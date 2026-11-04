import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/payment_model.dart';
import 'package:handy_trust/providers/platform_config_provider.dart';

// Stage 4 (design/REMEDIATION_STAGE4_REPORT_2026-11-03.md): minimum job value
// shown to users (D1), new money states, server-written refund mirror.
void main() {
  group('PlatformConfig — minimum job value (D1)', () {
    test('defaults to ₦3,212 when config/platform is missing', () {
      final c = PlatformConfig.fromMap(null);
      expect(c.minJobValueNgn, 3212);
      expect(c.minJobValueLabel, '₦3,212');
    });

    test('follows trusted backend config', () {
      final c = PlatformConfig.fromMap({'minJobValueNgn': 5000});
      expect(c.minJobValueNgn, 5000);
      expect(c.minJobValueLabel, '₦5,000');
    });

    test('meetsMinimum is inclusive and rejects missing amounts', () {
      const c = PlatformConfig();
      expect(c.meetsMinimum(3211), isFalse);
      expect(c.meetsMinimum(3212), isTrue);
      expect(c.meetsMinimum(null), isFalse);
    });
  });

  group('PaymentStatus — Stage 4 money states parse as themselves', () {
    for (final s in ['releasing', 'refundPending', 'settling', 'settled', 'refunded']) {
      test(s, () {
        final p = PaymentModel.fromJson({
          'id': 'p1', 'jobId': 'j1', 'payerId': 'c', 'artisanId': 'a', 'amount': 50000, 'status': s,
        });
        expect(p.status.name, s);
      });
    }
  });

  test('JobModel parses the server-written refund/settlement mirror', () {
    final j = JobModel.fromJson({
      'id': 'j1',
      'customerId': 'c',
      'status': 'cancelled',
      'refundStatus': 'submitted',
      'settlementOutcome': 'full_refund',
      'settlementStatus': 'executing',
    });
    expect(j.refundStatus, 'submitted');
    expect(j.settlementOutcome, 'full_refund');
    expect(j.settlementStatus, 'executing');
  });
}
