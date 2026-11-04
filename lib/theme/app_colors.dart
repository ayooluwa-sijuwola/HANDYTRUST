import 'package:flutter/material.dart';

abstract final class AppColors {
  // Brand Primary — Trust Green
  static const Color primary = Color(0xFF22C55E);
  static const Color primaryLight = Color(0xFF4ADE80);
  static const Color primaryDark = Color(0xFF16A34A);
  static const Color primarySurface = Color(0xFFDCFCE7);

  // Accent — Electric Blue
  static const Color accent = Color(0xFF3B82F6);
  static const Color accentLight = Color(0xFF60A5FA);
  static const Color accentSurface = Color(0xFFEFF6FF);

  // Escrow-specific
  static const Color escrowLocked = Color(0xFF22C55E);
  static const Color escrowPending = Color(0xFFF59E0B);
  static const Color escrowReleased = Color(0xFF3B82F6);

  // Semantic
  static const Color error = Color(0xFFEF4444);
  static const Color errorSurface = Color(0xFFFEF2F2);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSurface = Color(0xFFFFFBEB);
  static const Color success = Color(0xFF22C55E);

  // Light mode neutrals
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFF1F5F9);

  // Light mode text
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textInverse = Color(0xFFFFFFFF);

  // Chat bubbles — pixel-matched to Stitch's chat screen: sent bubbles are
  // solid black, not the app's Trust Green, a deliberate deviation on this
  // one surface.
  static const Color bubbleSent = Color(0xFF000000);
  static const Color bubbleReceived = Color(0xFFF1F5F9);

  // Status chips
  static const Color statusRequested = Color(0xFF94A3B8);
  static const Color statusMatched = Color(0xFF8B5CF6);
  static const Color statusInChat = Color(0xFF3B82F6);
  static const Color statusEscrowLocked = Color(0xFF22C55E);
  static const Color statusInProgress = Color(0xFFF59E0B);
  static const Color statusSubmitted = Color(0xFF3B82F6);
  static const Color statusCompleted = Color(0xFF22C55E);
  static const Color statusDisputed = Color(0xFFEF4444);
  static const Color statusResolved = Color(0xFF94A3B8);

  // Rating
  static const Color ratingGold = Color(0xFFF59E0B);

  // Shimmer (light)
  static const Color shimmerBase = Color(0xFFE2E8F0);
  static const Color shimmerHighlight = Color(0xFFF8FAFC);

  // Rising Professional badge
  static const Color risingBadge = Color(0xFF8B5CF6);
  static const Color risingBadgeSurface = Color(0xFFF5F3FF);

  // Trust tier badges
  static const Color trustElite = Color(0xFFF59E0B);
  static const Color trustEliteSurface = Color(0xFFFFFBEB);
  static const Color trustTrusted = Color(0xFF22C55E);
  static const Color trustTrustedSurface = Color(0xFFDCFCE7);

  // Stitch design-system additions — "commitment" surfaces used on top of
  // either theme (not theme-dependent, unlike the palette above): a fixed
  // near-black pill for high-commitment actions (Lock Funds in Escrow, Post
  // Job, Book Now) distinct from the Trust Green everyday primary, and a
  // fixed navy card surface (TrustScore-style cards) that stays dark
  // regardless of light/dark app theme.
  static const Color ink = Color(0xFF111827);
  static const Color onInk = Color(0xFFFFFFFF);
  static const Color navy = Color(0xFF0F172A);
  static const Color navySurface = Color(0xFF1E293B);
  static const Color onNavy = Color(0xFFFFFFFF);
  static const Color onNavySecondary = Color(0xFF94A3B8);

  // Dark mode palette — a 4-step elevation ladder (background < surface <
  // surfaceElevated < surfaceVariant is NOT a strict lightness ordering;
  // surfaceVariant is a distinct *tint* for inset/alternate fills like chip
  // backgrounds and input fields, while surfaceElevated is the "raised
  // above a card" tier for dialogs/sheets/popovers). darkBorder and
  // darkBorderLight were previously identical to darkSurfaceVariant and
  // darkSurface respectively — an invisible-border bug where any border
  // drawn in the "border" color against a surfaceVariant-filled element
  // (or "borderLight" against a surface-filled one) had zero contrast.
  // Both are now distinct from every fill tier they're likely to sit on.
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkSurfaceElevated = Color(0xFF25324A);
  static const Color darkSurfaceVariant = Color(0xFF334155);
  static const Color darkBorder = Color(0xFF44536D);
  static const Color darkBorderLight = Color(0xFF29374C);

  // Dark mode text — darkTextTertiary replaces the old inline 0xFF64748B
  // used for tertiary text (timestamps, hint labels, unselected nav):
  // that value measured ~3:1 against both darkBackground and darkSurface,
  // below the 4.5:1 WCAG AA threshold for normal text. The old value is
  // kept below as darkDisabled, for genuinely disabled/decorative UI where
  // sub-AA contrast is expected and acceptable — not for anything meant
  // to be read.
  static const Color darkTextTertiary = Color(0xFF8A97AE);
  static const Color darkDisabled = Color(0xFF64748B);

  // Dark-mode-specific "commitment" tones. AppColors.ink/navy below are
  // intentionally fixed across themes for their original purpose (a bold
  // near-black/navy accent that pops against a *light* page) — but that
  // fixed value collides almost exactly with darkBackground/darkSurface,
  // making CommitButton, TrustScoreCard, and the selected PillTabSelector
  // pill nearly invisible in dark mode. These give dark mode its own
  // raised, distinguishable version of the same idea instead of reusing
  // the light-mode literal.
  static const Color darkInk = Color(0xFF26344C);
  static const Color darkNavy = Color(0xFF1C2942);
  static const Color darkNavySurface = Color(0xFF16223A);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
  );

  static const LinearGradient darkHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0xCC000000)],
  );

  static const LinearGradient serviceHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF166534), Color(0xFF22C55E)],
  );
}
