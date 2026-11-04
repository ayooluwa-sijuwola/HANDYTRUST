import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/services/workflow_gate_service.dart';
import '../../models/payment_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/payment_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/balance_card.dart';
import '../../widgets/earnings_summary_card.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/shimmer_loaders.dart';
import '../../widgets/transaction_card.dart';
import '../../widgets/web_content_wrapper.dart';

/// Minimal, real Wallet/Earnings screen — built against the *existing*
/// single-payment data model (PaymentModel/payments collection). MVP
/// simple-wallet model per the settled product decision: no milestone
/// payments, no invented "available balance" distinct from what's
/// actually been released (payout is automatic — see
/// design/STITCH_WALLET_AUDIT.md).
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.asData?.value;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isArtisanMode = user.isArtisan && user.activeRole == 'artisan';
    return isArtisanMode ? _ArtisanEarningsView(uid: user.uid) : _CustomerWalletView(uid: user.uid);
  }
}

final _fmt = NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);

// ─── Customer Wallet ────────────────────────────────────────────────────────

class _CustomerWalletView extends ConsumerWidget {
  final String uid;
  const _CustomerWalletView({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(customerPaymentsProvider(uid));

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: WebContentWrapper(child: paymentsAsync.when(
          loading: () => const _WalletLoadingSkeleton(),
          error: (e, _) => _WalletErrorState(message: '$e'),
          data: (payments) {
            if (payments.isEmpty) {
              return CustomScrollView(slivers: [
                const SliverToBoxAdapter(child: _PageHeader('Wallet')),
                SliverToBoxAdapter(
                  child: _WalletEmptyState(
                    title: 'No transactions yet',
                    subtitle: 'Post a job to get started.',
                  ),
                ),
              ]);
            }

            final active = payments
                .where((p) => p.status == PaymentStatus.pending ||
                    p.status == PaymentStatus.processing ||
                    p.status == PaymentStatus.escrowHeld)
                .toList();
            final completed = payments.where((p) => p.status == PaymentStatus.released).toList();
            final other = payments
                .where((p) => p.status == PaymentStatus.refunded || p.status == PaymentStatus.failed)
                .toList();

            final inEscrow = payments
                .where((p) => p.status == PaymentStatus.escrowHeld)
                .fold<double>(0, (sum, p) => sum + p.amount);
            // Customer view: what was actually charged (incl. platform fee).
            final totalSpent = payments.fold<double>(0, (sum, p) => sum + p.chargedTotal);

            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _PageHeader('Wallet')),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: BalanceCard(stats: [
                      BalanceStat(
                        label: 'In Escrow',
                        value: _fmt.format(inEscrow),
                        valueColor: context.colors.escrowLocked,
                      ),
                      BalanceStat(
                        label: 'Total Spent',
                        value: _fmt.format(totalSpent),
                        valueColor: context.colors.textPrimary,
                      ),
                    ]),
                  ),
                ),
                _TransactionSection(
                  title: 'Active Escrow',
                  payments: active,
                  isArtisan: false,
                ),
                _TransactionSection(
                  title: 'Completed',
                  payments: completed,
                  isArtisan: false,
                ),
                if (other.isNotEmpty)
                  _TransactionSection(title: 'Other', payments: other, isArtisan: false),
                SliverToBoxAdapter(
                  child: SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
                ),
              ],
            );
          },
        )),
      ),
    );
  }
}

// ─── Artisan Earnings ───────────────────────────────────────────────────────

class _ArtisanEarningsView extends ConsumerWidget {
  final String uid;
  const _ArtisanEarningsView({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(artisanPaymentsProvider(uid));
    final payoutReadyAsync = ref.watch(artisanPayoutReadyProvider(uid));

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: WebContentWrapper(child: paymentsAsync.when(
          loading: () => const _WalletLoadingSkeleton(),
          error: (e, _) => _WalletErrorState(message: '$e'),
          data: (payments) {
            if (payments.isEmpty) {
              return CustomScrollView(slivers: [
                const SliverToBoxAdapter(child: _PageHeader('Earnings')),
                SliverToBoxAdapter(child: _PayoutReadinessBanner(payoutReadyAsync: payoutReadyAsync)),
                SliverToBoxAdapter(
                  child: _WalletEmptyState(
                    title: 'No earnings yet',
                    subtitle: 'Complete your first job to see payouts here.',
                  ),
                ),
              ]);
            }

            final pendingEscrow = payments
                .where((p) => p.status == PaymentStatus.pending ||
                    p.status == PaymentStatus.processing ||
                    p.status == PaymentStatus.escrowHeld)
                .toList();
            final released = payments.where((p) => p.status == PaymentStatus.released).toList();
            final other = payments
                .where((p) => p.status == PaymentStatus.refunded || p.status == PaymentStatus.failed)
                .toList();

            final pendingTotal = pendingEscrow.fold<double>(0, (sum, p) => sum + p.amount);
            final releasedTotal = released.fold<double>(0, (sum, p) => sum + p.amount);

            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _PageHeader('Earnings')),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: EarningsSummaryCard(
                      totalFormatted: _fmt.format(pendingTotal + releasedTotal),
                      pendingEscrowFormatted: _fmt.format(pendingTotal),
                      releasedFormatted: _fmt.format(releasedTotal),
                      pendingColor: context.colors.escrowPending,
                      releasedColor: context.colors.escrowReleased,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _PayoutReadinessBanner(payoutReadyAsync: payoutReadyAsync)),
                _TransactionSection(
                  title: 'Pending Escrow',
                  payments: pendingEscrow,
                  isArtisan: true,
                ),
                _TransactionSection(
                  title: 'Released',
                  payments: released,
                  isArtisan: true,
                ),
                if (other.isNotEmpty)
                  _TransactionSection(title: 'Other', payments: other, isArtisan: true),
                SliverToBoxAdapter(
                  child: SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
                ),
              ],
            );
          },
        )),
      ),
    );
  }
}

/// Payout is fully automatic (processEscrowRelease fires the moment escrow
/// releases and transfers straight to the artisan's bank account) — there
/// is no "Withdraw" action to build. What's real and worth surfacing is
/// whether payout is actually *set up* to succeed, so an artisan finds out
/// before finishing a job rather than from a failed transfer after.
class _PayoutReadinessBanner extends StatelessWidget {
  final AsyncValue<bool> payoutReadyAsync;
  const _PayoutReadinessBanner({required this.payoutReadyAsync});

  @override
  Widget build(BuildContext context) {
    return payoutReadyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (ready) {
        if (ready) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 15, color: context.colors.primary),
                const SizedBox(width: 6),
                Text(
                  'Payouts are automatic — sent to your bank as soon as a job releases.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: GestureDetector(
            onTap: () => context.push('/bank-details'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.colors.warningSurface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_outlined, size: 16, color: context.colors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Complete payout setup so releases can reach your bank account.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.colors.warning,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 12, color: context.colors.warning),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Shared section/row rendering ──────────────────────────────────────────

class _TransactionSection extends StatelessWidget {
  final String title;
  final List<PaymentModel> payments;
  final bool isArtisan;

  const _TransactionSection({required this.title, required this.payments, required this.isArtisan});

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      sliver: SliverMainAxisGroup(slivers: [
        SliverToBoxAdapter(
          child: Text(
            '$title (${payments.length})',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 10),
          sliver: SliverList.separated(
            itemCount: payments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _TransactionRow(payment: payments[i], isArtisan: isArtisan),
          ),
        ),
      ]),
    );
  }
}

class _TransactionRow extends ConsumerWidget {
  final PaymentModel payment;
  final bool isArtisan;

  const _TransactionRow({required this.payment, required this.isArtisan});

  (String, Color) _statusMeta(BuildContext context) {
    switch (payment.status) {
      case PaymentStatus.escrowHeld:
        return ('In Escrow', context.colors.escrowLocked);
      case PaymentStatus.pending:
      case PaymentStatus.processing:
        return ('Pending', context.colors.escrowPending);
      case PaymentStatus.released:
        return ('Released', context.colors.escrowReleased);
      case PaymentStatus.refunded:
        return ('Refunded', context.colors.textTertiary);
      case PaymentStatus.failed:
        return ('Failed', context.colors.escrowFailed);
      // Stage 3 server-only statuses.
      case PaymentStatus.abandoned:
        return ('Expired', context.colors.textTertiary);
      case PaymentStatus.requiresRefund:
        return ('Refund Pending', context.colors.escrowPending);
      // Stage 4 in-flight money states.
      case PaymentStatus.releasing:
        return ('Payout Processing', context.colors.escrowPending);
      case PaymentStatus.refundPending:
        return ('Refund Processing', context.colors.escrowPending);
      case PaymentStatus.settling:
        return ('Settlement Processing', context.colors.escrowPending);
      case PaymentStatus.settled:
        return ('Settled', context.colors.escrowReleased);
      // Stage 7.1 (F-1).
      case PaymentStatus.chargedBack:
        return ('Charged Back', context.colors.escrowFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (statusLabel, statusColor) = _statusMeta(context);
    // Related job + current workflow stage — both from data this screen
    // already has access to (jobStreamProvider, WorkflowGateService), not
    // new wallet functionality. Job may still be loading/gone; the row
    // degrades gracefully to payment-only info if so.
    final job = ref.watch(jobStreamProvider(payment.jobId)).asData?.value;
    final phase =
        job != null ? WorkflowGateService.describeStep(job, viewerIsCustomer: !isArtisan).phase : null;

    return TransactionCard(
      jobTitle: job?.category ?? 'Job',
      amountFormatted: _fmt.format(payment.amount),
      dateFormatted: DateFormat('d MMM yyyy').format(payment.createdAt),
      statusLabel: statusLabel,
      statusColor: statusColor,
      phase: phase,
      onTap: () => context.push('/job/${payment.jobId}'),
    );
  }
}

// ─── Shared chrome ──────────────────────────────────────────────────────────

/// "HandyTrust" wordmark + bell — pixel-matched to Stitch's Wallet header
/// (same pattern Home's header uses; [title] ("Wallet"/"Earnings") is kept
/// as a screen-reader-only distinction point but not shown as a separate
/// big headline the way My Bookings' header is, since Stitch's Wallet
/// reference doesn't have one.
///
/// WalletScreen is both a bottom-nav tab (MainShellScreen, nothing to
/// pop — no back arrow) and reachable as the standalone /wallet route
/// (something to pop — needs one). No AppBar here to get that
/// automatically the way most other screens do (AppBar's own
/// automaticallyImplyLeading already defaults to exactly this canPop
/// check), so it's replicated explicitly.
class _PageHeader extends StatelessWidget {
  final String title;
  const _PageHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 8 : 20, 16, 20, 4),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.arrow_back_rounded, color: context.colors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            )
          else
            const Icon(Icons.handyman_rounded, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'HandyTrust',
              semanticsLabel: title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFamily: 'Inter',
                color: context.colors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const NotificationBell(),
        ],
      ),
    );
  }
}

class _WalletEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _WalletEmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 48, color: context.colors.textTertiary),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletLoadingSkeleton extends StatelessWidget {
  const _WalletLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          AppShimmer(child: HomeHeaderSkeleton()),
        ],
      ),
    );
  }
}

class _WalletErrorState extends StatelessWidget {
  final String message;

  const _WalletErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: context.colors.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary, fontFamily: 'Inter'),
            ),
          ],
        ),
      ),
    );
  }
}
