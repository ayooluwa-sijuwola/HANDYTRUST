import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Web/desktop responsive breakpoints — the app has no Stitch reference for
/// web (there isn't one; mobile Stitch is the visual foundation only, not a
/// layout to stretch). These thresholds are the one place "is this a
/// desktop-width viewport" gets decided, so every screen's responsive
/// branching agrees with every other screen's.
abstract final class AppBreakpoints {
  /// Below this: the existing mobile experience (bottom nav, single-column,
  /// phone-width content) renders exactly as it already does — untouched.
  static const double tablet = 700;

  /// At/above this: sidebar navigation, multi-column dashboard layouts,
  /// content no longer stretches edge-to-edge. Between [tablet] and
  /// [desktop] the sidebar shows icon-only (collapsed); at/above [desktop]
  /// it shows full icon+label.
  static const double desktop = 1100;

  /// Content column max-width on desktop — professional web apps don't let
  /// a paragraph or a form span a 1920px window; this caps it, centered,
  /// with the remaining width used for sidebar/whitespace/secondary
  /// columns rather than stretched line lengths.
  static const double maxContentWidth = 1120;
}

/// Platform-gated responsive checks — [kIsWeb] first, viewport width
/// second. Every desktop/tablet layout branch in the app reads through
/// these three getters (never a raw MediaQuery width check of its own), so
/// this is the single point where "should this render as desktop" is
/// decided.
///
/// Gating on kIsWeb is deliberate, not incidental: without it, a wide
/// Android device — a tablet in landscape, a foldable unfolded, a phone in
/// a desktop-mode window — would cross these same width thresholds and get
/// the desktop/tablet layout too, which is exactly the "mobile widget tree
/// got replaced" outcome this was built to avoid. Android renders the
/// mobile experience unconditionally, at any width; only Flutter Web
/// varies by viewport.
extension ResponsiveContext on BuildContext {
  double get _width => MediaQuery.of(this).size.width;

  /// True only on web, at tablet width and above (>=700) — sidebar nav
  /// replaces the bottom bar starting here, collapsed until [isDesktop].
  /// Always false on Android, regardless of width.
  bool get isTablet => kIsWeb && _width >= AppBreakpoints.tablet;

  /// True only on web, in the 700–1100 band — distinct from [isTablet],
  /// which is also true at desktop widths. Use this when a layout
  /// genuinely differs at tablet vs. desktop (e.g. the sidebar's
  /// collapsed/expanded state), not just "is this at least tablet-wide."
  bool get isTabletOnly =>
      kIsWeb && _width >= AppBreakpoints.tablet && _width < AppBreakpoints.desktop;

  /// True only on web, at desktop width and above (>=1100). Always false
  /// on Android, regardless of width.
  bool get isDesktop => kIsWeb && _width >= AppBreakpoints.desktop;
}
