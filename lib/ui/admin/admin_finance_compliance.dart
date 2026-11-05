import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/admin_audit_log_model.dart';
import '../../models/finance_record.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart' show jobStreamProvider;
import '../../providers/theme_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../components/ht_kit.dart';
import '../theme/ht_theme.dart';
import 'admin_kit.dart';
import 'admin_people.dart' show payoutFreezeFact;

// ─── Finance (AD-13, read-only per Q-4) ─────────────────────────────────────

class AdminFinanceSection extends ConsumerStatefulWidget {
  const AdminFinanceSection({super.key});
  @override
  ConsumerState<AdminFinanceSection> createState() => _AdminFinanceSectionState();
}

class _AdminFinanceSectionState extends ConsumerState<AdminFinanceSection> {
  FinanceKind _kind = FinanceKind.chargebacks;
  String? _selected;

  HtTone _tone(FinanceRecord r) {
    final s = (r.status ?? '').toLowerCase();
    if (s == 'open' || s == 'failed' || s == 'needs_attention') return HtTone.danger;
    if (s.contains('pending') || s == 'requested' || s == 'executing' || s == 'submitted' || s == 'paystack_resolved') return HtTone.warning;
    if (s == 'closed' || s == 'processed' || s == 'completed' || s == 'success' || s == 'settled') return HtTone.success;
    return HtTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminFinanceProvider(_kind));
    final counts = [for (final k in FinanceKind.values) ref.watch(adminFinanceProvider(k)).asData?.value.length];
    return AdminPage(
      title: 'Finance',
      subtitle: 'Read-only financial records',
      toolbar: AdminFilterBar(
        labels: [for (final k in FinanceKind.values) k.label],
        counts: counts,
        selected: _kind.index,
        onSelected: (i) => setState(() {
          _kind = FinanceKind.values[i];
          _selected = null;
        }),
      ),
      child: async.when(
        loading: () => const HtLoadingView(),
        error: (e, _) => HtCard(child: HtErrorView(message: '${_kind.label} could not be loaded.', onRetry: () => ref.invalidate(adminFinanceProvider(_kind)))),
        data: (list) {
          final sel = _selected == null ? null : list.where((r) => r.id == _selected).firstOrNull;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AdminListDetail(
              detailTitle: sel == null ? '' : '${_kind.label.substring(0, _kind.label.length - 1)} ${sel.id}',
              onClose: () => setState(() => _selected = null),
              detail: sel == null ? null : FinanceDetail(record: sel),
              list: AdminTable<FinanceRecord>(
                items: list,
                selected: (r) => r.id == _selected,
                onTap: (r) => adminIsWide(context) ? setState(() => _selected = r.id) : openAdminDetailPage(context, title: r.id, builder: (_) => FinanceDetail(record: r)),
                empty: HtCard(child: HtEmptyView(icon: Icons.account_balance_outlined, title: 'No ${_kind.label.toLowerCase()} recorded')),
                columns: [
                  AdminCol('Record', (c, r) => adminTwoLine(c, r.id, r.jobId == null ? null : 'Job #${HtFormat.bookingRef(r.jobId!)}'), flex: 4),
                  AdminCol('Status', (c, r) => HtStatusPill(label: FinanceRecord.humanise(r.status), tone: _tone(r), dot: true), flex: 3),
                  AdminCol(_kind == FinanceKind.chargebacks ? 'Outcome' : (_kind == FinanceKind.refunds ? 'Kind' : 'Detail'), (c, r) => adminText(c, FinanceRecord.humanise(switch (_kind) {
                        FinanceKind.chargebacks => r.outcome,
                        FinanceKind.refunds => r.refundKind,
                        FinanceKind.settlements => r.settlementOutcome,
                        FinanceKind.platformLosses => r.recoveryStatus,
                      }), muted: true), flex: 3),
                  AdminCol('Amount', (c, r) => adminText(c, r.amount == null ? '—' : HtFormat.naira(r.amount)), numeric: true),
                  AdminCol('Date', (c, r) => adminText(c, adminDate(r.at), muted: true), numeric: true),
                ],
                mobileRow: (c, r) => Row(children: [
                  Expanded(child: adminTwoLine(c, r.id, '${r.amount == null ? '—' : HtFormat.naira(r.amount)} · ${adminDate(r.at)}')),
                  HtStatusPill(label: FinanceRecord.humanise(r.status), tone: _tone(r)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            const HtInfoBanner(
              icon: Icons.visibility_outlined,
              tone: HtTone.neutral,
              text: 'Read-only. Amounts are shown exactly as recorded (kobo converted to naira). Chargebacks are closed and investigated through server-side processes; those actions are not available here.',
            ),
          ]);
        },
      ),
    );
  }
}

class FinanceDetail extends ConsumerWidget {
  const FinanceDetail({super.key, required this.record});
  final FinanceRecord record;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = record;
    final job = r.jobId == null ? null : ref.watch(jobStreamProvider(r.jobId!)).asData?.value;
    String n(double? v) => v == null ? '—' : HtFormat.naira(v);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      adminFact(context, 'Status', '${FinanceRecord.humanise(r.status)} (${r.status ?? '—'})'),
      if (r.jobId != null) adminFact(context, 'Job', '#${HtFormat.bookingRef(r.jobId!)}'),
      if (r.str('paymentId') != null) adminFact(context, 'Payment', r.str('paymentId')!),
      if (r.str('paystackReference') != null) adminFact(context, 'Paystack reference', r.str('paystackReference')!),
      ...switch (r.kind) {
        FinanceKind.chargebacks => [
            adminFact(context, 'Charged amount', n(r.amount)),
            adminFact(context, 'Payout at open', FinanceRecord.humanise(r.payoutStateAtOpen)),
            if (r.investigationStatus != null) adminFact(context, 'Investigation', FinanceRecord.humanise(r.investigationStatus)),
            if (r.outcome != null) adminFact(context, 'Outcome', FinanceRecord.humanise(r.outcome)),
            adminFact(context, 'Opened', adminDate(r.at)),
            if (r.closedAt != null) adminFact(context, 'Closed', adminDate(r.closedAt)),
          ],
        FinanceKind.refunds => [
            adminFact(context, 'Amount', n(r.amount)),
            adminFact(context, 'Kind', FinanceRecord.humanise(r.refundKind)),
            adminFact(context, 'Attempts', '${r.attempts}'),
            if (r.reason != null) adminFact(context, 'Reason', r.reason!),
            adminFact(context, 'Requested', adminDate(r.at)),
          ],
        FinanceKind.settlements => [
            adminFact(context, 'Outcome', FinanceRecord.humanise(r.settlementOutcome)),
            adminFact(context, 'Service amount', n(r.amount)),
            adminFact(context, 'To artisan', '${n(r.artisanLeg)} · ${FinanceRecord.humanise(r.artisanLegStatus)}'),
            adminFact(context, 'Refund', '${n(r.refundLeg)} · ${FinanceRecord.humanise(r.refundLegStatus)}'),
            adminFact(context, 'Retained', n(r.retained)),
            adminFact(context, 'Created', adminDate(r.at)),
          ],
        FinanceKind.platformLosses => [
            adminFact(context, 'Amount', n(r.amount)),
            adminFact(context, 'Absorbed by', FinanceRecord.humanise(r.absorbedBy)),
            adminFact(context, 'Recovery', FinanceRecord.humanise(r.recoveryStatus)),
            if (r.str('chargebackId') != null) adminFact(context, 'Chargeback', r.str('chargebackId')!),
            adminFact(context, 'Recorded', adminDate(r.at)),
          ],
      },
      if (r.jobId != null) ...[
        adminSection(context, 'Payout freeze'),
        if (job == null) const HtLoadingView() else payoutFreezeFact(context, frozen: job.payoutFrozen, reason: job.payoutFreezeReason),
      ],
    ]);
  }
}

// ─── Audit logs (AD-10) ─────────────────────────────────────────────────────

class AdminAuditLogsSection extends ConsumerStatefulWidget {
  const AdminAuditLogsSection({super.key});
  @override
  ConsumerState<AdminAuditLogsSection> createState() => _AdminAuditLogsSectionState();
}

class _AdminAuditLogsSectionState extends ConsumerState<AdminAuditLogsSection> {
  final _q = TextEditingController();
  int _filter = 0;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  static String actionLabel(AdminAuditLogModel l) {
    final raw = l.actionId.isNotEmpty ? l.actionId : l.action.name;
    final spaced = raw.replaceAll('_', ' ').replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]!.toLowerCase()}');
    return spaced.isEmpty ? '—' : spaced[0].toUpperCase() + spaced.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminAuditLogsProvider);
    return AdminPage(
      title: 'Audit logs',
      subtitle: 'Every admin action, newest first (read-only)',
      child: async.when(
        loading: () => const HtLoadingView(),
        error: (e, _) => HtCard(child: HtErrorView(message: 'The audit log could not be loaded.', onRetry: () => ref.invalidate(adminAuditLogsProvider))),
        data: (logs) {
          final names = ref.watch(adminPeopleNamesProvider(peopleKey(logs.map((l) => l.adminId)))).asData?.value ?? const <String, String>{};
          final filters = <bool Function(AdminAuditLogModel)>[
            (_) => true,
            (l) => l.targetType == 'user' || l.targetType == 'artisan',
            (l) => l.targetType == 'payment' || l.targetType == 'job' && l.actionId.toLowerCase().contains('payout') || l.actionId.toLowerCase().contains('refund') || l.actionId.toLowerCase().contains('chargeback'),
            (l) => l.actionId.toLowerCase().contains('dispute'),
            (l) => l.targetType == 'verification',
          ];
          final q = _q.text.trim().toLowerCase();
          final list = logs.where(filters[_filter]).where((l) => q.isEmpty || l.targetId.toLowerCase().contains(q) || '${l.metadata['reason'] ?? ''}'.toLowerCase().contains(q) || actionLabel(l).toLowerCase().contains(q)).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HtSearchField(controller: _q, hint: 'Search target, action or reason', onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            AdminFilterBar(labels: const ['All actions', 'Users', 'Finance', 'Disputes', 'Verifications'], selected: _filter, onSelected: (i) => setState(() => _filter = i)),
            const SizedBox(height: 12),
            AdminTable<AdminAuditLogModel>(
              items: list,
              empty: const HtCard(child: HtEmptyView(icon: Icons.history_rounded, title: 'No matching entries')),
              columns: [
                AdminCol('Time', (c, l) => adminText(c, adminDateTime(l.timestamp), muted: true), flex: 3),
                AdminCol('Admin', (c, l) => adminText(c, names[l.adminId]?.isNotEmpty ?? false ? names[l.adminId]! : l.adminId), flex: 2),
                AdminCol('Action', (c, l) => adminText(c, actionLabel(l)), flex: 3),
                AdminCol('Target', (c, l) => adminTwoLine(c, l.targetId, l.targetType), flex: 3),
                AdminCol('Reason', (c, l) => adminText(c, '${l.metadata['reason'] ?? '—'}', muted: true), flex: 3),
              ],
              mobileRow: (c, l) => adminTwoLine(c, actionLabel(l), '${adminDateTime(l.timestamp)} · ${l.targetType} ${l.targetId}'),
            ),
          ]);
        },
      ),
    );
  }
}

// ─── Settings (AD-12) ───────────────────────────────────────────────────────

class AdminSettingsSection extends ConsumerWidget {
  const AdminSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final me = ref.watch(currentUserProvider).asData?.value;
    final dark = ref.watch(themeProvider) == ThemeMode.dark;
    return AdminPage(
      title: 'Settings',
      subtitle: 'Your admin account',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminPanel(
            title: 'Admin account',
            child: Row(children: [
              HtAvatar(name: me?.name ?? '', imageUrl: me?.photoUrl, size: 52),
              const SizedBox(width: 12),
              Expanded(child: adminTwoLine(context, me?.name ?? '—', me?.email)),
              // F-3: there is a single admin role; no invented role tiers.
              const HtStatusPill(label: 'Administrator', tone: HtTone.accent),
            ]),
          ),
          const SizedBox(height: 14),
          AdminPanel(
            title: 'Appearance',
            child: HtToggleRow(icon: Icons.dark_mode_outlined, title: 'Dark mode', subtitle: 'Applies to the whole app on this device', value: dark, onChanged: (_) => ref.read(themeProvider.notifier).toggle()),
          ),
          const SizedBox(height: 14),
          AdminPanel(
            title: 'Session',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HtSecondaryButton(label: 'Back to app', icon: Icons.open_in_new_rounded, onPressed: () => context.go('/home')),
              const SizedBox(height: 8),
              HtDangerButton(
                label: 'Sign out',
                icon: Icons.logout_rounded,
                onPressed: () async {
                  final ok = await htConfirm(context, title: 'Sign out?', message: 'You can sign back in at any time.', confirmLabel: 'Sign out');
                  if (ok) await ref.read(authNotifierProvider.notifier).signOut();
                },
              ),
              const SizedBox(height: 8),
              Text('Admin access is granted and removed by the platform owner; it can’t be changed here.', style: HtType.small(p.textMuted)),
            ]),
          ),
        ]),
      ),
    );
  }
}
