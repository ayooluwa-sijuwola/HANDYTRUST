import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Dark-premium SaaS palette scoped to the admin dashboard only — the rest
/// of the app keeps its green/blue [AppColors] theme. Derived from
/// [ThemeMode] so the existing theme toggle still does something real here:
/// dark mode matches the reference design exactly, light mode reuses the
/// same structure (purple/indigo accents, rounded glass cards) on a light
/// base so the toggle isn't a no-op.
class AdminPalette {
  final bool isDark;

  const AdminPalette._(this.isDark);

  factory AdminPalette.of(ThemeMode mode) =>
      AdminPalette._(mode == ThemeMode.dark);

  // Backgrounds
  Color get bg0 => isDark ? const Color(0xFF0B1020) : const Color(0xFFF3F4FA);
  Color get bg1 => isDark ? const Color(0xFF111827) : const Color(0xFFFFFFFF);
  Color get bg2 => isDark ? const Color(0xFF151A2D) : const Color(0xFFF8F8FD);
  Color get card => isDark ? const Color(0xFF151A2D) : const Color(0xFFFFFFFF);

  // Borders / shadows
  Color get border => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : const Color(0xFFE5E7F5);
  Color get borderStrong => isDark
      ? Colors.white.withValues(alpha: 0.10)
      : const Color(0xFFD8DAF0);

  // Text
  Color get textPrimary =>
      isDark ? Colors.white : const Color(0xFF15172B);
  Color get textSecondary =>
      isDark ? const Color(0xFFA1A6C4) : const Color(0xFF6B6F8C);
  Color get textTertiary =>
      isDark ? const Color(0xFF6B7094) : const Color(0xFF9C9FBD);

  // Accents — the 4 semantic colors derive from AppColors (single source
  // of truth, per 02-design-system-v2.md §7/redesign/v2/08-admin.md §1)
  // rather than re-typing the same hex values, so a future brand-color
  // change can't silently fail to propagate here. Verified byte-identical
  // to AppColors at the time of this refactor: green=primary, red=error,
  // amber=warning, blue=accent. The other 4 have no consumer-app
  // equivalent and stay as genuinely admin-exclusive tokens.
  static Color get green => AppColors.primary;
  static Color get red => AppColors.error;
  static Color get amber => AppColors.warning;
  static Color get blue => AppColors.accent;
  static const Color purple = Color(0xFF8B5CF6);
  static const Color indigo = Color(0xFF6366F1);
  static const Color pink = Color(0xFFEC4899);
  static const Color cyan = Color(0xFF06B6D4);

  static const LinearGradient purpleIndigoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [purple, indigo],
  );

  // Borderless per redesign/v2/08-admin.md §1 — extends the app-wide
  // card-language consistency change to admin too; shadow-based
  // separation (already present) is kept unchanged.
  BoxDecoration cardDecoration({double radius = 20}) => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: indigo.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
      );
}
