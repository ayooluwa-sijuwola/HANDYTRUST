import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/paystack_service.dart';
import 'package:handy_trust/core/services/workflow_gate_service.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/payment_model.dart';

// Stage 3 (design/REMEDIATION_STAGE3_REPORT_2026-11-03.md): resume an
// abandoned payment, display only server-computed fees, and parse the new
// server-only payment statuses without masquerading them as "pending".
void main() {
  JobModel job(JobStatus status) => JobModel(
        id: 'job-1',
        customerId: 'customer-1',
        artisanId: 'artisan-1',
        category: 'Plumbing',
        description: 'Fix a leaking pipe',
        status: status,
        createdAt: DateTime(2026, 1, 1),
      );

  group('paymentPending is no longer a dead end (HT-009)', () {
    test('customer is offered Resume Payment', () {
      final step = WorkflowGateService.describeStep(job(JobStatus.paymentPending), viewerIsCustomer: true);
      expect(step.primaryAction, WorkflowAction.payIntoEscrow);
      expect(step.primaryLabel, 'Resume Payment');
    });

    test('artisan is told to wait for payment and has no action', () {
      final step = WorkflowGateService.describeStep(job(JobStatus.paymentPending), viewerIsCustomer: false);
      expect(step.primaryAction, WorkflowAction.none);
      expect(step.waitingOn, WorkflowActor.customer);
    });
  });

  group('PaymentBreakdown — server numbers only (HT-013)', () {
    test('parses the getPaymentBreakdown callable result', () {
      final b = PaymentBreakdown.fromMap({
        'serviceAmount': 50000,
        'platformFee': 2500,
        'totalCharged': 52500,
        'platformFeePercent': 5,
        'minPlatformFeeNgn': 0,
        'currency': 'NGN',
      });
      expect(b.serviceAmount, 50000);
      expect(b.platformFee, 2500);
      expect(b.totalCharged, 52500);
      expect(b.platformFeePercent, 5);
    });
  });

  group('PaymentModel — fee fields and server-only statuses', () {
    Map<String, dynamic> base(Map<String, dynamic> o) => {
          'id': 'p1',
          'jobId': 'job-1',
          'payerId': 'customer-1',
          'artisanId': 'artisan-1',
          'amount': 50000,
          'status': 'escrowHeld',
          ...o,
        };

    test('chargedTotal is what the customer paid; amount stays the service price', () {
      final p = PaymentModel.fromJson(base({'platformFee': 2500, 'totalCharged': 52500}));
      expect(p.amount, 50000);
      expect(p.chargedTotal, 52500);
    });

    test('legacy payments without a fee: chargedTotal == amount', () {
      expect(PaymentModel.fromJson(base({})).chargedTotal, 50000);
    });

    test('abandoned / requiresRefund parse as themselves, not pending', () {
      expect(PaymentModel.fromJson(base({'status': 'abandoned'})).status, PaymentStatus.abandoned);
      expect(PaymentModel.fromJson(base({'status': 'requiresRefund'})).status, PaymentStatus.requiresRefund);
    });
  });
}
