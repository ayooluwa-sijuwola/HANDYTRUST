import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_theme.dart';

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 16);
  static const EdgeInsets cardPadding = EdgeInsets.all(16);
  static const EdgeInsets chipPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 6);
}

abstract final class AppRadius {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double full = 100;

  static BorderRadius get cardBorderRadius =>
      BorderRadius.circular(xl);
  static BorderRadius get buttonBorderRadius =>
      BorderRadius.circular(md);
  static BorderRadius get chipBorderRadius =>
      BorderRadius.circular(full);
  static BorderRadius get inputBorderRadius =>
      BorderRadius.circular(md);
}

abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> cardDark = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> floatingNav = [
    BoxShadow(
      color: Color(0x28000000),
      blurRadius: 24,
      spreadRadius: 0,
      offset: Offset(0, -4),
    ),
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> floatingNavDark = [
    BoxShadow(
      color: Color(0x60000000),
      blurRadius: 24,
      spreadRadius: 0,
      offset: Offset(0, -4),
    ),
  ];

  static const List<BoxShadow> button = [
    BoxShadow(
      color: Color(0x3322C55E),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> snackbar = [
    BoxShadow(
      color: Color(0x28000000),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
}

abstract final class AppGradients {
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
  );

  static const LinearGradient darkBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0F172A), Color(0xFF0B1120)],
  );

  // Pale mint-to-white wash for the Wallet/Earnings balance card — pixel-
  // matched to Stitch's light green card (distinct from serviceHero's
  // saturated green, which is a different, bolder use elsewhere).
  static const LinearGradient walletBalance = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFDCFCE7), Color(0xFFF0FDF4)],
  );

  static const LinearGradient serviceHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF166534), Color(0xFF22C55E)],
    stops: [0.0, 1.0],
  );

  static const LinearGradient cardOverlay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0xCC000000)],
  );

  static const LinearGradient accentBlue = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
  );

  static const LinearGradient warmGold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
  );

  static const LinearGradient glassDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1AFFFFFF), Color(0x08FFFFFF)],
  );

  static const LinearGradient statsCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
  );
}

abstract final class AppAnimations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration page = Duration(milliseconds: 300);

  static const Curve defaultCurve = Curves.easeOutCubic;
  static const Curve bounceCurve = Curves.elasticOut;
  static const Curve sharpCurve = Curves.easeInOut;
}

/// Reusable card decoration that automatically adapts to light/dark.
/// Borderless, gray-fill per 02-design-system-v2.md §9.2 — matches the
/// cardTheme change in app_theme.dart; kept as a separate helper for
/// decorations built outside Flutter's Card widget (e.g. Container-based
/// cards), so both paths stay visually identical.
BoxDecoration appCardDecoration(BuildContext context, {
  bool elevated = false,
  Color? color,
  double radius = 20,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // A black box-shadow reads as essentially invisible against a page that's
  // already near-black, so "elevated" in dark mode leans on a lighter fill
  // tier (surfaceElevated) rather than relying on the shadow to do the work
  // — the shadow is kept too, but only as a secondary cue.
  final bg = color ??
      (isDark
          ? (elevated ? AppColors.darkSurfaceElevated : AppColors.darkSurface)
          : AppColors.surfaceVariant);
  return BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: elevated
        ? (isDark ? AppShadows.cardDark : AppShadows.card)
        : null,
  );
}

/// Stitch-derived headline styles — heavier weight and larger size than the
/// existing headlineLarge/displayMedium theme styles, for page-title text
/// like "My Bookings" / "Find your expert helper". Additive: the existing
/// TextTheme styles are untouched, and every screen in this codebase sets
/// text style inline rather than via Theme.of(context).textTheme, so this
/// follows that same convention rather than introducing a second one.
abstract final class AppTextStyles {
  static const TextStyle pageHeadline = TextStyle(
    fontFamily: 'Inter',
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    height: 1.1,
  );

  static const TextStyle pageSubtitle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
}

/// Black "commitment" pill button — reserved for high-commitment actions
/// (Lock Funds in Escrow, Post Job, Book Now), distinct from the Trust Green
/// primary used for everyday actions. Deliberately a separate widget rather
/// than a change to ElevatedButtonTheme, since that theme is still correct
/// for the vast majority of buttons in the app — this is an additive
/// second primary, not a replacement.
class CommitButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const CommitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: context.colors.ink,
          foregroundColor: context.colors.onInk,
          disabledBackgroundColor: context.colors.ink.withValues(alpha: 0.5),
          // A hairline light border, dark mode only: context.colors.ink is
          // already lifted above the page background there (see
          // app_colors.dart), but a "raised dark" button on a dark page
          // still benefits from an unambiguous edge — light mode's ink
          // button already has all the contrast it needs against a light
          // page and stays borderless.
          side: isDark
              ? BorderSide(color: Colors.white.withValues(alpha: 0.10))
              : BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          elevation: 0,
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: context.colors.onInk,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: context.colors.onInk),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.colors.onInk,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Premium badge widget used across artisan cards and status chips.
class AppBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color backgroundColor;
  final IconData? icon;

  const AppBadge({
    super.key,
    required this.label,
    required this.color,
    required this.backgroundColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}
