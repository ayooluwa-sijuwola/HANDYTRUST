import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/admin_finance_service.dart';
import '../../core/services/admin_service.dart';
import '../../core/services/customer_booking_logic.dart';
import '../../models/dispute_model.dart';
import '../../models/job_model.dart';
import '../../models/review_model.dart';
import '../../models/support_ticket_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart' show jobPrivateLocationProvider;
import '../../providers/quote_provider.dart';
import '../../providers/review_provider.dart';
import '../../providers/support_ticket_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../components/ht_kit.dart';
import '../theme/ht_theme.dart';
import 'admin_kit.dart';
import 'admin_people.dart' show payoutFreezeFact;
import 'admin_shell.dart';

String? _me(WidgetRef ref) => ref.read(currentUserProvider).asData?.value?.uid;

/// The job reached escrow at some point (server timestamp, or a state only
/// reachable after funding — including disputes and completion).
bool _everFunded(JobModel j) =>
    j.escrowLockedAt != null ||
    const {JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted, JobStatus.disputed, JobStatus.completed, JobStatus.resolved}.contains(j.status);

(String, HtTone) _jobPill(JobModel j) => switch (j.status) {
      JobStatus.disputed => ('Disputed', HtTone.danger),
      JobStatus.completed || JobStatus.resolved => ('Completed', HtTone.success),
      JobStatus.cancelled || JobStatus.expired => (CustomerBookingLogic.statusLabel(j), HtTone.neutral),
      JobStatus.requested => ('Requested', HtTone.neutral),
      _ => (CustomerBookingLogic.statusLabel(j), HtTone.warning),
    };

// ─── Jobs (AD-5) ────────────────────────────────────────────────────────────

class AdminJobsSection extends ConsumerStatefulWidget {
  const AdminJobsSection({super.key});
  @override
  ConsumerState<AdminJobsSection> createState() => _AdminJobsSectionState();
}

class _AdminJobsSectionState extends ConsumerState<AdminJobsSection> {
  final _q = TextEditingController();
  int _filter = 0;
  String? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selected ??= adminFocus(context);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminJobsProvider);
    return AdminPage(
      title: 'Jobs',
      subtitle: 'All bookings and requests · latest ${async.asData?.value.length ?? 0}',
      child: async.when(
        loading: () => const HtLoadingView(label: 'Loading jobs…'),
        error: (e, _) => HtCard(child: HtErrorView(message: 'Jobs could not be loaded.', onRetry: () => ref.invalidate(adminJobsProvider))),
        data: (jobs) {
          final names = ref.watch(adminPeopleNamesProvider(peopleKey(jobs.expand((j) => [j.customerId, j.artisanId])))).asData?.value ?? const <String, String>{};
          String nameOf(String id) => id.isEmpty ? '—' : (names[id]?.isNotEmpty ?? false ? names[id]! : 'Unknown');
          final filters = <bool Function(JobModel)>[
            (_) => true,
            (j) => j.status == JobStatus.requested,
            (j) => const {JobStatus.matched, JobStatus.inChat, JobStatus.paymentPending, JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted}.contains(j.status),
            (j) => j.status == JobStatus.disputed,
            (j) => j.status == JobStatus.completed || j.status == JobStatus.resolved,
          ];
          final q = _q.text.trim().toLowerCase();
          final list = jobs
              .where(filters[_filter])
              .where((j) => q.isEmpty ||
                  j.description.toLowerCase().contains(q) ||
                  j.category.toLowerCase().contains(q) ||
                  HtFormat.bookingRef(j.id).toLowerCase().contains(q) ||
                  nameOf(j.customerId).toLowerCase().contains(q) ||
                  nameOf(j.artisanId).toLowerCase().contains(q))
              .toList();
          final sel = _selected == null ? null : jobs.where((j) => j.id == _selected).firstOrNull;
          return AdminListDetail(
            detailTitle: sel == null ? '' : '#${HtFormat.bookingRef(sel.id)} · ${sel.category}',
            onClose: () => setState(() => _selected = null),
            detail: sel == null ? null : JobDetail(job: sel, customer: nameOf(sel.customerId), artisan: nameOf(sel.artisanId)),
            list: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HtSearchField(controller: _q, hint: 'Search job, person or reference', onChanged: (_) => setState(() {})),
              const SizedBox(height: 10),
              AdminFilterBar(
                labels: const ['All', 'Requested', 'Active', 'Disputed', 'Completed'],
                counts: [for (final f in filters) jobs.where(f).length],
                selected: _filter,
                onSelected: (i) => setState(() => _filter = i),
              ),
              const SizedBox(height: 12),
              AdminTable<JobModel>(
                items: list,
                selected: (j) => j.id == _selected,
                onTap: (j) => adminIsWide(context)
                    ? setState(() => _selected = j.id)
                    : openAdminDetailPage(context, title: '#${HtFormat.bookingRef(j.id)}', builder: (_) => JobDetail(job: j, customer: nameOf(j.customerId), artisan: nameOf(j.artisanId))),
                empty: const HtCard(child: HtEmptyView(icon: Icons.work_off_outlined, title: 'No jobs match')),
                columns: [
                  AdminCol('Job', (c, j) => adminTwoLine(c, '#${HtFormat.bookingRef(j.id)}', j.description.split('\n').first), flex: 4),
                  AdminCol('Category', (c, j) => adminText(c, j.category)),
                  AdminCol('Customer', (c, j) => adminText(c, nameOf(j.customerId))),
                  AdminCol('Artisan', (c, j) => adminText(c, nameOf(j.artisanId), muted: j.artisanId.isEmpty)),
                  AdminCol('Status', (c, j) {
                    final (l, t) = _jobPill(j);
                    return HtStatusPill(label: l, tone: t, dot: true, maxLines: 2);
                  }, flex: 3),
                  AdminCol('Amount', (c, j) => adminText(c, j.agreedAmount == null ? '—' : HtFormat.naira(j.agreedAmount)), numeric: true),
                ],
                mobileRow: (c, j) {
                  final (l, t) = _jobPill(j);
                  return Row(children: [
                    Expanded(child: adminTwoLine(c, '#${HtFormat.bookingRef(j.id)} · ${j.category}', '${nameOf(j.customerId)} · ${j.agreedAmount == null ? 'no price yet' : HtFormat.naira(j.agreedAmount)}')),
                    HtStatusPill(label: l, tone: t),
                  ]);
                },
              ),
            ]),
          );
        },
      ),
    );
  }
}

/// Job detail: people, money, lifecycle, location, photos, payout-freeze
/// state, and (F-1) deletion only when the rules allow it.
class JobDetail extends ConsumerStatefulWidget {
  const JobDetail({super.key, required this.job, required this.customer, required this.artisan});
  final JobModel job;
  final String customer;
  final String artisan;
  @override
  ConsumerState<JobDetail> createState() => _JobDetailState();
}

class _JobDetailState extends ConsumerState<JobDetail> {
  bool _deleting = false;

  Future<void> _delete() async {
    final j = widget.job;
    final ok = await htConfirm(
      context,
      title: 'Delete this job request?',
      message: 'This permanently removes the job and its chat. Use it only for spam or fake requests. Recorded in the audit log.',
      confirmLabel: 'Delete job request',
    );
    final me = _me(ref);
    if (!ok || me == null || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(adminServiceProvider).deleteJob(j, adminId: me);
      if (mounted) htSnack(context, 'Job request deleted');
    } catch (e) {
      if (mounted) htSnack(context, 'Could not delete the job: ${adminError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final j = widget.job;
    final quotes = ref.watch(jobQuotesProvider(j.id)).asData?.value.length;
    final loc = ref.watch(jobPrivateLocationProvider(j.id)).asData?.value?['customerAddress'] as String?;
    final (l, t) = _jobPill(j);
    final steps = <(String, DateTime?)>[
      ('Requested', j.createdAt),
      ('Booked', j.matchedAt ?? j.bookingConfirmedAt),
      ('Escrow funded', j.escrowLockedAt),
      ('Work started', j.startedAt),
      ('Work submitted', j.submittedAt),
      ('Completed', j.completedAt),
      if (j.cancelledAt != null) ('Cancelled', j.cancelledAt),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(alignment: Alignment.centerLeft, child: HtStatusPill(label: l, tone: t, dot: true)),
      const SizedBox(height: 8),
      Text(j.description, style: HtType.small(p.textPrimary), maxLines: 5, overflow: TextOverflow.ellipsis),
      adminSection(context, 'People and money'),
      adminFact(context, 'Customer', widget.customer),
      adminFact(context, 'Artisan', widget.artisan),
      adminFact(context, 'Agreed price', j.agreedAmount == null ? '—' : HtFormat.naira(j.agreedAmount)),
      adminFact(context, 'Budget', j.budgetMin == null ? 'Not specified' : '${HtFormat.naira(j.budgetMin)} – ${HtFormat.naira(j.budgetMax)}'),
      adminFact(context, 'Escrow', _everFunded(j) ? (j.status == JobStatus.completed || j.status == JobStatus.resolved ? 'Funded · settled' : 'Funded · held') : 'Not funded'),
      adminFact(context, 'Quotes', quotes == null ? '…' : '$quotes'),
      if (j.payoutStatus != null) adminFact(context, 'Payout', j.payoutStatus!),
      adminSection(context, 'Lifecycle'),
      for (final (label, at) in steps)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(at == null ? Icons.radio_button_unchecked_rounded : Icons.check_circle_rounded, size: 16, color: at == null ? p.textMuted : p.accentStrong),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: HtType.small(at == null ? p.textMuted : p.textPrimary))),
            Text(at == null ? '' : adminDate(at), style: HtType.small(p.textMuted)),
          ]),
        ),
      adminSection(context, 'Location'),
      Text(loc ?? j.areaLabel ?? 'Not specified', style: HtType.small(p.textPrimary)),
      if (j.completionImageUrls.isNotEmpty || j.beforePhotoUrls.isNotEmpty) ...[
        adminSection(context, 'Photos'),
        HtPhotoGrid(urls: [...j.beforePhotoUrls, ...j.completionImageUrls], tileHeight: 76, max: 10),
      ],
      payoutFreezeFact(context, frozen: j.payoutFrozen, reason: j.payoutFreezeReason),
      const SizedBox(height: 14),
      if (AdminService.canDeleteJob(j))
        (_deleting ? const Center(child: CircularProgressIndicator()) : HtDangerButton(label: 'Delete job request', icon: Icons.delete_outline_rounded, onPressed: _delete))
      else
        const HtInfoBanner(
          icon: Icons.inventory_2_outlined,
          tone: HtTone.neutral,
          title: 'Deletion unavailable',
          text: 'This job held funds or is past booking. Its record, chat, photos and financial history are kept.',
        ),
    ]);
  }
}

// ─── Disputes (AD-6) ────────────────────────────────────────────────────────

class AdminDisputesSection extends ConsumerStatefulWidget {
  const AdminDisputesSection({super.key});
  @override
  ConsumerState<AdminDisputesSection> createState() => _AdminDisputesSectionState();
}

class _AdminDisputesSectionState extends ConsumerState<AdminDisputesSection> {
  int _filter = 0;
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminDisputesProvider);
    return AdminPage(
      title: 'Disputes',
      subtitle: 'Disputes awaiting a decision',
      child: async.when(
        loading: () => const HtLoadingView(),
        error: (e, _) => HtCard(child: HtErrorView(message: 'Disputes could not be loaded.', onRetry: () => ref.invalidate(adminDisputesProvider))),
        data: (all) {
          bool open(DisputeModel d) => d.status == DisputeStatus.open || d.status == DisputeStatus.underReview;
          final list = _filter == 0 ? all.where(open).toList() : all.where((d) => !open(d)).toList();
          final names = ref.watch(adminPeopleNamesProvider(peopleKey(all.expand((d) => [d.raisedBy, d.againstUserId])))).asData?.value ?? const <String, String>{};
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AdminFilterBar(labels: const ['Open', 'Closed'], counts: [all.where(open).length, all.where((d) => !open(d)).length], selected: _filter, onSelected: (i) => setState(() => _filter = i)),
            const SizedBox(height: 12),
            if (list.isEmpty)
              HtCard(child: HtEmptyView(icon: Icons.task_alt_rounded, title: _filter == 0 ? 'No open disputes' : 'No closed disputes'))
            else
              AdminGrid(minTileWidth: 460, children: [for (final d in list) _DisputeCard(dispute: d, names: names, open: open(d))]),
          ]);
        },
      ),
    );
  }
}

class _DisputeCard extends ConsumerStatefulWidget {
  const _DisputeCard({required this.dispute, required this.names, required this.open});
  final DisputeModel dispute;
  final Map<String, String> names;
  final bool open;
  @override
  ConsumerState<_DisputeCard> createState() => _DisputeCardState();
}

class _DisputeCardState extends ConsumerState<_DisputeCard> {
  bool _busy = false;

  Future<void> _resolve() async {
    final d = widget.dispute;
    final decision = await showSettlementDialog(context, loadHeld: ref.read(adminServiceProvider).heldFunds, title: 'Resolve dispute #${HtFormat.bookingRef(d.jobId)}', jobId: d.jobId);
    if (decision == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // Executed server-side (adminResolveDispute): release, full refund or
      // split, with the audit log and both parties notified.
      await ref.read(adminFinanceServiceProvider).resolveDispute(
            jobId: d.jobId,
            disputeId: d.id,
            outcome: decision.outcome,
            reason: decision.reason,
            artisanAmount: decision.artisanAmount,
            refundAmount: decision.refundAmount,
          );
      if (mounted) htSnack(context, 'Decision recorded');
    } catch (e) {
      if (mounted) htSnack(context, 'Decision failed: ${financeError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final d = widget.dispute;
    String name(String id) => widget.names[id]?.isNotEmpty ?? false ? widget.names[id]! : 'Unknown';
    return HtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: adminTwoLine(context, 'Job #${HtFormat.bookingRef(d.jobId)}', 'Raised ${adminDate(d.createdAt)} by ${name(d.raisedBy)}')),
          HtStatusPill(label: widget.open ? 'Open' : (d.status == DisputeStatus.dismissed ? 'Dismissed' : 'Resolved'), tone: widget.open ? HtTone.danger : HtTone.success, dot: true),
        ]),
        adminSection(context, 'Claim'),
        Text(d.reason, style: HtType.small(p.textPrimary)),
        if (d.evidenceImageUrls.isNotEmpty) ...[const SizedBox(height: 8), HtPhotoGrid(urls: d.evidenceImageUrls, tileHeight: 70)],
        adminSection(context, 'Response from ${name(d.againstUserId)}'),
        Text(d.artisanResponseText?.isNotEmpty ?? false ? d.artisanResponseText! : 'No response yet', style: HtType.small(d.artisanResponseText?.isNotEmpty ?? false ? p.textPrimary : p.textMuted)),
        if (d.artisanEvidenceUrls.isNotEmpty) ...[const SizedBox(height: 8), HtPhotoGrid(urls: d.artisanEvidenceUrls, tileHeight: 70)],
        if (!widget.open && (d.resolution?.isNotEmpty ?? false)) ...[adminSection(context, 'Decision'), Text(d.resolution!, style: HtType.small(p.textPrimary))],
        const SizedBox(height: 12),
        if (widget.open)
          _busy ? const Center(child: CircularProgressIndicator()) : HtPrimaryButton(label: 'Resolve dispute', height: 44, onPressed: _resolve),
      ]),
    );
  }
}

// ─── Support (AD-8) ─────────────────────────────────────────────────────────

class AdminSupportSection extends ConsumerStatefulWidget {
  const AdminSupportSection({super.key});
  @override
  ConsumerState<AdminSupportSection> createState() => _AdminSupportSectionState();
}

class _AdminSupportSectionState extends ConsumerState<AdminSupportSection> {
  int _filter = 0;
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allTicketsProvider);
    return AdminPage(
      title: 'Support',
      subtitle: 'Tickets from users',
      child: async.when(
        loading: () => const HtLoadingView(),
        error: (e, _) => HtCard(child: HtErrorView(message: 'Tickets could not be loaded.', onRetry: () => ref.invalidate(allTicketsProvider))),
        data: (all) {
          final open = all.where((t) => t.status == 'open').toList();
          final done = all.where((t) => t.status != 'open').toList();
          final list = _filter == 0 ? open : done;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AdminFilterBar(labels: const ['Open', 'Resolved'], counts: [open.length, done.length], selected: _filter, onSelected: (i) => setState(() => _filter = i)),
            const SizedBox(height: 12),
            if (list.isEmpty)
              HtCard(child: HtEmptyView(icon: Icons.task_alt_rounded, title: _filter == 0 ? 'No open tickets' : 'No resolved tickets'))
            else
              AdminGrid(minTileWidth: 460, children: [for (final t in list) _TicketCard(ticket: t)]),
          ]);
        },
      ),
    );
  }
}

class _TicketCard extends ConsumerStatefulWidget {
  const _TicketCard({required this.ticket});
  final SupportTicketModel ticket;
  @override
  ConsumerState<_TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends ConsumerState<_TicketCard> {
  bool _busy = false;
  Future<void> _respond() async {
    final ctrl = TextEditingController();
    final response = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final p = ctx.ht;
        return AlertDialog(
          backgroundColor: p.surface,
          title: Text('Reply and resolve', style: HtType.sectionTitle(p.textPrimary)),
          content: SizedBox(width: 460, child: HtTextField(label: 'Your reply', controller: ctrl, lines: 4, hint: 'The user sees this under Your tickets')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Send and resolve')),
          ],
        );
      },
    );
    if (response == null || response.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(supportTicketServiceProvider).resolveTicket(ticketId: widget.ticket.id, adminResponse: response);
      if (mounted) htSnack(context, 'Reply sent');
    } catch (e) {
      if (mounted) htSnack(context, 'Could not send the reply: ${adminError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final t = widget.ticket;
    final open = t.status == 'open';
    return HtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: adminTwoLine(context, t.subject, '${t.userName} · ${adminDateTime(t.createdAt)}')),
          HtStatusPill(label: open ? 'Open' : 'Resolved', tone: open ? HtTone.warning : HtTone.success, dot: true),
        ]),
        const SizedBox(height: 8),
        Text(t.message, style: HtType.small(p.textPrimary)),
        if (t.adminResponse?.isNotEmpty ?? false) ...[adminSection(context, 'Reply'), Text(t.adminResponse!, style: HtType.small(p.textSecondary))],
        if (open) ...[
          const SizedBox(height: 12),
          _busy ? const Center(child: CircularProgressIndicator()) : HtPrimaryButton(label: 'Reply and resolve', height: 44, onPressed: _respond),
        ],
      ]),
    );
  }
}

// ─── Reviews (AD-7) ─────────────────────────────────────────────────────────

class AdminReviewsSection extends ConsumerWidget {
  const AdminReviewsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allReviewsProvider);
    return AdminPage(
      title: 'Reviews',
      subtitle: 'Customer reviews of artisans',
      child: async.when(
        loading: () => const HtLoadingView(),
        error: (e, _) => HtCard(child: HtErrorView(message: 'Reviews could not be loaded.', onRetry: () => ref.invalidate(allReviewsProvider))),
        data: (list) {
          if (list.isEmpty) return const HtCard(child: HtEmptyView(icon: Icons.star_outline_rounded, title: 'No reviews yet'));
          final names = ref.watch(adminPeopleNamesProvider(peopleKey(list.expand((r) => [r.customerId, r.artisanId])))).asData?.value ?? const <String, String>{};
          return AdminGrid(minTileWidth: 460, children: [for (final r in list) _ReviewCard(review: r, names: names)]);
        },
      ),
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({required this.review, required this.names});
  final ReviewModel review;
  final Map<String, String> names;
  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _busy = false;
  Future<void> _delete() async {
    final r = widget.review;
    final ok = await htConfirm(context, title: 'Delete this review?', message: 'It is removed and the artisan’s rating is recalculated from the remaining reviews.', confirmLabel: 'Delete review');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminServiceProvider).deleteReview(reviewId: r.id, artisanId: r.artisanId);
      if (mounted) htSnack(context, 'Review deleted');
    } catch (e) {
      if (mounted) htSnack(context, 'Delete failed: ${adminError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final r = widget.review;
    String name(String id) => widget.names[id]?.isNotEmpty ?? false ? widget.names[id]! : 'Unknown';
    return HtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: adminTwoLine(context, '${name(r.customerId)} → ${name(r.artisanId)}', '${adminDate(r.createdAt)} · job #${HtFormat.bookingRef(r.jobId)}')),
          Row(children: [for (var i = 1; i <= 5; i++) Icon(i <= r.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: p.warning)]),
        ]),
        if (r.comment.isNotEmpty) ...[const SizedBox(height: 8), Text(r.comment, style: HtType.small(p.textPrimary))],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : TextButton.icon(onPressed: _delete, icon: Icon(Icons.delete_outline_rounded, color: p.danger, size: 18), label: Text('Delete', style: HtType.smallStrong(p.danger))),
        ),
      ]),
    );
  }
}

// ─── Deletion requests (AD-9) ───────────────────────────────────────────────

class AdminDeletionsSection extends ConsumerStatefulWidget {
  const AdminDeletionsSection({super.key});
  @override
  ConsumerState<AdminDeletionsSection> createState() => _AdminDeletionsSectionState();
}

class _AdminDeletionsSectionState extends ConsumerState<AdminDeletionsSection> {
  final Set<String> _busy = {};
  Future<void> _resolve(String uid) async {
    final ok = await htConfirm(context, title: 'Mark this request handled?', message: 'Use this after the account has been dealt with (for example, deleted from Users).', confirmLabel: 'Mark handled');
    if (!ok || !mounted) return;
    setState(() => _busy.add(uid));
    try {
      await ref.read(adminServiceProvider).resolveDeletionRequest(uid);
    } catch (e) {
      if (mounted) htSnack(context, 'Failed: ${adminError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminDeletionRequestsProvider);
    return AdminPage(
      title: 'Deletion requests',
      subtitle: 'Accounts asking to be deleted',
      child: async.when(
        loading: () => const HtLoadingView(),
        error: (e, _) => HtCard(child: HtErrorView(message: 'Requests could not be loaded.', onRetry: () => ref.invalidate(adminDeletionRequestsProvider))),
        data: (list) {
          final names = ref.watch(adminPeopleNamesProvider(peopleKey(list.map((d) => d['uid'] as String? ?? '')))).asData?.value ?? const <String, String>{};
          return AdminTable<Map<String, dynamic>>(
            items: list,
            empty: const HtCard(child: HtEmptyView(icon: Icons.task_alt_rounded, title: 'No deletion requests')),
            columns: [
              AdminCol('User', (c, d) => adminTwoLine(c, names[d['uid']]?.isNotEmpty ?? false ? names[d['uid']]! : (d['uid'] as String? ?? '—'), d['reason'] as String?), flex: 4),
              AdminCol('Requested', (c, d) => adminText(c, adminDate((d['requestedAt'] as Timestamp?)?.toDate()), muted: true)),
              AdminCol('Status', (c, d) => HtStatusPill(label: d['status'] == 'resolved' ? 'Handled' : 'Pending', tone: d['status'] == 'resolved' ? HtTone.success : HtTone.warning, dot: true)),
              AdminCol('', (c, d) => d['status'] == 'resolved' ? const SizedBox.shrink() : _action(d['uid'] as String), numeric: true),
            ],
            mobileRow: (c, d) => Row(children: [
              Expanded(child: adminTwoLine(c, names[d['uid']] ?? (d['uid'] as String? ?? '—'), 'Requested ${adminDate((d['requestedAt'] as Timestamp?)?.toDate())}')),
              if (d['status'] != 'resolved') _action(d['uid'] as String) else const HtStatusPill(label: 'Handled', tone: HtTone.success),
            ]),
          );
        },
      ),
    );
  }

  Widget _action(String uid) => _busy.contains(uid)
      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
      : HtSmallPrimaryButton(label: 'Mark handled', onPressed: () => _resolve(uid));
}
