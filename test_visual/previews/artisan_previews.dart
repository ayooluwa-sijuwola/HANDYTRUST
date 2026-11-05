// Stage 8.1 REVISED artisan previews ("HandyTrust Pro"). Purpose-built
// artisan layouts — not customer screens with new labels. SAMPLE DATA; every
// value shown maps to an existing field or provider (see
// design/STAGE8_ARTISAN_REDESIGN_PREVIEW.md). Not wired to providers.
import 'package:flutter/material.dart';
import 'package:handy_trust/ui/components/ht_components.dart';
import 'package:handy_trust/ui/theme/ht_theme.dart';

import 'artisan_pro_kit.dart';
import 'preview_kit.dart';

Color _a(HtPalette p) => p.isDark ? p.accent : p.accentStrong;

Widget _proScreen(BuildContext context, {required List<Widget> children, int? nav, Widget? header, Widget? bottomBar, Widget? sheet}) => PhoneScreen(
      header: header ?? const ProHeader(name: 'Tunde Balogun', trade: 'Plumber · Ibadan', messages: 2, alerts: 3),
      navBar: nav == null ? null : ProNavBar(current: nav),
      bottomBar: bottomBar,
      sheet: sheet,
      children: children,
    );

Widget _workHeader(BuildContext context, String title, {String? sub}) => proBackHeader(context, title, sub: sub);

Widget _title(BuildContext context, String t) => Text(t, style: HtType.screenTitle(context.ht.textPrimary).copyWith(fontSize: 25));

Widget _addTile(BuildContext context, double h) {
  final p = context.ht;
  return Container(height: h, decoration: BoxDecoration(borderRadius: BorderRadius.circular(HtRadius.tile), border: Border.all(color: _a(p), width: 1.4)), child: Center(child: Icon(Icons.add_a_photo_outlined, color: _a(p))));
}

// ─── Home: today ────────────────────────────────────────────────────────────

Widget proHome() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, nav: 0, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: p.isDark ? [const Color(0xFF2A3315), p.surface] : [p.accentSoft, p.surface], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(HtRadius.inner),
            border: Border.all(color: p.border),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ready to work', style: HtType.sectionTitle(p.textPrimary)),
                Text('Matching jobs within 15 km of Bodija', style: HtType.small(p.textSecondary)),
              ]),
            ),
            Switch(value: true, onChanged: (_) {}, activeThumbColor: p.isDark ? p.onPrimary : Colors.white, activeTrackColor: _a(p)),
          ]),
        ),
        proSection(context, 'Needs your action', count: 3),
        const ProActionCard(tone: HtTone.danger, icon: Icons.mark_email_unread_outlined, title: 'Booking request · Kitchen sink leak', subtitle: 'Funke Adeyemi · Bodija · ₦24,500 quote', deadline: 'Respond within 18 h', action: 'Respond'),
        const ProActionCard(tone: HtTone.warning, icon: Icons.handshake_outlined, title: 'Agreement changes requested', subtitle: '“Please include the ceiling.” · #HT-0B8491', action: 'Revise'),
        const ProActionCard(tone: HtTone.accent, icon: Icons.event_available_outlined, title: 'Propose appointment times', subtitle: 'Escrow funded · #HT-7C2210', action: 'Schedule'),
        proSection(context, 'Work pipeline', trailing: 'My Jobs'),
        const ProPipeline(stages: [('Requests', 1), ('Agreement', 1), ('Scheduled', 2), ('Working', 1), ('In review', 2)]),
        proSection(context, 'Next appointment'),
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: _a(p), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text('THU', style: HtType.caps(p.isDark ? p.onPrimary : Colors.white).copyWith(fontSize: 10)),
                Text('24', style: HtType.amount(p.isDark ? p.onPrimary : Colors.white, size: 22)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('9:00 AM · Repaint living room', style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)),
                Text('Funke Adeyemi · Bodija, Ibadan', style: HtType.small(p.textSecondary)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ]),
        ),
        proSection(context, 'This month', trailing: 'Earnings'),
        htGrid(const [
          ProStat(icon: Icons.south_west_rounded, label: 'Released to you', value: '₦117,000', sub: '3 jobs · October'),
          ProStat(icon: Icons.lock_outline_rounded, label: 'In escrow', value: '₦85,000', sub: '1 funded job'),
        ], columns: 2, gap: 10),
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const ProCountdownRing(fraction: 0.86, big: '86', small: 'Trust', size: 70, tone: HtTone.success),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Trusted artisan', style: HtType.bodyStrong(p.textPrimary)),
                Text('Strongest: Verification · Customer rating', style: HtType.small(p.textSecondary)),
                const SizedBox(height: 4),
                Text('See breakdown', style: HtType.smallStrong(_a(p))),
              ]),
            ),
          ]),
        ),
      ]);
    });

/// New artisan: verification pending, no payout account, empty pipeline.
Widget proHomeNew() => Builder(builder: (context) {
      final p = context.ht;
      Widget step(String t, String s, int state) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: state == 2 ? p.success : (state == 1 ? p.warningSoft : p.surfaceRaised), shape: BoxShape.circle),
                child: Icon(state == 2 ? Icons.check_rounded : (state == 1 ? Icons.hourglass_top_rounded : Icons.circle_outlined), size: 16, color: state == 2 ? Colors.white : (state == 1 ? p.warning : p.textMuted)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5)), Text(s, style: HtType.small(p.textSecondary))])),
            ]),
          );
      return _proScreen(context, header: const ProHeader(name: 'Kola Ade', trade: 'Carpenter · Lagos', available: false, alerts: 1), nav: 0, children: [
        Text('Get ready to quote', style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 24)),
        Text('Finish these steps to appear in matches.', style: HtType.body(p.textSecondary)),
        const SizedBox(height: 16),
        HtCard(
          child: Column(children: [
            step('Profile submitted', 'Category, skills and service area', 2),
            step('Identity verification', 'Under review by HandyTrust', 1),
            step('Payout account', 'Add the bank account for payouts', 0),
            step('Turn on Ready to work', 'Available once you can quote', 0),
          ]),
        ),
        const SizedBox(height: 12),
        const ProActionCard(tone: HtTone.warning, icon: Icons.account_balance_outlined, title: 'Add payout details', subtitle: 'Released payments need a bank account', action: 'Add'),
        proSection(context, 'Work pipeline'),
        const HtCard(child: HtEmptyView(icon: Icons.assignment_outlined, title: 'No jobs yet', message: 'Matched jobs appear in Find Work once you can quote.')),
      ]);
    });

// ─── Find Work ──────────────────────────────────────────────────────────────

Widget _boardRow(BuildContext context, {required String title, required String meta, required String budget, String? flag, String? quote}) {
  final p = context.ht;
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      htIconTile(context, Icons.plumbing_rounded, size: 40),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (flag != null) ...[const SizedBox(width: 6), Icon(Icons.bolt_rounded, size: 15, color: p.warning), Text(flag, style: HtType.smallStrong(p.warning).copyWith(fontSize: 11.5))],
          ]),
          Text(meta, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Text(budget, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5)),
            const Spacer(),
            if (quote != null)
              HtStatusPill(label: quote, tone: HtTone.accent, dot: true)
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(color: _a(p), borderRadius: BorderRadius.circular(HtRadius.pill)),
                child: Text('Quote', style: HtType.smallStrong(p.isDark ? p.onPrimary : Colors.white)),
              ),
          ]),
        ]),
      ),
    ]),
  );
}

Widget proFindWork() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, nav: 1, children: [
        Row(children: [Expanded(child: _title(context, 'Find Work')), const HtStatusPill(label: 'Ready to work', tone: HtTone.success, dot: true)]),
        const SizedBox(height: 12),
        proSegments(context, ['Open jobs', 'My quotes'], 0, counts: [12, 3]),
        const SizedBox(height: 12),
        HtFilterBar(hint: 'Search tasks, locations…'),
        const SizedBox(height: 10),
        Row(children: [for (final (i, c) in ['All Matched', 'Recent', 'Urgent'].indexed) ...[HtChip(label: c, selected: i == 0, onTap: () {}), const SizedBox(width: 8)]]),
        const SizedBox(height: 6),
        Text('Matched to Plumbing within 15 km', style: HtType.small(p.textMuted)),
        _boardRow(context, title: 'Kitchen sink leaking under the cabinet', meta: 'Bodija · 2.4 km · posted 3 h ago', budget: '₦20,000 – ₦30,000', flag: 'Urgent'),
        _boardRow(context, title: 'Install a new water heater', meta: 'Jericho · 5.1 km · posted 5 h ago', budget: '₦45,000', quote: 'Quoted ₦42,000'),
        _boardRow(context, title: 'Replace bathroom tap and washers', meta: 'Agodi · 6.8 km · posted 1 d ago', budget: '₦12,000'),
        _boardRow(context, title: 'Unblock outside drain', meta: 'Mokola · 9.0 km · posted 2 d ago', budget: 'No budget given'),
      ]);
    });

Widget proMyQuotes() => Builder(builder: (context) {
      final p = context.ht;
      Widget q(String t, String meta, String amount, String status, HtTone tone, {bool actions = true}) => Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.tile + 2), border: Border.all(color: p.border), boxShadow: p.cardShadow),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(t, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)), HtStatusPill(label: status, tone: tone, dot: true)]),
              Text(meta, style: HtType.small(p.textSecondary)),
              const SizedBox(height: 10),
              Row(children: [
                Text(amount, style: HtType.amount(p.textPrimary, size: 18)),
                const SizedBox(width: 8),
                Text('1 day', style: HtType.small(p.textMuted)),
                const Spacer(),
                if (actions) ...[Text('Edit', style: HtType.smallStrong(_a(p))), const SizedBox(width: 16), Text('Withdraw', style: HtType.smallStrong(p.danger))],
              ]),
            ]),
          );
      return _proScreen(context, nav: 1, children: [
        _title(context, 'Find Work'),
        const SizedBox(height: 12),
        proSegments(context, ['Open jobs', 'My quotes'], 1, counts: [12, 3]),
        proSection(context, 'Waiting for the customer', count: 2),
        q('Install a new water heater', 'Jericho · sent 4 h ago', '₦42,000', 'Pending', HtTone.warning),
        q('Fix leaking shower head', 'Bodija · sent 1 d ago', '₦9,500', 'Pending', HtTone.warning),
        proSection(context, 'Closed'),
        q('Garden tap replacement', 'Agodi · 3 d ago', '₦7,000', 'Declined', HtTone.neutral, actions: false),
        const SizedBox(height: 6),
        HtInfoBanner(icon: Icons.info_outline_rounded, tone: HtTone.neutral, text: 'Quotes on jobs still open in your matches. Accepted quotes become bookings in My Jobs.', trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted)),
      ]);
    });

Widget proQuoteComposer() => Builder(builder: (context) {
      final p = context.ht;
      Widget money(String label, String v, {String? hint}) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)), if (hint != null) Text(hint, style: HtType.small(p.textMuted))])),
              Container(
                width: 150,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.isDark ? Colors.transparent : p.border)),
                child: Row(children: [Text('₦', style: HtType.bodyStrong(p.textMuted)), const SizedBox(width: 6), Text(v, style: HtType.bodyStrong(p.textPrimary))]),
              ),
            ]),
          );
      return _proScreen(context,
          header: _workHeader(context, 'New quote', sub: 'Kitchen sink leaking · Bodija'),
          bottomBar: HtPrimaryButton(label: 'Send quote · ₦24,500', icon: Icons.send_rounded, onPressed: () {}),
          children: [
            HtCard(
              radius: HtRadius.inner,
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('THE JOB', style: HtType.caps(p.textMuted)),
                const SizedBox(height: 6),
                Text('Kitchen sink is leaking under the cabinet and the tap drips constantly.', style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5)),
                const SizedBox(height: 10),
                Row(children: const [Expanded(child: HtPhotoTile(label: 'Photo 1', height: 64)), SizedBox(width: 8), Expanded(child: HtPhotoTile(label: 'Photo 2', height: 64)), SizedBox(width: 8), Expanded(child: SizedBox())]),
                const SizedBox(height: 10),
                Text('Budget ₦20,000 – ₦30,000 · Urgent', style: HtType.smallStrong(p.textSecondary)),
              ]),
            ),
            proSection(context, 'Your price'),
            money('Labour / service', '20,000'),
            money('Materials', '4,500', hint: 'Optional'),
            Row(children: [
              Expanded(child: Text('Estimated duration', style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14))),
              Container(
                decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.isDark ? Colors.transparent : p.border)),
                child: Row(children: [
                  IconButton(onPressed: () {}, icon: Icon(Icons.remove_rounded, color: p.textSecondary)),
                  Text('1 day', style: HtType.bodyStrong(p.textPrimary)),
                  IconButton(onPressed: () {}, icon: Icon(Icons.add_rounded, color: _a(p))),
                ]),
              ),
            ]),
            htField(context, 'Notes for the customer (optional)', 'e.g. parts included, when you can start', lines: 2),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.isDark ? p.backgroundDeep : p.accentSoft, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border)),
              child: Column(children: [
                htKv(context, 'Quote total', '₦24,500', strong: true),
                Text('You receive the full agreed price when the work is approved. The customer pays HandyTrust’s 5% platform fee on top.', style: HtType.small(p.textSecondary)),
              ]),
            ),
          ]);
    });

Widget proQuoteSent() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, header: _workHeader(context, 'Quote sent'), children: [
        const SizedBox(height: 70),
        Center(child: Container(width: 96, height: 96, decoration: BoxDecoration(color: p.successSoft, shape: BoxShape.circle), child: Icon(Icons.send_rounded, size: 42, color: p.success))),
        const SizedBox(height: 22),
        Text('Your quote is with Funke', textAlign: TextAlign.center, style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 23)),
        const SizedBox(height: 8),
        Text('₦24,500 · 1 day. You’ll get a notification if it’s accepted, and you can edit or withdraw it until then.', textAlign: TextAlign.center, style: HtType.body(p.textSecondary)),
        const SizedBox(height: 26),
        HtPrimaryButton(label: 'Back to Find Work', onPressed: () {}),
        const SizedBox(height: 10),
        HtSecondaryButton(label: 'View my quotes', onPressed: () {}),
      ]);
    });

// ─── Booking request ────────────────────────────────────────────────────────

Widget proBookingRequest() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context,
          header: _workHeader(context, 'Booking request', sub: 'Job #HT-5D7720'),
          bottomBar: Row(children: [
            Expanded(child: HtSecondaryButton(label: 'Decline', height: 52, onPressed: () {})),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: HtPrimaryButton(label: 'Accept booking', onPressed: () {})),
          ]),
          children: [
            HtCard(
              child: Row(children: [
                const ProCountdownRing(fraction: 0.75, big: '18 h', small: 'to respond', size: 104, tone: HtTone.danger),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Funke Adeyemi wants to book you', style: HtType.cardTitle(p.textPrimary)),
                    const SizedBox(height: 4),
                    Text('If you don’t respond in time, the job reopens for other artisans.', style: HtType.small(p.textSecondary)),
                  ]),
                ),
              ]),
            ),
            proSection(context, 'The job'),
            HtCard(
              radius: HtRadius.inner,
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Kitchen sink leaking under the cabinet', style: HtType.bodyStrong(p.textPrimary)),
                const SizedBox(height: 6),
                htKv(context, 'Area', 'Bodija, Ibadan · 2.4 km'),
                htKv(context, 'Preferred date', 'As soon as possible'),
                htKv(context, 'Your quote', '₦24,500', strong: true),
                const SizedBox(height: 6),
                Row(children: const [Expanded(child: HtPhotoTile(label: 'Photo 1', height: 70)), SizedBox(width: 8), Expanded(child: HtPhotoTile(label: 'Photo 2', height: 70))]),
              ]),
            ),
            const SizedBox(height: 12),
            const HtInfoBanner(icon: Icons.handshake_outlined, text: 'Accepting starts the agreement step. Nothing is charged until the customer funds escrow.'),
          ]);
    });

// ─── My Jobs pipeline ───────────────────────────────────────────────────────

Widget proMyJobs() => Builder(builder: (context) {
      return _proScreen(context, nav: 2, children: [
        _title(context, 'My Jobs'),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (i, s) in [('Active', 7), ('Requests', 1), ('Agreement', 1), ('Scheduled', 2), ('Working', 1), ('In review', 2), ('Completed', 42)].indexed) ...[
              HtChip(label: s.$1, count: s.$2, selected: i == 0, onTap: () {}),
              const SizedBox(width: 8),
            ],
          ]),
        ),
        proSection(context, 'Working now', count: 1),
        const ProTicket(day: '24', month: 'Oct', title: 'Repaint living room', meta: 'Funke Adeyemi · Bodija', stage: '50% done', stageTone: HtTone.warning, amount: '₦85,000', action: 'Update progress', icon: Icons.format_paint_outlined),
        proSection(context, 'Requests', count: 1),
        const ProTicket(day: '—', month: 'ASAP', title: 'Kitchen sink leak', meta: 'Funke Adeyemi · Bodija', stage: 'Booking request', stageTone: HtTone.danger, deadline: 'Respond within 18 h', amount: '₦24,500', action: 'Respond'),
        proSection(context, 'In review', count: 2),
        const ProTicket(day: '15', month: 'Oct', title: 'Install water heater', meta: 'Emeka Okafor · Jericho', stage: 'Awaiting customer', stageTone: HtTone.accent, deadline: 'Auto-release 29 Oct', amount: '₦32,000', action: 'View'),
      ]);
    });

// ─── Work order (job workspace) ─────────────────────────────────────────────

Widget _workOrderTop(BuildContext context, int step, {String status = 'In escrow', HtTone tone = HtTone.warning}) {
  final p = context.ht;
  return HtCard(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('WORK ORDER · #HT-0B8491', style: HtType.caps(p.textMuted).copyWith(fontSize: 10.5)),
        const Spacer(),
        HtStatusPill(label: status, tone: tone, icon: Icons.lock_outline_rounded),
      ]),
      const SizedBox(height: 6),
      Text('Repaint living room', style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 22)),
      Text('Funke Adeyemi · 14 Awolowo Ave, Bodija', style: HtType.small(p.textSecondary)),
      const SizedBox(height: 8),
      Row(children: [Text('₦85,000', style: HtType.amount(p.textPrimary, size: 20)), const SizedBox(width: 8), Text('agreed · paid to you in full', style: HtType.small(p.textMuted))]),
      const SizedBox(height: 14),
      ProWorkStepper(current: step),
    ]),
  );
}

Widget _tabs(BuildContext context, int selected) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: proTabs(context, ['Overview', 'Agreement', 'Schedule', 'Photos', 'Activity'], selected),
    );

Widget proWorkspace() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, header: _workHeader(context, 'Work order', sub: 'Working · started 24 Oct'), bottomBar: proActionBar(context, 'Submit work'), children: [
        _workOrderTop(context, 3),
        _tabs(context, 0),
        proSection(context, 'Progress'),
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ProProgressMeter(index: 4),
            const SizedBox(height: 14),
            HtSecondaryButton(label: 'Update progress', icon: Icons.trending_up_rounded, onPressed: () {}),
          ]),
        ),
        proSection(context, 'Appointment'),
        HtCard(radius: HtRadius.inner, padding: const EdgeInsets.all(14), child: Column(children: [htKv(context, 'Confirmed', 'Thu 24 Oct · 9:00 AM'), htKv(context, 'Scope', '2 coats, walls and ceiling')])),
        const SizedBox(height: 14),
        Center(child: Text('Withdraw from job', style: HtType.smallStrong(p.danger))),
      ]);
    });

Widget _agreeParty(BuildContext context, String who, bool ok) {
  final p = context.ht;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.tile + 2), border: Border.all(color: p.border)),
    child: Row(children: [
      Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: ok ? p.success : p.textMuted, size: 20),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(who, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5)), Text(ok ? 'Confirmed' : 'Not confirmed', style: HtType.small(p.textSecondary))])),
    ]),
  );
}

Widget proAgreement() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, header: _workHeader(context, 'Work order', sub: 'Agreement · changes requested'), bottomBar: proActionBar(context, 'Send agreement'), children: [
        _workOrderTop(context, 1, status: 'Not funded yet', tone: HtTone.neutral),
        _tabs(context, 1),
        const SizedBox(height: 10),
        const HtInfoBanner(icon: Icons.chat_outlined, tone: HtTone.warning, title: 'Customer requested changes', text: '“Please include the ceiling.”'),
        htField(context, 'Scope of work', 'Two coats on all four walls and the ceiling. Customer supplies paint.', lines: 3),
        htField(context, 'Agreed price (₦)', '95,000'),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: _agreeParty(context, 'You', false)), const SizedBox(width: 10), Expanded(child: _agreeParty(context, 'Customer', false))]),
        const SizedBox(height: 10),
        Text('The price locks once you both confirm. The customer then funds escrow.', style: HtType.small(p.textSecondary)),
      ]);
    });

Widget proSchedule() => Builder(builder: (context) {
      final p = context.ht;
      Widget slot(String d, String m, String t, bool chosen) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.tile + 2), border: Border.all(color: chosen ? _a(p) : p.border, width: chosen ? 1.6 : 1)),
            child: Row(children: [
              Container(width: 46, padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(10)), child: Column(children: [Text(m, style: HtType.caps(p.textMuted).copyWith(fontSize: 9)), Text(d, style: HtType.amount(p.textPrimary, size: 18))])),
              const SizedBox(width: 12),
              Expanded(child: Text(t, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14))),
              Icon(Icons.close_rounded, color: p.textMuted, size: 18),
            ]),
          );
      return _proScreen(context, header: _workHeader(context, 'Work order', sub: 'Schedule · up to 3 times'), bottomBar: proActionBar(context, 'Send times to customer'), children: [
        _workOrderTop(context, 2, status: 'Funded', tone: HtTone.success),
        _tabs(context, 2),
        proSection(context, 'Your proposed times'),
        slot('24', 'THU', '9:00 AM', true),
        slot('25', 'FRI', '2:00 PM', false),
        HtSecondaryButton(label: 'Add another time', icon: Icons.add_rounded, onPressed: () {}),
        const SizedBox(height: 10),
        Text('The customer picks one; it appears on your Home as the next appointment.', style: HtType.small(p.textSecondary)),
      ]);
    });

// ─── Submit work, in review ─────────────────────────────────────────────────

Widget proSubmitWork() => Builder(builder: (context) {
      final p = context.ht;
      Widget check(String t, String s, bool ok) => Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: ok ? p.success : p.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(t, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5))),
            Text(s, style: HtType.smallStrong(p.textSecondary)),
          ]);
      return _proScreen(context,
          header: _workHeader(context, 'Submit work', sub: 'Repaint living room · #HT-0B8491'),
          bottomBar: HtPrimaryButton(label: 'Submit for review', icon: Icons.task_alt_rounded, onPressed: () {}),
          children: [
            HtCard(radius: HtRadius.inner, padding: const EdgeInsets.all(14), child: Column(children: [check('Before photos', '2 filed', true), const SizedBox(height: 10), check('After photos', '2 of 5', true), const SizedBox(height: 10), check('Notes', 'Added', true)])),
            proSection(context, 'After photos'),
            Row(children: [
              const Expanded(child: HtPhotoTile(label: 'Living room', height: 96)),
              const SizedBox(width: 8),
              const Expanded(child: HtPhotoTile(label: 'Wall detail', height: 96)),
              const SizedBox(width: 8),
              Expanded(child: _addTile(context, 96)),
            ]),
            htField(context, 'What was done', 'Two coats on all walls and the ceiling; furniture moved back.', lines: 3),
            const SizedBox(height: 14),
            const HtInfoBanner(icon: Icons.schedule_rounded, title: '14-day review', text: 'The customer has 14 days to approve or raise a dispute. Payment releases automatically when the period ends.'),
            const SizedBox(height: 10),
            const HtInfoBanner(icon: Icons.privacy_tip_outlined, tone: HtTone.neutral, text: 'Location data is removed from photos before upload.'),
          ]);
    });

Widget proInReview() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, header: _workHeader(context, 'Work order', sub: 'Submitted · awaiting the customer'), children: [
        _workOrderTop(context, 4),
        const SizedBox(height: 14),
        HtCard(
          child: Row(children: [
            const ProCountdownRing(fraction: 0.79, big: '11 d', small: 'left', size: 104, tone: HtTone.accent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Payment releases on 7 Nov', style: HtType.cardTitle(p.textPrimary)),
                const SizedBox(height: 4),
                Text('Or sooner if Funke approves. Before then she can ask for one rework or raise a dispute.', style: HtType.small(p.textSecondary)),
              ]),
            ),
          ]),
        ),
        proSection(context, 'Submitted photos'),
        Row(children: const [Expanded(child: HtPhotoTile(label: 'Living room', height: 90)), SizedBox(width: 8), Expanded(child: HtPhotoTile(label: 'Wall detail', height: 90))]),
        proSection(context, 'Activity'),
        const HtTimeline(entries: [('Work submitted', '24 Oct · 4:40 PM', true), ('Customer review', 'Until 7 Nov', false), ('Payment released', 'Pending', false)]),
      ]);
    });

// ─── Rework, dispute ────────────────────────────────────────────────────────

Widget proRework() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, header: _workHeader(context, 'Rework requested', sub: 'Install water heater · #HT-7C2210'), bottomBar: proActionBar(context, 'Send response'), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: p.warningSoft, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.warning.withValues(alpha: 0.35))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.replay_rounded, color: p.warning), const SizedBox(width: 8), Text('Emeka asked for changes', style: HtType.bodyStrong(p.textPrimary))]),
            const SizedBox(height: 8),
            Text('“The pressure valve still drips when the heater runs.”', style: HtType.body(p.textPrimary)),
            const SizedBox(height: 6),
            Text('Requested 26 Oct · this job’s one rework request', style: HtType.small(p.textSecondary)),
          ]),
        ),
        htField(context, 'Your response', 'I’ll replace the valve seal on Monday morning.', lines: 3),
        const SizedBox(height: 14),
        const HtInfoBanner(icon: Icons.schedule_rounded, text: 'After you fix and resubmit the work, a new 14-day review period starts.'),
      ]);
    });

Widget proDispute() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, header: _workHeader(context, 'Dispute', sub: 'Unblock drain · #HT-3A9115'), bottomBar: proActionBar(context, 'Send response'), children: [
        Row(children: [const HtStatusPill(label: 'Open · with HandyTrust', tone: HtTone.danger, dot: true), const Spacer(), Text('Escrow on hold', style: HtType.smallStrong(p.warning))]),
        proSection(context, 'Customer’s claim'),
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Work quality is poor', style: HtType.bodyStrong(p.textPrimary)),
            Text('“The drain blocked again the next day.”', style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5)),
            const SizedBox(height: 10),
            Row(children: const [Expanded(child: HtPhotoTile(label: 'Evidence', height: 70)), SizedBox(width: 8), Expanded(child: HtPhotoTile(label: 'Evidence', height: 70)), SizedBox(width: 8), Expanded(child: SizedBox())]),
          ]),
        ),
        proSection(context, 'Your response'),
        htField(context, 'Explain what happened', 'Describe the work and anything the reviewer should know…', lines: 3),
        const SizedBox(height: 10),
        Row(children: [const Expanded(child: HtPhotoTile(label: 'Completion photo', height: 70)), const SizedBox(width: 8), Expanded(child: _addTile(context, 70)), const SizedBox(width: 8), const Expanded(child: SizedBox())]),
        const SizedBox(height: 12),
        Text('An administrator reviews both sides and decides: release, refund or split.', style: HtType.small(p.textSecondary)),
      ]);
    });

// ─── Earnings, payout account ───────────────────────────────────────────────

Widget proEarnings() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, nav: 3, children: [
        _title(context, 'Earnings'),
        const SizedBox(height: 12),
        HtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('RELEASED TO YOU · LAST 6 MONTHS', style: HtType.caps(p.textMuted).copyWith(fontSize: 10.5)),
            const SizedBox(height: 4),
            Text('₦612,000', style: HtType.amount(p.textPrimary, size: 30)),
            const SizedBox(height: 12),
            const ProMonthBars(months: ['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct'], values: [64, 92, 78, 120, 141, 117], labels: ['64k', '92k', '78k', '120k', '141k', '117k']),
          ]),
        ),
        const SizedBox(height: 12),
        htGrid(const [
          ProStat(icon: Icons.lock_outline_rounded, label: 'In escrow', value: '₦85,000', sub: 'Funded, work ongoing'),
          ProStat(icon: Icons.hourglass_bottom_rounded, label: 'Awaiting release', value: '₦32,000', sub: 'In customer review'),
        ], columns: 2, gap: 10),
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            htIconTile(context, Icons.account_balance_outlined, tone: HtTone.success, size: 40),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Payout account', style: HtType.bodyStrong(p.textPrimary)), Text('Bank account on file', style: HtType.small(p.textSecondary))])),
            Text('Manage', style: HtType.smallStrong(_a(p))),
          ]),
        ),
        proSection(context, 'Payout ledger'),
        proLedgerRow(context, date: '15 Oct', title: 'Install water heater', status: 'Processing', tone: HtTone.warning, amount: '₦32,000'),
        proLedgerRow(context, date: '09 Oct', title: 'Bathroom re-pipe', status: 'Paid', tone: HtTone.success, amount: '₦60,000'),
        proLedgerRow(context, date: '02 Oct', title: 'Borehole pump service', status: 'Paid', tone: HtTone.success, amount: '₦25,000'),
        proLedgerRow(context, date: '28 Sep', title: 'Kitchen tap', status: 'On hold', tone: HtTone.danger, amount: '₦8,000'),
      ]);
    });

Widget proPayoutAccount() => Builder(builder: (context) {
      return _proScreen(context, header: _workHeader(context, 'Payout account'), bottomBar: HtPrimaryButton(label: 'Save bank details', onPressed: () {}), children: [
        const HtInfoBanner(icon: Icons.lock_outline_rounded, tone: HtTone.neutral, text: 'Only you and HandyTrust administrators can see these details.'),
        htField(context, 'Bank Name', 'Guaranty Trust Bank'),
        htField(context, 'Account Number', '0123454821'),
        htField(context, 'Account Name', 'Name exactly as it appears on your account', placeholder: true),
        const SizedBox(height: 14),
        const HtInfoBanner(icon: Icons.info_outline_rounded, tone: HtTone.neutral, text: 'Released payments are sent to this account.'),
      ]);
    });

// ─── Profile, verification, business, portfolio ─────────────────────────────

Widget proProfile() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, nav: 4, children: [
        _title(context, 'Profile'),
        proSection(context, 'How customers see you', trailing: 'Preview'),
        HtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const HtAvatar(name: 'Tunde Balogun', size: 60, ring: true, online: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Tunde Balogun', style: HtType.cardTitle(p.textPrimary)),
                  Text('Plumbing · Bodija, Ibadan', style: HtType.small(p.textSecondary)),
                  const SizedBox(height: 6),
                  const HtVerifiedBadge(),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: const [
              Expanded(child: ProStat(label: 'Rating', value: '4.8', sub: '37 reviews')),
              SizedBox(width: 8),
              Expanded(child: ProStat(label: 'Jobs done', value: '42')),
              SizedBox(width: 8),
              Expanded(child: ProStat(label: 'Trust', value: '86', sub: 'Trusted')),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final s in ['Pipe repair', 'Water heaters', 'Boreholes']) HtStatusPill(label: s, tone: HtTone.accent)]),
          ]),
        ),
        proSection(context, 'Your business'),
        HtCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            HtMenuRow(icon: Icons.storefront_outlined, title: 'Business profile', subtitle: 'Balogun Plumbing Services · 15 km radius', onTap: () {}),
            HtMenuRow(icon: Icons.photo_library_outlined, title: 'Portfolio', subtitle: '4 projects · 289 views', onTap: () {}),
            HtMenuRow(icon: Icons.verified_user_outlined, title: 'Identity verification', subtitle: 'Verified', onTap: () {}),
            HtMenuRow(icon: Icons.star_outline_rounded, title: 'My reviews', subtitle: '4.8 average', onTap: () {}),
            HtMenuRow(icon: Icons.account_balance_outlined, title: 'Payout account', subtitle: 'Bank account on file', onTap: () {}),
          ]),
        ),
        proSection(context, 'Account'),
        HtCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            HtMenuRow(icon: Icons.swap_horiz_rounded, title: 'Switch to Customer mode', subtitle: 'You have both roles', onTap: () {}),
            HtMenuRow(icon: Icons.settings_outlined, title: 'Settings', subtitle: 'Account, security, notifications', onTap: () {}),
            HtMenuRow(icon: Icons.support_agent_rounded, title: 'Help & Support', onTap: () {}),
            HtMenuRow(icon: Icons.logout_rounded, title: 'Log out', destructive: true, onTap: () {}),
          ]),
        ),
      ]);
    });

Widget proVerification() => Builder(builder: (context) {
      final p = context.ht;
      Widget row(IconData i, String t, String s, HtTone tone, String status) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: HtCard(
              radius: HtRadius.inner,
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                htIconTile(context, i, tone: tone, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)), Text(s, style: HtType.small(p.textSecondary))])),
                HtStatusPill(label: status, tone: tone),
              ]),
            ),
          );
      return _proScreen(context, header: _workHeader(context, 'Identity verification'), children: [
        HtCard(
          child: Row(children: [
            const ProCountdownRing(fraction: 0.66, big: '2/3', small: 'steps', size: 84, tone: HtTone.warning),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Under review', style: HtType.cardTitle(p.textPrimary)), Text('You can keep setting up your profile while HandyTrust reviews your documents.', style: HtType.small(p.textSecondary))])),
          ]),
        ),
        const SizedBox(height: 12),
        row(Icons.badge_outlined, 'Government ID', 'Photo uploaded', HtTone.success, 'Done'),
        row(Icons.face_outlined, 'Selfie', 'Photo uploaded', HtTone.success, 'Done'),
        row(Icons.fact_check_outlined, 'HandyTrust review', 'An administrator checks your documents', HtTone.warning, 'Pending'),
        const SizedBox(height: 4),
        const HtInfoBanner(icon: Icons.lock_outline_rounded, tone: HtTone.neutral, text: 'Your ID photos are seen only by HandyTrust reviewers and are never shown to customers.'),
      ]);
    });

Widget proBusiness() => Builder(builder: (context) {
      final p = context.ht;
      return _proScreen(context, header: _workHeader(context, 'Business profile'), bottomBar: HtPrimaryButton(label: 'Save', onPressed: () {}), children: [
        proSegments(context, ['Individual', 'Business'], 1),
        htField(context, 'Business Name', 'Balogun Plumbing Services'),
        htField(context, 'Business Registration Number', 'e.g. RC 1234567'),
        htField(context, 'Business Address', 'Registered office or shop address', placeholder: true),
        proSection(context, 'Service area'),
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Row(children: [Icon(Icons.my_location_rounded, color: _a(p), size: 20), const SizedBox(width: 8), Expanded(child: Text('Bodija, Ibadan', style: HtType.bodyStrong(p.textPrimary))), HtSecondaryButton(label: 'Use my location', dense: true, height: 36, onPressed: () {})]),
            const SizedBox(height: 8),
            htKv(context, 'Matching radius', '15 km'),
          ]),
        ),
      ]);
    });

Widget proPortfolio() => Builder(builder: (context) {
      final p = context.ht;
      Widget project(String t, String v) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border), boxShadow: p.cardShadow),
            clipBehavior: Clip.antiAlias,
            child: Row(children: [
              const SizedBox(width: 110, child: HtPhotoTile(label: 'Cover', height: 84)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)), Text('Plumbing · 5 photos', style: HtType.small(p.textSecondary)), Row(children: [Icon(Icons.visibility_outlined, size: 14, color: p.textMuted), const SizedBox(width: 4), Text(v, style: HtType.small(p.textMuted))])])),
              Icon(Icons.more_vert_rounded, color: p.textMuted),
              const SizedBox(width: 8),
            ]),
          );
      return _proScreen(context, header: _workHeader(context, 'Portfolio', sub: '4 projects · 289 views'), bottomBar: HtPrimaryButton(label: 'Add project', leadingIcon: Icons.add_rounded, onPressed: () {}), children: [
        proSegments(context, ['Projects', 'Photos'], 0, counts: [4, 12]),
        const SizedBox(height: 12),
        project('Bathroom re-pipe', '128 views'),
        project('Kitchen sink install', '76 views'),
        project('Water heater', '54 views'),
        project('Borehole pump', '31 views'),
      ]);
    });

// ─── Notifications, messages, chat ──────────────────────────────────────────

Widget proNotifications() => Builder(builder: (context) {
      final p = context.ht;
      Widget n(IconData i, HtTone t, String title, String body, String time, bool unread) => Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              htIconTile(context, i, tone: t, size: 38),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5)), Text(body, style: HtType.small(p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis)])),
              const SizedBox(width: 8),
              Column(children: [Text(time, style: HtType.small(p.textMuted).copyWith(fontSize: 11)), if (unread) Container(margin: const EdgeInsets.only(top: 6), width: 8, height: 8, decoration: BoxDecoration(color: _a(p), shape: BoxShape.circle))]),
            ]),
          );
      return _proScreen(context, header: _workHeader(context, 'Notifications', sub: '3 unread'), children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final (i, c) in ['All', 'Jobs', 'Escrow & Pay', 'Account'].indexed) ...[HtChip(label: c, selected: i == 0, onTap: () {}), const SizedBox(width: 8)]])),
        proSection(context, 'Today'),
        n(Icons.mark_email_unread_outlined, HtTone.danger, 'New booking request', 'Funke Adeyemi wants to book you for “Kitchen sink leak”.', '10:14', true),
        n(Icons.request_quote_outlined, HtTone.accent, 'Quote accepted', 'Your quote on “Install a new water heater” was accepted.', '09:02', true),
        n(Icons.payments_outlined, HtTone.success, 'Payout processing', '₦32,000 for “Install water heater” is being paid out.', '08:30', true),
        proSection(context, 'Earlier'),
        n(Icons.replay_rounded, HtTone.warning, 'Rework requested', 'Emeka asked for changes on #HT-7C2210.', 'Mon', false),
      ]);
    });

Widget proMessages() => Builder(builder: (context) {
      final p = context.ht;
      Widget c(String name, String job, String stage, HtTone tone, String last, String time, int unread) => Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
            child: Row(children: [
              HtAvatar(name: name, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(name, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14))), Text(time, style: HtType.small(p.textMuted).copyWith(fontSize: 11))]),
                  Text(last, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Row(children: [
                    HtStatusPill(label: stage, tone: tone),
                    const SizedBox(width: 6),
                    Expanded(child: Text(job, style: HtType.small(p.textMuted).copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (unread > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1), decoration: BoxDecoration(color: _a(p), borderRadius: BorderRadius.circular(HtRadius.pill)), child: Text('$unread', style: HtType.smallStrong(p.isDark ? p.onPrimary : Colors.white).copyWith(fontSize: 11))),
                  ]),
                ]),
              ),
            ]),
          );
      return _proScreen(context, header: _workHeader(context, 'Messages'), children: [
        HtFilterBar(hint: 'Search customers or jobs'),
        const SizedBox(height: 6),
        c('Funke Adeyemi', 'Repaint living room', 'Working', HtTone.warning, 'Thursday 9:00 AM works perfectly.', '10:25', 2),
        c('Emeka Okafor', 'Install water heater', 'Rework', HtTone.danger, 'The valve still drips a little.', 'Mon', 0),
        c('Aisha Bello', 'Garden tap replacement', 'Quote', HtTone.accent, 'Can you come on Saturday instead?', '12 Oct', 0),
      ]);
    });

Widget proChat() => Builder(builder: (context) {
      final p = context.ht;
      Widget bubble(String t, bool mine, String time) => Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 270),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(gradient: mine ? LinearGradient(colors: p.outgoingBubble) : null, color: mine ? null : p.incomingBubble, border: mine ? null : Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Align(alignment: Alignment.centerLeft, widthFactor: 1, child: Text(t, style: HtType.body(mine ? p.onOutgoingBubble : p.textPrimary).copyWith(fontSize: 13.5))),
                Text(time, style: HtType.small(mine ? p.onOutgoingBubble.withValues(alpha: 0.8) : p.textMuted).copyWith(fontSize: 10.5)),
              ]),
            ),
          );
      return PhoneScreen(
        header: Column(children: [
          _workHeader(context, 'Funke Adeyemi', sub: 'Customer · Bodija'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: HtSpace.gutter),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.tile + 2), border: Border.all(color: p.border)),
            child: Column(children: [
              Row(children: [Text('#HT-0B8491 · Repaint living room', style: HtType.smallStrong(p.textPrimary)), const Spacer(), Text('₦85,000', style: HtType.smallStrong(p.textPrimary))]),
              const SizedBox(height: 8),
              const ProWorkStepper(current: 3),
            ]),
          ),
        ]),
        bottomBar: Row(children: [
          const HtIconCircle(icon: Icons.add_rounded, tooltip: 'Attach'),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 46, padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.centerLeft, decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(HtRadius.pill), border: Border.all(color: p.isDark ? Colors.transparent : p.border)), child: Text('Message Funke…', style: HtType.body(p.textMuted)))),
          const SizedBox(width: 10),
          HtIconCircle(icon: Icons.arrow_upward_rounded, fill: _a(p), iconColor: p.isDark ? p.onPrimary : Colors.white, tooltip: 'Send'),
        ]),
        children: [
          const SizedBox(height: 8),
          bubble('Good morning Funke, I can start Thursday at 9.', true, '9:44 AM'),
          bubble('Perfect. The paint is already on-site.', false, '9:46 AM'),
          bubble('Great, see you then.', true, '9:48 AM'),
        ],
      );
    });

// ─── States and tablet ──────────────────────────────────────────────────────

Widget proLoading() => Builder(builder: (context) {
      final p = context.ht;
      Widget bone(double h, {double w = double.infinity}) => Container(height: h, width: w, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.tile + 2)));
      return _proScreen(context, nav: 2, children: [
        _title(context, 'My Jobs'),
        const SizedBox(height: 12),
        bone(38, w: 260),
        bone(112),
        bone(112),
        bone(112),
        Text('Loading your jobs…', textAlign: TextAlign.center, style: HtType.small(p.textMuted)),
      ]);
    });

Widget proError() => Builder(builder: (context) {
      return _proScreen(context, nav: 1, children: [
        _title(context, 'Find Work'),
        const SizedBox(height: 12),
        proSegments(context, ['Open jobs', 'My quotes'], 0),
        const SizedBox(height: 30),
        HtCard(child: HtErrorView(message: 'We couldn’t load matched jobs. Check your connection.', onRetry: () {})),
      ]);
    });

/// Tablet / landscape My Jobs: stage columns.
Widget proJobsBoardTablet() => Builder(builder: (context) {
      final p = context.ht;
      Widget col(String t, int n, List<Widget> cards) => Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.isDark ? p.backgroundDeep : p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [Text(t.toUpperCase(), style: HtType.caps(p.textSecondary)), const SizedBox(width: 6), Text('$n', style: HtType.smallStrong(p.textMuted))]),
                const SizedBox(height: 10),
                ...cards,
              ]),
            ),
          );
      return Scaffold(
        backgroundColor: p.background,
        bottomNavigationBar: const ProNavBar(current: 2),
        body: SafeArea(
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ProHeader(name: 'Tunde Balogun', trade: 'Plumber · Ibadan', messages: 2, alerts: 3, title: 'My Jobs'),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 8, 8, 16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    col('Requests', 1, const [ProTicket(day: '', month: 'ASAP', title: 'Kitchen sink leak', meta: 'Bodija', stage: 'Booking request', stageTone: HtTone.danger, deadline: '18 h left', compact: true)]),
                    col('Agreement', 1, const [ProTicket(day: '', month: 'Date TBC', title: 'Repaint hallway', meta: 'Agodi', stage: 'Changes requested', stageTone: HtTone.warning, compact: true)]),
                    col('Scheduled', 2, const [
                      ProTicket(day: '24', month: 'Oct', title: 'Repaint living room', meta: 'Bodija', stage: '9:00 AM', stageTone: HtTone.accent, compact: true),
                      ProTicket(day: '27', month: 'Oct', title: 'Fix shower head', meta: 'Jericho', stage: '2:00 PM', stageTone: HtTone.accent, compact: true),
                    ]),
                    col('In review', 1, const [ProTicket(day: '15', month: 'Oct', title: 'Water heater', meta: 'Jericho', stage: 'Awaiting customer', stageTone: HtTone.accent, deadline: 'Releases 29 Oct', compact: true)]),
                  ]),
                ),
              ),
            ]),
            const Positioned(bottom: 6, right: 16, child: PreviewTag()),
          ]),
        ),
      );
    });
