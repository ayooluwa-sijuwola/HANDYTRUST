import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/services/admin_service.dart' show HeldFunds;

import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../components/ht_kit.dart';
import '../theme/ht_theme.dart';

/// Stage 8.2 admin building blocks (HandyTrust design system, light/dark).

const double kAdminWide = 1100; // table + side detail panel
const double kAdminTablet = 720; // table vs stacked cards

String adminError(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? e.code;
  if (e is StateError) return e.message;
  return 'Something went wrong. Please try again.';
}

String adminDate(DateTime? d) => d == null ? '—' : HtFormat.date(d.toLocal());
String adminDateTime(DateTime? d) => d == null ? '—' : HtFormat.dateTime(d.toLocal());

/// Section frame: title + subtitle, optional toolbar, scrolling body.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.title, this.subtitle, required this.child, this.toolbar, this.scroll = true});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? toolbar;
  final bool scroll;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final pad = MediaQuery.of(context).size.width < kAdminTablet ? 14.0 : 24.0;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(pad, 18, pad, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 24)),
        if (subtitle != null) Text(subtitle!, style: HtType.small(p.textSecondary)),
        if (toolbar != null) ...[const SizedBox(height: 12), toolbar!],
      ]),
    );
    if (!scroll) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, Expanded(child: Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, pad), child: child))]);
    return ListView(padding: EdgeInsets.only(bottom: pad), children: [header, Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: child)]);
  }
}

/// Card with a header row.
class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key, required this.title, required this.child, this.trailing, this.subtitle, this.badge, this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16)});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final int? badge;
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return HtCard(
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Flexible(child: Text(title, style: HtType.sectionTitle(p.textPrimary).copyWith(fontSize: 16.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (badge != null) ...[const SizedBox(width: 8), AdminCountBadge(badge!)],
          const Spacer(),
          ?trailing,
        ]),
        if (subtitle != null) Text(subtitle!, style: HtType.small(p.textMuted)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class AdminCountBadge extends StatelessWidget {
  const AdminCountBadge(this.count, {super.key, this.tone = HtTone.accent});
  final int count;
  final HtTone tone;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final (bg, fg) = switch (tone) {
      HtTone.danger => (p.dangerSoft, p.danger),
      HtTone.warning => (p.warningSoft, p.warning),
      _ => (p.accentSoft, p.accentSoftText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(HtRadius.pill)),
      child: Text('$count', style: HtType.smallStrong(fg).copyWith(fontSize: 11.5)),
    );
  }
}

/// KPI tile. [note] states where the figure comes from when it isn't an
/// exact total (e.g. "of the latest 200 jobs").
class AdminStatCard extends StatelessWidget {
  const AdminStatCard({super.key, required this.icon, required this.label, required this.value, this.note, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return HtCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          htIconTile(context, icon, size: 34),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: HtType.smallStrong(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 12),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: HtType.amount(p.textPrimary, size: 26))),
        if (note != null) ...[const SizedBox(height: 2), Text(note!, style: HtType.small(p.textMuted).copyWith(fontSize: 11.5), maxLines: 2, overflow: TextOverflow.ellipsis)],
      ]),
    );
  }
}

/// Wrap of equal-width tiles: [columns] across on wide screens.
class AdminGrid extends StatelessWidget {
  const AdminGrid({super.key, required this.children, this.minTileWidth = 210, this.gap = 14});
  final List<Widget> children;
  final double minTileWidth;
  final double gap;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minTileWidth).floor().clamp(1, 4);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
    });
  }
}

class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({super.key, required this.labels, required this.selected, required this.onSelected, this.counts});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final List<int?>? counts;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < labels.length; i++) ...[
            HtChip(label: labels[i], selected: i == selected, count: counts?[i], onTap: () => onSelected(i)),
            const SizedBox(width: 8),
          ],
        ]),
      );
}

/// Column definition for [AdminTable].
class AdminCol<T> {
  const AdminCol(this.label, this.cell, {this.flex = 2, this.numeric = false});
  final String label;
  final Widget Function(BuildContext, T) cell;
  final int flex;
  final bool numeric;
}

/// Table on tablet/desktop; stacked rows ([mobileRow]) on phones.
class AdminTable<T> extends StatelessWidget {
  const AdminTable({super.key, required this.items, required this.columns, required this.mobileRow, this.onTap, this.selected, this.empty});
  final List<T> items;
  final List<AdminCol<T>> columns;
  final Widget Function(BuildContext, T) mobileRow;
  final ValueChanged<T>? onTap;
  final bool Function(T)? selected;
  final Widget? empty;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    if (items.isEmpty) return empty ?? const HtCard(child: HtEmptyView(icon: Icons.inbox_outlined, title: 'Nothing here yet'));
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < kAdminTablet) {
        return HtCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: p.border),
              InkWell(onTap: onTap == null ? null : () => onTap!(items[i]), child: Padding(padding: const EdgeInsets.all(14), child: mobileRow(context, items[i]))),
            ],
          ]),
        );
      }
      Widget cell(AdminCol<T> col, Widget child) => Expanded(flex: col.flex, child: Align(alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft, child: child));
      return HtCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
            child: Row(children: [for (final col in columns) cell(col, Text(col.label.toUpperCase(), style: HtType.caps(p.textMuted).copyWith(fontSize: 10.5)))]),
          ),
          Divider(height: 1, color: p.border),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            Material(
              color: (selected?.call(items[i]) ?? false) ? p.accentSoft : Colors.transparent,
              child: InkWell(
                onTap: onTap == null ? null : () => onTap!(items[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(children: [for (final col in columns) cell(col, Padding(padding: const EdgeInsets.only(right: 8), child: col.cell(context, items[i])))]),
                ),
              ),
            ),
          ],
        ]),
      );
    });
  }
}

/// Two-line cell: primary text + muted secondary line.
Widget adminTwoLine(BuildContext context, String a, [String? b]) {
  final p = context.ht;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    Text(a, style: HtType.smallStrong(p.textPrimary).copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
    if (b != null && b.isNotEmpty) Text(b, style: HtType.small(p.textMuted).copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
  ]);
}

Widget adminText(BuildContext context, String t, {bool muted = false}) =>
    Text(t, style: HtType.small(muted ? context.ht.textMuted : context.ht.textPrimary).copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis);

/// List + detail: side panel on wide screens; a full page on narrow ones.
class AdminListDetail extends StatelessWidget {
  const AdminListDetail({super.key, required this.list, required this.detail, required this.detailTitle, required this.onClose});
  final Widget list;
  final Widget? detail;
  final String detailTitle;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= kAdminWide;
    if (!wide || detail == null) return list;
    final p = context.ht;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: list),
      const SizedBox(width: 18),
      SizedBox(
        width: 380,
        child: HtCard(
          padding: const EdgeInsets.fromLTRB(18, 10, 10, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(detailTitle, style: HtType.cardTitle(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(tooltip: 'Close', onPressed: onClose, icon: Icon(Icons.close_rounded, color: p.textMuted)),
            ]),
            Padding(padding: const EdgeInsets.only(right: 8), child: detail!),
          ]),
        ),
      ),
    ]);
  }
}

/// On narrow screens a selection opens the detail as a page.
Future<void> openAdminDetailPage(BuildContext context, {required String title, required WidgetBuilder builder}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (ctx) {
      final p = ctx.ht;
      return Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(backgroundColor: p.background, surfaceTintColor: Colors.transparent, foregroundColor: p.textPrimary, title: Text(title, style: HtType.cardTitle(p.textPrimary))),
        body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [HtCard(child: builder(ctx))])),
      );
    },
  ));
}

bool adminIsWide(BuildContext context) => MediaQuery.of(context).size.width >= kAdminWide;

Widget adminSection(BuildContext context, String label) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(label.toUpperCase(), style: HtType.caps(context.ht.textMuted).copyWith(fontSize: 10.5)),
    );

/// Labelled fact row inside detail panels.
Widget adminFact(BuildContext context, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(k, style: HtType.small(context.ht.textSecondary))),
        Expanded(child: Text(v, textAlign: TextAlign.right, style: HtType.smallStrong(context.ht.textPrimary))),
      ]),
    );

// ─── Dialogs (rebuilt; same validation as before) ───────────────────────────

const int kAdminMinReason = 10; // the server enforces the same minimum

class SettlementDecision {
  const SettlementDecision({required this.outcome, required this.reason, this.artisanAmount, this.refundAmount});
  final String outcome;
  final String reason;
  final double? artisanAmount;
  final double? refundAmount;
}

/// Settlement decision for a dispute or paid-cancellation request. Shows
/// what is held in escrow (read for display only; the server re-derives
/// everything). Outcomes and validation match the previous dialog.
Future<SettlementDecision?> showSettlementDialog(
  BuildContext context, {
  required String title,
  required String jobId,
  bool allowDecline = false,
  bool allowRelease = true,
  String initialOutcome = 'release',
  required Future<HeldFunds?> Function(String jobId) loadHeld,
}) async {
  final held = await loadHeld(jobId);
  if (!context.mounted) return null;
  var outcome = initialOutcome;
  final reason = TextEditingController();
  final artisan = TextEditingController();
  final refund = TextEditingController();
  String? error;
  return showDialog<SettlementDecision>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final p = ctx.ht;
      final options = <(String, String, String)>[
        if (allowDecline) ('decline', 'Decline request', 'The job continues; escrow is untouched.'),
        if (allowRelease) ('release', 'Release to artisan', 'The artisan receives the full agreed price.'),
        ('full_refund', 'Full refund to customer', 'The customer gets back everything they paid, including the platform fee.'),
        ('split', 'Split settlement', 'Part to the artisan, part refunded; any remainder is retained and recorded.'),
      ];
      return AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HtRadius.card)),
        title: Text(title, style: HtType.sectionTitle(p.textPrimary)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                held == null
                    ? 'No funds are currently held in escrow for this job.'
                    : 'Held in escrow: ${HtFormat.naira(held.total)} (artisan price ${HtFormat.naira(held.service)}, platform fee ${HtFormat.naira(held.total - held.service)})',
                style: HtType.small(held == null ? p.danger : p.textSecondary),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (v, label, _) in options) HtChip(label: label, selected: outcome == v, onTap: () => setState(() => outcome = v)),
              ]),
              const SizedBox(height: 6),
              Text(options.firstWhere((o) => o.$1 == outcome, orElse: () => options.first).$3, style: HtType.small(p.textMuted)),
              if (outcome == 'split') ...[
                HtTextField(label: 'To artisan (₦)', controller: artisan, keyboard: const TextInputType.numberWithOptions(decimal: true), hint: held == null ? null : 'At most ${HtFormat.naira(held.service)}'),
                HtTextField(label: 'Refund to customer (₦)', controller: refund, keyboard: const TextInputType.numberWithOptions(decimal: true)),
              ],
              HtTextField(label: 'Reason (required)', controller: reason, lines: 3, hint: 'Recorded in the audit log and shown to both parties'),
              if (error != null) ...[const SizedBox(height: 8), Text(error!, style: HtType.small(p.danger))],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: HtType.bodyStrong(p.textSecondary))),
          FilledButton(
            onPressed: held == null && outcome != 'decline'
                ? null
                : () {
                    final r = reason.text.trim();
                    if (r.length < kAdminMinReason) {
                      setState(() => error = 'Please give a reason of at least $kAdminMinReason characters.');
                      return;
                    }
                    double? a;
                    double? f;
                    if (outcome == 'split') {
                      a = double.tryParse(artisan.text.trim());
                      f = double.tryParse(refund.text.trim());
                      if (a == null || f == null || a <= 0 || f <= 0) {
                        setState(() => error = 'Enter both split amounts.');
                        return;
                      }
                    }
                    Navigator.of(ctx).pop(SettlementDecision(outcome: outcome, reason: r, artisanAmount: a, refundAmount: f));
                  },
            child: const Text('Confirm decision'),
          ),
        ],
      );
    }),
  );
}

/// Mandatory reason (≥ 10 characters) before a sensitive action.
Future<String?> showAdminReasonDialog(BuildContext context, {required String title, required String message, String confirmLabel = 'Confirm'}) {
  final ctrl = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final p = ctx.ht;
      return AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HtRadius.card)),
        title: Text(title, style: HtType.sectionTitle(p.textPrimary)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(message, style: HtType.body(p.textSecondary)),
            HtTextField(label: 'Reason (required)', controller: ctrl, lines: 3),
            if (error != null) ...[const SizedBox(height: 6), Text(error!, style: HtType.small(p.danger))],
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.history_rounded, size: 15, color: p.textMuted),
              const SizedBox(width: 6),
              Expanded(child: Text('Recorded in the audit log with your name.', style: HtType.small(p.textMuted))),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: HtType.bodyStrong(p.textSecondary))),
          FilledButton(
            onPressed: () {
              final r = ctrl.text.trim();
              if (r.length < kAdminMinReason) {
                setState(() => error = 'Please give a reason of at least $kAdminMinReason characters.');
                return;
              }
              Navigator.of(ctx).pop(r);
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    }),
  );
}

/// Policy D9 suspension types. fraud / safety / security freeze the
/// artisan's payouts server-side; administrative / verification don't.
const suspensionTypes = <String, String>{
  'administrative': 'Administrative — existing jobs may be completed',
  'verification': 'Verification — existing jobs may be completed',
  'fraud': 'Fraud — freezes all payouts pending review',
  'safety': 'Safety — freezes all payouts pending review',
  'security': 'Security — freezes all payouts pending review',
};

Future<String?> showSuspensionTypeDialog(BuildContext context, {required String userName}) {
  var selected = 'administrative';
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final p = ctx.ht;
      return AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HtRadius.card)),
        title: Text('Suspend $userName?', style: HtType.sectionTitle(p.textPrimary)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('They will be blocked from new marketplace activity. Choose the suspension type:', style: HtType.body(p.textSecondary)),
            const SizedBox(height: 10),
            for (final e in suspensionTypes.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: HtCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  color: selected == e.key ? p.accentSoft : null,
                  onTap: () => setState(() => selected = e.key),
                  child: Row(children: [
                    Icon(selected == e.key ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: selected == e.key ? p.accentStrong : p.textMuted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.value, style: HtType.small(p.textPrimary))),
                  ]),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: HtType.bodyStrong(p.textSecondary))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: p.danger), onPressed: () => Navigator.of(ctx).pop(selected), child: const Text('Suspend')),
        ],
      );
    }),
  );
}

/// Finance error text from an AdminFinanceService call.
String financeError(Object e) => e is FirebaseFunctionsException ? (e.message ?? e.code) : adminError(e);

/// Inline text link in the design system's type (no Material default font).
class AdminLink extends StatelessWidget {
  const AdminLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: HtType.smallStrong(p.accentStrong)),
            Icon(Icons.chevron_right_rounded, size: 16, color: p.accentStrong),
          ]),
        ),
      ),
    );
  }
}
