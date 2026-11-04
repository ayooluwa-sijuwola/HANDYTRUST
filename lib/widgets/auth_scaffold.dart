import 'package:flutter/material.dart';
import '../theme/app_design_system.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';

/// Shared visual language for the auth screens (login, register) — a
/// logo lockup, a card-elevated form on a soft background, and a
/// coming-soon social sign-in row. Kept in one place per the design
/// system's "one canonical widget per concept" rule (02-design-system.md
/// §8) so login/register/forgot-password never re-derive this styling.

const String _kLogoAsset = 'assets/icons/watermark-removed-WhatsApp Image 2026-08-03 at 13.55.31.jpg';

/// Desktop presentation for every auth screen (login/register/forgot-
/// password/verify-email) — centers the existing mobile column (brand
/// header, AuthCard, footer) at a professional form width on a full-bleed
/// tinted backdrop, instead of letting AuthCard's `width: double.infinity`
/// stretch edge-to-edge on a wide viewport. Below [AppBreakpoints.tablet]
/// this is a no-op — [child] renders exactly as it already does, so the
/// mobile layout is untouched.
///
/// Deliberately just a centered card, not a marketing split-screen (image/
/// copy on one side) — that would mean inventing brand copy/imagery this
/// task never supplied, which is exactly the "fake feature" the brief
/// rules out. The backdrop tint is the one new visual element, built from
/// the existing primarySurface token, not a new color.
class AuthWebLayout extends StatelessWidget {
  final Widget child;
  const AuthWebLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!context.isTablet) return child;
    return Container(
      color: context.colors.primarySurface.withValues(alpha: 0.35),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: child,
        ),
      ),
    );
  }
}

class AuthLogoBadge extends StatelessWidget {
  final double size;
  const AuthLogoBadge({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Image.asset(
        _kLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// Small logo + wordmark, sits above the card (outside it), matching the
/// reference's top-left brand header.
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AuthLogoBadge(size: 36),
        const SizedBox(width: 10),
        Text(
          'HandyTrust',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: context.colors.textPrimary,
              ),
        ),
      ],
    );
  }
}

/// Borderless, gray-fill card wrapping the auth form — updated to match
/// the app-wide card language resolved in 02-design-system-v2.md §9.2
/// (light gray fill, no border, minimal-to-no shadow), superseding this
/// component's original white-bordered-card build (which matched the
/// login mockup literally, before the borderless standard was decided).
/// Every screen since (Home, Artisan Profile, Wallet, ...) uses the
/// borderless language — updating this shared component keeps
/// login/signup visually consistent with the rest of the app rather than
/// looking like a leftover from an earlier design pass.
class AuthCard extends StatelessWidget {
  final Widget child;
  const AuthCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: child,
    );
  }
}

/// Static label above a field, with an optional trailing action (e.g.
/// "Forgot Password?") on the same row — a deliberate, scoped departure
/// from the app's default floating-labelText input pattern, specific to
/// the auth screens per the reference; not applied to the global theme.
class AuthFieldLabel extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const AuthFieldLabel(this.label, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: context.colors.textPrimary,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Label + TextFormField pair — bundles [AuthFieldLabel] with the field it
/// labels, since every auth form (Login/Register/Forgot Password) repeated
/// this pairing field-by-field. Styling itself comes from the app-wide
/// InputDecorationTheme (unchanged); this only removes the boilerplate of
/// wiring the two together identically each time.
class AuthTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final Widget? labelTrailing;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;

  const AuthTextField({
    super.key,
    required this.label,
    required this.controller,
    this.labelTrailing,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onFieldSubmitted,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthFieldLabel(label, trailing: labelTrailing),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: suffixIcon,
          ),
          validator: validator,
        ),
      ],
    );
  }
}

/// Primary submit button with a built-in loading spinner — closes the
/// identical loading-ternary block that was copy-pasted across Login,
/// Register, Forgot Password, and Artisan Registration. Uses the standard
/// Trust Green ElevatedButtonTheme (not CommitButton): no Stitch mockup
/// exists for auth screens, so there's no evidence the black "commitment"
/// treatment belongs here — this keeps the look every auth screen already
/// had, just without four copies of the same markup.
class AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? trailingIcon;

  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  Icon(trailingIcon, size: 18),
                ],
              ],
            ),
    );
  }
}

/// Google + Apple buttons, styled per the reference, wired to a
/// coming-soon snackbar rather than a real provider — real Google/Apple
/// Sign-In needs Firebase console provider config and (for Apple) a
/// platform entitlement, tracked as separate follow-up work, not a UI
/// change.
class SocialSignInRow extends StatelessWidget {
  const SocialSignInRow({super.key});

  void _comingSoon(BuildContext context, String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$provider sign-in is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SocialButton(
            label: 'Google',
            glyph: 'G',
            onTap: () => _comingSoon(context, 'Google'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SocialButton(
            icon: Icons.apple,
            label: 'Apple',
            onTap: () => _comingSoon(context, 'Apple'),
          ),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final String? glyph;
  final IconData? icon;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.onTap,
    this.glyph,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.colors.textPrimary,
        side: BorderSide(color: context.colors.border),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) Icon(icon, size: 20, color: context.colors.textPrimary),
          if (glyph != null)
            Text(
              glyph!,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: context.colors.textPrimary,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Muted "OR CONTINUE WITH" divider between the primary action and the
/// social row.
class AuthDivider extends StatelessWidget {
  final String label;
  const AuthDivider({super.key, this.label = 'OR CONTINUE WITH'});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: context.colors.borderLight)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: context.colors.textTertiary,
            ),
          ),
        ),
        Expanded(child: Divider(color: context.colors.borderLight)),
      ],
    );
  }
}

/// Centered footer copyright line below the card.
class AuthFooter extends StatelessWidget {
  const AuthFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        '© $year HandyTrust Services. All rights reserved.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: context.colors.textTertiary,
        ),
      ),
    );
  }
}
