import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_info.dart';
import '../../models/support_ticket_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/platform_config_provider.dart';
import '../../providers/support_ticket_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../components/ht_kit.dart';
import '../theme/ht_theme.dart';
import 'settings_screens.dart';

// ─── About HandyTrust ───────────────────────────────────────────────────────

/// Stage 8.2 About. Only verifiable product facts: what the app does and
/// how its protections work, as implemented. No company registration,
/// licences, certifications, statistics or history are claimed.
class AboutHandyTrustScreen extends StatelessWidget {
  const AboutHandyTrustScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    Widget fact(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            htIconTile(context, icon, size: 40),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: HtType.bodyStrong(p.textPrimary)),
              const SizedBox(height: 2),
              Text(body, style: HtType.small(p.textSecondary)),
            ])),
          ]),
        );
    return SettingsPage(
      title: 'About HandyTrust',
      children: [
        const SizedBox(height: 12),
        Center(
          child: Column(children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.verified_user_rounded, size: 38, color: p.accentStrong),
            ),
            const SizedBox(height: 12),
            Text(AppInfo.name, style: HtType.screenTitle(p.textPrimary)),
            const SizedBox(height: 2),
            Text('Version ${AppInfo.version} (build ${AppInfo.build})', style: HtType.small(p.textMuted)),
            const SizedBox(height: 10),
            Text(AppInfo.tagline, textAlign: TextAlign.center, style: HtType.body(p.textSecondary)),
          ]),
        ),
        SettingsGroup(label: 'How HandyTrust works', children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              fact(Icons.badge_outlined, 'Reviewed artisans', 'HandyTrust approves artisans before they can quote. Artisans who complete identity verification (a government ID and a selfie, reviewed by HandyTrust) show a Verified badge.'),
              fact(Icons.lock_outline_rounded, 'Payment held in escrow', 'You pay through Paystack. The money is held, not paid to the artisan, until the work is done.'),
              fact(Icons.fact_check_outlined, '14-day review', 'After the artisan submits the work you have 14 days to approve it, ask for one rework, or raise a dispute. If you do nothing, payment releases when the period ends.'),
              fact(Icons.gavel_rounded, 'Disputes reviewed by people', 'If something goes wrong, the payment stays on hold while an administrator reviews both sides and decides on a release, refund or split.'),
            ]),
          ),
        ]),
        SettingsGroup(label: 'More', children: [
          HtMenuRow(icon: Icons.support_agent_rounded, title: 'Support Centre', onTap: () => context.push('/support')),
          HtMenuRow(
            icon: Icons.description_outlined,
            title: 'Open-source licences',
            subtitle: 'Software HandyTrust is built with',
            onTap: () => showLicensePage(context: context, applicationName: AppInfo.name, applicationVersion: '${AppInfo.version} (${AppInfo.build})'),
          ),
        ]),
      ],
    );
  }
}

// ─── Support Centre ─────────────────────────────────────────────────────────

/// Stage 8.2 Support Centre. Contact is through the existing in-app ticket
/// system (`support_tickets`), the only real support channel; no email,
/// phone or response-time promise is invented. Help topics link to the
/// screens where each thing is actually done. Reachable while suspended.
class SupportCentreScreen extends ConsumerStatefulWidget {
  const SupportCentreScreen({super.key});
  @override
  ConsumerState<SupportCentreScreen> createState() => _SupportCentreScreenState();
}

class _SupportCentreScreenState extends ConsumerState<SupportCentreScreen> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _contactKey = GlobalKey();
  bool _sending = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final user = ref.read(currentUserProvider).asData?.value;
    if (user == null) return;
    setState(() => _sending = true);
    try {
      await ref.read(supportTicketServiceProvider).createTicket(
            userId: user.uid,
            userName: user.name,
            subject: _subject.text.trim(),
            message: _message.text.trim(),
          );
      if (!mounted) return;
      _subject.clear();
      _message.clear();
      htSnack(context, 'Ticket sent. You’ll see the reply under Your tickets.');
    } catch (_) {
      if (mounted) htSnack(context, 'Could not send your ticket. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toContact() {
    final c = _contactKey.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final user = ref.watch(currentUserProvider).asData?.value;
    final cfg = ref.watch(platformConfigProvider);
    final fee = cfg.platformFeePercent;
    final feeText = fee == fee.roundToDouble() ? fee.round().toString() : fee.toString();
    final topics = <_HelpTopic>[
      _HelpTopic(Icons.payments_outlined, 'Payments', [
        ('How do I pay?', 'Once you and the artisan confirm the agreement, you pay through Paystack’s secure checkout. The money is held in escrow.'),
        ('What does it cost?', 'You pay the agreed price plus a $feeText% platform fee. The full breakdown is shown before you pay.'),
        ('When is the artisan paid?', 'When you confirm the work, or automatically when the 14-day review period after submission ends.'),
      ], ('View payments', '/wallet')),
      _HelpTopic(Icons.event_note_outlined, 'Jobs and bookings', [
        ('How do I book an artisan?', 'Post a job, compare the quotes you receive, and book the artisan you choose.'),
        ('What if the artisan doesn’t respond?', 'An artisan has ${cfg.bookingConfirmationHours} hours to accept a booking request. If they don’t, the job reopens so you can book someone else.'),
        ('Can I ask for changes to the work?', 'Yes. After the artisan submits the work you can ask for one rework before approving.'),
      ], ('My bookings', '/jobs')),
      _HelpTopic(Icons.gavel_rounded, 'Disputes and refunds', [
        ('How do I raise a dispute?', 'Open the job and choose Raise Dispute before you approve the work. The payment stays on hold.'),
        ('Who decides a dispute?', 'An administrator reviews the evidence from both sides and decides to release the payment, refund you, or split it.'),
        ('Can I cancel a paid job?', 'While the job is funded and before the work is submitted, either side can request a cancellation. An administrator reviews it and decides whether, and how much, to refund. After submission, raise a dispute instead.'),
      ], ('My bookings', '/jobs')),
      _HelpTopic(Icons.manage_accounts_outlined, 'Account', [
        ('How do I change my password?', 'Go to Settings › Security and password. You can also email yourself a reset link from there.'),
        ('How do I delete my account?', 'Go to Settings › Request account deletion. An administrator reviews the request; your job history, payments and reviews are kept.'),
      ], ('Security and password', '/settings/security')),
    ];
    return SettingsPage(
      title: 'Support Centre',
      subtitle: 'Help topics and contact',
      children: [
        const SizedBox(height: 8),
        HtCard(
          onTap: _toContact,
          child: Row(children: [
            htIconTile(context, Icons.support_agent_rounded),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Contact support', style: HtType.bodyStrong(p.textPrimary)),
              Text('Send a ticket to the HandyTrust team', style: HtType.small(p.textSecondary)),
            ])),
            Icon(Icons.arrow_downward_rounded, color: p.textMuted),
          ]),
        ),
        for (final t in topics) _TopicCard(topic: t),
        Padding(
          key: _contactKey,
          padding: const EdgeInsets.only(top: 18),
          child: HtCard(
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Contact support', style: HtType.sectionTitle(p.textPrimary)),
                const SizedBox(height: 2),
                Text('Replies appear under Your tickets below.', style: HtType.small(p.textSecondary)),
                HtTextField(label: 'Subject', controller: _subject, hint: 'e.g. Payment not showing', maxLength: 120,
                    validator: (v) => (v ?? '').trim().length < 3 ? 'Add a short subject' : null),
                HtTextField(label: 'Message', controller: _message, hint: 'Describe what happened and which job it’s about', lines: 4, maxLength: 2000,
                    validator: (v) => (v ?? '').trim().length < 10 ? 'Describe the issue (at least 10 characters)' : null),
                const SizedBox(height: 12),
                HtPrimaryButton(label: 'Send ticket', loading: _sending, onPressed: _sending || user == null ? null : _submit),
              ]),
            ),
          ),
        ),
        if (user != null) _MyTickets(uid: user.uid),
      ],
    );
  }
}

class _HelpTopic {
  const _HelpTopic(this.icon, this.title, this.faqs, this.link);
  final IconData icon;
  final String title;
  final List<(String, String)> faqs;
  final (String, String) link;
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic});
  final _HelpTopic topic;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: HtCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: htIconTile(context, topic.icon, size: 40),
            title: Text(topic.title, style: HtType.bodyStrong(p.textPrimary)),
            subtitle: Text('${topic.faqs.length} questions', style: HtType.small(p.textMuted)),
            iconColor: p.textSecondary,
            collapsedIconColor: p.textMuted,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (q, a) in topic.faqs) ...[
                Text(q, style: HtType.smallStrong(p.textPrimary)),
                const SizedBox(height: 2),
                Text(a, style: HtType.small(p.textSecondary)),
                const SizedBox(height: 10),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: HtSmallPrimaryButton(label: topic.link.$1, onPressed: () => context.push(topic.link.$2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyTickets extends ConsumerWidget {
  const _MyTickets({required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final async = ref.watch(userTicketsProvider(uid));
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text('YOUR TICKETS', style: HtType.caps(p.textMuted))),
        async.when(
          loading: () => const HtLoadingView(label: 'Loading your tickets…'),
          error: (e, _) => HtCard(child: HtErrorView(message: 'We couldn’t load your tickets.', onRetry: () => ref.invalidate(userTicketsProvider(uid)))),
          data: (tickets) => tickets.isEmpty
              ? const HtCard(child: HtEmptyView(icon: Icons.confirmation_number_outlined, title: 'No tickets yet', message: 'Tickets you send appear here with the team’s reply.'))
              : Column(children: [for (final t in tickets) _TicketTile(ticket: t)]),
        ),
      ]),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket});
  final SupportTicketModel ticket;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final open = ticket.status == 'open';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HtCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(ticket.subject, style: HtType.bodyStrong(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
            HtStatusPill(label: open ? 'Open' : 'Resolved', tone: open ? HtTone.warning : HtTone.success, dot: true),
          ]),
          const SizedBox(height: 2),
          Text('Sent ${HtFormat.date(ticket.createdAt.toLocal())}', style: HtType.small(p.textMuted)),
          const SizedBox(height: 6),
          Text(ticket.message, style: HtType.small(p.textSecondary), maxLines: 3, overflow: TextOverflow.ellipsis),
          if (ticket.adminResponse?.isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(HtRadius.tile)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('HandyTrust support', style: HtType.smallStrong(p.accentSoftText)),
                const SizedBox(height: 2),
                Text(ticket.adminResponse!, style: HtType.small(p.textPrimary)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
