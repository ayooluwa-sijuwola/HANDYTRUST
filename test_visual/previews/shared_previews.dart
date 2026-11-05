// Stage 8.1 authentication and remaining customer PREVIEWS. Static
// compositions with SAMPLE DATA; fields, actions and states mirror the
// existing screens (lib/screens/auth, settings, support, dispute, review,
// artisan/secure_booking, artisan_list, favorites, payment webview result).
import 'package:flutter/material.dart';
import 'package:handy_trust/ui/components/ht_components.dart';
import 'package:handy_trust/ui/theme/ht_theme.dart';

import 'preview_kit.dart';

// ─── Authentication ─────────────────────────────────────────────────────────

Widget _brandPill(BuildContext context) {
  final p = context.ht;
  return Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.pill), border: Border.all(color: p.border), boxShadow: p.cardShadow),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.handyman_outlined, size: 20, color: p.isDark ? p.accent : p.textPrimary),
        const SizedBox(width: 8),
        Text('HandyTrust', style: HtType.brand(p.textPrimary).copyWith(fontSize: 17)),
      ]),
    ),
  );
}

Widget _authHero(BuildContext context, String a, String b, String sub) {
  final p = context.ht;
  return Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(children: [
        TextSpan(text: a, style: HtType.hero(p.textPrimary)),
        TextSpan(text: b, style: HtType.hero(p.isDark ? p.accent : p.accentStrong)),
      ])),
      const SizedBox(height: 8),
      Text(sub, style: HtType.body(p.textSecondary)),
    ]),
  );
}

Widget _link(BuildContext context, String lead, String action) {
  final p = context.ht;
  return Center(
    child: Text.rich(TextSpan(children: [
      TextSpan(text: lead, style: HtType.body(p.textSecondary)),
      TextSpan(text: action, style: HtType.bodyStrong(p.isDark ? p.accent : p.accentStrong)),
    ])),
  );
}

/// [error]: message from AuthService.friendlyError; [loading]: request in
/// flight (fields locked, button spinner).
Widget authLogin({String? error, bool loading = false}) => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        deep: true,
        children: [
          const SizedBox(height: 12),
          _brandPill(context),
          _authHero(context, 'Welcome ', 'Back', 'Enter your details to access your account'),
          if (error != null) ...[
            const SizedBox(height: 10),
            HtInfoBanner(icon: Icons.error_outline_rounded, tone: HtTone.danger, title: 'Sign-in failed', text: error),
          ],
          Opacity(
            opacity: loading ? 0.6 : 1,
            child: Column(children: [
              htField(context, 'Email Address', 'funke.a@example.com'),
              htField(context, 'Password', '••••••••••'),
            ]),
          ),
          Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 12), child: Text('Forgot Password?', style: HtType.bodyStrong(p.isDark ? p.accent : p.accentStrong).copyWith(fontSize: 13.5)))),
          const SizedBox(height: 26),
          HtPrimaryButton(label: 'Login to Account', icon: Icons.arrow_forward_rounded, loading: loading, onPressed: () {}),
          const SizedBox(height: 22),
          _link(context, 'New to HandyTrust? ', 'Sign Up'),
        ],
      );
    });

Widget authRegister() => Builder(builder: (context) {
      final p = context.ht;
      Widget role(String t, String s, IconData i, bool sel) => Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: sel ? p.accentSoft : p.surface,
                borderRadius: BorderRadius.circular(HtRadius.inner),
                border: Border.all(color: sel ? p.accentStrong : p.border, width: sel ? 1.6 : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(i, color: sel ? p.accentSoftText : p.textSecondary),
                const SizedBox(height: 8),
                Text(t, style: HtType.bodyStrong(p.textPrimary)),
                Text(s, style: HtType.small(p.textSecondary)),
              ]),
            ),
          );
      return PhoneScreen(
        deep: true,
        children: [
          const SizedBox(height: 12),
          _brandPill(context),
          _authHero(context, 'Create your ', 'account', 'Hire trusted hands or offer your services.'),
          const SizedBox(height: 10),
          Row(children: [
            role('Customer', 'I need services', Icons.home_repair_service_outlined, true),
            const SizedBox(width: 10),
            role('Artisan', 'I offer services', Icons.handyman_outlined, false),
          ]),
          htField(context, 'Full Name', 'Your full name', placeholder: true),
          htField(context, 'Email Address', 'e.g. name@example.com'),
          htField(context, 'City / Area (optional)', 'e.g. Bodija, Ibadan'),
          Row(children: [
            Expanded(child: htField(context, 'Password', '••••••••')),
            const SizedBox(width: 10),
            Expanded(child: htField(context, 'Confirm Password', '••••••••')),
          ]),
          const SizedBox(height: 24),
          HtPrimaryButton(label: 'Create Account', onPressed: () {}),
          const SizedBox(height: 18),
          _link(context, 'Already have an account? ', 'Sign In'),
        ],
      );
    });

Widget authForgotPassword() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        deep: true,
        header: const HtScreenHeader(title: ''),
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
            child: Icon(Icons.lock_reset_rounded, size: 30, color: p.accentSoftText),
          ),
          _authHero(context, 'Reset your ', 'password', 'Enter the email you signed up with. We will send you a reset link.'),
          htField(context, 'Email Address', 'funke.a@example.com'),
          const SizedBox(height: 26),
          HtPrimaryButton(label: 'Send Reset Link', onPressed: () {}),
          const SizedBox(height: 18),
          Center(child: Text('Back to Login', style: HtType.bodyStrong(p.isDark ? p.accent : p.accentStrong))),
        ],
      );
    });

Widget authVerifyEmail() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        deep: true,
        children: [
          const SizedBox(height: 40),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.mark_email_unread_outlined, size: 44, color: p.accentSoftText),
            ),
          ),
          const SizedBox(height: 24),
          Text('Verify your email', textAlign: TextAlign.center, style: HtType.screenTitle(p.textPrimary)),
          const SizedBox(height: 10),
          Text('We sent a verification link to\nfunke.a@example.com\n\nOpen your email and tap the link to activate your account.', textAlign: TextAlign.center, style: HtType.body(p.textSecondary)),
          const SizedBox(height: 28),
          HtPrimaryButton(label: 'Resend verification email', leadingIcon: Icons.refresh_rounded, onPressed: () {}),
          const SizedBox(height: 12),
          HtSecondaryButton(label: 'Use a different account', onPressed: () {}),
        ],
      );
    });

Widget authRoleSelect() => Builder(builder: (context) {
      final p = context.ht;
      Widget card(String t, String s, IconData i, bool sel) => Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: sel ? p.accentSoft : p.surface,
              borderRadius: BorderRadius.circular(HtRadius.card),
              border: Border.all(color: sel ? p.accentStrong : p.border, width: sel ? 1.6 : 1),
              boxShadow: p.cardShadow,
            ),
            child: Row(children: [
              htIconTile(context, i, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: HtType.cardTitle(p.textPrimary)),
                  Text(s, style: HtType.small(p.textSecondary)),
                ]),
              ),
              Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: sel ? p.accentStrong : p.textMuted),
            ]),
          );
      return PhoneScreen(
        deep: true,
        bottomBar: HtPrimaryButton(label: 'Continue as Artisan', icon: Icons.arrow_forward_rounded, onPressed: () {}),
        children: [
          const SizedBox(height: 12),
          _brandPill(context),
          _authHero(context, 'How will you use ', 'HandyTrust today?', 'You have both roles. You can switch any time from your profile.'),
          const SizedBox(height: 14),
          card('Continue as Customer', 'Post jobs, hire artisans, manage payments.', Icons.home_repair_service_outlined, false),
          card('Continue as Artisan', 'Browse open jobs, submit quotes, track earnings.', Icons.handyman_outlined, true),
        ],
      );
    });

Widget authArtisanRegistration() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: const HtScreenHeader(title: 'Artisan profile'),
        bottomBar: HtPrimaryButton(label: 'Submit for review', onPressed: () {}),
        children: [
          Text('Set up your artisan profile', style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 23)),
          const SizedBox(height: 4),
          Text('Your profile will be reviewed before appearing publicly.', style: HtType.body(p.textSecondary)),
          const HtFieldLabel('Primary service category'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, c) in ['Plumbing', 'Electrical', 'Painting', 'Carpentry', 'Cleaning'].indexed) HtChip(label: c, selected: i == 0, onTap: () {}),
          ]),
          const HtFieldLabel('Skills & specialisations'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in ['Pipe repair', 'Water heaters', 'Boreholes']) HtStatusPill(label: c, tone: HtTone.accent, icon: Icons.close_rounded),
            HtStatusPill(label: 'Add skill', icon: Icons.add_rounded),
          ]),
          htField(context, 'About you', 'Tell customers about your experience and what makes you stand out…', lines: 3),
          htField(context, 'Service area', 'Bodija, Ibadan · 15 km'),
        ],
      );
    });

Widget authSuspended() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        deep: true,
        children: [
          const SizedBox(height: 40),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: p.dangerSoft, shape: BoxShape.circle),
              child: Icon(Icons.block_rounded, size: 44, color: p.danger),
            ),
          ),
          const SizedBox(height: 24),
          Text('Account Suspended', textAlign: TextAlign.center, style: HtType.screenTitle(p.textPrimary)),
          const SizedBox(height: 10),
          Text('Your account has restricted access. You can still view and complete your existing jobs.', textAlign: TextAlign.center, style: HtType.body(p.textSecondary)),
          const SizedBox(height: 26),
          HtPrimaryButton(label: 'View My Existing Jobs', onPressed: () {}),
          const SizedBox(height: 12),
          HtSecondaryButton(label: 'Contact support', onPressed: () {}),
          const SizedBox(height: 12),
          Center(child: Text('Sign Out', style: HtType.bodyStrong(p.danger))),
        ],
      );
    });

// ─── Remaining customer screens ─────────────────────────────────────────────

Widget _group(BuildContext context, String title, List<Widget> rows) {
  final p = context.ht;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(left: 6, bottom: 8, top: 18), child: Text(title.toUpperCase(), style: HtType.caps(p.textMuted))),
    HtCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: rows)),
  ]);
}

Widget cuSettings() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: const HtScreenHeader(title: 'Settings'),
        children: [
          _group(context, 'Account', [
            HtMenuRow(icon: Icons.alternate_email_rounded, title: 'Username', subtitle: '@funke.a', onTap: () {}),
            HtMenuRow(icon: Icons.badge_outlined, title: 'Display Name', subtitle: 'Funke Adeyemi', onTap: () {}),
            HtMenuRow(icon: Icons.mail_outline_rounded, title: 'Change Email', subtitle: 'funke.a@example.com', onTap: () {}),
            HtMenuRow(icon: Icons.password_rounded, title: 'Change Password', onTap: () {}),
          ]),
          _group(context, 'Preferences', [
            HtMenuRow(icon: Icons.dark_mode_outlined, title: 'Dark Mode', showChevron: false, trailing: Switch(value: p.isDark, onChanged: (_) {}), onTap: () {}),
            HtMenuRow(icon: Icons.notifications_none_rounded, title: 'Notifications', subtitle: 'On', showChevron: false, trailing: Switch(value: true, onChanged: (_) {}), onTap: () {}),
            HtMenuRow(icon: Icons.swap_horiz_rounded, title: 'Active Mode', subtitle: 'Customer mode', onTap: () {}),
          ]),
          _group(context, 'Help', [
            HtMenuRow(icon: Icons.help_outline_rounded, title: 'Frequently asked questions', onTap: () {}),
            HtMenuRow(icon: Icons.support_agent_rounded, title: 'Contact our team', onTap: () {}),
          ]),
          _group(context, 'Account actions', [
            HtMenuRow(icon: Icons.delete_forever_outlined, title: 'Permanently delete your account', subtitle: 'Reviewed by an administrator', destructive: true, onTap: () {}),
            HtMenuRow(icon: Icons.logout_rounded, title: 'Sign out', destructive: true, onTap: () {}),
          ]),
        ],
      );
    });

Widget cuSupport() => Builder(builder: (context) {
      return PhoneScreen(
        header: const HtScreenHeader(title: 'Help & Support'),
        children: [
          HtCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Submit a Ticket', style: HtType.cardTitle(context.ht.textPrimary)),
              htField(context, 'Subject', 'Payment not showing'),
              htField(context, 'Message', 'Describe your issue…', lines: 3),
              const SizedBox(height: 16),
              HtPrimaryButton(label: 'Submit', height: 48, onPressed: () {}),
            ]),
          ),
          const SizedBox(height: 22),
          const HtSectionHeader(title: 'Your Tickets'),
          const SizedBox(height: 12),
          HtListCard(leading: htIconTile(context, Icons.confirmation_number_outlined), title: 'Payment not showing', subtitle: 'Submitted 22 Oct 2026', trailing: const HtStatusPill(label: 'Open', tone: HtTone.warning, dot: true)),
          const SizedBox(height: 10),
          HtListCard(leading: htIconTile(context, Icons.confirmation_number_outlined), title: 'Change my phone number', subtitle: 'Submitted 10 Oct 2026', trailing: const HtStatusPill(label: 'Resolved', tone: HtTone.success, dot: true)),
        ],
      );
    });

Widget cuDispute() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: const HtScreenHeader(title: 'Raise Dispute', subtitle: 'Job #HT-3A9115'),
        bottomBar: HtPrimaryButton(label: 'Submit Dispute', onPressed: () {}),
        children: [
          const HtInfoBanner(icon: Icons.lock_outline_rounded, tone: HtTone.warning, title: 'Escrow stays locked', text: 'Raising a dispute keeps the payment in escrow until HandyTrust reviews the evidence from both parties.'),
          const HtFieldLabel('Reason for Dispute'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, r) in ['Work not completed', 'Work quality is poor', 'Wrong service delivered', 'Artisan is unresponsive', 'Other'].indexed) HtChip(label: r, selected: i == 1, onTap: () {}),
          ]),
          htField(context, 'Additional Details', 'Describe the issue in detail. More evidence helps resolve faster.', lines: 3, placeholder: true),
          const HtFieldLabel('Evidence Photos (optional)', trailing: '1 / 5'),
          Row(children: [
            const Expanded(child: HtPhotoTile(label: 'Leak under sink')),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 96,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(HtRadius.tile), border: Border.all(color: p.accentStrong, width: 1.4)),
                child: Center(child: Icon(Icons.add_a_photo_outlined, color: p.accent)),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(child: SizedBox()),
          ]),
        ],
      );
    });

Widget cuReview() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: const HtScreenHeader(title: 'Leave a Review'),
        bottomBar: HtPrimaryButton(label: 'Submit Review', onPressed: () {}),
        children: [
          const SizedBox(height: 10),
          const Center(child: HtAvatar(name: 'Tunde Balogun', size: 84, ring: true)),
          const SizedBox(height: 12),
          Text('Tunde Balogun', textAlign: TextAlign.center, style: HtType.cardTitle(p.textPrimary)),
          Text('Fix leaking kitchen sink · completed', textAlign: TextAlign.center, style: HtType.small(p.textSecondary)),
          const SizedBox(height: 24),
          Text('How was the service?', textAlign: TextAlign.center, style: HtType.sectionTitle(p.textPrimary)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 5; i++) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Icon(i < 4 ? Icons.star_rounded : Icons.star_outline_rounded, size: 42, color: i < 4 ? const Color(0xFFF5B83D) : p.textMuted)),
          ]),
          const SizedBox(height: 6),
          Text('Very Good', textAlign: TextAlign.center, style: HtType.bodyStrong(p.textSecondary)),
          htField(context, 'Your review', 'Share your experience (optional)…', lines: 3),
          const SizedBox(height: 12),
          Text('Your review helps other customers and motivates artisans.', textAlign: TextAlign.center, style: HtType.small(p.textMuted)),
          const SizedBox(height: 8),
          Center(child: Text('Skip for now', style: HtType.bodyStrong(p.textSecondary))),
        ],
      );
    });

Widget cuSecureBooking() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: const HtScreenHeader(title: 'Secure Booking'),
        bottomBar: HtPrimaryButton(label: 'Send Booking Request', icon: Icons.arrow_forward_rounded, onPressed: () {}),
        children: [
          HtListCard(leading: const HtAvatar(name: 'Tunde Balogun', size: 46, online: true), title: 'Tunde Balogun', subtitle: 'Plumbing · Ibadan', trailing: const HtVerifiedBadge(), chevron: false),
          htField(context, 'Task Details', 'Kitchen sink is leaking under the cabinet.', lines: 2),
          const HtFieldLabel('Schedule Preferences'),
          Row(children: [HtChip(label: 'As soon as possible', selected: true, onTap: () {}), const SizedBox(width: 8), HtChip(label: 'Pick a specific date', selected: false, onTap: () {})]),
          htField(context, 'Your proposed budget (optional)', '₦25,000'),
          const SizedBox(height: 18),
          HtCard(
            radius: HtRadius.inner,
            child: Column(children: [
              htKv(context, 'Your proposed amount', '₦25,000'),
              htKv(context, 'Platform fee (5%)', '₦1,250'),
              Divider(color: p.border),
              htKv(context, 'Total, once accepted', '₦26,250', strong: true),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Nothing is charged yet — you pay into escrow only after the artisan accepts.', style: HtType.small(p.textSecondary)),
        ],
      );
    });

Widget cuMatchedArtisans() => Builder(builder: (context) {
      final p = context.ht;
      Widget a(String n, String meta, String rating) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HtCard(
              child: Row(children: [
                HtAvatar(name: n, size: 52, online: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Flexible(child: Text(n, style: HtType.cardTitle(p.textPrimary))), const SizedBox(width: 6), Icon(Icons.verified_rounded, size: 16, color: p.success)]),
                    Text(meta, style: HtType.small(p.textSecondary)),
                    const SizedBox(height: 4),
                    Row(children: [const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5B83D)), const SizedBox(width: 3), Text(rating, style: HtType.smallStrong(p.textPrimary))]),
                  ]),
                ),
                HtSmallPrimaryButton(label: 'Select', onPressed: () {}),
              ]),
            ),
          );
      return PhoneScreen(
        header: const HtScreenHeader(title: 'Choose an Artisan', subtitle: 'Plumbing · Bodija'),
        children: [
          const HtSectionHeader(title: 'Top Professionals', badge: '2'),
          const SizedBox(height: 12),
          a('Tunde Balogun', 'Plumbing · 2.4 km', '4.8 · 42 jobs'),
          a('Aisha Bello', 'Plumbing · 5.1 km', '4.9 · 17 jobs'),
          const SizedBox(height: 6),
          const HtSectionHeader(title: 'Rising Professionals', badge: '1'),
          const SizedBox(height: 4),
          Text('Fresh talent — eager, available, and affordable', style: HtType.small(p.textSecondary)),
          const SizedBox(height: 12),
          a('Kola Ade', 'Plumbing · 6.0 km', 'New · 2 jobs'),
        ],
      );
    });

Widget cuFavorites() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: const HtScreenHeader(title: 'Saved Artisans'),
        children: [
          for (final (n, m) in [('Tunde Balogun', 'Plumbing · Ibadan'), ('Funmi Ola', 'Painting · Ibadan')])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: HtCard(
                child: Row(children: [
                  HtAvatar(name: n, size: 52),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(n, style: HtType.cardTitle(p.textPrimary)), Text(m, style: HtType.small(p.textSecondary))])),
                  Icon(Icons.favorite_rounded, color: p.danger),
                  const SizedBox(width: 10),
                  HtSmallPrimaryButton(label: 'Hire', onPressed: () {}),
                ]),
              ),
            ),
        ],
      );
    });

Widget cuPaymentResult() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        deep: true,
        children: [
          const SizedBox(height: 60),
          Center(
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(color: p.successSoft, shape: BoxShape.circle),
              child: Icon(Icons.lock_rounded, size: 46, color: p.success),
            ),
          ),
          const SizedBox(height: 24),
          Text('Payment Successful', textAlign: TextAlign.center, style: HtType.screenTitle(p.textPrimary)),
          const SizedBox(height: 10),
          Text('Your funds are locked in escrow. The artisan will begin work shortly — you’ll release payment once you confirm the job is done.', textAlign: TextAlign.center, style: HtType.body(p.textSecondary)),
          const SizedBox(height: 22),
          HtCard(
            radius: HtRadius.inner,
            child: Column(children: [
              htKv(context, 'Job', '#HT-0B8491'),
              htKv(context, 'Paid into escrow', '₦89,250', strong: true),
              htKv(context, 'Verified by', 'HandyTrust server'),
            ]),
          ),
          const SizedBox(height: 24),
          HtPrimaryButton(label: 'View Job', onPressed: () {}),
        ],
      );
    });

Widget cuAbout() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: const HtScreenHeader(title: 'About'),
        children: [
          const SizedBox(height: 20),
          Center(child: HtIconCircle(icon: Icons.verified_user_outlined, size: 84, fill: p.accentSoft, iconColor: p.accentSoftText)),
          const SizedBox(height: 14),
          Text('HandyTrust', textAlign: TextAlign.center, style: HtType.screenTitle(p.textPrimary)),
          Text('Version 1.0.0', textAlign: TextAlign.center, style: HtType.small(p.textSecondary)),
          const SizedBox(height: 24),
          HtCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              HtMenuRow(icon: Icons.description_outlined, title: 'Terms of Service', onTap: () {}),
              HtMenuRow(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', onTap: () {}),
            ]),
          ),
        ],
      );
    });

// ─── Authentication states ──────────────────────────────────────────────────

Widget _fieldError(BuildContext context, String label, String value, String error) {
  final p = context.ht;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    HtFieldLabel(label),
    Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(HtRadius.input), border: Border.all(color: p.danger, width: 1.4)),
      child: Text(value, style: HtType.body(p.textPrimary)),
    ),
    Padding(padding: const EdgeInsets.only(left: 12, top: 6), child: Text(error, style: HtType.small(p.danger))),
  ]);
}

Widget authRegisterErrors() => Builder(builder: (context) {
      return PhoneScreen(
        deep: true,
        children: [
          const SizedBox(height: 12),
          _brandPill(context),
          _authHero(context, 'Create your ', 'account', 'Hire trusted hands or offer your services.'),
          const HtInfoBanner(icon: Icons.error_outline_rounded, tone: HtTone.danger, title: 'Registration failed', text: 'An account with this email already exists.'),
          htField(context, 'Full Name', 'Funke Adeyemi'),
          _fieldError(context, 'Email Address', 'funke.a@example', 'Enter a valid email address'),
          _fieldError(context, 'Password', '••••••', 'Password must be at least 8 characters'),
          _fieldError(context, 'Confirm Password', '•••••••', 'Passwords do not match'),
          const SizedBox(height: 24),
          HtPrimaryButton(label: 'Create Account', onPressed: () {}),
        ],
      );
    });

Widget authResetSent() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        deep: true,
        header: const HtScreenHeader(title: ''),
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: p.successSoft, shape: BoxShape.circle),
              child: Icon(Icons.mark_email_read_outlined, size: 44, color: p.success),
            ),
          ),
          const SizedBox(height: 24),
          Text('Check your inbox', textAlign: TextAlign.center, style: HtType.screenTitle(p.textPrimary)),
          const SizedBox(height: 10),
          Text('We sent a password reset link to\nfunke.a@example.com', textAlign: TextAlign.center, style: HtType.body(p.textSecondary)),
          const SizedBox(height: 18),
          const HtInfoBanner(icon: Icons.open_in_new_rounded, tone: HtTone.neutral, text: 'The link opens a secure Firebase page where you choose a new password, then you can sign in here.'),
          const SizedBox(height: 26),
          HtPrimaryButton(label: 'Back to Login', onPressed: () {}),
        ],
      );
    });

Widget authSplash() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        deep: true,
        children: [
          const SizedBox(height: 230),
          Center(child: HtIconCircle(icon: Icons.verified_user_outlined, size: 88, fill: p.accentSoft, iconColor: p.accentSoftText)),
          const SizedBox(height: 18),
          Text('HandyTrust', textAlign: TextAlign.center, style: HtType.screenTitle(p.textPrimary)),
          const SizedBox(height: 28),
          Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, value: 0.7, color: p.isDark ? p.accent : p.accentStrong))),
        ],
      );
    });

Widget authStartupError() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        deep: true,
        children: [
          const SizedBox(height: 150),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: p.dangerSoft, shape: BoxShape.circle),
              child: Icon(Icons.wifi_tethering_error_rounded, size: 44, color: p.danger),
            ),
          ),
          const SizedBox(height: 24),
          Text('Something went wrong while starting HandyTrust.', textAlign: TextAlign.center, style: HtType.sectionTitle(p.textPrimary)),
          const SizedBox(height: 10),
          Text('Check your internet connection and try again.', textAlign: TextAlign.center, style: HtType.body(p.textSecondary)),
          const SizedBox(height: 26),
          HtPrimaryButton(label: 'Retry', leadingIcon: Icons.refresh_rounded, onPressed: () {}),
        ],
      );
    });
