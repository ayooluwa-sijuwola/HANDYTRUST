import 'package:flutter/material.dart';
import '../theme/app_design_system.dart';

enum _SnackType { success, error, warning, info }

void showSuccessSnackbar(BuildContext context, String message,
    {String? actionLabel, VoidCallback? onAction}) {
  _show(context, message, _SnackType.success,
      actionLabel: actionLabel, onAction: onAction);
}

void showErrorSnackbar(BuildContext context, String message,
    {VoidCallback? onRetry}) {
  _show(context, message, _SnackType.error,
      actionLabel: onRetry != null ? 'Retry' : null, onAction: onRetry);
}

void showWarningSnackbar(BuildContext context, String message) {
  _show(context, message, _SnackType.warning);
}

void showInfoSnackbar(BuildContext context, String message) {
  _show(context, message, _SnackType.info);
}

void _show(
  BuildContext context,
  String message,
  _SnackType type, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final (bg, fg, icon, iconBg) = switch (type) {
    _SnackType.success => (
        isDark ? const Color(0xFF14532D) : const Color(0xFF166534),
        const Color(0xFFDCFCE7),
        Icons.check_circle_rounded,
        const Color(0xFF22C55E),
      ),
    _SnackType.error => (
        isDark ? const Color(0xFF7F1D1D) : const Color(0xFF991B1B),
        const Color(0xFFFEE2E2),
        Icons.error_rounded,
        const Color(0xFFEF4444),
      ),
    _SnackType.warning => (
        isDark ? const Color(0xFF78350F) : const Color(0xFF92400E),
        const Color(0xFFFEF3C7),
        Icons.warning_rounded,
        const Color(0xFFF59E0B),
      ),
    _SnackType.info => (
        isDark ? const Color(0xFF1E3A8A) : const Color(0xFF1E40AF),
        const Color(0xFFDBEAFE),
        Icons.info_rounded,
        const Color(0xFF3B82F6),
      ),
  };

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      elevation: 0,
      duration: const Duration(seconds: 4),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.snackbar,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconBg, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: fg,
                  height: 1.4,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  onAction();
                },
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: iconBg,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
