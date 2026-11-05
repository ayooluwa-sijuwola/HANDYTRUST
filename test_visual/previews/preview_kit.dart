// Stage 8.1 design PREVIEW kit (design/STAGE8_1_PREVIEW_REVIEW.md).
//
// Prototype components proposed in design/STAGE8_1_DESIGN_SPECIFICATION.md
// §1.3, built only from the Stage 8 tokens (lib/ui/theme/ht_theme.dart) and
// components (lib/ui/components/). Preview-only: nothing in lib/ imports this
// file; on approval the components move to lib/ui/components/ in Phase C.
// All text and numbers rendered with this kit are SAMPLE DATA.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:handy_trust/ui/components/ht_bottom_nav.dart';
import 'package:handy_trust/ui/components/ht_components.dart';
import 'package:handy_trust/ui/theme/ht_theme.dart';

// ─── Tokens added by the spec (§1.2) ────────────────────────────────────────

/// Categorical chart series, validated with the data-viz palette checks
/// (light on #FFFFFF, dark on #1C2118: all checks pass).
List<Color> htChartColors(HtPalette p) => p.isDark
    ? const [Color(0xFF8E9F45), Color(0xFF3987E5), Color(0xFFD55181)]
    : const [Color(0xFF6E7D31), Color(0xFF2A78D6), Color(0xFFD55181)];

Color htInfo(HtPalette p) => p.isDark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);

const artisanNavItems = [
  HtNavItem(Icons.home_outlined, 'Home'),
  HtNavItem(Icons.travel_explore_rounded, 'Find Work'),
  HtNavItem(Icons.work_outline_rounded, 'My Jobs'),
  HtNavItem(Icons.payments_outlined, 'Earnings'),
  HtNavItem(Icons.person_outline_rounded, 'Profile'),
];

// ─── Frames ─────────────────────────────────────────────────────────────────

/// Small tag in the status-bar area marking every preview as sample data.
class PreviewTag extends StatelessWidget {
  const PreviewTag({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.pill), border: Border.all(color: p.border)),
      child: Text('PREVIEW · SAMPLE DATA', style: HtType.caps(p.textMuted).copyWith(fontSize: 9)),
    );
  }
}

/// Phone screen: background, header, scrolling content, optional floating
/// bottom nav, sticky bottom bar or modal sheet overlay.
class PhoneScreen extends StatelessWidget {
  const PhoneScreen({
    super.key,
    this.header,
    required this.children,
    this.nav,
    this.navIndex = 0,
    this.bottomBar,
    this.sheet,
    this.deep = false,
    this.padding = const EdgeInsets.fromLTRB(HtSpace.gutter, 4, HtSpace.gutter, 24),
    this.navBar,
  });
  final Widget? header;
  final List<Widget> children;
  final List<HtNavItem>? nav;
  final int navIndex;
  final Widget? bottomBar;
  final Widget? sheet;
  final bool deep;
  final EdgeInsets padding;
  /// Custom bottom navigation (artisan Pro bar) instead of [nav].
  final Widget? navBar;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final top = MediaQuery.paddingOf(context).top;
    final bottomInset = (nav != null || navBar != null) ? 104.0 : (bottomBar != null ? 96.0 : 0.0);
    return Scaffold(
      backgroundColor: deep ? p.backgroundDeep : p.background,
      extendBody: true,
      bottomNavigationBar: navBar ?? (nav != null ? HtBottomNav(items: nav!, current: navIndex, onTap: (_) {}) : null),
      body: Stack(
        children: [
          HtBackground(
            deep: deep,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  ?header,
                  Expanded(
                    child: ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: padding.copyWith(bottom: padding.bottom + bottomInset),
                      children: children,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(top: top / 2 - 9, left: 0, right: 0, child: const Center(child: PreviewTag())),
          if (bottomBar != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(HtSpace.gutter, 14, HtSpace.gutter, 14 + MediaQuery.paddingOf(context).bottom),
                decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
                child: bottomBar,
              ),
            ),
          if (sheet != null) ...[
            Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: p.isDark ? 0.6 : 0.35))),
            Positioned(left: 0, right: 0, bottom: 0, child: HtSheet(child: sheet!)),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet surface (drag handle, large top radius).
class HtSheet extends StatelessWidget {
  const HtSheet({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 10, 22, 18 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(HtRadius.card)),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: p.textMuted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)))),
          child,
        ],
      ),
    );
  }
}

/// Standard artisan/customer tab header: brand + chat + bell + avatar.
Widget htTabHeader(BuildContext context, {required String name, bool chatBadge = false, bool bellBadge = true}) {
  final p = context.ht;
  return HtAppHeader(actions: [
    HtIconCircle(icon: Icons.chat_bubble_outline_rounded, badge: chatBadge, tooltip: 'Messages'),
    HtIconCircle(icon: Icons.notifications_none_rounded, badge: bellBadge, tooltip: 'Notifications'),
    CircleAvatar(radius: 20, backgroundColor: p.headerAvatarFill, child: Text(name.substring(0, 1), style: HtType.bodyStrong(p.onHeaderAvatar))),
  ]);
}

Widget htTitleBlock(BuildContext context, String title, String subtitle) {
  final p = context.ht;
  return Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: HtType.screenTitle(p.textPrimary)),
        const SizedBox(height: 4),
        Text(subtitle, style: HtType.body(p.textSecondary)),
      ],
    ),
  );
}

// ─── Proposed components (§1.3) ─────────────────────────────────────────────

/// Metric tile: label, value, week-over-week change as arrow + text.
class HtKpiTile extends StatelessWidget {
  const HtKpiTile({super.key, required this.icon, required this.label, required this.value, this.change, this.up, this.caption = 'vs last week', this.note = 'No prior week to compare'});
  final IconData icon;
  final String label;
  final String value;
  final String? change;
  final bool? up;
  final String caption;
  /// Shown instead of a change for metrics without a trend (definition).
  final String note;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border), boxShadow: p.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 18, color: p.accentSoftText),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: HtType.smallStrong(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 14),
          Text(value, style: HtType.amount(p.textPrimary, size: 25), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(
            children: [
              if (change != null && up != null) ...[
                Icon(up! ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: up! ? p.success : p.danger),
                const SizedBox(width: 3),
                Text(change!, style: HtType.smallStrong(p.textPrimary).copyWith(fontSize: 11.5)),
                const SizedBox(width: 5),
              ],
              Flexible(child: Text(change == null ? note : caption, style: HtType.small(p.textMuted).copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ),
    );
  }
}

/// One-row filter bar: search, chips, optional trailing control.
class HtFilterBar extends StatelessWidget {
  const HtFilterBar({super.key, required this.hint, this.chips = const [], this.selected = 0, this.trailing, this.counts});
  final String hint;
  final List<String> chips;
  final int selected;
  final Widget? trailing;
  final List<int?>? counts;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final search = Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(HtRadius.pill), border: Border.all(color: p.isDark ? Colors.transparent : p.border)),
      child: Row(children: [
        Icon(Icons.search_rounded, size: 20, color: p.textMuted),
        const SizedBox(width: 10),
        Expanded(child: Text(hint, style: HtType.body(p.textMuted).copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
    final chipRow = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < chips.length; i++) HtChip(label: chips[i], selected: i == selected, count: counts?[i], onTap: () {}),
      ],
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          search,
          if (chips.isNotEmpty) ...[const SizedBox(height: 12), chipRow],
        ]);
      }
      return Row(children: [
        SizedBox(width: 300, child: search),
        const SizedBox(width: 14),
        Expanded(child: chipRow),
        ?trailing,
      ]);
    });
  }
}

class HtColumn {
  const HtColumn(this.label, {this.flex = 2, this.numeric = false});
  final String label;
  final int flex;
  final bool numeric;
}

/// Wide admin table: sticky-style header, rows, selection highlight.
class HtDataTable extends StatelessWidget {
  const HtDataTable({super.key, required this.columns, required this.rows, this.selected, this.footer});
  final List<HtColumn> columns;
  final List<List<Widget>> rows;
  final int? selected;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    // Numeric columns are right-aligned with a gutter so they never touch
    // the next column's left-aligned text.
    Widget cell(int i, Widget w) => Expanded(
          flex: columns[i].flex,
          child: Padding(
            padding: EdgeInsets.only(right: columns[i].numeric ? 24 : 8),
            child: Align(alignment: columns[i].numeric ? Alignment.centerRight : Alignment.centerLeft, child: w),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border), boxShadow: p.cardShadow),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: p.surfaceRaised,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(children: [
              for (var i = 0; i < columns.length; i++) cell(i, Text(columns[i].label.toUpperCase(), style: HtType.caps(p.textSecondary).copyWith(fontSize: 10.5))),
            ]),
          ),
          for (var r = 0; r < rows.length; r++)
            Container(
              decoration: BoxDecoration(
                color: r == selected ? p.accentSoft.withValues(alpha: p.isDark ? 0.6 : 1) : null,
                border: Border(top: BorderSide(color: p.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              child: Row(children: [for (var i = 0; i < columns.length; i++) cell(i, rows[r][i])]),
            ),
          if (footer != null)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: Text(footer!, style: HtType.smallStrong(p.accent)),
            ),
        ],
      ),
    );
  }
}

/// Text helpers for table cells.
Widget tCell(BuildContext context, String text, {bool strong = false, bool muted = false}) {
  final p = context.ht;
  return Text(text,
      style: strong ? HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5) : HtType.small(muted ? p.textMuted : p.textPrimary).copyWith(fontSize: 13),
      maxLines: 1,
      overflow: TextOverflow.ellipsis);
}

Widget tPerson(BuildContext context, String name, String sub) {
  final p = context.ht;
  return Row(children: [
    HtAvatar(name: name, size: 32),
    const SizedBox(width: 10),
    Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(sub, style: HtType.small(p.textMuted).copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    ),
  ]);
}

/// Narrow list row (artisan and admin lists).
class HtListCard extends StatelessWidget {
  const HtListCard({super.key, required this.leading, required this.title, this.subtitle, this.meta, this.trailing, this.chevron = true});
  final Widget leading;
  final String title;
  final String? subtitle;
  final String? meta;
  final Widget? trailing;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return HtCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      radius: HtRadius.inner,
      onTap: () {},
      child: Row(children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle != null) Text(subtitle!, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (meta != null) Text(meta!, style: HtType.small(p.textMuted).copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        if (chevron) ...[const SizedBox(width: 4), Icon(Icons.chevron_right_rounded, color: p.textMuted)],
      ]),
    );
  }
}

/// Icon in a rounded tile (list leading).
Widget htIconTile(BuildContext context, IconData icon, {HtTone tone = HtTone.accent, double size = 42}) {
  final p = context.ht;
  final (bg, fg) = switch (tone) {
    HtTone.success => (p.successSoft, p.success),
    HtTone.warning => (p.warningSoft, p.warning),
    HtTone.danger => (p.dangerSoft, p.danger),
    HtTone.neutral => (p.surfaceRaised, p.textSecondary),
    HtTone.accent => (p.accentSoft, p.accentSoftText),
  };
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.32)),
    child: Icon(icon, size: size * 0.48, color: fg),
  );
}

/// Operational alert row. Shows the human label AND the original type id.
class HtAlertRow extends StatelessWidget {
  const HtAlertRow({super.key, required this.tone, required this.title, required this.typeId, required this.detail, required this.time, this.actions = const []});
  final HtTone tone;
  final String title;
  final String typeId;
  final String detail;
  final String time;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final (icon, sev) = switch (tone) {
      HtTone.danger => (Icons.error_outline_rounded, 'Action required'),
      HtTone.warning => (Icons.warning_amber_rounded, 'Needs attention'),
      HtTone.success => (Icons.check_circle_outline_rounded, 'Resolved upstream'),
      _ => (Icons.info_outline_rounded, 'Information'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        htIconTile(context, icon, tone: tone, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(time, style: HtType.small(p.textMuted).copyWith(fontSize: 11.5)),
            ]),
            const SizedBox(height: 2),
            Text(detail, style: HtType.small(p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              HtStatusPill(label: sev, tone: tone == HtTone.neutral ? HtTone.neutral : tone),
              // Original backend identifier, kept visible next to the label.
              Text(typeId, style: HtType.small(p.textMuted).copyWith(fontSize: 11, letterSpacing: 0.3)),
            ]),
            if (actions.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: [for (final a in actions) IntrinsicWidth(child: a)])],
          ]),
        ),
      ]),
    );
  }
}

/// Chart card: title, legend (≥2 series), body, "View as table" affordance.
class HtChartCard extends StatelessWidget {
  const HtChartCard({super.key, required this.title, this.subtitle, this.legend = const [], required this.child, this.height = 200});
  final String title;
  final String? subtitle;
  final List<String> legend;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final colors = htChartColors(p);
    return HtCard(
      radius: HtRadius.inner,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: HtType.cardTitle(p.textPrimary)),
              if (subtitle != null) Text(subtitle!, style: HtType.small(p.textSecondary)),
            ]),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.table_rows_outlined, size: 16, color: p.accent),
            const SizedBox(width: 4),
            Text('View as table', style: HtType.smallStrong(p.accent).copyWith(fontSize: 11.5)),
          ]),
        ]),
        if (legend.length > 1) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 14, children: [
            for (var i = 0; i < legend.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                Text(legend[i], style: HtType.small(p.textSecondary)),
              ]),
          ]),
        ],
        const SizedBox(height: 14),
        SizedBox(height: height, child: child),
      ]),
    );
  }
}

/// Line chart (2 px lines, recessive grid, one axis).
Widget htLineChart(BuildContext context, List<List<double>> series, List<String> xLabels) {
  final p = context.ht;
  final colors = htChartColors(p);
  final maxY = series.expand((s) => s).reduce((a, b) => a > b ? a : b);
  final top = ((maxY / 4).ceil() + 1) * 4.0; // four whole-number intervals
  return LineChart(
    LineChartData(
      minY: 0,
      maxY: top,
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: top / 4,
        getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: top / 4,
            getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: HtType.small(p.textMuted).copyWith(fontSize: 10.5)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 1,
            getTitlesWidget: (v, _) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(xLabels[v.toInt().clamp(0, xLabels.length - 1)], style: HtType.small(p.textMuted).copyWith(fontSize: 10.5)),
            ),
          ),
        ),
      ),
      lineBarsData: [
        for (var s = 0; s < series.length; s++)
          LineChartBarData(
            spots: [for (var i = 0; i < series[s].length; i++) FlSpot(i.toDouble(), series[s][i])],
            isCurved: true,
            curveSmoothness: 0.22,
            color: colors[s],
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
          ),
      ],
    ),
    duration: Duration.zero,
  );
}

/// Horizontal single-hue bars with direct labels (magnitude).
Widget htBarList(BuildContext context, List<(String, int)> rows) {
  final p = context.ht;
  final c = htChartColors(p).first;
  final max = rows.map((r) => r.$2).reduce((a, b) => a > b ? a : b);
  return Column(
    children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            SizedBox(width: 92, child: Text(r.$1, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: LayoutBuilder(builder: (context, cons) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: cons.maxWidth * r.$2 / max,
                    height: 14,
                    decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))),
                  ),
                );
              }),
            ),
            SizedBox(width: 36, child: Text('${r.$2}', textAlign: TextAlign.right, style: HtType.smallStrong(p.textPrimary))),
          ]),
        ),
    ],
  );
}

/// Job summary card (artisan feed / lists).
class HtJobCard extends StatelessWidget {
  const HtJobCard({super.key, required this.category, required this.area, required this.description, required this.meta, this.badge, this.badgeTone = HtTone.warning, this.actions = const [], this.icon = Icons.handyman_outlined});
  final String category;
  final String area;
  final String description;
  final String meta;
  final String? badge;
  final HtTone badgeTone;
  final List<Widget> actions;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return HtCard(
      radius: HtRadius.inner,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          htIconTile(context, icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(category, style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 15.5)),
              Row(children: [
                Icon(Icons.place_outlined, size: 14, color: p.textMuted),
                const SizedBox(width: 3),
                Flexible(child: Text(area, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ]),
          ),
          if (badge != null) HtStatusPill(label: badge!, tone: badgeTone, dot: true),
        ]),
        const SizedBox(height: 12),
        Text(description, style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 10),
        Text(meta, style: HtType.small(p.textSecondary)),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: actions[i])]]),
        ],
      ]),
    );
  }
}

/// Photo placeholder tile (previews never load real user images).
class HtPhotoTile extends StatelessWidget {
  const HtPhotoTile({super.key, required this.label, this.height = 96, this.icon = Icons.image_outlined});
  final String label;
  final double height;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HtRadius.tile),
        gradient: LinearGradient(colors: [p.accentSoft, p.surfaceRaised], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: p.border),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: p.accentSoftText, size: 24),
          const SizedBox(height: 4),
          Text(label, style: HtType.small(p.textSecondary).copyWith(fontSize: 11), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

/// Labelled switch with explanation.
class HtToggleRow extends StatelessWidget {
  const HtToggleRow({super.key, required this.title, required this.subtitle, required this.value, this.icon = Icons.bolt_rounded});
  final String title;
  final String subtitle;
  final bool value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Row(children: [
      htIconTile(context, icon, tone: value ? HtTone.success : HtTone.neutral, size: 40),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)),
          Text(subtitle, style: HtType.small(p.textSecondary)),
        ]),
      ),
      Switch(
        value: value,
        onChanged: (_) {},
        activeThumbColor: p.isDark ? p.onPrimary : Colors.white,
        activeTrackColor: p.isDark ? p.accent : p.accentStrong,
      ),
    ]);
  }
}

/// Workflow timeline (replaces workflow_timeline / workflow_status_card).
class HtTimeline extends StatelessWidget {
  const HtTimeline({super.key, required this.entries});
  final List<(String, String, bool)> entries;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Column(children: [
      for (var i = 0; i < entries.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 22,
              child: Column(children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: entries[i].$3 ? (p.isDark ? p.accent : p.accentStrong) : p.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: entries[i].$3 ? Colors.transparent : p.textMuted, width: 2),
                  ),
                ),
                if (i < entries.length - 1) Expanded(child: Container(width: 2, color: p.border)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entries[i].$1, style: HtType.bodyStrong(entries[i].$3 ? p.textPrimary : p.textSecondary).copyWith(fontSize: 13.5)),
                  Text(entries[i].$2, style: HtType.small(p.textMuted).copyWith(fontSize: 11.5)),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// Labelled read-only field value (detail panels, forms in previews).
Widget htField(BuildContext context, String label, String value, {String? trailing, int lines = 1, bool placeholder = false}) {
  final p = context.ht;
  final isHint = placeholder || value.startsWith('e.g.') || value.endsWith('…');
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    HtFieldLabel(label, trailing: trailing),
    Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(HtRadius.input), border: Border.all(color: p.isDark ? Colors.transparent : p.border)),
      child: Text(value, style: HtType.body(isHint ? p.textMuted : p.textPrimary), maxLines: lines, overflow: TextOverflow.ellipsis),
    ),
  ]);
}

/// Key/value row.
Widget htKv(BuildContext context, String k, String v, {bool strong = false}) {
  final p = context.ht;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Expanded(child: Text(k, style: HtType.small(p.textSecondary).copyWith(fontSize: 13))),
      Text(v, style: strong ? HtType.bodyStrong(p.textPrimary) : HtType.small(p.textPrimary).copyWith(fontSize: 13)),
    ]),
  );
}

// ─── Admin shell ────────────────────────────────────────────────────────────

class AdminNavGroup {
  const AdminNavGroup(this.label, this.items);
  final String label;
  final List<(IconData, String, int?)> items;
}

const adminNavGroups = [
  AdminNavGroup('Overview', [(Icons.dashboard_outlined, 'Dashboard', null), (Icons.insights_outlined, 'Analytics', null)]),
  AdminNavGroup('People', [(Icons.people_alt_outlined, 'Users', null), (Icons.handyman_outlined, 'Artisans', 4), (Icons.verified_user_outlined, 'Verifications', 2)]),
  AdminNavGroup('Operations', [
    (Icons.work_outline_rounded, 'Jobs', null),
    (Icons.gavel_rounded, 'Disputes', 1),
    (Icons.support_agent_rounded, 'Support', 3),
    (Icons.star_outline_rounded, 'Reviews', null),
    (Icons.person_remove_outlined, 'Deletion requests', 1),
  ]),
  AdminNavGroup('Finance', [(Icons.account_balance_outlined, 'Finance', null)]),
  AdminNavGroup('Compliance', [(Icons.history_rounded, 'Audit logs', null)]),
];

/// Grouped admin navigation (rail ≥1024 px, drawer below).
class HtSideNav extends StatelessWidget {
  const HtSideNav({super.key, required this.current});
  final String current;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    Widget item(IconData icon, String label, int? count) {
      final active = label == current;
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: active
            ? BoxDecoration(gradient: p.isDark ? p.primary : null, color: p.isDark ? null : p.navActive, borderRadius: BorderRadius.circular(HtRadius.pill))
            : null,
        child: Row(children: [
          Icon(icon, size: 20, color: active ? p.onNavActive : p.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: HtType.bodyStrong(active ? p.onNavActive : p.textPrimary).copyWith(fontSize: 13.5))),
          if (count != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: active ? Colors.black.withValues(alpha: 0.15) : p.accentSoft, borderRadius: BorderRadius.circular(HtRadius.pill)),
              child: Text('$count', style: HtType.smallStrong(active ? p.onNavActive : p.accentSoftText).copyWith(fontSize: 11)),
            ),
        ]),
      );
    }

    return Container(
      width: 256,
      decoration: BoxDecoration(color: p.isDark ? p.backgroundDeep : p.surface, border: Border(right: BorderSide(color: p.border))),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          HtIconCircle(icon: Icons.verified_user_outlined, fill: p.isDark ? p.surface : p.accentSoft, iconColor: p.isDark ? p.accent : p.accentStrong),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('HandyTrust', style: HtType.brand(p.isDark ? p.textPrimary : p.accentStrong).copyWith(fontSize: 17)),
            Text('ADMIN', style: HtType.caps(p.textMuted).copyWith(fontSize: 10)),
          ]),
        ]),
        const SizedBox(height: 24),
        for (final g in adminNavGroups) ...[
          Padding(padding: const EdgeInsets.only(left: 14, bottom: 6, top: 6), child: Text(g.label.toUpperCase(), style: HtType.caps(p.textMuted).copyWith(fontSize: 10))),
          for (final it in g.items) item(it.$1, it.$2, it.$3),
        ],
        const Spacer(),
        Divider(color: p.border),
        item(Icons.settings_outlined, 'Settings', null),
      ]),
    );
  }
}

/// Admin frame: sidebar + top bar + content (+ optional right detail panel)
/// on wide screens; top bar with menu + stacked content on narrow screens.
class AdminFrame extends StatelessWidget {
  const AdminFrame({super.key, required this.section, required this.title, this.subtitle, required this.children, this.panel, this.overlay, this.alerts = 3});
  final String section;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? panel;
  final Widget? overlay;
  final int alerts;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final topBar = Container(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 18 : 10, wide ? 28 : 16, wide ? 18 : 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: Row(children: [
        if (!wide) ...[const HtIconCircle(icon: Icons.menu_rounded, tooltip: 'Menu'), const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: wide ? HtType.screenTitle(p.textPrimary).copyWith(fontSize: 24) : HtType.headerTitle(p.textPrimary)),
            if (subtitle != null && wide) Text(subtitle!, style: HtType.small(p.textSecondary)),
          ]),
        ),
        if (wide) ...[
          SizedBox(width: 280, child: HtFilterBar(hint: 'Search users, jobs, references…')),
          const SizedBox(width: 12),
        ] else ...[
          const HtIconCircle(icon: Icons.search_rounded, tooltip: 'Search'),
          const SizedBox(width: 8),
        ],
        HtIconCircle(icon: Icons.notifications_none_rounded, badge: alerts > 0, tooltip: 'Alerts'),
        const SizedBox(width: 8),
        HtIconCircle(icon: p.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, tooltip: 'Theme'),
        if (wide) ...[const SizedBox(width: 12), HtSecondaryButton(label: 'Back to app', icon: Icons.open_in_new_rounded, onPressed: () {}, dense: true)],
      ]),
    );
    final content = ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.all(wide ? 28 : 16),
      children: children,
    );
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: p.background,
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: Row(children: [
            if (wide) HtSideNav(current: section),
            Expanded(child: Column(children: [topBar, Expanded(child: content)])),
            if (panel != null && wide)
              Container(
                width: 420,
                decoration: BoxDecoration(color: p.surface, border: Border(left: BorderSide(color: p.border))),
                child: ListView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(24), children: [panel!]),
              ),
          ]),
        ),
        if (wide)
          const Positioned(bottom: 12, right: 16, child: PreviewTag())
        else
          Positioned(top: top / 2 - 9, right: 0, left: 0, child: const Center(child: PreviewTag())),
        if (overlay != null) ...[
          Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: p.isDark ? 0.6 : 0.35))),
          Center(child: SizedBox(width: wide ? 520 : MediaQuery.sizeOf(context).width - 24, child: overlay)),
        ],
      ]),
    );
  }
}

/// Admin dialog surface (centred on wide, full-width on narrow).
class HtDialogCard extends StatelessWidget {
  const HtDialogCard({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.card), border: Border.all(color: p.border)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: HtType.sectionTitle(p.textPrimary)),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }
}

/// Section card with title (admin).
Widget htPanel(BuildContext context, String title, List<Widget> children, {String? trailing, String? badge}) {
  return HtCard(
    radius: HtRadius.inner,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      HtSectionHeader(title: title, trailing: trailing, onTrailing: trailing == null ? null : () {}, badge: badge),
      const SizedBox(height: 8),
      ...children,
    ]),
  );
}

/// Danger-tone button for destructive actions.
class HtDangerButton extends StatelessWidget {
  const HtDangerButton({super.key, required this.label, this.icon});
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      height: 46,
      decoration: BoxDecoration(color: p.dangerSoft, borderRadius: BorderRadius.circular(HtRadius.pill), border: Border.all(color: p.danger.withValues(alpha: 0.4))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ...[Icon(icon, size: 18, color: p.danger), const SizedBox(width: 8)],
        Text(label, style: HtType.bodyStrong(p.danger).copyWith(fontSize: 13.5)),
      ]),
    );
  }
}

/// Grid of widgets with a fixed column count.
Widget htGrid(List<Widget> items, {required int columns, double gap = 14}) {
  final rows = <Widget>[];
  for (var i = 0; i < items.length; i += columns) {
    rows.add(Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = 0; j < columns; j++) ...[
            if (j > 0) SizedBox(width: gap),
            Expanded(child: i + j < items.length ? items[i + j] : const SizedBox()),
          ],
        ]),
      ),
    ));
  }
  return Column(children: rows);
}
