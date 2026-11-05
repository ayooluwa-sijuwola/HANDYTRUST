import 'package:flutter/material.dart';

import '../theme/ht_theme.dart';
import 'ht_format.dart';

// ─── Page background ────────────────────────────────────────────────────────

/// Page background with the reference's top glow (dark: olive radial glow;
/// light: pale-lime wash). [deep] selects the near-black Discovery/profile
/// page colour in dark mode.
class HtBackground extends StatelessWidget {
  const HtBackground({super.key, required this.child, this.deep = false, this.glow = true});
  final Widget child;
  final bool deep;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final base = deep ? p.backgroundDeep : p.background;
    return DecoratedBox(
      decoration: BoxDecoration(color: base),
      child: Stack(
        children: [
          if (glow)
            Positioned(
              top: -120,
              left: -60,
              right: -60,
              height: 640,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 1.0,
                      colors: [p.glow, base.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

// ─── Icon circles / headers ─────────────────────────────────────────────────

class HtIconCircle extends StatelessWidget {
  const HtIconCircle({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 40,
    this.fill,
    this.iconColor,
    this.badge = false,
    this.tooltip,
    this.square = false,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? fill;
  final Color? iconColor;
  final bool badge;
  final String? tooltip;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill ?? (p.isDark ? p.surface : p.surface),
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(size * 0.32) : null,
        border: Border.all(color: p.border),
        boxShadow: p.isDark ? null : p.cardShadow,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: size * 0.48, color: iconColor ?? p.textPrimary),
          if (badge)
            Positioned(
              top: size * 0.22,
              right: size * 0.24,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle, border: Border.all(color: fill ?? p.surface, width: 1.5)),
              ),
            ),
        ],
      ),
    );
    final child = onTap == null
        ? circle
        : Semantics(
            button: true,
            label: tooltip,
            child: InkResponse(onTap: onTap, radius: size / 2 + 4, child: circle),
          );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// App header used on tab screens: shield logo tile, brand, optional
/// actions (search / bell / avatar) — references 4, 5, 6, 19, 21, 22.
class HtAppHeader extends StatelessWidget {
  const HtAppHeader({super.key, this.subtitle, this.actions = const [], this.title = 'HandyTrust'});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 8, HtSpace.gutter, 8),
      child: Row(
        children: [
          HtIconCircle(
            icon: Icons.verified_user_outlined,
            size: 40,
            fill: p.isDark ? p.surface : p.accentSoft,
            iconColor: p.isDark ? p.accent : p.accentStrong,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: HtType.brand(p.isDark ? p.textPrimary : p.accentStrong), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null) Text(subtitle!, style: HtType.small(p.textSecondary)),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 10), a],
        ],
      ),
    );
  }
}

/// Screen header: round back button, title, optional trailing widget
/// (references 3, 7, 10, 11, 12, 17, 18, 23, 24).
class HtScreenHeader extends StatelessWidget {
  const HtScreenHeader({super.key, required this.title, this.onBack, this.trailing, this.center = true, this.subtitle});
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final titleW = Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: HtType.headerTitle(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (subtitle != null) Text(subtitle!, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 8, HtSpace.gutter, 8),
      child: Row(
        children: [
          HtIconCircle(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(child: center ? Center(child: titleW) : titleW),
          const SizedBox(width: 12),
          trailing ?? const SizedBox(width: 40),
        ],
      ),
    );
  }
}

// ─── Buttons ────────────────────────────────────────────────────────────────

/// Gradient pill CTA (references 2, 3, 10, 13, 14, 16–18, 23).
class HtPrimaryButton extends StatelessWidget {
  const HtPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leadingIcon,
    this.loading = false,
    this.height = 52,
    this.expand = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? leadingIcon;
  final bool loading;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final enabled = onPressed != null && !loading;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: p.onPrimary))
        else ...[
          if (leadingIcon != null) ...[Icon(leadingIcon, size: 20, color: p.onPrimary), const SizedBox(width: 10)],
          Flexible(child: Text(label, style: HtType.button(p.onPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (icon != null) ...[const SizedBox(width: 10), Icon(icon, size: 20, color: p.onPrimary)],
        ],
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: expand ? 0 : 22),
        decoration: BoxDecoration(
          gradient: p.primary,
          borderRadius: BorderRadius.circular(HtRadius.pill),
          boxShadow: enabled ? [BoxShadow(color: p.primaryGlow, blurRadius: 24, offset: const Offset(0, 6))] : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(HtRadius.pill),
            onTap: enabled ? onPressed : null,
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}

/// Neutral pill (e.g. "View Details", "Withdraw"-style secondary).
class HtSecondaryButton extends StatelessWidget {
  const HtSecondaryButton({super.key, required this.label, required this.onPressed, this.icon, this.height = 42, this.dense = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Material(
      color: p.isDark ? p.surfaceRaised : p.surface,
      shape: StadiumBorder(side: BorderSide(color: p.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: dense ? 16 : 22),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: dense ? 12.5 : 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (icon != null) ...[const SizedBox(width: 6), Icon(icon, size: 18, color: p.textPrimary)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small gradient pill ("View", "Post Job").
class HtSmallPrimaryButton extends StatelessWidget {
  const HtSmallPrimaryButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        gradient: p.primary,
        borderRadius: BorderRadius.circular(HtRadius.pill),
        boxShadow: [BoxShadow(color: p.primaryGlow, blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(HtRadius.pill),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: HtType.bodyStrong(p.onPrimary)),
                if (icon != null) ...[const SizedBox(width: 6), Icon(icon, size: 17, color: p.onPrimary)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Chips, tabs, pills ─────────────────────────────────────────────────────

class HtChip extends StatelessWidget {
  const HtChip({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.count});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final fg = selected ? p.onChipActive : p.onChipInactive;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? p.chipActive : p.chipInactive,
        shape: StadiumBorder(side: BorderSide(color: selected ? Colors.transparent : p.border)),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 7)],
                Text(label, style: HtType.bodyStrong(fg).copyWith(fontSize: 12.5)),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected ? Colors.black.withValues(alpha: p.isDark ? 0.18 : 0.16) : p.surfaceRaised,
                      borderRadius: BorderRadius.circular(HtRadius.pill),
                    ),
                    child: Text('$count', style: HtType.smallStrong(fg)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum HtTone { neutral, accent, success, warning, danger }

class HtStatusPill extends StatelessWidget {
  const HtStatusPill({super.key, required this.label, this.tone = HtTone.neutral, this.icon, this.dot = false, this.maxLines = 1});
  final String label;

  /// Narrow layouts (e.g. board columns) may allow a second line.
  final int maxLines;
  final HtTone tone;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final (bg, fg) = switch (tone) {
      HtTone.neutral => (p.surfaceRaised, p.textSecondary),
      HtTone.accent => (p.accentSoft, p.accentSoftText),
      HtTone.success => (p.successSoft, p.success),
      HtTone.warning => (p.warningSoft, p.warning),
      HtTone.danger => (p.dangerSoft, p.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(HtRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)), const SizedBox(width: 7)],
          if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
          Flexible(child: Text(label, style: HtType.smallStrong(fg), maxLines: maxLines, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// "ID Verified" badge — only rendered for a verification status the
/// backend actually records (id_verified / trusted).
class HtVerifiedBadge extends StatelessWidget {
  const HtVerifiedBadge({super.key, this.label = 'ID Verified'});
  final String label;
  @override
  Widget build(BuildContext context) => HtStatusPill(label: label, tone: HtTone.success, icon: Icons.verified_outlined);
}

/// Horizontally scrolling segmented tabs with counts (references 4, 19).
class HtSegmentedTabs extends StatelessWidget {
  const HtSegmentedTabs({super.key, required this.labels, required this.counts, required this.selected, required this.onSelected});
  final List<String> labels;
  final List<int?> counts;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            HtChip(label: labels[i], count: counts[i], selected: i == selected, onTap: () => onSelected(i)),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

// ─── Cards ──────────────────────────────────────────────────────────────────

class HtCard extends StatelessWidget {
  const HtCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.radius = HtRadius.card, this.color, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final box = Container(
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.border),
        boxShadow: p.cardShadow,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return box;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: box),
    );
  }
}

/// Icon tile + title + text banner (escrow notes, guarantees).
class HtInfoBanner extends StatelessWidget {
  const HtInfoBanner({super.key, required this.icon, required this.text, this.title, this.tone = HtTone.accent, this.trailing});
  final IconData icon;
  final String? title;
  final String text;
  final HtTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final (bg, fg) = switch (tone) {
      HtTone.success => (p.successSoft, p.success),
      HtTone.warning => (p.warningSoft, p.warning),
      HtTone.danger => (p.dangerSoft, p.danger),
      HtTone.neutral => (p.surface, p.textSecondary),
      HtTone.accent => (p.isDark ? p.accentSoft : p.accentSoft, p.accentSoftText),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HtRadius.inner),
        border: Border.all(color: p.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: fg.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: HtType.bodyStrong(p.isDark || tone != HtTone.accent ? fg : p.textPrimary)),
                Text(text, style: HtType.small(p.isDark ? p.textSecondary : p.textSecondary)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class HtStatTile extends StatelessWidget {
  const HtStatTile({super.key, required this.value, required this.label, this.icon, this.valueColor});
  final String value;
  final String label;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(HtRadius.inner),
        border: Border.all(color: p.border),
        boxShadow: p.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20, color: p.isDark ? const Color(0xFFF5B83D) : p.accentStrong), const SizedBox(width: 4)],
              Flexible(child: Text(value, style: HtType.cardTitle(valueColor ?? p.textPrimary).copyWith(fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: HtType.small(p.textSecondary), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class HtSectionHeader extends StatelessWidget {
  const HtSectionHeader({super.key, required this.title, this.trailing, this.onTrailing, this.badge, this.caps = false});
  final String title;
  final String? trailing;
  final VoidCallback? onTrailing;
  final String? badge;
  final bool caps;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Row(
      children: [
        // Title + badge share one Expanded so the title can use all the free
        // width (a Flexible title next to a Spacer would get only half).
        Expanded(
          child: Row(
            children: [
              Flexible(child: Text(caps ? title.toUpperCase() : title, style: caps ? HtType.caps(p.textPrimary).copyWith(fontSize: 11) : HtType.sectionTitle(p.textPrimary))),
              if (badge != null) ...[
                const SizedBox(width: 10),
                HtStatusPill(label: badge!, tone: p.isDark ? HtTone.neutral : HtTone.accent),
              ],
            ],
          ),
        ),
        if (trailing != null)
          InkWell(
            onTap: onTrailing,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(trailing!, style: HtType.smallStrong(p.accent).copyWith(fontSize: 12)),
                  if (onTrailing != null) Icon(Icons.chevron_right_rounded, size: 18, color: p.accent),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Settings/menu row (references 6, 22).
class HtMenuRow extends StatelessWidget {
  const HtMenuRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.showChevron = true, this.destructive = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final fg = destructive ? p.danger : p.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: destructive ? p.dangerSoft : (p.isDark ? p.surfaceRaised : p.accentSoft),
                shape: p.isDark ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: p.isDark ? BorderRadius.circular(12) : null,
              ),
              child: Icon(icon, size: 21, color: destructive ? p.danger : (p.isDark ? p.accent : p.accentStrong)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: HtType.bodyStrong(fg).copyWith(fontSize: 14)),
                  if (subtitle != null) Text(subtitle!, style: HtType.small(p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (showChevron && onTap != null) ...[const SizedBox(width: 6), Icon(Icons.chevron_right_rounded, color: p.textMuted)],
          ],
        ),
      ),
    );
  }
}

// ─── Avatar ─────────────────────────────────────────────────────────────────

/// Initials (or photo) avatar with optional online dot and lime ring.
class HtAvatar extends StatelessWidget {
  const HtAvatar({super.key, required this.name, this.imageUrl, this.size = 52, this.online = false, this.ring = false});
  final String? name;
  final String? imageUrl;
  final double size;
  final bool online;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: p.avatarFill,
              shape: BoxShape.circle,
              border: ring ? Border.all(color: p.accent, width: size > 80 ? 3 : 2) : Border.all(color: p.border),
              image: hasImage ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover) : null,
            ),
            alignment: Alignment.center,
            child: hasImage
                ? null
                : Text(HtFormat.initials(name),
                    style: TextStyle(fontFamily: HtType.display, fontWeight: FontWeight.w800, fontSize: size * 0.34, color: p.avatarText)),
          ),
          if (online)
            Positioned(
              right: size * 0.02,
              bottom: size * 0.02,
              child: Container(
                width: size * 0.24,
                height: size * 0.24,
                decoration: BoxDecoration(
                  color: p.isDark ? const Color(0xFF27C485) : const Color(0xFF16803C),
                  shape: BoxShape.circle,
                  border: Border.all(color: p.isDark ? p.backgroundDeep : p.surface, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Lifecycle stepper ──────────────────────────────────────────────────────

class HtLifecycleStep {
  const HtLifecycleStep(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Escrow lifecycle stepper (references 4, 10, 19). [current] is the
/// zero-based index of the active step; steps before it are complete.
class HtLifecycle extends StatelessWidget {
  const HtLifecycle({super.key, required this.steps, required this.current, this.allDone = false});
  final List<HtLifecycleStep> steps;
  final int current;
  final bool allDone;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: i == 0 ? const SizedBox() : Container(height: 3, color: i <= current || allDone ? p.accentStrong : p.border)),
                    _dot(p, i),
                    Expanded(child: i == steps.length - 1 ? const SizedBox() : Container(height: 3, color: i < current || allDone ? p.accentStrong : p.border)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(steps[i].label,
                    textAlign: TextAlign.center,
                    style: HtType.smallStrong(i == current && !allDone ? p.accent : (i < current || allDone ? p.textPrimary : p.textSecondary))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _dot(HtPalette p, int i) {
    final done = i < current || allDone;
    final active = i == current && !allDone;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: done || active ? (p.isDark ? p.accent : p.accentStrong) : (p.isDark ? p.surfaceRaised : p.surfaceRaised),
        shape: BoxShape.circle,
        border: active ? Border.all(color: (p.isDark ? p.accent : p.accentStrong).withValues(alpha: 0.35), width: 5, strokeAlign: BorderSide.strokeAlignOutside) : null,
      ),
      child: Icon(done ? Icons.check_rounded : steps[i].icon, size: 17, color: done || active ? (p.isDark ? p.onPrimary : Colors.white) : p.textSecondary),
    );
  }
}

// ─── Form fields ────────────────────────────────────────────────────────────

class HtFieldLabel extends StatelessWidget {
  const HtFieldLabel(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 6, bottom: 10, top: 22),
      child: Row(
        children: [
          Expanded(child: Text(text, style: HtType.label(p.textSecondary))),
          if (trailing != null) Text(trailing!, style: HtType.label(p.textSecondary)),
        ],
      ),
    );
  }
}

InputDecoration htInputDecoration(BuildContext context, {String? hint, Widget? suffix, Widget? prefix}) {
  final p = context.ht;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(HtRadius.input),
    borderSide: BorderSide(color: p.isDark ? Colors.transparent : p.border),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: HtType.body(p.textMuted),
    filled: true,
    fillColor: p.input,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(borderSide: BorderSide(color: p.accentStrong, width: 1.4)),
    errorBorder: border.copyWith(borderSide: BorderSide(color: p.danger)),
    focusedErrorBorder: border.copyWith(borderSide: BorderSide(color: p.danger, width: 1.4)),
    errorStyle: HtType.small(p.danger),
    suffixIcon: suffix,
    prefixIcon: prefix,
  );
}

// ─── State views ────────────────────────────────────────────────────────────

class HtLoadingView extends StatelessWidget {
  const HtLoadingView({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: p.accentStrong)),
            if (label != null) ...[const SizedBox(height: 14), Text(label!, style: HtType.small(p.textSecondary))],
          ],
        ),
      ),
    );
  }
}

class HtEmptyView extends StatelessWidget {
  const HtEmptyView({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: p.accentSoftText),
          ),
          const SizedBox(height: 16),
          Text(title, style: HtType.cardTitle(p.textPrimary), textAlign: TextAlign.center),
          if (message != null) ...[const SizedBox(height: 6), Text(message!, style: HtType.small(p.textSecondary), textAlign: TextAlign.center)],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

class HtErrorView extends StatelessWidget {
  const HtErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => HtEmptyView(
        icon: Icons.error_outline_rounded,
        title: 'Something went wrong',
        message: message,
        action: onRetry == null ? null : HtSecondaryButton(label: 'Try again', onPressed: onRetry, icon: Icons.refresh_rounded),
      );
}

/// Non-blocking feedback in the design's palette.
void htSnack(BuildContext context, String message, {bool error = false}) {
  final p = context.ht;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? p.danger : (p.isDark ? p.surfaceRaised : const Color(0xFF1F2417)),
      content: Text(message, style: HtType.small(Colors.white)),
    ));
}

/// Confirmation sheet in the design language for irreversible actions.
Future<bool> htConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final p = context.ht;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: p.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HtRadius.card))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: HtType.sectionTitle(p.textPrimary)),
            const SizedBox(height: 10),
            Text(message, style: HtType.body(p.textSecondary)),
            const SizedBox(height: 22),
            HtPrimaryButton(label: confirmLabel, onPressed: () => Navigator.of(ctx).pop(true)),
            const SizedBox(height: 10),
            Center(child: TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Cancel', style: HtType.bodyStrong(p.textSecondary)))),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}
