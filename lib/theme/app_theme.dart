import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color primary;
  final Color primaryDark;
  final Color primarySurface;
  final Color accent;
  final Color accentSurface;
  final Color error;
  final Color errorSurface;
  final Color warning;
  final Color warningSurface;
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceVariant;
  final Color border;
  final Color borderLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInverse;
  final Color disabled;
  final Color bubbleSent;
  final Color bubbleReceived;
  final Color statusRequested;
  final Color statusMatched;
  final Color statusInChat;
  final Color statusEscrowLocked;
  final Color statusInProgress;
  final Color statusSubmitted;
  final Color statusCompleted;
  final Color statusDisputed;
  final Color statusResolved;
  final Color ratingGold;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color risingBadge;
  final Color risingBadgeSurface;
  final Color trustElite;
  final Color trustEliteSurface;
  final Color trustTrusted;
  final Color trustTrustedSurface;
  // Escrow-specific — added per 02-design-system.md §2.2 Gap 1: these
  // existed only as raw AppColors constants with no dark-mode pair,
  // unlike every other semantic color in this extension. Closed here
  // while building the first real escrow-status UI (Wallet).
  final Color escrowLocked;
  final Color escrowPending;
  final Color escrowReleased;
  final Color escrowFailed;
  // Stitch design-system additions — fixed regardless of light/dark theme,
  // see app_colors.dart for rationale.
  final Color ink;
  final Color onInk;
  final Color navy;
  final Color navySurface;
  final Color onNavy;
  final Color onNavySecondary;

  const AppColorsExtension({
    required this.primary,
    required this.primaryDark,
    required this.primarySurface,
    required this.accent,
    required this.accentSurface,
    required this.error,
    required this.errorSurface,
    required this.warning,
    required this.warningSurface,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceVariant,
    required this.border,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.disabled,
    required this.bubbleSent,
    required this.bubbleReceived,
    required this.statusRequested,
    required this.statusMatched,
    required this.statusInChat,
    required this.statusEscrowLocked,
    required this.statusInProgress,
    required this.statusSubmitted,
    required this.statusCompleted,
    required this.statusDisputed,
    required this.statusResolved,
    required this.ratingGold,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.risingBadge,
    required this.risingBadgeSurface,
    required this.trustElite,
    required this.trustEliteSurface,
    required this.trustTrusted,
    required this.trustTrustedSurface,
    required this.escrowLocked,
    required this.escrowPending,
    required this.escrowReleased,
    required this.escrowFailed,
    required this.ink,
    required this.onInk,
    required this.navy,
    required this.navySurface,
    required this.onNavy,
    required this.onNavySecondary,
  });

  static const light = AppColorsExtension(
    primary: AppColors.primary,
    primaryDark: AppColors.primaryDark,
    primarySurface: AppColors.primarySurface,
    accent: AppColors.accent,
    accentSurface: AppColors.accentSurface,
    error: AppColors.error,
    errorSurface: AppColors.errorSurface,
    warning: AppColors.warning,
    warningSurface: AppColors.warningSurface,
    background: AppColors.background,
    surface: AppColors.surface,
    // Light mode has no prior elevated-surface concept — dialogs/sheets
    // already default to plain white, which is correct and unchanged.
    surfaceElevated: AppColors.surface,
    surfaceVariant: AppColors.surfaceVariant,
    border: AppColors.border,
    borderLight: AppColors.borderLight,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    textInverse: AppColors.textInverse,
    disabled: AppColors.textTertiary,
    bubbleSent: AppColors.bubbleSent,
    bubbleReceived: AppColors.bubbleReceived,
    statusRequested: AppColors.statusRequested,
    statusMatched: AppColors.statusMatched,
    statusInChat: AppColors.statusInChat,
    statusEscrowLocked: AppColors.statusEscrowLocked,
    statusInProgress: AppColors.statusInProgress,
    statusSubmitted: AppColors.statusSubmitted,
    statusCompleted: AppColors.statusCompleted,
    statusDisputed: AppColors.statusDisputed,
    statusResolved: AppColors.statusResolved,
    ratingGold: AppColors.ratingGold,
    shimmerBase: AppColors.shimmerBase,
    shimmerHighlight: AppColors.shimmerHighlight,
    risingBadge: AppColors.risingBadge,
    risingBadgeSurface: AppColors.risingBadgeSurface,
    trustElite: AppColors.trustElite,
    trustEliteSurface: AppColors.trustEliteSurface,
    trustTrusted: AppColors.trustTrusted,
    trustTrustedSurface: AppColors.trustTrustedSurface,
    escrowLocked: AppColors.escrowLocked,
    escrowPending: AppColors.escrowPending,
    escrowReleased: AppColors.escrowReleased,
    escrowFailed: AppColors.error,
    ink: AppColors.ink,
    onInk: AppColors.onInk,
    navy: AppColors.navy,
    navySurface: AppColors.navySurface,
    onNavy: AppColors.onNavy,
    onNavySecondary: AppColors.onNavySecondary,
  );

  static const dark = AppColorsExtension(
    primary: AppColors.primary,
    primaryDark: AppColors.primaryLight,
    primarySurface: Color(0xFF14532D),
    accent: AppColors.accentLight,
    accentSurface: Color(0xFF1E3A8A),
    error: Color(0xFFF87171),
    errorSurface: Color(0xFF7F1D1D),
    warning: Color(0xFFFBBF24),
    warningSurface: Color(0xFF78350F),
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceElevated: AppColors.darkSurfaceElevated,
    surfaceVariant: AppColors.darkSurfaceVariant,
    border: AppColors.darkBorder,
    borderLight: AppColors.darkBorderLight,
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    textTertiary: AppColors.darkTextTertiary,
    textInverse: AppColors.darkBackground,
    disabled: AppColors.darkDisabled,
    bubbleSent: AppColors.primary,
    bubbleReceived: AppColors.darkSurfaceVariant,
    statusRequested: Color(0xFF64748B),
    statusMatched: Color(0xFFA78BFA),
    statusInChat: Color(0xFF60A5FA),
    statusEscrowLocked: AppColors.primary,
    statusInProgress: Color(0xFFFBBF24),
    statusSubmitted: Color(0xFF60A5FA),
    statusCompleted: AppColors.primary,
    statusDisputed: Color(0xFFF87171),
    statusResolved: Color(0xFF64748B),
    ratingGold: Color(0xFFFBBF24),
    shimmerBase: AppColors.darkSurfaceVariant,
    shimmerHighlight: Color(0xFF475569),
    risingBadge: Color(0xFFC4B5FD),
    risingBadgeSurface: Color(0xFF4C1D95),
    trustElite: Color(0xFFFBBF24),
    trustEliteSurface: Color(0xFF78350F),
    trustTrusted: AppColors.primary,
    trustTrustedSurface: Color(0xFF14532D),
    escrowLocked: AppColors.primary,
    escrowPending: Color(0xFFFBBF24),
    escrowReleased: AppColors.accentLight,
    escrowFailed: Color(0xFFF87171),
    // Dark-specific raised tones — see app_colors.dart for why these can't
    // reuse the light-mode-fixed AppColors.ink/navy values here.
    ink: AppColors.darkInk,
    onInk: AppColors.onInk,
    navy: AppColors.darkNavy,
    navySurface: AppColors.darkNavySurface,
    onNavy: AppColors.onNavy,
    onNavySecondary: AppColors.onNavySecondary,
  );

  @override
  AppColorsExtension copyWith() => this;

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    Color m(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppColorsExtension(
      primary: m(primary, other.primary),
      primaryDark: m(primaryDark, other.primaryDark),
      primarySurface: m(primarySurface, other.primarySurface),
      accent: m(accent, other.accent),
      accentSurface: m(accentSurface, other.accentSurface),
      error: m(error, other.error),
      errorSurface: m(errorSurface, other.errorSurface),
      warning: m(warning, other.warning),
      warningSurface: m(warningSurface, other.warningSurface),
      background: m(background, other.background),
      surface: m(surface, other.surface),
      surfaceElevated: m(surfaceElevated, other.surfaceElevated),
      surfaceVariant: m(surfaceVariant, other.surfaceVariant),
      border: m(border, other.border),
      borderLight: m(borderLight, other.borderLight),
      textPrimary: m(textPrimary, other.textPrimary),
      textSecondary: m(textSecondary, other.textSecondary),
      textTertiary: m(textTertiary, other.textTertiary),
      textInverse: m(textInverse, other.textInverse),
      disabled: m(disabled, other.disabled),
      bubbleSent: m(bubbleSent, other.bubbleSent),
      bubbleReceived: m(bubbleReceived, other.bubbleReceived),
      statusRequested: m(statusRequested, other.statusRequested),
      statusMatched: m(statusMatched, other.statusMatched),
      statusInChat: m(statusInChat, other.statusInChat),
      statusEscrowLocked: m(statusEscrowLocked, other.statusEscrowLocked),
      statusInProgress: m(statusInProgress, other.statusInProgress),
      statusSubmitted: m(statusSubmitted, other.statusSubmitted),
      statusCompleted: m(statusCompleted, other.statusCompleted),
      statusDisputed: m(statusDisputed, other.statusDisputed),
      statusResolved: m(statusResolved, other.statusResolved),
      ratingGold: m(ratingGold, other.ratingGold),
      shimmerBase: m(shimmerBase, other.shimmerBase),
      shimmerHighlight: m(shimmerHighlight, other.shimmerHighlight),
      risingBadge: m(risingBadge, other.risingBadge),
      risingBadgeSurface: m(risingBadgeSurface, other.risingBadgeSurface),
      trustElite: m(trustElite, other.trustElite),
      trustEliteSurface: m(trustEliteSurface, other.trustEliteSurface),
      trustTrusted: m(trustTrusted, other.trustTrusted),
      trustTrustedSurface: m(trustTrustedSurface, other.trustTrustedSurface),
      escrowLocked: m(escrowLocked, other.escrowLocked),
      escrowPending: m(escrowPending, other.escrowPending),
      escrowReleased: m(escrowReleased, other.escrowReleased),
      escrowFailed: m(escrowFailed, other.escrowFailed),
      ink: m(ink, other.ink),
      onInk: m(onInk, other.onInk),
      navy: m(navy, other.navy),
      navySurface: m(navySurface, other.navySurface),
      onNavy: m(onNavy, other.onNavy),
      onNavySecondary: m(onNavySecondary, other.onNavySecondary),
    );
  }
}

extension AppColorsX on BuildContext {
  AppColorsExtension get colors =>
      Theme.of(this).extension<AppColorsExtension>() ?? AppColorsExtension.light;
}

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        extensions: const [AppColorsExtension.light],
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: AppColors.primarySurface,
          onPrimaryContainer: AppColors.primaryDark,
          secondary: AppColors.accent,
          onSecondary: Colors.white,
          secondaryContainer: AppColors.accentSurface,
          onSecondaryContainer: Color(0xFF1E3A8A),
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          surfaceContainerHighest: AppColors.surfaceVariant,
          onSurfaceVariant: AppColors.textSecondary,
          error: AppColors.error,
          onError: Colors.white,
          errorContainer: AppColors.errorSurface,
          onErrorContainer: Color(0xFF7F1D1D),
          outline: AppColors.border,
          outlineVariant: AppColors.borderLight,
          shadow: Color(0x1A000000),
        ),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.error, width: 1.5),
          ),
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
          hintStyle: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textTertiary,
            fontSize: 14,
          ),
        ),
        // Borderless, gray-fill cards — per 02-design-system-v2.md §9.2
        // (visual reference reset), superseding the earlier white-card
        // hairline-border pattern. surfaceVariant reads as a subtle gray
        // against the background's near-white, matching the reference's
        // card-vs-page separation.
        cardTheme: CardThemeData(
          color: AppColors.surfaceVariant,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          margin: EdgeInsets.zero,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfaceVariant,
          selectedColor: AppColors.primarySurface,
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textTertiary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.borderLight,
          thickness: 1,
          space: 1,
        ),
        // Explicit rather than left to the Material3 default — matches
        // that default exactly (AppColors.surface = white) so light mode
        // is unchanged; exists so the dark theme below can override it to
        // a properly elevated tone instead of inheriting the same default.
        dialogTheme: const DialogThemeData(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.textPrimary,
          contentTextStyle: const TextStyle(
            fontFamily: 'Inter',
            color: Colors.white,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.8,
          ),
          displayMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.4,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
          headlineSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          titleSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
          ),
          bodySmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          labelLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          labelSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
          ),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        extensions: const [AppColorsExtension.dark],
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFF14532D),
          onPrimaryContainer: Color(0xFFDCFCE7),
          secondary: AppColors.accentLight,
          onSecondary: AppColors.darkBackground,
          secondaryContainer: Color(0xFF1E3A8A),
          onSecondaryContainer: Color(0xFFDBEAFE),
          surface: AppColors.darkSurface,
          onSurface: Color(0xFFF8FAFC),
          surfaceContainerHighest: AppColors.darkSurfaceVariant,
          onSurfaceVariant: Color(0xFF94A3B8),
          error: Color(0xFFF87171),
          onError: Color(0xFF450A0A),
          errorContainer: Color(0xFF7F1D1D),
          onErrorContainer: Color(0xFFFEE2E2),
          outline: AppColors.darkBorder,
          outlineVariant: AppColors.darkBorderLight,
          shadow: Color(0x40000000),
        ),
        scaffoldBackgroundColor: AppColors.darkBackground,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkBackground,
          foregroundColor: Color(0xFFF8FAFC),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF8FAFC),
            letterSpacing: -0.3,
          ),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFF87171)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFFF87171), width: 1.5),
          ),
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFF94A3B8),
            fontSize: 14,
          ),
          hintStyle: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.darkTextTertiary,
            fontSize: 14,
          ),
        ),
        // Borderless per 02-design-system-v2.md §9.2 — darkSurface is
        // already visually distinct from darkBackground, so unlike light
        // mode this needed no color change, only the border removed.
        cardTheme: CardThemeData(
          color: AppColors.darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          margin: EdgeInsets.zero,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.darkSurfaceVariant,
          selectedColor: const Color(0xFF14532D),
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFFF8FAFC),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkSurface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.darkTextTertiary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.darkBorder,
          thickness: 1,
          space: 1,
        ),
        // surfaceElevated (not darkSurface) — dialogs/sheets sit visually
        // "above" a regular card, so they get their own, lighter rung on
        // the elevation ladder instead of blending into the same tone as
        // whatever card triggered them.
        dialogTheme: const DialogThemeData(
          backgroundColor: AppColors.darkSurfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.darkSurfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.darkSurfaceVariant,
          contentTextStyle: const TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFFF8FAFC),
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Color(0xFFF8FAFC),
            letterSpacing: -0.8,
          ),
          displayMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF8FAFC),
            letterSpacing: -0.5,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF8FAFC),
            letterSpacing: -0.4,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF8FAFC),
            letterSpacing: -0.3,
          ),
          headlineSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF8FAFC),
            letterSpacing: -0.2,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF8FAFC),
          ),
          titleMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFFF8FAFC),
          ),
          titleSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF94A3B8),
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Color(0xFFF8FAFC),
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFFF8FAFC),
          ),
          bodySmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: Color(0xFF94A3B8),
          ),
          labelLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF8FAFC),
          ),
          labelSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.darkTextTertiary,
          ),
        ),
      );
}
