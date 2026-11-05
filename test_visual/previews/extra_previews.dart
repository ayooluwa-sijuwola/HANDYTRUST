// Stage 8 complete-audit PREVIEWS, batch 2: system screens, nested
// screens, dialogs and sheets found by the application-wide audit
// (design/STAGE8_COMPLETE_SCREEN_INVENTORY.md). SAMPLE DATA; copy and
// actions mirror the existing implementation unless marked PROPOSED.
import 'package:flutter/material.dart';
import 'package:handy_trust/ui/components/ht_components.dart';
import 'package:handy_trust/ui/theme/ht_theme.dart';

import 'admin_previews.dart' show adUsers;
import 'artisan_pro_kit.dart';
import 'artisan_previews.dart' show proHome, proSchedule;
import 'preview_kit.dart';
import 'shared_previews.dart' show cuSettings;

/// Proposed app ThemeData derived from HtPalette, so Material pickers and
/// dialogs follow the design system (Phase C: used by main.dart).
ThemeData htThemeData(HtPalette p) => ThemeData(
      useMaterial3: true,
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: p.background,
      fontFamily: HtType.text,
      colorScheme: ColorScheme(
        brightness: p.isDark ? Brightness.dark : Brightness.light,
        primary: p.isDark ? p.accent : p.accentStrong,
        onPrimary: p.isDark ? p.onPrimary : Colors.white,
        secondary: p.accentStrong,
        onSecondary: Colors.white,
        error: p.danger,
        onError: Colors.white,
        surface: p.surface,
        onSurface: p.textPrimary,
      ),
      dialogTheme: DialogThemeData(backgroundColor: p.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HtRadius.card))),
    );

// ─── Overlay helpers ────────────────────────────────────────────────────────

/// Renders [base] with a dimmed scrim and a centred dialog card on top.
Widget _dialogOver(Widget base, Widget Function(BuildContext) dialog) => Builder(builder: (context) {
      final p = context.ht;
      return Stack(children: [
        base,
        Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: p.isDark ? 0.6 : 0.35))),
        Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Material(type: MaterialType.transparency, child: dialog(context)))),
      ]);
    });

Widget _actions(BuildContext context, String cancel, String confirm, {bool danger = false}) {
  return Row(children: [
    Expanded(child: HtSecondaryButton(label: cancel, onPressed: () {})),
    const SizedBox(width: 12),
    Expanded(child: danger ? HtDangerButton(label: confirm) : HtPrimaryButton(label: confirm, height: 46, onPressed: () {})),
  ]);
}

// ─── System screens ─────────────────────────────────────────────────────────

Widget _statusScreen(BuildContext context, {required IconData icon, required HtTone tone, required String title, required String body, required List<Widget> actions}) {
  final p = context.ht;
  final (bg, fg) = switch (tone) {
    HtTone.success => (p.successSoft, p.success),
    HtTone.danger => (p.dangerSoft, p.danger),
    HtTone.warning => (p.warningSoft, p.warning),
    _ => (p.accentSoft, p.accentSoftText),
  };
  return PhoneScreen(deep: true, children: [
    const SizedBox(height: 120),
    Center(child: Container(width: 96, height: 96, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Icon(icon, size: 44, color: fg))),
    const SizedBox(height: 24),
    Text(title, textAlign: TextAlign.center, style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 24)),
    const SizedBox(height: 10),
    Text(body, textAlign: TextAlign.center, style: HtType.body(p.textSecondary)),
    const SizedBox(height: 26),
    ...actions,
  ]);
}

Widget syNotFound() => Builder(builder: (context) => _statusScreen(context,
    icon: Icons.explore_off_outlined,
    tone: HtTone.accent,
    title: 'Page not found',
    body: 'This link doesn’t match any page in HandyTrust.',
    actions: [HtPrimaryButton(label: 'Go to home', onPressed: () {})]));

Widget syCannotOpen() => Builder(builder: (context) => _statusScreen(context,
    icon: Icons.link_off_rounded,
    tone: HtTone.warning,
    title: 'This page can’t be opened directly',
    body: 'Please navigate here from within the app instead of using a direct link, refresh, or bookmark.',
    actions: [HtPrimaryButton(label: 'Go back', onPressed: () {})]));

// ─── Payment ────────────────────────────────────────────────────────────────

Widget cuPaymentCheckout() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: const HtScreenHeader(title: 'Secure Payment', subtitle: 'Job #HT-0B8491 · ₦89,250'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        children: [
          Container(
            height: 640,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border)),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline_rounded, color: Color(0xFF6B7063), size: 32),
                const SizedBox(height: 10),
                Text('Paystack checkout loads here', style: HtType.bodyStrong(const Color(0xFF141712))),
                Text('(third-party page, not restyled)', style: HtType.small(const Color(0xFF6B7063))),
              ]),
            ),
          ),
        ],
      );
    });

Widget cuPaymentNotCompleted() => Builder(builder: (context) => _statusScreen(context,
    icon: Icons.error_outline_rounded,
    tone: HtTone.danger,
    title: 'Payment Not Completed',
    body: 'We couldn’t confirm this payment with Paystack. No funds were moved — you can try again.',
    actions: [HtPrimaryButton(label: 'Try Again', onPressed: () {}), const SizedBox(height: 12), HtSecondaryButton(label: 'View Job', onPressed: () {})]));

Widget cuPaymentVerifying() => Builder(builder: (context) {
      final p = context.ht;
      return _statusScreen(context,
          icon: Icons.hourglass_top_rounded,
          tone: HtTone.accent,
          title: 'Verifying payment…',
          body: 'Checking the payment with HandyTrust’s server.',
          actions: [Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, value: 0.65, color: p.isDark ? p.accent : p.accentStrong)))]);
    });

/// Approved (Q-7), new: transaction detail sheet over the
/// Payments list, showing only existing PaymentModel fields.
Widget cuTransactionDetail() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: const HtScreenHeader(title: 'Payments'),
        sheet: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Payment details', style: HtType.sectionTitle(p.textPrimary))),
            const HtStatusPill(label: 'In escrow', tone: HtTone.warning, icon: Icons.lock_outline_rounded),
          ]),
          const SizedBox(height: 6),
          Text('Repaint living room · Job #HT-0B8491', style: HtType.small(p.textSecondary)),
          const SizedBox(height: 14),
          HtCard(
            radius: HtRadius.inner,
            color: p.surfaceRaised,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              htKv(context, 'Service amount', '₦85,000'),
              htKv(context, 'Platform fee (5%)', '₦4,250'),
              Divider(color: p.border),
              htKv(context, 'Total charged', '₦89,250', strong: true),
            ]),
          ),
          const SizedBox(height: 10),
          htKv(context, 'Paystack reference', 'HT_0B8491_1729'),
          htKv(context, 'Paid', '21 Oct 2026, 10:03 AM'),
          htKv(context, 'Released', 'Not yet released'),
          const SizedBox(height: 16),
          HtPrimaryButton(label: 'View job', onPressed: () {}),
        ]),
        children: const [SizedBox(height: 400)],
      );
    });

// ─── Job detail, customer view ──────────────────────────────────────────────

Widget cuJobDetailQuotes() => Builder(builder: (context) {
      final p = context.ht;
      Widget quote(String name, String meta, String price, String detail, bool isNew) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HtCard(
              radius: HtRadius.inner,
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  HtAvatar(name: name, size: 44),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: HtType.bodyStrong(p.textPrimary)), Text(meta, style: HtType.small(p.textSecondary))])),
                  if (isNew) const HtStatusPill(label: 'New', tone: HtTone.accent),
                ]),
                const SizedBox(height: 12),
                Row(children: [Text(price, style: HtType.amount(p.textPrimary, size: 20)), const Spacer(), Text(detail, style: HtType.small(p.textSecondary))]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: HtSecondaryButton(label: 'Chat', onPressed: () {})),
                  const SizedBox(width: 8),
                  Expanded(child: HtSecondaryButton(label: 'Decline', onPressed: () {})),
                  const SizedBox(width: 8),
                  Expanded(child: HtSmallPrimaryButton(label: 'Accept', onPressed: () {})),
                ]),
              ]),
            ),
          );
      return PhoneScreen(
        header: HtScreenHeader(title: 'Job #HT-5D7720', trailing: const HtIconCircle(icon: Icons.more_horiz_rounded, tooltip: 'More')),
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ELECTRICAL', style: HtType.caps(p.textMuted)),
              Text('Replace faulty socket', style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 23)),
            ])),
            const HtStatusPill(label: 'Requested', dot: true),
          ]),
          const SizedBox(height: 18),
          const HtSectionHeader(title: 'Quotes', badge: '3'),
          const SizedBox(height: 10),
          Row(children: [Text('Sort by', style: HtType.small(p.textSecondary)), const SizedBox(width: 10), HtChip(label: 'Price', selected: true, onTap: () {}), const SizedBox(width: 8), HtChip(label: 'Trust', selected: false, onTap: () {})]),
          const SizedBox(height: 14),
          quote('Aisha Bello', 'Electrician · ★ 4.9 · Trust 91', '₦18,000', '1 day · materials incl.', true),
          quote('Kola Ade', 'Electrician · ★ 4.6 · Trust 78', '₦21,500', '1 day', false),
          const SizedBox(height: 4),
          const HtInfoBanner(icon: Icons.lock_outline_rounded, text: 'Accepting a quote doesn’t charge you. You pay into escrow after you both confirm the agreement.'),
          const SizedBox(height: 12),
          Center(child: Text('Cancel job', style: HtType.bodyStrong(p.danger).copyWith(fontSize: 13.5))),
        ],
      );
    });

// ─── Portfolio ──────────────────────────────────────────────────────────────

Widget shPortfolioViewer() => Builder(builder: (context) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            const Center(child: SizedBox(width: 360, height: 460, child: HtPhotoTile(label: 'Project photo (full screen)', height: 460))),
            Positioned(top: 8, left: 16, child: HtIconCircle(icon: Icons.close_rounded, fill: Colors.white.withValues(alpha: 0.12), iconColor: Colors.white, tooltip: 'Close')),
            Positioned(
              left: 20,
              right: 20,
              bottom: 40,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bathroom re-pipe', style: HtType.cardTitle(Colors.white)),
                Text('2 of 5 · Plumbing', style: HtType.small(Colors.white70)),
              ]),
            ),
            const Positioned(top: 14, left: 0, right: 0, child: Center(child: PreviewTag())),
          ]),
        ),
      );
    });

Widget arPortfolioProject() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: proBackHeader(context, 'Add project', sub: 'Portfolio'),
        bottomBar: HtPrimaryButton(label: 'Save Project', onPressed: () {}),
        children: [
          htField(context, 'Project Title', 'Bathroom re-pipe'),
          const HtFieldLabel('Category'),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final (i, c) in ['Plumbing', 'Electrical', 'Painting'].indexed) HtChip(label: c, selected: i == 0, onTap: () {})]),
          htField(context, 'Description', 'Describe the project…', lines: 3),
          const HtFieldLabel('Photos', trailing: '2 / 10'),
          Row(children: [
            const Expanded(child: HtPhotoTile(label: 'Before')),
            const SizedBox(width: 10),
            const Expanded(child: HtPhotoTile(label: 'After')),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 96,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(HtRadius.tile), border: Border.all(color: p.accentStrong, width: 1.4)),
                child: Center(child: Icon(Icons.add_a_photo_outlined, color: p.accent)),
              ),
            ),
          ]),
        ],
      );
    });

// ─── Artisan sheets ─────────────────────────────────────────────────────────

Widget arFeedFilterSheet() => Builder(builder: (context) {
      final p = context.ht;
      return PhoneScreen(
        header: htTabHeader(context, name: 'Tunde'),
        sheet: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Matched Job Opportunities', style: HtType.sectionTitle(p.textPrimary)),
          const HtFieldLabel('Status'),
          Wrap(spacing: 8, runSpacing: 8, children: [HtChip(label: 'All Matched', selected: true, onTap: () {}), HtChip(label: 'Recent', selected: false, onTap: () {}), HtChip(label: 'Urgent', selected: false, onTap: () {})]),
          const SizedBox(height: 20),
          Row(children: [Expanded(child: HtSecondaryButton(label: 'Clear filters', onPressed: () {})), const SizedBox(width: 12), Expanded(child: HtPrimaryButton(label: 'Show 3 jobs', height: 46, onPressed: () {}))]),
        ]),
        children: const [SizedBox(height: 400)],
      );
    });

Widget arTrustScoreSheet() => Builder(builder: (context) {
      final p = context.ht;
      Widget row(String l, double f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(l, style: HtType.smallStrong(p.textPrimary))), Text('${(f * 100).round()}%', style: HtType.smallStrong(p.textSecondary))]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: f, minHeight: 8, color: htChartColors(p).first, backgroundColor: p.surfaceRaised),
              ),
            ]),
          );
      return Stack(children: [
        proHome(),
        Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: p.isDark ? 0.6 : 0.35))),
        Positioned(left: 0, right: 0, bottom: 0, child: Material(type: MaterialType.transparency, child: HtSheet(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('TRUSTSCORE', style: HtType.caps(p.textMuted)),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('86', style: HtType.amount(p.textPrimary, size: 40)),
            const SizedBox(width: 6),
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('/100 · Trusted', style: HtType.bodyStrong(p.textSecondary))),
          ]),
          const SizedBox(height: 16),
          row('Completed Jobs', 0.84),
          row('Customer Rating', 0.96),
          row('Verification', 1.0),
          row('Response Time', 0.72),
          row('Dispute History', 0.9),
          Text('A higher score leads to more visibility in search results.', style: HtType.small(p.textSecondary)),
        ])))),
      ]);
    });

// ─── Dialogs (settings, job) ────────────────────────────────────────────────

Widget dlEditName() => _dialogOver(cuSettings(), (c) => HtDialogCard(title: 'Edit Name', children: [
      htField(c, 'Full Name', 'Funke Adeyemi'),
      const SizedBox(height: 20),
      _actions(c, 'Cancel', 'Save'),
    ]));

Widget dlChangeEmail() => _dialogOver(cuSettings(), (c) => HtDialogCard(title: 'Change Email', children: [
      Text('Enter your current password and the new email. A verification link will be sent to the new address.', style: HtType.small(c.ht.textSecondary)),
      htField(c, 'Current Password', '••••••••'),
      htField(c, 'New Email', 'funke.new@example.com'),
      const SizedBox(height: 20),
      _actions(c, 'Cancel', 'Update'),
    ]));

Widget dlChangePassword() => _dialogOver(cuSettings(), (c) => HtDialogCard(title: 'Change Password', children: [
      htField(c, 'Current Password', '••••••••'),
      htField(c, 'New Password', '••••••••••'),
      // Q-3: same rule as sign-up (8+ characters, an uppercase letter, a number).
      Padding(padding: const EdgeInsets.only(left: 12, top: 6), child: Text('At least 8 characters, with an uppercase letter and a number.', style: HtType.small(c.ht.textSecondary))),
      htField(c, 'Confirm New Password', '••••••••••'),
      const SizedBox(height: 20),
      _actions(c, 'Cancel', 'Update'),
    ]));

Widget dlRequestDeletion() => _dialogOver(cuSettings(), (c) => HtDialogCard(title: 'Request Account Deletion', children: [
      // Q-6: no unverified timing; F-12: no unenforced precondition claims.
      Text('An administrator will review your request. Your job history, payments and reviews are kept.', style: HtType.body(c.ht.textSecondary)),
      htField(c, 'Reason (optional)', 'e.g. I no longer use the app', lines: 2),
      const SizedBox(height: 20),
      _actions(c, 'Cancel', 'Submit Request', danger: true),
    ]));

Widget dlSwitchMode() => _dialogOver(cuSettings(), (c) {
      final p = c.ht;
      Widget opt(String t, String s, bool sel) => Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: sel ? p.accentSoft : p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: sel ? p.accentStrong : p.border)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: HtType.bodyStrong(p.textPrimary)), Text(s, style: HtType.small(p.textSecondary))])),
              Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: sel ? p.accentStrong : p.textMuted),
            ]),
          );
      return HtDialogCard(title: 'Active Mode', children: [
        opt('Customer', 'Post jobs and hire artisans', false),
        opt('Artisan', 'Find work and manage your jobs', true),
        const SizedBox(height: 20),
        _actions(c, 'Cancel', 'Switch'),
      ]);
    });

Widget dlCancelJob() => _dialogOver(cuJobDetailQuotes(), (c) => HtDialogCard(title: 'Cancel Job', children: [
      Text('Select a reason:', style: HtType.small(c.ht.textSecondary)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (i, r) in ['Found another artisan', 'No longer needed', 'Too expensive', 'Other'].indexed) HtChip(label: r, selected: i == 1, onTap: () {}),
      ]),
      const SizedBox(height: 20),
      _actions(c, 'Keep Job', 'Confirm Cancel', danger: true),
    ]));

Widget dlRequestChanges() => _dialogOver(cuJobDetailQuotes(), (c) => HtDialogCard(title: 'Request Changes', children: [
      htField(c, 'What would you like to change?', 'Please include ceiling paint in the scope.', lines: 3),
      const SizedBox(height: 20),
      _actions(c, 'Cancel', 'Send'),
    ]));

Widget dlDatePicker() => Builder(builder: (context) {
      final p = context.ht;
      return Theme(
        data: htThemeData(p),
        child: _dialogOver(
          proSchedule(),
          (c) => DatePickerDialog(initialDate: DateTime(2026, 10, 24), firstDate: DateTime(2026, 10, 1), lastDate: DateTime(2027, 1, 31), currentDate: DateTime(2026, 10, 24)),
        ),
      );
    });

// ─── Admin ──────────────────────────────────────────────────────────────────

Widget adArtisansPending() => Builder(builder: (context) {
      final p = context.ht;
      Widget app(String n, String meta, String about, List<String> skills) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: HtCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  HtAvatar(name: n, size: 48),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(n, style: HtType.cardTitle(p.textPrimary)), Text(meta, style: HtType.small(p.textSecondary))])),
                  const HtStatusPill(label: 'Pending', tone: HtTone.warning, dot: true),
                ]),
                const SizedBox(height: 12),
                Text('About', style: HtType.caps(p.textMuted)),
                Text(about, style: HtType.small(p.textPrimary)),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final s in skills) HtStatusPill(label: s, tone: HtTone.accent)]),
                const SizedBox(height: 14),
                Row(children: [const Spacer(), const SizedBox(width: 160, child: HtDangerButton(label: 'Reject')), const SizedBox(width: 10), SizedBox(width: 160, child: HtPrimaryButton(label: 'Approve', height: 46, onPressed: () {}))]),
              ]),
            ),
          );
      return AdminFrame(section: 'Artisans', title: 'Artisans', subtitle: 'Applications and approved artisans', children: [
        Row(children: [HtChip(label: 'Pending', count: 4, selected: true, onTap: () {}), const SizedBox(width: 8), HtChip(label: 'All artisans', count: 312, selected: false, onTap: () {})]),
        const SizedBox(height: 16),
        app('Aisha Bello', 'Electrical · Ibadan · applied 2 d ago', 'Licensed electrician, 6 years with residential rewiring.', ['Rewiring', 'Sockets', 'Inverters']),
        app('Kola Ade', 'Carpentry · Lagos · applied 3 d ago', 'Furniture repair and fitted wardrobes.', ['Wardrobes', 'Doors']),
      ]);
    });

Widget adReviews() => Builder(builder: (context) {
      return AdminFrame(section: 'Reviews', title: 'Reviews', subtitle: 'Customer ratings of completed jobs', children: [
        HtFilterBar(hint: 'Search reviews by comment…', chips: const ['All', '5★', '4★', '3★', '≤2★']),
        const SizedBox(height: 16),
        HtDataTable(
          columns: const [HtColumn('Rating', flex: 1), HtColumn('Comment', flex: 5), HtColumn('Artisan'), HtColumn('Date'), HtColumn('', flex: 1, numeric: true)],
          rows: [
            for (final r in [('5.0', 'Fixed the leak fast and left the kitchen clean.', 'Tunde Balogun', '22 Oct'), ('2.0', 'Arrived late and did not finish.', 'Kola Ade', '20 Oct'), ('4.0', 'Good work, slightly over the estimate.', 'Aisha Bello', '18 Oct')])
              [tCell(context, '★ ${r.$1}', strong: true), tCell(context, r.$2), tCell(context, r.$3), tCell(context, r.$4, muted: true), Icon(Icons.delete_outline_rounded, color: context.ht.danger, size: 20)],
          ],
        ),
      ]);
    });

Widget adSupport() => Builder(builder: (context) {
      final p = context.ht;
      return AdminFrame(
        section: 'Support',
        title: 'Support tickets',
        subtitle: 'Questions from customers and artisans',
        panel: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text('Payment not showing', style: HtType.cardTitle(p.textPrimary))), const HtStatusPill(label: 'Open', tone: HtTone.warning, dot: true)]),
          Text('From Funke Adeyemi · 22 Oct 2026', style: HtType.small(p.textSecondary)),
          const SizedBox(height: 14),
          HtCard(radius: HtRadius.inner, color: p.surfaceRaised, child: Text('I paid for my job yesterday but it still shows Pending.', style: HtType.body(p.textPrimary))),
          htField(context, 'Your response to the user', 'Your payment is confirmed; the status updated this morning.', lines: 3),
          const SizedBox(height: 16),
          HtPrimaryButton(label: 'Respond & Resolve', onPressed: () {}),
        ]),
        children: [
          HtFilterBar(hint: 'Search by subject or user…', chips: const ['All', 'Open', 'Resolved'], selected: 1),
          const SizedBox(height: 16),
          HtDataTable(
            selected: 0,
            columns: const [HtColumn('Subject', flex: 4), HtColumn('From', flex: 3), HtColumn('Created'), HtColumn('Status')],
            rows: [
              for (final r in [('Payment not showing', 'Funke Adeyemi', '22 Oct', 'Open'), ('Cannot upload ID', 'Aisha Bello', '21 Oct', 'Open'), ('Change my phone number', 'Kunle Ade', '10 Oct', 'Resolved')])
                [tCell(context, r.$1, strong: true), tCell(context, r.$2), tCell(context, r.$3, muted: true), HtStatusPill(label: r.$4, tone: r.$4 == 'Open' ? HtTone.warning : HtTone.success, dot: true)],
            ],
          ),
        ],
      );
    });

Widget adDeletions() => Builder(builder: (context) {
      final p = context.ht;
      return AdminFrame(section: 'Deletion requests', title: 'Deletion requests', subtitle: 'Users who asked for their account to be deleted', children: [
        for (final r in [('Kunle Ade', 'kunle.a@example.com', 'Requested 23 Oct 2026', 'No longer using the app'), ('Bisi Ola', 'bisi.o@example.com', 'Requested 21 Oct 2026', '—')])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HtCard(
              child: Row(children: [
                HtAvatar(name: r.$1, size: 46),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.$1, style: HtType.cardTitle(p.textPrimary)), Text('${r.$2} · ${r.$3}', style: HtType.small(p.textSecondary)), Text('Reason: ${r.$4}', style: HtType.small(p.textMuted))])),
                HtSecondaryButton(label: 'Open user', dense: true, onPressed: () {}),
                const SizedBox(width: 10),
                HtSmallPrimaryButton(label: 'Mark Resolved', onPressed: () {}),
              ]),
            ),
          ),
      ]);
    });

Widget adAnalytics() => Builder(builder: (context) {
      return AdminFrame(section: 'Analytics', title: 'Analytics', subtitle: 'Trends derived from live records', children: [
        htGrid(const [
          HtKpiTile(icon: Icons.person_add_alt_outlined, label: 'New Users', value: '86', note: 'Last 8 weeks'),
          HtKpiTile(icon: Icons.add_task_rounded, label: 'New Jobs', value: '214', note: 'Last 8 weeks'),
          HtKpiTile(icon: Icons.shield_outlined, label: 'Avg Trust Score', value: '74', note: 'Across artisans'),
          HtKpiTile(icon: Icons.event_available_outlined, label: 'Appt Confirmed', value: '131', note: 'Jobs with a confirmed slot'),
        ], columns: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: HtChartCard(
              title: 'User & Job Growth',
              subtitle: 'Last 8 weeks',
              legend: const ['New users', 'New jobs'],
              height: 220,
              child: htLineChart(context, const [
                [6, 8, 9, 11, 10, 12, 14, 16],
                [18, 22, 21, 26, 25, 29, 33, 40],
              ], const ['W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7', 'W8']),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: Column(children: [
              HtChartCard(title: 'Rating Distribution', height: 150, child: htBarList(context, const [('5 stars', 412), ('4 stars', 201), ('3 stars', 48), ('2 stars', 17), ('1 star', 9)])),
            ]),
          ),
        ]),
      ]);
    });

Widget adSearch() => Builder(builder: (context) {
      final p = context.ht;
      return AdminFrame(
        section: 'Dashboard',
        title: 'Dashboard',
        overlay: HtDialogCard(title: 'Search', children: [
          HtFilterBar(hint: 'Search or jump to a section…'),
          const SizedBox(height: 14),
          Text('GO TO', style: HtType.caps(p.textMuted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final s in ['Users', 'Jobs', 'Disputes', 'Finance', 'Audit logs']) HtChip(label: s, selected: false, onTap: () {})]),
          const SizedBox(height: 14),
          Text('PEOPLE', style: HtType.caps(p.textMuted)),
          HtMenuRow(icon: Icons.person_outline_rounded, title: 'Funke Adeyemi', subtitle: 'Customer · funke.a@example.com', onTap: () {}),
          HtMenuRow(icon: Icons.handyman_outlined, title: 'Tunde Balogun', subtitle: 'Artisan · Plumbing', onTap: () {}),
          Text('JOBS', style: HtType.caps(p.textMuted)),
          HtMenuRow(icon: Icons.work_outline_rounded, title: '#HT-0B8491 · Painting', subtitle: 'In progress', onTap: () {}),
        ]),
        children: const [SizedBox(height: 600)],
      );
    });

Widget adNotifications() => Builder(builder: (context) {
      final p = context.ht;
      Widget n(IconData i, String t, String s) => HtMenuRow(icon: i, title: t, subtitle: s, onTap: () {});
      return AdminFrame(
        section: 'Dashboard',
        title: 'Dashboard',
        overlay: HtDialogCard(title: 'Notifications', children: [
          n(Icons.handyman_outlined, 'New artisan application', 'Aisha Bello · 2 h ago'),
          n(Icons.verified_user_outlined, 'New verification request', 'Kola Ade · 5 h ago'),
          n(Icons.support_agent_rounded, 'New support ticket', 'Payment not showing · 1 d ago'),
          n(Icons.gavel_rounded, 'Job dispute raised', '#HT-3A9115 · 2 d ago'),
          const SizedBox(height: 8),
          Text('Opens the related section.', style: HtType.small(p.textMuted)),
        ]),
        children: const [SizedBox(height: 600)],
      );
    });

Widget adReasonDialog() => Builder(builder: (context) {
      final p = context.ht;
      return Stack(children: [
        adUsers(),
        Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: p.isDark ? 0.6 : 0.35))),
        Center(
          child: SizedBox(
            width: 520,
            child: Material(
              type: MaterialType.transparency,
              child: HtDialogCard(title: 'Delete User?', children: [
                // Existing copy; adminDeleteUser takes only the uid (no reason)
                // and writes its own admin_audit_logs entry.
                Text('This permanently deletes Emeka Okafor’s sign-in, profile and photos. Their job history, payments, and reviews are kept — this cannot be undone.', style: HtType.body(p.textSecondary)),
                const SizedBox(height: 12),
                const HtInfoBanner(icon: Icons.history_rounded, tone: HtTone.neutral, text: 'Recorded in the audit log.'),
                const SizedBox(height: 18),
                _actions(context, 'Cancel', 'Delete user', danger: true),
              ]),
            ),
          ),
        ),
      ]);
    });
