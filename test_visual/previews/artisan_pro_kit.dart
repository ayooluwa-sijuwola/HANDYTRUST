// HandyTrust Pro — artisan-specific PREVIEW components (Stage 8.1 revision).
//
// Purpose-built for artisans, not customer layouts with new labels: a docked
// work bar, an availability header, an action queue with real deadlines, a
// work pipeline, work-order tickets, a 6-step work-order stepper, the 8-step
// progress meter (JobProgressStage), countdown rings and an earnings ledger.
// Built only from HtPalette / HtType tokens so it stays coherent with the
// customer app. Preview-only; promoted to lib/ui/artisan/components/ in
// Phase C. All content rendered with it is SAMPLE DATA.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:handy_trust/ui/components/ht_components.dart';
import 'package:handy_trust/ui/theme/ht_theme.dart';

import 'preview_kit.dart';

// ─── Navigation ─────────────────────────────────────────────────────────────

/// Docked artisan work bar: full-width, top indicator + filled icon on the
/// active tab (customer app uses a floating pill). Order approved in D-2.
class ProNavBar extends StatelessWidget {
  const ProNavBar({super.key, required this.current});
  final int current;
  static const items = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Home'),
    (Icons.travel_explore_outlined, Icons.travel_explore_rounded, 'Find Work'),
    (Icons.assignment_outlined, Icons.assignment_rounded, 'My Jobs'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Earnings'),
    (Icons.badge_outlined, Icons.badge_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final active = p.isDark ? p.accent : p.accentStrong;
    return Container(
      decoration: BoxDecoration(
        color: p.isDark ? p.backgroundDeep : p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: 64,
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Column(children: [
                Container(height: 3, width: 28, decoration: BoxDecoration(color: i == current ? active : Colors.transparent, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)))),
                const Spacer(),
                Icon(i == current ? items[i].$2 : items[i].$1, size: 23, color: i == current ? active : p.textMuted),
                const SizedBox(height: 3),
                Text(items[i].$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: HtType.smallStrong(i == current ? p.textPrimary : p.textMuted).copyWith(fontSize: 10.5)),
                const Spacer(),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Artisan header: avatar with availability ring, name, availability chip,
/// messages + notifications actions with badges.
class ProHeader extends StatelessWidget {
  const ProHeader({super.key, required this.name, required this.trade, this.available = true, this.messages = 0, this.alerts = 0, this.title});
  final String name;
  final String trade;
  final bool available;
  final int messages;
  final int alerts;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final ring = available ? p.success : p.textMuted;
    Widget action(IconData i, int n, String tip) => Stack(clipBehavior: Clip.none, children: [
          HtIconCircle(icon: i, tooltip: tip, square: true),
          if (n > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(HtRadius.pill), border: Border.all(color: p.background, width: 1.5)),
                child: Text('$n', style: HtType.smallStrong(Colors.white).copyWith(fontSize: 10)),
              ),
            ),
        ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 8, HtSpace.gutter, 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2.5)),
          child: HtAvatar(name: name, size: 40),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title ?? name, style: HtType.cardTitle(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: ring, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(child: Text(available ? 'Available · $trade' : 'Not accepting jobs · $trade', style: HtType.small(p.textSecondary).copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ]),
        ),
        action(Icons.forum_outlined, messages, 'Messages'),
        const SizedBox(width: 10),
        action(Icons.notifications_none_rounded, alerts, 'Notifications'),
      ]),
    );
  }
}

/// Section title in the Pro language: caps label + optional count + link.
Widget proSection(BuildContext context, String label, {String? trailing, int? count}) {
  final p = context.ht;
  return Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Row(children: [
      Text(label.toUpperCase(), style: HtType.caps(p.textSecondary).copyWith(fontSize: 11.5, letterSpacing: 1.3)),
      if (count != null) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(color: p.isDark ? p.accent : p.accentStrong, borderRadius: BorderRadius.circular(HtRadius.pill)),
          child: Text('$count', style: HtType.smallStrong(p.isDark ? p.onPrimary : Colors.white).copyWith(fontSize: 11)),
        ),
      ],
      const Spacer(),
      if (trailing != null) Text(trailing, style: HtType.smallStrong(p.accent).copyWith(fontSize: 12)),
    ]),
  );
}

// ─── Dashboard pieces ───────────────────────────────────────────────────────

/// Action-queue card: coloured rail, icon, title, context, deadline chip,
/// one primary action. Deadlines come from real job fields.
class ProActionCard extends StatelessWidget {
  const ProActionCard({super.key, required this.tone, required this.icon, required this.title, required this.subtitle, this.deadline, required this.action});
  final HtTone tone;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? deadline;
  final String action;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final c = switch (tone) { HtTone.danger => p.danger, HtTone.warning => p.warning, HtTone.success => p.success, _ => p.isDark ? p.accent : p.accentStrong };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.tile + 2), border: Border.all(color: p.border), boxShadow: p.cardShadow),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: c),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(children: [
                Icon(icon, color: c, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)),
                    Text(subtitle, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (deadline != null) ...[
                      const SizedBox(height: 5),
                      Row(children: [Icon(Icons.schedule_rounded, size: 13, color: c), const SizedBox(width: 4), Text(deadline!, style: HtType.smallStrong(c).copyWith(fontSize: 11.5))]),
                    ],
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(HtRadius.pill)),
                  child: Text(action, style: HtType.smallStrong(c)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Work pipeline: stage counters in one strip.
class ProPipeline extends StatelessWidget {
  const ProPipeline({super.key, required this.stages, this.selected});
  final List<(String, int)> stages;
  final int? selected;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border), boxShadow: p.cardShadow),
      child: Row(children: [
        for (var i = 0; i < stages.length; i++) ...[
          if (i > 0) Container(width: 1, height: 34, color: p.border),
          Expanded(
            child: Column(children: [
              Text('${stages[i].$2}', style: HtType.amount(i == selected ? (p.isDark ? p.accent : p.accentStrong) : p.textPrimary, size: 20)),
              const SizedBox(height: 2),
              Text(stages[i].$1, textAlign: TextAlign.center, maxLines: 2, style: HtType.small(p.textSecondary).copyWith(fontSize: 10.5, height: 1.15)),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Circular countdown (booking response window, review window).
class ProCountdownRing extends StatelessWidget {
  const ProCountdownRing({super.key, required this.fraction, required this.big, required this.small, this.size = 96, this.tone = HtTone.warning});
  final double fraction;
  final String big;
  final String small;
  final double size;
  final HtTone tone;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final c = switch (tone) { HtTone.danger => p.danger, HtTone.success => p.success, HtTone.accent => p.isDark ? p.accent : p.accentStrong, _ => p.warning };
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(fraction, c, p.surfaceRaised),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(big, style: HtType.amount(p.textPrimary, size: size * 0.24)),
            Text(small, style: HtType.small(p.textSecondary).copyWith(fontSize: 10.5)),
          ]),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f, this.c, this.bg);
  final double f;
  final Color c;
  final Color bg;
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(5, 5, s.width - 10, s.height - 10);
    final base = Paint()..color = bg..style = PaintingStyle.stroke..strokeWidth = 8;
    final fg = Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * f, false, fg);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Work-order ticket: date block, job, customer, stage chip, deadline,
/// stage-specific action.
class ProTicket extends StatelessWidget {
  const ProTicket({super.key, required this.day, required this.month, required this.title, required this.meta, required this.stage, required this.stageTone, this.deadline, this.amount, this.action, this.icon = Icons.plumbing_rounded, this.compact = false});
  final String day;
  final String month;
  final String title;
  final String meta;
  final String stage;
  final HtTone stageTone;
  final String? deadline;
  final String? amount;
  final String? action;
  final IconData icon;
  /// Board-column variant: no date block (date inline), two-line title.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    if (compact) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.tile + 2), border: Border.all(color: p.border), boxShadow: p.cardShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${month.toUpperCase()} $day'.trim(), style: HtType.caps(p.isDark ? p.accent : p.accentStrong).copyWith(fontSize: 10)),
          const SizedBox(height: 4),
          Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(meta, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          HtStatusPill(label: stage, tone: stageTone, dot: true),
          if (deadline != null) ...[
            const SizedBox(height: 6),
            Row(children: [Icon(Icons.schedule_rounded, size: 13, color: p.textSecondary), const SizedBox(width: 3), Flexible(child: Text(deadline!, style: HtType.smallStrong(p.textSecondary).copyWith(fontSize: 11.5)))]),
          ],
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border), boxShadow: p.cardShadow),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: p.isDark ? p.backgroundDeep : p.accentSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
              child: Column(children: [
                Text(month.toUpperCase(), style: HtType.caps(p.isDark ? p.accent : p.accentStrong).copyWith(fontSize: 9.5)),
                Text(day, style: HtType.amount(p.textPrimary, size: 21)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, size: 15, color: p.textMuted),
                  const SizedBox(width: 5),
                  Expanded(child: Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (amount != null) Text(amount!, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)),
                ]),
                const SizedBox(height: 2),
                Text(meta, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  HtStatusPill(label: stage, tone: stageTone, dot: true),
                  if (deadline != null)
                    Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.schedule_rounded, size: 13, color: p.textSecondary), const SizedBox(width: 3), Text(deadline!, style: HtType.smallStrong(p.textSecondary).copyWith(fontSize: 11.5))]),
                ]),
              ]),
            ),
          ]),
        ),
        if (action != null)
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border, style: BorderStyle.solid))),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 18, color: p.textSecondary),
              const SizedBox(width: 6),
              Text('Chat', style: HtType.smallStrong(p.textSecondary)),
              const Spacer(),
              Text(action!, style: HtType.bodyStrong(p.isDark ? p.accent : p.accentStrong).copyWith(fontSize: 13.5)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded, size: 17, color: p.isDark ? p.accent : p.accentStrong),
            ]),
          ),
      ]),
    );
  }
}

/// Work-order stepper: Booked · Agreed · Scheduled · Working · Submitted · Paid.
class ProWorkStepper extends StatelessWidget {
  const ProWorkStepper({super.key, required this.current});
  final int current;
  static const labels = ['Booked', 'Agreed', 'Scheduled', 'Working', 'Submitted', 'Paid'];
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final a = p.isDark ? p.accent : p.accentStrong;
    return Column(children: [
      Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: i < current ? a : (i == current ? a.withValues(alpha: 0.45) : p.surfaceRaised),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(labels[i],
                  maxLines: 1,
                  style: HtType.small(i == current ? p.textPrimary : p.textMuted).copyWith(fontSize: 10.5, fontWeight: i == current ? FontWeight.w700 : FontWeight.w400)),
            ),
          ),
      ]),
    ]);
  }
}

/// 8-step progress meter over JobProgressStage.
class ProProgressMeter extends StatelessWidget {
  const ProProgressMeter({super.key, required this.index});
  final int index;
  static const labels = ['Accepted', 'On the way', 'Work started', '25% done', '50% done', '75% done', 'Almost finished', 'Completed'];
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final a = htChartColors(p).first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(labels[index], style: HtType.bodyStrong(p.textPrimary)),
        const Spacer(),
        Text('Step ${index + 1} of 8', style: HtType.small(p.textSecondary)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        for (var i = 0; i < 8; i++)
          Expanded(
            child: Container(
              height: 12,
              margin: EdgeInsets.only(right: i < 7 ? 3 : 0),
              decoration: BoxDecoration(color: i <= index ? a : p.surfaceRaised, borderRadius: BorderRadius.circular(3)),
            ),
          ),
      ]),
    ]);
  }
}

/// Compact pro stat: big number, label, optional sub-line; left aligned.
class ProStat extends StatelessWidget {
  const ProStat({super.key, required this.value, required this.label, this.sub, this.icon});
  final String value;
  final String label;
  final String? sub;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.tile + 2), border: Border.all(color: p.border), boxShadow: p.cardShadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: p.textMuted), const SizedBox(width: 6)],
          Expanded(child: Text(label, style: HtType.smallStrong(p.textSecondary).copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 6),
        Text(value, style: HtType.amount(p.textPrimary, size: 21), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (sub != null) Text(sub!, style: HtType.small(p.textMuted).copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// Monthly released-payout bars (single hue, direct labels).
class ProMonthBars extends StatelessWidget {
  const ProMonthBars({super.key, required this.months, required this.values, required this.labels});
  final List<String> months;
  final List<double> values;
  final List<String> labels;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final c = htChartColors(p).first;
    final max = values.reduce(math.max);
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(labels[i], style: HtType.smallStrong(p.textSecondary).copyWith(fontSize: 10)),
              const SizedBox(height: 4),
              Container(
                height: 96 * values[i] / max,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(color: i == values.length - 1 ? c : c.withValues(alpha: 0.55), borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
              ),
              const SizedBox(height: 6),
              Text(months[i], style: HtType.small(p.textMuted).copyWith(fontSize: 10.5)),
            ]),
          ),
      ]),
    );
  }
}

/// Ledger row: date, job, status chip, amount (right aligned).
Widget proLedgerRow(BuildContext context, {required String date, required String title, required String status, required HtTone tone, required String amount}) {
  final p = context.ht;
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
    child: Row(children: [
      SizedBox(width: 54, child: Text(date, style: HtType.smallStrong(p.textMuted).copyWith(fontSize: 11.5))),
      Expanded(child: Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 8),
      HtStatusPill(label: status, tone: tone),
      const SizedBox(width: 10),
      SizedBox(width: 78, child: Text(amount, textAlign: TextAlign.right, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5))),
    ]),
  );
}

/// Segmented control (pro style: squared track).
Widget proSegments(BuildContext context, List<String> labels, int selected, {List<int?>? counts}) {
  final p = context.ht;
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: p.isDark ? p.backgroundDeep : p.surfaceRaised, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
    child: Row(children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: i == selected ? BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), boxShadow: p.cardShadow, border: Border.all(color: p.border)) : null,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: HtType.smallStrong(i == selected ? p.textPrimary : p.textSecondary).copyWith(fontSize: 12.5))),
              if (counts != null && counts[i] != null) ...[const SizedBox(width: 5), Text('${counts[i]}', style: HtType.smallStrong(p.textMuted).copyWith(fontSize: 11.5))],
            ]),
          ),
        ),
    ]),
  );
}

/// Sticky artisan action bar: next action + secondary icon actions.
Widget proActionBar(BuildContext context, String primary, {String? note}) {
  final p = context.ht;
  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (note != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(note, textAlign: TextAlign.center, style: HtType.small(p.textSecondary))),
    Row(children: [
      const HtIconCircle(icon: Icons.forum_outlined, size: 50, tooltip: 'Chat', square: true),
      const SizedBox(width: 10),
      Expanded(child: HtPrimaryButton(label: primary, icon: Icons.arrow_forward_rounded, onPressed: () {})),
    ]),
  ]);
}

/// Artisan inner-screen header: square back button, title, context line,
/// chat shortcut.
Widget proBackHeader(BuildContext context, String title, {String? sub}) {
  final p = context.ht;
  return Padding(
    padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 8, HtSpace.gutter, 8),
    child: Row(children: [
      const HtIconCircle(icon: Icons.arrow_back_rounded, tooltip: 'Back', square: true),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: HtType.cardTitle(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (sub != null) Text(sub, style: HtType.small(p.textSecondary).copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
      const HtIconCircle(icon: Icons.forum_outlined, tooltip: 'Chat', square: true),
    ]),
  );
}

/// Underline tabs for the work order (scrolls when labels don't fit).
Widget proTabs(BuildContext context, List<String> labels, int selected) {
  final p = context.ht;
  final a = p.isDark ? p.accent : p.accentStrong;
  return Container(
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Container(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
            margin: const EdgeInsets.only(right: 18),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == selected ? a : Colors.transparent, width: 2.5))),
            child: Text(labels[i], style: HtType.bodyStrong(i == selected ? p.textPrimary : p.textSecondary).copyWith(fontSize: 13.5)),
          ),
      ]),
    ),
  );
}
