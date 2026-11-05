import 'package:flutter/material.dart';

/// Stage 8 design system, measured from the Stitch reference screenshots
/// (design/STAGE8_SCREEN_INVENTORY.md). Colours were sampled from the
/// reference pixels; sizes, radii and spacing are estimates converted from
/// screenshot pixels to logical points (390 pt reference width) and are
/// documented as estimates in design/STAGE8_VISUAL_QA_REPORT.md.
///
/// Light and dark are two renderings of one design (the dark Profile
/// reference carries the dark-mode toggle); every new screen reads the
/// palette for the current [Brightness] through `context.ht`.
@immutable
class HtPalette {
  const HtPalette({
    required this.isDark,
    required this.background,
    required this.backgroundDeep,
    required this.glow,
    required this.surface,
    required this.surfaceRaised,
    required this.input,
    required this.border,
    required this.navBar,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentStrong,
    required this.accentSoft,
    required this.accentSoftText,
    required this.primaryGradient,
    required this.onPrimary,
    required this.primaryGlow,
    required this.chipActive,
    required this.onChipActive,
    required this.chipInactive,
    required this.onChipInactive,
    required this.navActive,
    required this.onNavActive,
    required this.avatarFill,
    required this.avatarText,
    required this.headerAvatarFill,
    required this.onHeaderAvatar,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.outgoingBubble,
    required this.onOutgoingBubble,
    required this.incomingBubble,
    required this.cardShadow,
  });

  final bool isDark;
  final Color background;
  /// Discovery / artisan profile / onboarding page colour (near-black in dark).
  final Color backgroundDeep;
  /// Top-of-page radial glow (dark) or lime wash (light).
  final Color glow;
  final Color surface;
  final Color surfaceRaised;
  final Color input;
  final Color border;
  final Color navBar;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentStrong;
  final Color accentSoft;
  final Color accentSoftText;
  final List<Color> primaryGradient;
  final Color onPrimary;
  final Color primaryGlow;
  final Color chipActive;
  final Color onChipActive;
  final Color chipInactive;
  final Color onChipInactive;
  final Color navActive;
  final Color onNavActive;
  final Color avatarFill;
  final Color avatarText;
  final Color headerAvatarFill;
  final Color onHeaderAvatar;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final List<Color> outgoingBubble;
  final Color onOutgoingBubble;
  final Color incomingBubble;
  final List<BoxShadow> cardShadow;

  // Sampled: page #10150D, cards #1C2118–#1F2417, inputs #0A0D08, nav
  // #22261D, CTA gradient #7E8E3D→#BECD77, verified pill #184633, lime
  // panels #262D0A, Discovery/profile page #07090A (references 2–13).
  static const dark = HtPalette(
    isDark: true,
    background: Color(0xFF10150D),
    backgroundDeep: Color(0xFF07090A),
    glow: Color(0xFF4A5530),
    surface: Color(0xFF1C2118),
    surfaceRaised: Color(0xFF262B1F),
    input: Color(0xFF0A0D08),
    border: Color(0x14FFFFFF),
    navBar: Color(0xFF1C2018),
    textPrimary: Color(0xFFF2F4EC),
    textSecondary: Color(0xFFA4AA98),
    textMuted: Color(0xFF737A68),
    accent: Color(0xFFC5D77C),
    accentStrong: Color(0xFF98A955),
    accentSoft: Color(0xFF262D0A),
    accentSoftText: Color(0xFFC5D77C),
    primaryGradient: [Color(0xFF7E8E3D), Color(0xFFBECD77)],
    onPrimary: Color(0xFF1C2410),
    primaryGlow: Color(0x55BECD77),
    chipActive: Color(0xFFC5D77C),
    onChipActive: Color(0xFF1C2410),
    chipInactive: Color(0xFF1C2118),
    onChipInactive: Color(0xFFE4E7DC),
    navActive: Color(0xFFBECD77),
    onNavActive: Color(0xFF1C2410),
    avatarFill: Color(0xFF2A3020),
    avatarText: Color(0xFFC5D77C),
    headerAvatarFill: Color(0xFFC5D77C),
    onHeaderAvatar: Color(0xFF1C2410),
    success: Color(0xFF3ED6A0),
    successSoft: Color(0xFF163A2C),
    warning: Color(0xFFF2B33D),
    warningSoft: Color(0xFF3A3016),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3A1A18),
    outgoingBubble: [Color(0xFF7C8B3A), Color(0xFF55601F)],
    onOutgoingBubble: Color(0xFFF7F9EF),
    incomingBubble: Color(0xFF1C2118),
    cardShadow: [],
  );

  // Sampled: page #F9FAF4, cards #FFFFFF/#FEFEFC, CTA gradient
  // #6E7D31→#A9BE58, verified pill #DCFCE7 (Tailwind green-100) with
  // green-700 text, escrow-lock peach with orange-700 (references 14–24).
  static const light = HtPalette(
    isDark: false,
    background: Color(0xFFF9FAF4),
    backgroundDeep: Color(0xFFF9FAF4),
    glow: Color(0xFFE4ECC8),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF6F7EF),
    input: Color(0xFFFFFFFF),
    border: Color(0xFFECEEE3),
    navBar: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF141712),
    textSecondary: Color(0xFF6B7063),
    textMuted: Color(0xFF9A9E90),
    accent: Color(0xFF5E6E1F),
    accentStrong: Color(0xFF4F5D18),
    accentSoft: Color(0xFFEEF3D6),
    accentSoftText: Color(0xFF4F5D18),
    primaryGradient: [Color(0xFF6E7D31), Color(0xFFA9BE58)],
    onPrimary: Color(0xFFFFFFFF),
    primaryGlow: Color(0x406E7D31),
    chipActive: Color(0xFF6B7A2C),
    onChipActive: Color(0xFFFFFFFF),
    chipInactive: Color(0xFFFFFFFF),
    onChipInactive: Color(0xFF2B2F27),
    navActive: Color(0xFF5E6E1F),
    onNavActive: Color(0xFFFFFFFF),
    avatarFill: Color(0xFFEEF1E2),
    avatarText: Color(0xFF3F4A14),
    headerAvatarFill: Color(0xFF4F5D18),
    onHeaderAvatar: Color(0xFFFFFFFF),
    success: Color(0xFF15803D),
    successSoft: Color(0xFFDCFCE7),
    warning: Color(0xFFC2410C),
    warningSoft: Color(0xFFFFEDD5),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFEF2F2),
    outgoingBubble: [Color(0xFF5D671C), Color(0xFF5D671C)],
    onOutgoingBubble: Color(0xFFFFFFFF),
    incomingBubble: Color(0xFFFFFFFF),
    cardShadow: [BoxShadow(color: Color(0x0D1E2410), blurRadius: 18, offset: Offset(0, 4))],
  );

  LinearGradient get primary => LinearGradient(colors: primaryGradient);
}

/// Typography: Plus Jakarta Sans for display/headings (closest match to
/// the reference headings — the Stitch export's actual font name was not
/// available) and Inter for body text. Sizes are reference estimates.
abstract final class HtType {
  static const display = 'HtDisplay';
  static const text = 'HtText';

  static TextStyle hero(Color c) => TextStyle(fontFamily: display, fontSize: 30, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c);
  static TextStyle screenTitle(Color c) => TextStyle(fontFamily: display, fontSize: 27, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: c);
  static TextStyle headerTitle(Color c) => TextStyle(fontFamily: display, fontSize: 19, height: 1.2, fontWeight: FontWeight.w700, color: c);
  static TextStyle brand(Color c) => TextStyle(fontFamily: display, fontSize: 19, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: c);
  static TextStyle sectionTitle(Color c) => TextStyle(fontFamily: display, fontSize: 18, height: 1.2, fontWeight: FontWeight.w700, color: c);
  static TextStyle cardTitle(Color c) => TextStyle(fontFamily: display, fontSize: 16.5, height: 1.25, fontWeight: FontWeight.w700, color: c);
  static TextStyle amount(Color c, {double size = 24}) => TextStyle(fontFamily: display, fontSize: size, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: c);
  static TextStyle body(Color c) => TextStyle(fontFamily: text, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w400, color: c);
  static TextStyle bodyStrong(Color c) => TextStyle(fontFamily: text, fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w600, color: c);
  static TextStyle small(Color c) => TextStyle(fontFamily: text, fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w400, color: c);
  static TextStyle smallStrong(Color c) => TextStyle(fontFamily: text, fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600, color: c);
  static TextStyle caps(Color c) => TextStyle(fontFamily: text, fontSize: 11, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: c);
  static TextStyle button(Color c) => TextStyle(fontFamily: display, fontSize: 16, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: 0.1, color: c);
  static TextStyle label(Color c) => TextStyle(fontFamily: text, fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: 0.2, color: c);
}

abstract final class HtSpace {
  static const gutter = 20.0;
  static const section = 28.0;
  static const card = 20.0;
}

abstract final class HtRadius {
  static const card = 28.0;
  static const inner = 20.0;
  static const input = 20.0;
  static const tile = 14.0;
  static const pill = 999.0;
}

extension HtContext on BuildContext {
  HtPalette get ht => Theme.of(this).brightness == Brightness.dark ? HtPalette.dark : HtPalette.light;
}
