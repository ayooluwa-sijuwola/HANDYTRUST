import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../components/ht_components.dart';
import '../../theme/ht_theme.dart';

/// HandyTrust Pro — the artisan component set (Stage 8.1, approved in
/// design/STAGE8_ARTISAN_REDESIGN_PREVIEW.md). Purpose-built for artisan
/// work while sharing the HtPalette / HtType tokens with the customer app.

Color proAccent(HtPalette p) => p.isDark ? p.accent : p.accentStrong;
Color proOnAccent(HtPalette p) => p.isDark ? p.onPrimary : Colors.white;
List<Color> proChartColors(HtPalette p) =>
    p.isDark ? const [Color(0xFF8E9F45), Color(0xFF3987E5), Color(0xFFD55181)] : const [Color(0xFF6E7D31), Color(0xFF2A78D6), Color(0xFFD55181)];

// ─── Navigation ─────────────────────────────────────────────────────────────

/// Docked artisan work bar (approved D-2 order).
class ProNavBar extends StatelessWidget {
  const ProNavBar({super.key, required this.current, required this.onTap});
  final int current;
  final ValueChanged<int> onTap;
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
    final active = proAccent(p);
    return Container(
      decoration: BoxDecoration(color: p.isDark ? p.backgroundDeep : p.surface, border: Border(top: BorderSide(color: p.border))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == current,
                  button: true,
                  label: items[i].$3,
                  child: InkResponse(
                    onTap: () => onTap(i),
                    child: Column(children: [
                      Container(height: 3, width: 28, decoration: BoxDecoration(color: i == current ? active : Colors.transparent, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)))),
                      const Spacer(),
                      Icon(i == current ? items[i].$2 : items[i].$1, size: 23, color: i == current ? active : p.textMuted),
                      const SizedBox(height: 3),
                      Text(items[i].$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: HtType.smallStrong(i == current ? p.textPrimary : p.textMuted).copyWith(fontSize: 10.5)),
                      const Spacer(),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Square icon button with an optional count badge.
class ProBadgeButton extends StatelessWidget {
  const ProBadgeButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.count = 0});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int count;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Stack(clipBehavior: Clip.none, children: [
      HtIconCircle(icon: icon, tooltip: count > 0 ? '$tooltip ($count unread)' : tooltip, square: true, onTap: onTap),
      if (count > 0)
        Positioned(
          right: -4,
          top: -4,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(HtRadius.pill), border: Border.all(color: p.background, width: 1.5)),
              child: Text(count > 99 ? '99+' : '$count', style: HtType.smallStrong(Colors.white).copyWith(fontSize: 10)),
            ),
          ),
        ),
    ]);
  }
}

/// Artisan header: availability ring avatar, name/title, trade line,
/// messages + notifications actions.
class ProHeader extends StatelessWidget {
  const ProHeader({
    super.key,
    required this.name,
    required this.trade,
    required this.available,
    required this.messages,
    required this.alerts,
    required this.onMessages,
    required this.onAlerts,
    this.imageUrl,
    this.title,
  });
  final String name;
  final String trade;
  final bool available;
  final int messages;
  final int alerts;
  final VoidCallback onMessages;
  final VoidCallback onAlerts;
  final String? imageUrl;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final ring = available ? p.success : p.textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 8, HtSpace.gutter, 8),
      child: Row(children: [
        Semantics(
          label: available ? 'Available for work' : 'Not accepting jobs',
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2.5)),
            child: HtAvatar(name: name, imageUrl: imageUrl, size: 40),
          ),
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
        ProBadgeButton(icon: Icons.forum_outlined, tooltip: 'Messages', count: messages, onTap: onMessages),
        const SizedBox(width: 10),
        ProBadgeButton(icon: Icons.notifications_none_rounded, tooltip: 'Notifications', count: alerts, onTap: onAlerts),
      ]),
    );
  }
}

/// Inner-screen header: square back button, title, context line, optional
/// chat shortcut.
class ProBackHeader extends StatelessWidget {
  const ProBackHeader({super.key, required this.title, this.sub, this.onChat});
  final String title;
  final String? sub;
  final VoidCallback? onChat;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 8, HtSpace.gutter, 8),
      child: Row(children: [
        HtIconCircle(icon: Icons.arrow_back_rounded, tooltip: 'Back', square: true, onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: HtType.cardTitle(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (sub != null) Text(sub!, style: HtType.small(p.textSecondary).copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (onChat != null) HtIconCircle(icon: Icons.forum_outlined, tooltip: 'Chat', square: true, onTap: onChat),
      ]),
    );
  }
}

/// Section label: caps text + optional count + optional link.
class ProSection extends StatelessWidget {
  const ProSection(this.label, {super.key, this.count, this.trailing, this.onTrailing});
  final String label;
  final int? count;
  final String? trailing;
  final VoidCallback? onTrailing;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(children: [
        // The label takes all space the trailing link doesn't need.
        Expanded(
          child: Row(children: [
            Flexible(child: Text(label.toUpperCase(), style: HtType.caps(p.textSecondary).copyWith(fontSize: 11.5, letterSpacing: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: proAccent(p), borderRadius: BorderRadius.circular(HtRadius.pill)),
                child: Text('$count', style: HtType.smallStrong(proOnAccent(p)).copyWith(fontSize: 11)),
              ),
            ],
          ]),
        ),
        if (trailing != null)
          InkWell(
            onTap: onTrailing,
            borderRadius: BorderRadius.circular(8),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: Text(trailing!, style: HtType.smallStrong(p.accent).copyWith(fontSize: 12))),
          ),
      ]),
    );
  }
}

Widget proTitle(BuildContext context, String t) => Text(t, style: HtType.screenTitle(context.ht.textPrimary).copyWith(fontSize: 25));

// ─── Dashboard pieces ───────────────────────────────────────────────────────

Color _toneColor(HtPalette p, HtTone t) => switch (t) {
      HtTone.danger => p.danger,
      HtTone.warning => p.warning,
      HtTone.success => p.success,
      HtTone.neutral => p.textSecondary,
      HtTone.accent => proAccent(p),
    };

/// Action-queue card with a coloured rail, deadline and one action.
class ProActionCard extends StatelessWidget {
  const ProActionCard({super.key, required this.tone, required this.icon, required this.title, required this.subtitle, required this.action, required this.onTap, this.deadline});
  final HtTone tone;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? deadline;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final c = _toneColor(p, tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HtRadius.tile + 2), side: BorderSide(color: p.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
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
                        Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text(subtitle, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (deadline != null) ...[
                          const SizedBox(height: 5),
                          Row(children: [Icon(Icons.schedule_rounded, size: 13, color: c), const SizedBox(width: 4), Flexible(child: Text(deadline!, style: HtType.smallStrong(c).copyWith(fontSize: 11.5)))]),
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
        ),
      ),
    );
  }
}

/// Pipeline strip: stage counters, each tappable.
class ProPipeline extends StatelessWidget {
  const ProPipeline({super.key, required this.stages, required this.onTap});
  final List<(String, int)> stages;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border), boxShadow: p.cardShadow),
      child: Row(children: [
        for (var i = 0; i < stages.length; i++) ...[
          if (i > 0) Container(width: 1, height: 34, color: p.border),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  Text('${stages[i].$2}', style: HtType.amount(stages[i].$2 > 0 ? p.textPrimary : p.textMuted, size: 20)),
                  const SizedBox(height: 2),
                  Text(stages[i].$1, textAlign: TextAlign.center, maxLines: 2, style: HtType.small(p.textSecondary).copyWith(fontSize: 10.5, height: 1.15)),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Circular countdown / progress ring.
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
    return Semantics(
      label: '$big $small',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(fraction.clamp(0, 1), _toneColor(p, tone), p.surfaceRaised),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(child: Text(big, style: HtType.amount(p.textPrimary, size: size * 0.24))),
              Text(small, style: HtType.small(p.textSecondary).copyWith(fontSize: 10.5)),
            ]),
          ),
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
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()..color = bg..style = PaintingStyle.stroke..strokeWidth = 8);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * f, false, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.f != f || old.c != c || old.bg != bg;
}

/// Work-order ticket (list) or compact card (board column).
class ProTicket extends StatelessWidget {
  const ProTicket({
    super.key,
    required this.day,
    required this.month,
    required this.title,
    required this.meta,
    required this.stage,
    required this.stageTone,
    required this.onTap,
    this.deadline,
    this.amount,
    this.action,
    this.onChat,
    this.icon = Icons.handyman_outlined,
    this.compact = false,
  });
  final String day;
  final String month;
  final String title;
  final String meta;
  final String stage;
  final HtTone stageTone;
  final String? deadline;
  final String? amount;
  final String? action;
  final VoidCallback onTap;
  final VoidCallback? onChat;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? HtRadius.tile + 2 : HtRadius.inner), side: BorderSide(color: p.border));
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: p.surface,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${month.toUpperCase()} $day'.trim(), style: HtType.caps(proAccent(p)).copyWith(fontSize: 10)),
                const SizedBox(height: 4),
                Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(meta, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                HtStatusPill(label: stage, tone: stageTone, dot: true, maxLines: 2),
                if (deadline != null) ...[
                  const SizedBox(height: 6),
                  Row(children: [Icon(Icons.schedule_rounded, size: 13, color: p.textSecondary), const SizedBox(width: 3), Flexible(child: Text(deadline!, style: HtType.smallStrong(p.textSecondary).copyWith(fontSize: 11.5)))]),
                ],
              ]),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: p.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 52,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: p.isDark ? p.backgroundDeep : p.accentSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
                  child: Column(children: [
                    Text(month.toUpperCase(), style: HtType.caps(proAccent(p)).copyWith(fontSize: 9.5), maxLines: 1),
                    Text(day.isEmpty ? '—' : day, style: HtType.amount(p.textPrimary, size: 21)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(icon, size: 15, color: p.textMuted),
                      const SizedBox(width: 5),
                      Expanded(child: Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (amount != null) ...[const SizedBox(width: 6), Text(amount!, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14))],
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
            if (action != null || onChat != null)
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(children: [
                  if (onChat != null)
                    TextButton.icon(
                      onPressed: onChat,
                      icon: Icon(Icons.chat_bubble_outline_rounded, size: 18, color: p.textSecondary),
                      label: Text('Chat', style: HtType.smallStrong(p.textSecondary)),
                    ),
                  const Spacer(),
                  if (action != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(action!, style: HtType.bodyStrong(proAccent(p)).copyWith(fontSize: 13.5)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 17, color: proAccent(p)),
                      ]),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Six-step work-order stepper. [current] == labels.length means all done.
class ProWorkStepper extends StatelessWidget {
  const ProWorkStepper({super.key, required this.current, required this.labels});
  final int current;
  final List<String> labels;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final a = proAccent(p);
    return Semantics(
      label: current >= labels.length ? 'All steps complete' : 'Step ${current + 1} of ${labels.length}: ${labels[current]}',
      child: Column(children: [
        Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Container(
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: i < current ? a : (i == current ? a.withValues(alpha: 0.45) : p.surfaceRaised), borderRadius: BorderRadius.circular(3)),
              ),
            ),
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
      ]),
    );
  }
}

/// Segmented meter over the job progress stages.
class ProProgressMeter extends StatelessWidget {
  const ProProgressMeter({super.key, required this.index, required this.labels});
  final int index;
  final List<String> labels;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final a = proChartColors(p).first;
    final n = labels.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(index < 0 ? 'Not started' : labels[index], style: HtType.bodyStrong(p.textPrimary))),
        Text(index < 0 ? '0 of $n' : 'Step ${index + 1} of $n', style: HtType.small(p.textSecondary)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        for (var i = 0; i < n; i++)
          Expanded(
            child: Container(
              height: 12,
              margin: EdgeInsets.only(right: i < n - 1 ? 3 : 0),
              decoration: BoxDecoration(color: i <= index ? a : p.surfaceRaised, borderRadius: BorderRadius.circular(3)),
            ),
          ),
      ]),
    ]);
  }
}

/// Compact stat (label, value, sub-line).
class ProStat extends StatelessWidget {
  const ProStat({super.key, required this.value, required this.label, this.sub, this.icon, this.onTap});
  final String value;
  final String label;
  final String? sub;
  final IconData? icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(HtRadius.tile + 2), side: BorderSide(color: p.border));
    return Material(
      color: p.surface,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 16, color: p.textMuted), const SizedBox(width: 6)],
              Expanded(child: Text(label, style: HtType.smallStrong(p.textSecondary).copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: HtType.amount(p.textPrimary, size: 21), maxLines: 1)),
            if (sub != null) Text(sub!, style: HtType.small(p.textMuted).copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
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
    final c = proChartColors(p).first;
    final max = values.fold<double>(0, math.max);
    return Semantics(
      label: 'Released payouts by month: ${[for (var i = 0; i < months.length; i++) '${months[i]} ${labels[i]}'].join(', ')}',
      child: SizedBox(
        height: 150,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(labels[i], style: HtType.smallStrong(p.textSecondary).copyWith(fontSize: 10)),
                const SizedBox(height: 4),
                Container(
                  height: max <= 0 ? 2 : math.max(2, 96 * values[i] / max),
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(color: i == values.length - 1 ? c : c.withValues(alpha: 0.55), borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                ),
                const SizedBox(height: 6),
                Text(months[i], style: HtType.small(p.textMuted).copyWith(fontSize: 10.5)),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Ledger row: date, title, status chip, amount.
class ProLedgerRow extends StatelessWidget {
  const ProLedgerRow({super.key, required this.date, required this.title, required this.status, required this.tone, required this.amount, this.onTap});
  final String date;
  final String title;
  final String status;
  final HtTone tone;
  final String amount;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
        child: Row(children: [
          SizedBox(width: 54, child: Text(date, style: HtType.smallStrong(p.textMuted).copyWith(fontSize: 11.5))),
          Expanded(child: Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          HtStatusPill(label: status, tone: tone),
          const SizedBox(width: 10),
          SizedBox(width: 84, child: Text(amount, textAlign: TextAlign.right, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5))),
        ]),
      ),
    );
  }
}

/// Squared segmented control.
class ProSegments extends StatelessWidget {
  const ProSegments({super.key, required this.labels, required this.selected, required this.onSelected, this.counts});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final List<int?>? counts;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.isDark ? p.backgroundDeep : p.surfaceRaised, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Semantics(
              selected: i == selected,
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: i == selected ? BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), boxShadow: p.cardShadow, border: Border.all(color: p.border)) : null,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(child: Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: HtType.smallStrong(i == selected ? p.textPrimary : p.textSecondary).copyWith(fontSize: 12.5))),
                    if (counts != null && counts![i] != null) ...[const SizedBox(width: 5), Text('${counts![i]}', style: HtType.smallStrong(p.textMuted).copyWith(fontSize: 11.5))],
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Underline tabs (scroll when they don't fit).
class ProTabs extends StatelessWidget {
  const ProTabs({super.key, required this.labels, required this.selected, required this.onSelected});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final a = proAccent(p);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Semantics(
              selected: i == selected,
              button: true,
              child: InkWell(
                onTap: () => onSelected(i),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
                  margin: const EdgeInsets.only(right: 18),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == selected ? a : Colors.transparent, width: 2.5))),
                  child: Text(labels[i], style: HtType.bodyStrong(i == selected ? p.textPrimary : p.textSecondary).copyWith(fontSize: 13.5)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Sticky artisan action bar: chat shortcut + primary action.
class ProActionBar extends StatelessWidget {
  const ProActionBar({super.key, required this.label, required this.onPressed, this.onChat, this.loading = false, this.note, this.secondary});
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onChat;
  final bool loading;
  final String? note;
  final Widget? secondary;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: EdgeInsets.fromLTRB(HtSpace.gutter, 12, HtSpace.gutter, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (note != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(note!, textAlign: TextAlign.center, style: HtType.small(p.textSecondary))),
        Row(children: [
          if (onChat != null) ...[HtIconCircle(icon: Icons.forum_outlined, size: 50, tooltip: 'Chat', square: true, onTap: onChat), const SizedBox(width: 10)],
          if (secondary != null) ...[Expanded(child: secondary!), const SizedBox(width: 10)],
          Expanded(flex: secondary != null ? 2 : 1, child: HtPrimaryButton(label: label, icon: Icons.arrow_forward_rounded, loading: loading, onPressed: onPressed)),
        ]),
      ]),
    );
  }
}

/// Day / month labels for ticket date blocks.
String proDay(DateTime? d) => d == null ? '' : '${d.day}';
String proMonth(DateTime? d) => d == null ? 'TBC' : const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1];
