import 'package:flutter/material.dart';

/// Shows a floating premium error snackbar.
/// [onRetry] adds an action link, labeled "Retry" by default — pass
/// [actionLabel] to relabel it for a different action (e.g. "Open Settings").
void showErrorSnackbar(BuildContext context, String message,
    {VoidCallback? onRetry, String actionLabel = 'Retry'}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bg = isDark ? const Color(0xFF7F1D1D) : const Color(0xFF991B1B);
  const fg = Color(0xFFFEE2E2);
  const iconColor = Color(0xFFEF4444);

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
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x28000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.error_rounded, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: fg,
                  height: 1.4,
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  onRetry();
                },
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
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
