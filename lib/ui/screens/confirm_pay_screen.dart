import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/paystack_service.dart';
import '../../core/services/workflow_gate_service.dart';
import '../../models/job_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/paystack_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';
import 'discovery_screen.dart' show ArtisanDiscoveryCard;

/// Confirm & Pay (references 10 dark, 18 light). Amounts are the server's
/// getPaymentBreakdown (policy D1: agreed price + 5 % platform fee). The
/// only payment method is Paystack checkout (card / bank / transfer inside
/// Paystack) — no stored wallet, saved cards or dedicated accounts exist.
/// There is no simulated/demo payment path.
class ConfirmPayScreen extends ConsumerWidget {
  const ConfirmPayScreen({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final jobAsync = ref.watch(jobStreamProvider(jobId));
    return Scaffold(
      backgroundColor: p.background,
      body: HtBackground(
        glow: !p.isDark,
        child: SafeArea(
          child: Column(
            children: [
              HtScreenHeader(
                title: 'Confirm & Pay',
                center: !p.isDark,
                trailing: p.isDark
                    ? const HtStatusPill(label: 'ESCROW', tone: HtTone.success, icon: Icons.lock_outline_rounded)
                    : HtIconCircle(icon: Icons.verified_user_outlined, iconColor: p.accentStrong),
              ),
              Expanded(
                child: jobAsync.when(
                  loading: () => const HtLoadingView(),
                  error: (e, _) => HtErrorView(message: 'This job could not be loaded.', onRetry: () => ref.invalidate(jobStreamProvider(jobId))),
                  data: (job) => job == null
                      ? const HtEmptyView(icon: Icons.search_off_rounded, title: 'Job not found')
                      : _PayBody(job: job),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayBody extends ConsumerStatefulWidget {
  const _PayBody({required this.job});
  final JobModel job;
  @override
  ConsumerState<_PayBody> createState() => _PayBodyState();
}

class _PayBodyState extends ConsumerState<_PayBody> {
  bool _paying = false;
  String? _error;

  Future<void> _pay(PaymentBreakdown breakdown) async {
    final job = widget.job;
    final uid = ref.read(authStateChangesProvider).asData?.value?.uid;
    final email = ref.read(currentUserProvider).asData?.value?.email;
    if (uid == null) return setState(() => _error = 'Please sign in again to pay.');
    if (email == null || email.isEmpty) {
      return setState(() => _error = 'Your account needs an email address before you can pay. Add one in Settings.');
    }
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      // Same sequence as before Stage 8: move the job to paymentPending
      // unless already there (a resumed checkout), then initialize on the
      // server, which charges the frozen agreed price plus the fee.
      if (job.status != JobStatus.paymentPending) {
        await ref.read(escrowNotifierProvider.notifier).initPayment(job.id);
        final init = ref.read(escrowNotifierProvider);
        if (init.hasError) {
          if (mounted) setState(() => _error = 'Payment could not be started: ${init.error}');
          return;
        }
      }
      final payment = await ref.read(paystackServiceProvider).initializeTransaction(
            jobId: job.id,
            payerId: uid,
            artisanId: job.artisanId,
            amountNaira: breakdown.serviceAmount,
            customerEmail: email,
          );
      if (!mounted) return;
      if (payment == null) {
        htSnack(context, 'Payment already received — your funds are in escrow.');
        context.go('/job/${job.id}');
        return;
      }
      final url = payment.authorizationUrl;
      if (url == null || url.isEmpty) {
        setState(() => _error = 'Payment could not be started. Please try again.');
        return;
      }
      context.push('/payment/${job.id}/webview', extra: {'url': url, 'reference': payment.paystackReference});
    } catch (e) {
      if (mounted) setState(() => _error = 'Payment could not be started: $e');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final job = widget.job;
    final uid = ref.watch(authStateChangesProvider).asData?.value?.uid ?? '';
    final canPay = (WorkflowGateService.isReadyForPayment(job) || job.status == JobStatus.paymentPending) && WorkflowGateService.canPay(job, uid);
    final funded = {JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted, JobStatus.completed}.contains(job.status);

    if (funded) {
      return HtEmptyView(
        icon: Icons.lock_rounded,
        title: 'Payment received',
        message: 'Your funds are held in escrow for this job.',
        action: HtSecondaryButton(label: 'View job', onPressed: () => context.go('/job/${job.id}')),
      );
    }
    if (!canPay) {
      return HtEmptyView(
        icon: Icons.handshake_outlined,
        title: 'Not ready for payment yet',
        message: 'Agree the price and schedule with the artisan in chat first.',
        action: HtSecondaryButton(label: 'Open chat', onPressed: () => context.push('/chat/${job.id}')),
      );
    }

    final breakdownAsync = ref.watch(paymentBreakdownProvider(job.id));
    return breakdownAsync.when(
      loading: () => const HtLoadingView(label: 'Calculating your payment…'),
      error: (e, _) => HtErrorView(message: 'Could not load the payment breakdown.', onRetry: () => ref.invalidate(paymentBreakdownProvider(job.id))),
      data: (b) => Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 6, HtSpace.gutter, 20),
              children: [
                if (p.isDark) ...[
                  const HtInfoBanner(
                    icon: Icons.verified_user_outlined,
                    title: 'Escrow Protection Active',
                    text: 'Held in escrow until you approve the completed job',
                    tone: HtTone.success,
                  ),
                  const SizedBox(height: 16),
                ],
                _SummaryCard(job: job, breakdown: b),
                const SizedBox(height: 18),
                _PaymentMethodCard(),
                const SizedBox(height: 18),
                HtInfoBanner(
                  icon: Icons.lock_clock_outlined,
                  title: 'Escrow Release Guarantee',
                  text:
                      'Funds are released to the artisan when you approve the completed job — or automatically 14 days after the artisan submits it, unless you raise a dispute. The artisan cannot claim payment early.',
                  tone: p.isDark ? HtTone.neutral : HtTone.accent,
                ),
                const SizedBox(height: 18),
                HtCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ESCROW LIFECYCLE', style: HtType.caps(p.textSecondary)),
                      const SizedBox(height: 16),
                      const HtLifecycle(
                        current: 0,
                        steps: [
                          HtLifecycleStep('1. Fund Escrow', Icons.lock_outline_rounded),
                          HtLifecycleStep('2. Job Done', Icons.brush_outlined),
                          HtLifecycleStep('3. Release', Icons.verified_outlined),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  HtInfoBanner(icon: Icons.error_outline_rounded, text: _error!, tone: HtTone.danger),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 0, HtSpace.gutter, 18),
            child: HtPrimaryButton(
              label: 'Pay ${HtFormat.naira(b.totalCharged)} Securely',
              leadingIcon: p.isDark ? Icons.shield_outlined : null,
              icon: p.isDark ? null : Icons.arrow_forward_rounded,
              loading: _paying,
              onPressed: _paying ? null : () => _pay(b),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.job, required this.breakdown});
  final JobModel job;
  final PaymentBreakdown breakdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final artisan = job.artisanId.isEmpty ? null : ref.watch(artisanProfileProvider(job.artisanId)).asData?.value;
    final title = job.description.trim().split('\n').first;
    final (whole, kobo) = HtFormat.nairaSplit(breakdown.totalCharged);
    final pct = breakdown.platformFeePercent;
    final pctLabel = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
    return HtCard(
      radius: 30,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: HtStatusPill(
                  label: [job.category, ?job.areaLabel].join(' • '),
                  tone: p.isDark ? HtTone.neutral : HtTone.accent,
                  icon: Icons.format_paint_outlined,
                ),
              ),
              const SizedBox(width: 8),
              HtStatusPill(label: 'Job #${HtFormat.bookingRef(job.id)}', tone: HtTone.neutral),
            ],
          ),
          const SizedBox(height: 12),
          Text(title.isEmpty ? job.category : title, style: HtType.sectionTitle(p.textPrimary).copyWith(fontSize: 20.5), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          if (artisan != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.inner)),
              child: Row(
                children: [
                  HtAvatar(name: artisan.name, imageUrl: artisan.profileImageUrl, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(artisan.displayName, style: HtType.cardTitle(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          artisan.totalRatings > 0
                              ? '★ ${artisan.rating.toStringAsFixed(1)} (${artisan.completedJobs} jobs)'
                              : '${artisan.category ?? 'Artisan'} · ${artisan.completedJobs} jobs',
                          style: HtType.small(p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (ArtisanDiscoveryCard.isIdVerified(artisan)) const HtVerifiedBadge(),
                ],
              ),
            ),
          const SizedBox(height: 18),
          _row(p, 'Agreed service price', HtFormat.naira(breakdown.serviceAmount)),
          const SizedBox(height: 12),
          _row(p, 'Platform fee ($pctLabel%)', HtFormat.naira(breakdown.platformFee)),
          const SizedBox(height: 16),
          Divider(color: p.border, height: 1),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Escrow Deposit', style: HtType.cardTitle(p.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Held securely until you approve the job', style: HtType.small(p.textSecondary)),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(children: [TextSpan(text: whole), TextSpan(text: kobo, style: HtType.small(p.isDark ? p.accent : p.textPrimary))]),
                style: HtType.amount(p.isDark ? p.accent : p.textPrimary, size: 26),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(HtPalette p, String label, String value) => Row(
        children: [
          Expanded(child: Text(label, style: HtType.body(p.textSecondary).copyWith(fontSize: 14))),
          Text(value, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)),
        ],
      );
}

class _PaymentMethodCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return HtCard(
      radius: 30,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.isDark ? 'Payment Method' : 'PAYMENT METHOD', style: p.isDark ? HtType.sectionTitle(p.textPrimary) : HtType.caps(p.textSecondary).copyWith(fontSize: 11)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.isDark ? p.surfaceRaised : p.surface,
              borderRadius: BorderRadius.circular(HtRadius.inner),
              border: Border.all(color: p.isDark ? p.border : p.accentStrong.withValues(alpha: 0.45), width: p.isDark ? 1 : 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: p.isDark ? p.surface : p.surfaceRaised, shape: BoxShape.circle),
                  child: Icon(Icons.credit_card_rounded, color: p.textPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Card, Bank or Transfer', style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 14.5)),
                      Text('Secure Paystack checkout · Mastercard, Visa, Verve', style: HtType.small(p.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: p.isDark ? p.accent : p.accentStrong, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 18, color: p.isDark ? p.onPrimary : Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
