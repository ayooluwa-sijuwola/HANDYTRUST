import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/services/paystack_service.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';

class PaymentWebviewScreen extends ConsumerStatefulWidget {
  final String jobId;
  final String url;
  final String reference;

  const PaymentWebviewScreen({
    super.key,
    required this.jobId,
    required this.url,
    required this.reference,
  });

  @override
  ConsumerState<PaymentWebviewScreen> createState() =>
      _PaymentWebviewScreenState();
}

class _PaymentWebviewScreenState extends ConsumerState<PaymentWebviewScreen> {
  late final WebViewController _wvc;
  bool _verifying = false;
  // null while on the webview/verifying; true/false once verification
  // resolves — drives a polished result screen instead of a transient
  // SnackBar. Purely presentational: verifyTransaction's call and outcome
  // are unchanged, this only changes how the same outcome is shown.
  bool? _verified;

  @override
  void initState() {
    super.initState();
    _wvc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          // Paystack redirects to callback URL on success/failure
          if (req.url.contains('callback') ||
              req.url.contains('handytrust') ||
              req.url.contains('paystack.co/close')) {
            _onPaymentCallback();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _onPaymentCallback() async {
    if (_verifying) return;
    setState(() => _verifying = true);

    // Previously: any exception from verification (network error, function
    // not deployed, a genuine fraud/decline response) was caught and
    // silently treated as `verified = true` — meaning a failed or
    // unverifiable payment would still lock escrow. That fallback is
    // removed: a verification failure must now surface as a failure, not
    // be treated as a successful payment.
    bool verified;
    try {
      final svc = PaystackService(FirebaseFunctions.instance);
      // verifyPayment locks escrow server-side on success — this screen
      // must NOT also call EscrowNotifier.lockEscrow, or the redundant
      // second transition fails against the job's state machine.
      verified = await svc.verifyTransaction(
        reference: widget.reference,
        jobId: widget.jobId,
      );
    } catch (e) {
      debugPrint('[PaymentWebview] verifyTransaction failed: $e');
      if (mounted) {
        setState(() => _verifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not verify your payment: $e')),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _verifying = false;
      _verified = verified;
    });
  }

  void _continueAfterSuccess() => context.go('/job/${widget.jobId}');

  void _retryAfterFailure() => context.pop();

  @override
  Widget build(BuildContext context) {
    if (_verified != null) {
      return _PaymentResultView(
        success: _verified!,
        onContinue: _verified! ? _continueAfterSuccess : _retryAfterFailure,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Payment'),
        actions: [
          if (_verifying)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _wvc),
          if (_verifying)
            Container(
              color: Colors.black45,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: context.colors.accent),
                    const SizedBox(height: 16),
                    const Text(
                      'Verifying payment…',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Polished result screen for both outcomes — Task 3's "Payment successful"
/// / "Payment failed" states. Replaces the previous SnackBar-and-navigate
/// pattern; the actual verified/not-verified outcome above is untouched.
class _PaymentResultView extends StatelessWidget {
  final bool success;
  final VoidCallback onContinue;

  const _PaymentResultView({required this.success, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: success ? context.colors.primarySurface : context.colors.errorSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  success ? Icons.check_rounded : Icons.close_rounded,
                  size: 48,
                  color: success ? context.colors.primary : context.colors.error,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                success ? 'Payment Successful' : 'Payment Not Completed',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                success
                    ? 'Your funds are locked in escrow. The artisan will begin work shortly — you\'ll release payment once you confirm the job is done.'
                    : 'We couldn\'t confirm this payment with Paystack. No funds were moved — you can try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              CommitButton(
                label: success ? 'View Job' : 'Try Again',
                onPressed: onContinue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
