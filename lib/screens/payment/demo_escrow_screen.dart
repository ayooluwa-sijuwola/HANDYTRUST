import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/demo_payment_provider.dart';
import '../../theme/app_theme.dart';

/// Demo escrow payment screen — three states driven by Firestore streams.
///
/// State priority (highest to lowest):
///   Firestore escrow.status == "success"  → _SuccessView
///   Firestore escrow.status == "processing" || local notifier == processing
///                                         → _ProcessingView
///   otherwise                             → _IdleView
///
/// Pass [autoStart] = true (via GoRouter extra) to skip the idle state and
/// begin the simulation immediately on mount.
class DemoEscrowScreen extends ConsumerStatefulWidget {
  final String jobId;
  final bool autoStart;

  const DemoEscrowScreen({
    super.key,
    required this.jobId,
    this.autoStart = false,
  });

  @override
  ConsumerState<DemoEscrowScreen> createState() => _DemoEscrowScreenState();
}

class _DemoEscrowScreenState extends ConsumerState<DemoEscrowScreen>
    with SingleTickerProviderStateMixin {
  // Success check-mark scale + fade animation
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;
  late final Animation<double> _checkOpacity;

  bool _modalActive = false;

  @override
  void initState() {
    super.initState();

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _checkScale = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );
    _checkOpacity = CurvedAnimation(
      parent: _checkController,
      curve: Curves.easeIn,
    );

    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startPayment());
    }
  }

  @override
  void dispose() {
    _checkController.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _startPayment() async {
    _showPaystackModal();
    final uid = ref.read(authStateChangesProvider).value?.uid ?? '';
    await ref
        .read(demoPaymentNotifierProvider(widget.jobId).notifier)
        .startPayment(uid);
  }

  void _showPaystackModal() {
    if (_modalActive) return;
    _modalActive = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => const _PaystackLoadingDialog(),
    );
    // Auto-dismiss the modal after 2.5 s while processing continues in background
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _modalActive = false;
    });
  }

  void _playSuccessAnimation() {
    if (!_checkController.isAnimating && !_checkController.isCompleted) {
      _checkController.forward();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Defense in depth: payment_screen.dart only navigates here in debug
    // builds, but GoRouter would still resolve a direct/deep link to this
    // path in a release build. A simulated escrow payment must never be
    // reachable in release — that would let a job appear "paid" with no
    // real money having moved.
    if (!kDebugMode) {
      return Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(title: const Text('Payment')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'This payment method is not available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
        ),
      );
    }

    final paymentState = ref.watch(demoPaymentNotifierProvider(widget.jobId));

    // Play animation when notifier reaches success
    ref.listen<DemoPaymentState>(demoPaymentNotifierProvider(widget.jobId), (
      prev,
      next,
    ) {
      if (next.step == DemoPaymentStep.success &&
          prev?.step != DemoPaymentStep.success) {
        _playSuccessAnimation();
      }
    });

    return PopScope(
      // The AppBar's back arrow was already hidden during processing
      // (below) but Android's hardware/gesture back button was not —
      // it could still pop the screen mid-payment. This closes that
      // inconsistency: both the visual affordance and the actual system
      // back gesture are disabled together, only while processing.
      canPop: paymentState.step != DemoPaymentStep.processing,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          title: const Text('Secure Escrow Payment'),
          // Prevent back-navigation while payment is processing
          automaticallyImplyLeading:
              paymentState.step != DemoPaymentStep.processing,
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          // Real-time Firestore stream — no manual refresh required
          stream: FirebaseFirestore.instance
              .collection('jobs')
              .doc(widget.jobId)
              .snapshots(),
          builder: (context, snapshot) {
            // Safe field extraction — handles missing/null sub-maps gracefully
            final data = snapshot.data?.data() ?? <String, dynamic>{};
            final escrow = (data['escrow'] as Map<String, dynamic>?) ?? {};
            final payment = (data['payment'] as Map<String, dynamic>?) ?? {};

            final escrowStatus = escrow['status'] as String?;
            final paymentRef = payment['reference'] as String?;
            final agreedAmount = (data['agreedAmount'] as num?)?.toDouble();

            // Derive display state — Firestore is authoritative; local state
            // provides immediate response before Firestore round-trip completes.
            final firestoreSuccess = escrowStatus == 'success';
            final firestoreProcessing = escrowStatus == 'processing';
            final localProcessing =
                paymentState.step == DemoPaymentStep.processing;
            final localSuccess = paymentState.step == DemoPaymentStep.success;

            if (firestoreSuccess || localSuccess) {
              _playSuccessAnimation(); // ensure animation runs if reopened
              return _SuccessView(
                jobId: widget.jobId,
                reference: paymentRef,
                checkScale: _checkScale,
                checkOpacity: _checkOpacity,
              );
            }

            if (firestoreProcessing || localProcessing) {
              return const _ProcessingView();
            }

            if (paymentState.step == DemoPaymentStep.error) {
              return _ErrorView(
                message: paymentState.error ?? 'An unexpected error occurred.',
                onRetry: () => ref
                    .read(demoPaymentNotifierProvider(widget.jobId).notifier)
                    .reset(),
              );
            }

            return _IdleView(agreedAmount: agreedAmount, onPay: _startPayment);
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE 1 — IDLE
// ═══════════════════════════════════════════════════════════════════════════════

class _IdleView extends StatelessWidget {
  final double? agreedAmount;
  final VoidCallback onPay;

  const _IdleView({required this.agreedAmount, required this.onPay});

  @override
  Widget build(BuildContext context) {
    final fee = (agreedAmount ?? 0) * 0.05;
    final total = (agreedAmount ?? 0) + fee;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EscrowBadge(),
          const SizedBox(height: 28),
          if (agreedAmount != null) ...[
            _AmountCard(amount: agreedAmount!, fee: fee, total: total),
            const SizedBox(height: 24),
          ],
          _SecurityChip(),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: onPay,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.primary,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 20),
                SizedBox(width: 10),
                Text(
                  'Pay into Escrow',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Funds are held safely and released only when you confirm the work is complete.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textTertiary,
              fontFamily: 'Inter',
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE 2 — PROCESSING
// ═══════════════════════════════════════════════════════════════════════════════

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  color: context.colors.primary,
                  strokeWidth: 4,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Securing payment in escrow...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Please wait — do not close this screen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            const _PulseDots(),
          ],
        ),
      ),
    );
  }
}

/// Three pulsing dots to add visual life to the processing state.
class _PulseDots extends StatefulWidget {
  const _PulseDots();

  @override
  State<_PulseDots> createState() => _PulseDotsState();
}

class _PulseDotsState extends State<_PulseDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) {
            // Stagger each dot by 150 ms offset
            final phase = (_ctrl.value + i * 0.33).clamp(0.0, 1.0);
            final opacity = (0.3 + phase * 0.7).clamp(0.3, 1.0);
            return Opacity(
              opacity: opacity,
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE 3 — SUCCESS
// ═══════════════════════════════════════════════════════════════════════════════

class _SuccessView extends StatelessWidget {
  final String jobId;
  final String? reference;
  final Animation<double> checkScale;
  final Animation<double> checkOpacity;

  const _SuccessView({
    required this.jobId,
    required this.reference,
    required this.checkScale,
    required this.checkOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Animated check icon
          Center(
            child: ScaleTransition(
              scale: checkScale,
              child: FadeTransition(
                opacity: checkOpacity,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: context.colors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 72,
                    color: context.colors.accent,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Payment Successful',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Funds secured in escrow',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 32),

          // Transaction reference card
          if (reference != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: context.colors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transaction Reference',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textTertiary,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          reference!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                            fontFamily: 'Inter',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Escrow guarantee notice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.colors.accent.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_rounded,
                  color: context.colors.accent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Funds will only be released to the artisan after you confirm the work is complete.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.accent.withValues(alpha: 0.9),
                      fontFamily: 'Inter',
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          FilledButton(
            onPressed: () => context.go('/job/$jobId'),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.primary,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'View Job',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ERROR STATE
// ═══════════════════════════════════════════════════════════════════════════════

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: context.colors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Payment Failed',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.primary,
                minimumSize: const Size(200, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED IDLE-STATE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _EscrowBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.colors.primary.withValues(alpha: 0.08),
            context.colors.accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.security_rounded,
              color: context.colors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HandyTrust Escrow',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your payment is 100% protected.\nReleased only on your approval.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  final double amount;
  final double fee;
  final double total;

  const _AmountCard({
    required this.amount,
    required this.fee,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        children: [
          _row(context, 'Service amount', '₦${amount.toStringAsFixed(0)}'),
          const SizedBox(height: 8),
          _row(context, 'Platform fee (5%)', '₦${fee.toStringAsFixed(0)}'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _row(
            context,
            'Total charged',
            '₦${total.toStringAsFixed(0)}',
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: bold
              ? context.colors.textPrimary
              : context.colors.textSecondary,
          fontFamily: 'Inter',
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontFamily: 'Inter',
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: context.colors.textPrimary,
        ),
      ),
    ],
  );
}

class _SecurityChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 14,
              color: context.colors.textSecondary,
            ),
            SizedBox(width: 6),
            Text(
              '256-bit Encryption  ·  Zero-fee Escrow',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FAKE PAYSTACK LOADING DIALOG (optional "wow factor")
// ═══════════════════════════════════════════════════════════════════════════════

class _PaystackLoadingDialog extends StatefulWidget {
  const _PaystackLoadingDialog();

  @override
  State<_PaystackLoadingDialog> createState() => _PaystackLoadingDialogState();
}

class _PaystackLoadingDialogState extends State<_PaystackLoadingDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bar;
  late final Animation<double> _progress;

  static const _payColor = Color(0xFF00C3F7); // Paystack cyan

  @override
  void initState() {
    super.initState();
    _bar = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    _progress = CurvedAnimation(parent: _bar, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Paystack-style branded header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22),
            color: _payColor,
            child: Column(
              children: [
                const Text(
                  'Paystack',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Secure Payment Gateway',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
            child: Column(
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: _payColor,
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Initialising secure channel...',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 18),
                AnimatedBuilder(
                  animation: _progress,
                  builder: (_, child) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress.value,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(_payColor),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Verifying transaction security...',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
