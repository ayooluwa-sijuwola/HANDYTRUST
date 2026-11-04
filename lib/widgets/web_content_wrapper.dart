import 'package:flutter/material.dart';
import '../theme/breakpoints.dart';

/// Constrains and centers a pushed screen's body on wide *web* viewports so
/// it reads as a real web page instead of a phone-width column stretched
/// edge-to-edge. On Android, or below [AppBreakpoints.tablet] on web, this
/// is a no-op — the existing mobile layout renders exactly as it already
/// does.
///
/// Deliberately generic and non-invasive: it wraps a screen's existing
/// body without touching that screen's own internals, so every pushed
/// screen (Job Detail, Chat, Payment, Post a Job, Artisan Profile, ...)
/// gets a sane desktop presentation from one shared widget rather than
/// each screen re-implementing its own width constraint.
class WebContentWrapper extends StatelessWidget {
  final Widget child;

  /// Override for screens that want a narrower reading column (forms) vs
  /// the default (lists/detail pages).
  final double maxWidth;

  const WebContentWrapper({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    // context.isTablet is kIsWeb-gated (theme/breakpoints.dart) — this was
    // previously its own raw MediaQuery width check, which meant a wide
    // Android device (a tablet in landscape, a foldable unfolded) would
    // cross the threshold and get this treatment too. Routing through the
    // shared extension is what makes Android unconditionally exempt.
    if (!context.isTablet) {
      return child;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
