import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/services/paystack_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../models/job_model.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/web_content_wrapper.dart';

final _paystackServiceProvider = Provider<PaystackService>(
  (ref) => PaystackService(FirebaseFunctions.instance),
);

/// Server-computed fee breakdown (Stage 3) — the same calculation the
/// charge itself uses, so what's shown is exactly what's charged.
final _paymentBreakdownProvider =
    FutureProvider.autoDispose.family<PaymentBreakdown, String>(
  (ref, jobId) => ref.read(_paystackServiceProvider).getPaymentBreakdown(jobId),
);

class PaymentScreen extends ConsumerStatefulWidget {
  final String jobId;

  const PaymentScreen({super.key, required this.jobId});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _amountController = TextEditingController();
  bool _loading = false;
  bool _amountInitialized = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(jobStreamProvider(widget.jobId));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Escrow Payment')),
      body: WebContentWrapper(
        maxWidth: 640,
        child: jobAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (job) {
            if (job == null) return const Center(child: Text('Job not found'));
            return _buildBody(context, job);
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, JobModel job) {
    if (!_amountInitialized) {
      _amountInitialized = true;
      _amountController.text = job.agreedAmount?.toStringAsFixed(0) ?? '';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _escrowInfoCard(),
          const SizedBox(height: 24),
          const Text('Payment Amount',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              )),
          const SizedBox(height: 8),
          // Read-only: the amount actually charged is always the job's
          // server-recorded agreedAmount (initializePaystackTransaction
          // derives it from the job document, not from client input — see
          // design/P0_REMEDIATION_PLAN.md). This field used to be editable
          // even though nothing downstream ever honored a typed-in value
          // beyond this point — leaving it editable would silently ignore
          // whatever the customer typed, which is itself a misleading-UI
          // bug once the server stopped trusting it.
          TextField(
            controller: _amountController,
            readOnly: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixText: '₦ ',
              hintText: 'Enter amount',
              errorText: _error,
              helperText: 'This is the amount you agreed with the artisan.',
            ),
          ),
          const SizedBox(height: 12),
          _feeBreakdown(job),
          const SizedBox(height: 32),
          // Black "commitment" button — locking funds in escrow is exactly
          // the one-time, high-commitment action CommitButton is for, and
          // matches Stitch's own black "Lock Funds in Escrow" button.
          CommitButton(
            label: 'Lock Funds in Escrow',
            loading: _loading,
            onPressed: () => _initiatePayment(job),
            icon: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: 16),
          const _EscrowGuaranteeRow(),
        ],
      ),
    );
  }

  // Task 2's own instruction is "do not hide important information" — so
  // this is a static, always-visible list of the five things a first-time
  // payer needs answered (what/why/when/who/disputes), not a collapsed
  // accordion. Every line describes real, existing behavior — the auto-
  // release window (_DisputeCountdownBanner in job_detail_screen.dart),
  // JobService's completion-confirmation transition, and the existing
  // dispute flow — nothing here is aspirational.
  Widget _escrowInfoCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.accentSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.accent.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.colors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_outline_rounded,
                      color: context.colors.accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('How Escrow Protects You',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                        fontFamily: 'Inter',
                      )),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _escrowFact(
              icon: Icons.savings_outlined,
              question: 'What is escrow?',
              answer:
                  "A neutral holding account. Your payment doesn't go to the artisan directly — HandyTrust holds it until the work is confirmed done.",
            ),
            _escrowFact(
              icon: Icons.shield_outlined,
              question: 'Why is my payment held?',
              answer:
                  "So the artisan is guaranteed payment for real work, and you're guaranteed the work happens before any money moves — neither side is trusting the other on faith.",
            ),
            _escrowFact(
              icon: Icons.schedule_outlined,
              question: 'When is it released?',
              // Deliberately no specific number of days/hours here — see
              // design/STITCH_PAYMENT_AUDIT.md. The dispute-window text
              // shown once work is submitted (14 days) doesn't match the
              // Cloud Function that actually auto-releases funds (48h from
              // escrow lock), a real backend discrepancy out of scope to
              // fix in this pass. Stating either number here risked
              // promising something the backend doesn't actually do.
              answer:
                  "The moment you confirm the completed job. If you don't respond, it also releases automatically after a window once the artisan marks it done — you'll see that countdown once it starts.",
            ),
            _escrowFact(
              icon: Icons.how_to_reg_outlined,
              question: 'Who can release it?',
              answer:
                  'Only you, by confirming completion — or HandyTrust automatically, once the response window passes with no dispute raised.',
            ),
            _escrowFact(
              icon: Icons.gavel_outlined,
              question: 'What if something goes wrong?',
              answer:
                  "Raise a dispute before the window closes and the release pauses — an admin reviews it before any funds move either way.",
              isLast: true,
            ),
          ],
        ),
      );

  Widget _escrowFact({
    required IconData icon,
    required String question,
    required String answer,
    bool isLast = false,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: context.colors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    answer,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _feeBreakdown(JobModel job) {
    final breakdownAsync = ref.watch(_paymentBreakdownProvider(job.id));
    return breakdownAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(14),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        'Could not load the payment breakdown. Please try again.',
        style: TextStyle(color: context.colors.error, fontFamily: 'Inter', fontSize: 13),
      ),
      data: (b) => _feeBreakdownCard(b),
    );
  }

  Widget _feeBreakdownCard(PaymentBreakdown b) {
    final amount = b.serviceAmount;
    final platformFee = b.platformFee;
    final total = b.totalCharged;
    final pct = b.platformFeePercent == b.platformFeePercent.roundToDouble()
        ? b.platformFeePercent.toStringAsFixed(0)
        : b.platformFeePercent.toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _feeRow('Service amount', '₦${amount.toStringAsFixed(0)}'),
          const SizedBox(height: 6),
          _feeRow('Platform fee ($pct%)', '₦${platformFee.toStringAsFixed(0)}'),
          const Divider(height: 16),
          _feeRow('Total charged', '₦${total.toStringAsFixed(0)}',
              bold: true),
        ],
      ),
    );
  }

  Widget _feeRow(String label, String value, {bool bold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 13,
                color: bold ? context.colors.textPrimary : context.colors.textSecondary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                fontFamily: 'Inter',
              )),
          Text(value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              )),
        ],
      );

  Future<void> _initiatePayment(JobModel job) async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount < 100) {
      setState(() => _error = 'Minimum payment is ₦100');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final payerId = ref.read(authStateChangesProvider).value?.uid ?? '';
      if (payerId.isEmpty) throw Exception('Not signed in');

      // Transition job → paymentPending — unless it's already there (a
      // retry/resume after an abandoned or failed checkout, HT-009): the
      // initialize callable is idempotent and accepts paymentPending. The
      // amount above is display/validation only; the server charges the
      // frozen agreedAmount plus the platform fee.
      if (job.status != JobStatus.paymentPending) {
        await ref.read(escrowNotifierProvider.notifier).initPayment(job.id);
        // HT-042: this used to be ignored, so a rejected transition only
        // surfaced later as a confusing gateway error.
        final initState = ref.read(escrowNotifierProvider);
        if (initState.hasError) {
          if (mounted) {
            setState(() => _error =
                'Payment could not be started: ${initState.error}');
          }
          return;
        }
      }

      try {
        final user = ref.read(currentUserProvider).asData?.value;
        final email = user?.email ?? 'demo@handytrust.ng';
        final paystack = ref.read(_paystackServiceProvider);
        final payment = await paystack.initializeTransaction(
          jobId: job.id,
          payerId: payerId,
          artisanId: job.artisanId,
          amountNaira: amount,
          customerEmail: email,
        );
        if (!mounted) return;
        if (payment == null) {
          // The server found an earlier attempt had already been paid and
          // locked escrow itself — never open a second checkout.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment already received — escrow is secured.')),
          );
          context.go('/job/${job.id}');
          return;
        }
        if (payment.authorizationUrl != null) {
          context.push('/payment/${job.id}/webview', extra: {
            'url': payment.authorizationUrl!,
            'reference': payment.paystackReference!,
          });
        }
      } catch (e) {
        debugPrint('[PaymentScreen] initializeTransaction failed: $e');
        if (!mounted) return;
        // Demo simulation is a debug-only fallback for local development
        // without Paystack secrets configured. It must never silently
        // substitute fake money movement for a real payment in a release
        // build — that would let a customer think they paid when they
        // didn't, and a release-mode artisan could be marked "paid" for
        // nothing.
        if (kDebugMode) {
          await _simulatePaymentAndProceed(job.id);
        } else {
          setState(() => _error = 'Payment could not be started: $e');
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _simulatePaymentAndProceed(String jobId) async {
    if (!mounted) return;
    // Hand off to DemoEscrowScreen for the full animated payment experience
    context.push('/demo-payment/$jobId', extra: {'autoStart': true});
  }
}

class _EscrowGuaranteeRow extends StatelessWidget {
  const _EscrowGuaranteeRow();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.security_rounded, size: 14, color: context.colors.textTertiary),
          SizedBox(width: 6),
          Text(
            'Secured by Paystack · Escrow by HandyTrust',
            style: TextStyle(
              fontSize: 11,
              color: context.colors.textTertiary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      );
}
