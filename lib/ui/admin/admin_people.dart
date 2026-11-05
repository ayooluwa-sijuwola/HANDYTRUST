import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/admin_service.dart';
import '../../core/services/artisan_eligibility.dart';
import '../../models/admin_audit_log_model.dart';
import '../../models/artisan_model.dart';
import '../../models/job_model.dart';
import '../../models/user_model.dart';
import '../../models/verification_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/verification_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_kit.dart';
import '../theme/ht_theme.dart';
import 'admin_kit.dart';
import 'admin_shell.dart';

String? _me(WidgetRef ref) => ref.read(currentUserProvider).asData?.value?.uid;

HtStatusPill _statusPill(UserModel u) => u.isSuspended
    ? HtStatusPill(label: 'Suspended', tone: HtTone.danger, dot: true)
    : const HtStatusPill(label: 'Active', tone: HtTone.success, dot: true);

String _roleLabel(UserModel u) => u.hasBothRoles ? 'Customer · Artisan' : (u.isArtisan ? 'Artisan' : 'Customer');

/// Read-only payout-freeze state (Q-5). Written only by the
/// adminSetPayoutFreeze Cloud Function; no freeze action is offered here.
Widget payoutFreezeFact(BuildContext context, {required bool frozen, String? reason}) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: HtInfoBanner(
        icon: frozen ? Icons.ac_unit_rounded : Icons.payments_outlined,
        tone: frozen ? HtTone.warning : HtTone.neutral,
        title: frozen ? 'Payouts frozen' : 'Payouts not frozen',
        text: frozen ? (reason?.isNotEmpty ?? false ? reason! : 'Frozen by an administrator.') : 'Read-only. Freezes are set by the server-side payout freeze.',
      ),
    );

// ─── Users (AD-2) ───────────────────────────────────────────────────────────

class AdminUsersSection extends ConsumerStatefulWidget {
  const AdminUsersSection({super.key});
  @override
  ConsumerState<AdminUsersSection> createState() => _AdminUsersSectionState();
}

class _AdminUsersSectionState extends ConsumerState<AdminUsersSection> {
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

  void _open(UserModel u) {
    if (adminIsWide(context)) {
      setState(() => _selected = u.uid);
    } else {
      openAdminDetailPage(context, title: u.name, builder: (_) => UserDetail(uid: u.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminUsersProvider);
    final jobs = ref.watch(adminJobsProvider).asData?.value ?? const <JobModel>[];
    final total = ref.watch(adminTotalsProvider).asData?.value.users;
    return AdminPage(
      title: 'Users',
      subtitle: total == null ? 'Customers and artisans' : '$total accounts · showing the latest ${async.asData?.value.length ?? 0}',
      child: async.when(
        loading: () => const HtLoadingView(label: 'Loading users…'),
        error: (e, _) => HtCard(child: HtErrorView(message: 'Users could not be loaded.', onRetry: () => ref.invalidate(adminUsersProvider))),
        data: (users) {
          final filters = <bool Function(UserModel)>[(_) => true, (u) => u.isCustomer, (u) => u.isArtisan, (u) => u.isSuspended];
          final q = _q.text.trim().toLowerCase();
          final list = users.where(filters[_filter]).where((u) => q.isEmpty || u.name.toLowerCase().contains(q) || (u.email ?? '').toLowerCase().contains(q)).toList();
          int jobCount(UserModel u) => jobs.where((j) => j.customerId == u.uid || j.artisanId == u.uid).length;
          final table = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HtSearchField(controller: _q, hint: 'Search name or email', onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            AdminFilterBar(
              labels: const ['All', 'Customers', 'Artisans', 'Suspended'],
              counts: [for (final f in filters) users.where(f).length],
              selected: _filter,
              onSelected: (i) => setState(() => _filter = i),
            ),
            const SizedBox(height: 12),
            AdminTable<UserModel>(
              items: list,
              selected: (u) => u.uid == _selected,
              onTap: _open,
              empty: const HtCard(child: HtEmptyView(icon: Icons.person_search_rounded, title: 'No users match')),
              columns: [
                AdminCol('Name', (c, u) => adminTwoLine(c, u.name, u.email), flex: 4),
                AdminCol('Role', (c, u) => adminText(c, _roleLabel(u)), flex: 2),
                AdminCol('Joined', (c, u) => adminText(c, adminDate(u.createdAt), muted: true), flex: 2),
                AdminCol('Status', (c, u) => _statusPill(u), flex: 2),
                AdminCol('Jobs', (c, u) => adminText(c, '${jobCount(u)}'), flex: 1, numeric: true),
              ],
              mobileRow: (c, u) => Row(children: [
                HtAvatar(name: u.name, imageUrl: u.photoUrl, size: 40),
                const SizedBox(width: 10),
                Expanded(child: adminTwoLine(c, u.name, '${_roleLabel(u)} · ${u.email ?? ''}')),
                _statusPill(u),
              ]),
            ),
          ]);
          final sel = _selected == null ? null : users.where((u) => u.uid == _selected).firstOrNull;
          return AdminListDetail(
            list: table,
            detail: sel == null ? null : UserDetail(uid: sel.uid),
            detailTitle: sel?.name ?? '',
            onClose: () => setState(() => _selected = null),
          );
        },
      ),
    );
  }
}

/// User detail: facts, payout-freeze state, beta flag (artisans), suspend
/// or reactivate, delete (server callable). Admins can't delete themselves.
class UserDetail extends ConsumerStatefulWidget {
  const UserDetail({super.key, required this.uid});
  final String uid;
  @override
  ConsumerState<UserDetail> createState() => _UserDetailState();
}

class _UserDetailState extends ConsumerState<UserDetail> {
  bool _busy = false;

  Future<void> _toggleSuspension(UserModel u) async {
    String? type;
    if (!u.isSuspended) {
      type = await showSuspensionTypeDialog(context, userName: u.name);
      if (type == null || !mounted) return;
    } else {
      final ok = await htConfirm(context, title: 'Reactivate ${u.name}?', message: 'They regain full access to the marketplace.', confirmLabel: 'Reactivate');
      if (!ok || !mounted) return;
    }
    final me = _me(ref);
    if (me == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminServiceProvider).setAccountStatus(uid: u.uid, suspend: !u.isSuspended, suspensionType: type, isArtisan: u.isArtisan, name: u.name, adminId: me);
      if (mounted) htSnack(context, u.isSuspended ? '${u.name} reactivated' : '${u.name} suspended');
    } catch (e) {
      if (mounted) htSnack(context, 'Could not update the account: ${adminError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(UserModel u) async {
    final ok = await htConfirm(
      context,
      title: 'Delete ${u.name}?',
      message: 'Their account is removed and they can no longer sign in. Job history, payments and reviews are kept. Recorded in the audit log.',
      confirmLabel: 'Delete user',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminServiceProvider).deleteUser(u.uid);
      if (mounted) htSnack(context, '${u.name} was deleted.');
    } catch (e) {
      debugPrint('[admin] deleteUser failed for ${u.uid}: $e');
      if (mounted) htSnack(context, 'Unable to delete user. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final users = ref.watch(adminUsersProvider).asData?.value ?? const <UserModel>[];
    final u = users.where((x) => x.uid == widget.uid).firstOrNull;
    if (u == null) return const HtLoadingView();
    final artisan = u.isArtisan ? ref.watch(artisanProfileProvider(u.uid)).asData?.value : null;
    final jobs = ref.watch(adminJobsProvider).asData?.value ?? const <JobModel>[];
    final mine = _me(ref) == u.uid;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        HtAvatar(name: u.name, imageUrl: u.photoUrl, size: 48),
        const SizedBox(width: 12),
        Expanded(child: adminTwoLine(context, u.name, u.email)),
        _statusPill(u),
      ]),
      adminSection(context, 'Account'),
      adminFact(context, 'Role', _roleLabel(u)),
      adminFact(context, 'Joined', adminDate(u.createdAt)),
      if (u.isSuspended) adminFact(context, 'Suspension type', u.suspensionType ?? 'Not recorded'),
      if (u.isSuspended) adminFact(context, 'Access', u.hasRestrictedSuspension ? 'Existing jobs, chat and payments' : 'Existing jobs and disputes only'),
      adminFact(context, 'Jobs as customer', '${jobs.where((j) => j.customerId == u.uid).length}'),
      if (u.isArtisan) adminFact(context, 'Jobs as artisan', '${jobs.where((j) => j.artisanId == u.uid).length}'),
      if (u.accountDeletionRequested) adminFact(context, 'Deletion', 'Requested by the user'),
      if (u.isArtisan) ...[
        adminSection(context, 'Artisan'),
        if (artisan != null) ...[
          adminFact(context, 'Approval', artisan.approvalStatus),
          adminFact(context, 'Eligible to quote', ArtisanEligibility.canQuote(artisan) ? 'Yes' : 'No'),
          BetaTesterToggle(artisan: artisan),
        ],
        payoutFreezeFact(context, frozen: u.payoutFrozen || (artisan?.payoutFrozen ?? false), reason: u.payoutFreezeReason ?? artisan?.payoutFreezeReason),
      ],
      const SizedBox(height: 16),
      if (_busy)
        const Center(child: CircularProgressIndicator())
      else if (mine)
        Text('This is your own account.', style: HtType.small(p.textMuted))
      else ...[
        HtPrimaryButton(label: u.isSuspended ? 'Reactivate account' : 'Suspend account', onPressed: () => _toggleSuspension(u)),
        const SizedBox(height: 8),
        HtDangerButton(label: 'Delete user', icon: Icons.delete_outline_rounded, onPressed: () => _delete(u)),
        const SizedBox(height: 6),
        Text('Every action asks for confirmation and is recorded in the audit log.', style: HtType.small(p.textMuted)),
      ],
    ]);
  }
}

/// Beta-tester flag (artisans may quote without ID verification).
class BetaTesterToggle extends ConsumerStatefulWidget {
  const BetaTesterToggle({super.key, required this.artisan});
  final ArtisanModel artisan;
  @override
  ConsumerState<BetaTesterToggle> createState() => _BetaTesterToggleState();
}

class _BetaTesterToggleState extends ConsumerState<BetaTesterToggle> {
  bool _busy = false;
  Future<void> _set(bool next) async {
    final a = widget.artisan;
    final ok = await htConfirm(
      context,
      title: next ? 'Enable beta tester?' : 'Disable beta tester?',
      message: next ? '${a.name} will be able to quote without completing ID verification.' : '${a.name} will need ID verification to quote again.',
      confirmLabel: next ? 'Enable' : 'Disable',
    );
    final me = _me(ref);
    if (!ok || me == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminServiceProvider).setBetaTester(a.uid, value: next, previous: a.betaTester, name: a.name, adminId: me);
    } catch (e) {
      if (mounted) htSnack(context, 'Could not update: ${adminError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => HtToggleRow(
        icon: Icons.science_outlined,
        title: 'Beta tester',
        subtitle: 'Quote without ID verification',
        value: widget.artisan.betaTester,
        busy: _busy,
        onChanged: _set,
      );
}

// ─── Artisans (AD-3) ────────────────────────────────────────────────────────

class AdminArtisansSection extends ConsumerStatefulWidget {
  const AdminArtisansSection({super.key});
  @override
  ConsumerState<AdminArtisansSection> createState() => _AdminArtisansSectionState();
}

class _AdminArtisansSectionState extends ConsumerState<AdminArtisansSection> {
  int _tab = 0;
  String? _selected;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(adminPendingArtisansProvider);
    final all = ref.watch(adminArtisansProvider);
    final pendingCount = pending.asData?.value.length;
    return AdminPage(
      title: 'Artisans',
      subtitle: 'Applications and artisan accounts',
      toolbar: AdminFilterBar(labels: const ['Pending applications', 'All artisans'], counts: [pendingCount, all.asData?.value.length], selected: _tab, onSelected: (i) => setState(() => _tab = i)),
      child: _tab == 0
          ? pending.when(
              loading: () => const HtLoadingView(),
              error: (e, _) => HtCard(child: HtErrorView(message: 'Applications could not be loaded.', onRetry: () => ref.invalidate(adminPendingArtisansProvider))),
              data: (list) => list.isEmpty
                  ? const HtCard(child: HtEmptyView(icon: Icons.task_alt_rounded, title: 'No pending applications'))
                  : AdminGrid(minTileWidth: 420, children: [for (final a in list) _ApplicationCard(artisan: a)]),
            )
          : all.when(
              loading: () => const HtLoadingView(),
              error: (e, _) => HtCard(child: HtErrorView(message: 'Artisans could not be loaded.', onRetry: () => ref.invalidate(adminArtisansProvider))),
              data: (list) {
                final q = _q.text.trim().toLowerCase();
                final shown = list.where((a) => q.isEmpty || a.displayName.toLowerCase().contains(q) || (a.category ?? '').toLowerCase().contains(q)).toList();
                final sel = _selected == null ? null : list.where((a) => a.uid == _selected).firstOrNull;
                return AdminListDetail(
                  detailTitle: sel?.displayName ?? '',
                  onClose: () => setState(() => _selected = null),
                  detail: sel == null ? null : _ArtisanDetail(artisan: sel),
                  list: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    HtSearchField(controller: _q, hint: 'Search name or trade', onChanged: (_) => setState(() {})),
                    const SizedBox(height: 12),
                    AdminTable<ArtisanModel>(
                      items: shown,
                      selected: (a) => a.uid == _selected,
                      onTap: (a) => adminIsWide(context) ? setState(() => _selected = a.uid) : openAdminDetailPage(context, title: a.displayName, builder: (_) => _ArtisanDetail(artisan: a)),
                      columns: [
                        AdminCol('Artisan', (c, a) => adminTwoLine(c, a.displayName, a.category), flex: 4),
                        AdminCol('Approval', (c, a) => HtStatusPill(label: a.approvalStatus, tone: a.approvalStatus == 'approved' ? HtTone.success : (a.approvalStatus == 'pending' ? HtTone.warning : HtTone.neutral))),
                        AdminCol('Verified', (c, a) => adminText(c, ArtisanEligibility.isReallyVerified(a) ? 'Yes' : 'No')),
                        AdminCol('Rating', (c, a) => adminText(c, a.totalRatings == 0 ? '—' : '${a.rating.toStringAsFixed(1)} (${a.totalRatings})'), numeric: true),
                        AdminCol('Trust', (c, a) => adminText(c, a.trustScore.round().toString()), flex: 1, numeric: true),
                      ],
                      mobileRow: (c, a) => Row(children: [
                        HtAvatar(name: a.displayName, imageUrl: a.profileImageUrl, size: 40),
                        const SizedBox(width: 10),
                        Expanded(child: adminTwoLine(c, a.displayName, '${a.category ?? '—'} · trust ${a.trustScore.round()}')),
                        HtStatusPill(label: a.approvalStatus),
                      ]),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}

class _ArtisanDetail extends ConsumerWidget {
  const _ArtisanDetail({required this.artisan});
  final ArtisanModel artisan;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(artisanProfileProvider(artisan.uid)).asData?.value ?? artisan;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      adminFact(context, 'Trade', a.category ?? '—'),
      adminFact(context, 'Approval', a.approvalStatus),
      adminFact(context, 'Identity verified', ArtisanEligibility.isReallyVerified(a) ? 'Yes' : 'No'),
      adminFact(context, 'Eligible to quote', ArtisanEligibility.canQuote(a) ? 'Yes' : 'No'),
      adminFact(context, 'Completed jobs', '${a.completedJobs}'),
      adminFact(context, 'Rating', a.totalRatings == 0 ? 'No reviews' : '${a.rating.toStringAsFixed(1)} from ${a.totalRatings}'),
      adminFact(context, 'Trust score', a.trustScore.round().toString()),
      BetaTesterToggle(artisan: a),
      payoutFreezeFact(context, frozen: a.payoutFrozen, reason: a.payoutFreezeReason),
      const SizedBox(height: 12),
      HtSecondaryButton(label: 'View public profile', icon: Icons.open_in_new_rounded, onPressed: () => context.push('/artisan/${a.uid}')),
    ]);
  }
}

class _ApplicationCard extends ConsumerStatefulWidget {
  const _ApplicationCard({required this.artisan});
  final ArtisanModel artisan;
  @override
  ConsumerState<_ApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends ConsumerState<_ApplicationCard> {
  bool _busy = false;
  Future<void> _decide(bool approve) async {
    final a = widget.artisan;
    final ok = await htConfirm(
      context,
      title: approve ? 'Approve ${a.name}?' : 'Reject ${a.name}?',
      message: approve ? 'They can quote once identity verification is complete.' : 'Their application is marked rejected.',
      confirmLabel: approve ? 'Approve' : 'Reject',
    );
    final me = _me(ref);
    if (!ok || me == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminServiceProvider).setArtisanApproval(a.uid, approve: approve, adminId: me);
      if (mounted) htSnack(context, approve ? '${a.name} approved' : '${a.name} rejected');
    } catch (e) {
      if (mounted) htSnack(context, 'Could not update the application: ${adminError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final a = widget.artisan;
    return HtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          HtAvatar(name: a.displayName, imageUrl: a.profileImageUrl, size: 44),
          const SizedBox(width: 10),
          Expanded(child: adminTwoLine(context, a.displayName, '${a.category ?? '—'} · applied ${adminDate(a.createdAt)}')),
        ]),
        if (a.skills.isNotEmpty) ...[const SizedBox(height: 10), Text(a.skills, style: HtType.small(p.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis)],
        if (a.bio?.isNotEmpty ?? false) ...[const SizedBox(height: 6), Text(a.bio!, style: HtType.small(p.textSecondary), maxLines: 3, overflow: TextOverflow.ellipsis)],
        if (a.location?.isNotEmpty ?? false) ...[const SizedBox(height: 6), Text('Service area: ${a.location}', style: HtType.small(p.textMuted))],
        const SizedBox(height: 12),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else
          Row(children: [
            Expanded(child: HtSecondaryButton(label: 'Reject', onPressed: () => _decide(false))),
            const SizedBox(width: 10),
            Expanded(child: HtPrimaryButton(label: 'Approve', height: 42, onPressed: () => _decide(true))),
          ]),
      ]),
    );
  }
}

// ─── Verifications (AD-4) ───────────────────────────────────────────────────

class AdminVerificationsSection extends ConsumerWidget {
  const AdminVerificationsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingVerificationsProvider);
    return AdminPage(
      title: 'Verifications',
      subtitle: 'Identity documents awaiting review',
      child: async.when(
        loading: () => const HtLoadingView(),
        error: (e, _) => HtCard(child: HtErrorView(message: 'Submissions could not be loaded.', onRetry: () => ref.invalidate(pendingVerificationsProvider))),
        data: (list) => list.isEmpty
            ? const HtCard(child: HtEmptyView(icon: Icons.task_alt_rounded, title: 'No submissions to review'))
            : AdminGrid(minTileWidth: 420, children: [for (final v in list) _VerificationCard(v: v)]),
      ),
    );
  }
}

class _VerificationCard extends ConsumerStatefulWidget {
  const _VerificationCard({required this.v});
  final VerificationModel v;
  @override
  ConsumerState<_VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends ConsumerState<_VerificationCard> {
  bool _busy = false;

  Future<void> _approve() async {
    final me = _me(ref);
    if (me == null) return;
    final ok = await htConfirm(context, title: 'Approve verification?', message: 'The artisan’s profile shows as identity-verified.', confirmLabel: 'Approve');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(verificationServiceProvider).approve(uid: widget.v.uid, reviewerId: me);
      await ref.read(adminServiceProvider).audit(action: AdminAction.verificationApproved, adminId: me, targetId: widget.v.uid, targetType: 'verification');
      if (mounted) htSnack(context, 'Verification approved');
    } catch (e) {
      if (mounted) htSnack(context, 'Approve failed: ${adminError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final me = _me(ref);
    if (me == null) return;
    final reason = await showAdminReasonDialog(context, title: 'Reject verification', message: 'Tell the artisan what to fix. They can submit again.', confirmLabel: 'Reject');
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(verificationServiceProvider).reject(uid: widget.v.uid, reviewerId: me, reason: reason);
      await ref.read(adminServiceProvider).audit(action: AdminAction.verificationRejected, adminId: me, targetId: widget.v.uid, targetType: 'verification', metadata: {'reason': reason});
      if (mounted) htSnack(context, 'Verification rejected');
    } catch (e) {
      if (mounted) htSnack(context, 'Reject failed: ${adminError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final artisan = ref.watch(artisanProfileProvider(v.uid)).asData?.value;
    final photos = [v.governmentIdUrl, v.selfieUrl];
    return HtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        adminTwoLine(context, artisan?.displayName ?? v.uid, 'Submitted ${adminDateTime(v.submittedAt)}'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: HtPhotoTile(url: v.governmentIdUrl, label: 'Government ID', height: 120, onTap: () => showHtPhotoViewer(context, photos, initial: 0, title: 'Government ID'))),
          const SizedBox(width: 10),
          Expanded(child: HtPhotoTile(url: v.selfieUrl, label: 'Selfie', height: 120, onTap: () => showHtPhotoViewer(context, photos, initial: 1, title: 'Selfie'))),
        ]),
        const SizedBox(height: 12),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else
          Row(children: [
            Expanded(child: HtSecondaryButton(label: 'Reject', onPressed: _reject)),
            const SizedBox(width: 10),
            Expanded(child: HtPrimaryButton(label: 'Approve', height: 42, onPressed: _approve)),
          ]),
      ]),
    );
  }
}
