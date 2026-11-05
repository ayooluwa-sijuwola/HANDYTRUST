// Stage 8.1 admin PREVIEWS (AD-0 … AD-13). Static compositions with SAMPLE
// DATA; every control corresponds to an existing admin feature or an
// approved exposure of an existing endpoint (Finance read-only, payout
// freeze). Not wired to providers.
import 'package:flutter/material.dart';
import 'package:handy_trust/ui/components/ht_components.dart';
import 'package:handy_trust/ui/theme/ht_theme.dart';

import 'preview_kit.dart';

Widget _pill(String l, HtTone t) => HtStatusPill(label: l, tone: t, dot: true);

Widget adDashboard() => Builder(builder: (context) {
      final p = context.ht;
      final wide = MediaQuery.sizeOf(context).width >= 1024;
      final kpis = [
        const HtKpiTile(icon: Icons.people_alt_outlined, label: 'Total Users', value: '1,284', change: '+6%', up: true),
        const HtKpiTile(icon: Icons.handyman_outlined, label: 'Total Artisans', value: '312', change: '+3%', up: true),
        const HtKpiTile(icon: Icons.work_outline_rounded, label: 'Active Jobs', value: '57', change: '−4%', up: false),
        const HtKpiTile(icon: Icons.lock_outline_rounded, label: 'Escrow Volume', value: '₦4.8M', note: 'Payments currently held in escrow'),
        const HtKpiTile(icon: Icons.task_alt_rounded, label: 'Completed Jobs', value: '1,046', change: '+9%', up: true),
        const HtKpiTile(icon: Icons.verified_user_outlined, label: 'Pending Verifications', value: '2', change: '−50%', up: false),
        const HtKpiTile(icon: Icons.star_outline_rounded, label: 'Average Rating', value: '4.7', note: 'Mean of rated artisans'),
      ];
      final alerts = htPanel(context, 'Operational alerts', [
        HtAlertRow(
          tone: HtTone.danger,
          title: 'Refund failed at Paystack',
          typeId: 'refund_failed',
          detail: 'Refund RF-20931 for job #HT-0B8491 was rejected by Paystack.',
          time: '2 h ago',
          actions: [HtSmallPrimaryButton(label: 'Retry refund', onPressed: () {}), HtSecondaryButton(label: 'Resolve', dense: true, height: 38, onPressed: () {})],
        ),
        HtAlertRow(
          tone: HtTone.danger,
          title: 'Chargeback opened after payout',
          typeId: 'chargeback_after_payout',
          detail: 'Customer disputed the card charge after the artisan was paid. Any loss is absorbed by HandyTrust.',
          time: '5 h ago',
          actions: [HtSecondaryButton(label: 'View in Finance', dense: true, height: 38, onPressed: () {}), HtSecondaryButton(label: 'Resolve', dense: true, height: 38, onPressed: () {})],
        ),
        HtAlertRow(
          tone: HtTone.warning,
          title: 'Refund held: chargeback open',
          typeId: 'refund_held_chargeback',
          detail: 'Refund for job #HT-3A9115 is on hold until the chargeback closes.',
          time: '1 d ago',
          actions: [HtSecondaryButton(label: 'Resolve', dense: true, height: 38, onPressed: () {})],
        ),
      ], badge: '3 open');
      final chart = HtChartCard(
        title: 'Jobs overview',
        subtitle: 'Last 7 days',
        legend: const ['Created', 'In progress', 'Completed'],
        height: 190,
        child: htLineChart(context, const [
          [8, 11, 9, 14, 12, 16, 13],
          [5, 6, 8, 7, 9, 10, 11],
          [3, 5, 4, 6, 8, 7, 9],
        ], const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']),
      );
      final pending = htPanel(context, 'Pending actions', [
        for (final (i, l, n) in [
          (Icons.handyman_outlined, 'Artisan approvals', 4),
          (Icons.verified_user_outlined, 'Verifications', 2),
          (Icons.support_agent_rounded, 'Support tickets', 3),
          (Icons.gavel_rounded, 'Open disputes', 1),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              htIconTile(context, i, size: 34),
              const SizedBox(width: 10),
              Expanded(child: Text(l, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5))),
              HtStatusPill(label: '$n', tone: HtTone.accent),
              Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ]),
          ),
      ]);
      final cats = HtChartCard(
        title: 'Top categories',
        subtitle: 'Jobs created, last 30 days',
        height: 150,
        child: htBarList(context, const [('Plumbing', 64), ('Electrical', 51), ('Painting', 38), ('Carpentry', 22), ('Cleaning', 17)]),
      );
      final health = htPanel(context, 'Platform health', [
        htKv(context, 'Completion rate', '87%', strong: true),
        htKv(context, 'Verification rate', '74%', strong: true),
        htKv(context, 'Response time', '2.1 h', strong: true),
        htKv(context, 'Dispute rate', '1.8%', strong: true),
      ], trailing: 'Analytics');
      return AdminFrame(
        section: 'Dashboard',
        title: 'Dashboard',
        subtitle: 'Platform overview from live records',
        children: wide
            ? [
                htGrid(kpis, columns: 4),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: Column(children: [alerts, const SizedBox(height: 14), chart])),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: Column(children: [pending, const SizedBox(height: 14), cats, const SizedBox(height: 14), health])),
                ]),
              ]
            : [htGrid(kpis.take(4).toList(), columns: 2, gap: 10), alerts, const SizedBox(height: 14), pending],
      );
    });

Widget adUsers() => Builder(builder: (context) {
      final p = context.ht;
      final rows = [
        ['Funke Adeyemi', 'funke.a@example.com', 'Customer', '12 Mar 2026', 'Active', '6'],
        ['Tunde Balogun', 'tunde.b@example.com', 'Artisan', '02 Feb 2026', 'Active', '42'],
        ['Emeka Okafor', 'emeka.o@example.com', 'Customer', '28 Jan 2026', 'Suspended', '3'],
        ['Aisha Bello', 'aisha.b@example.com', 'Artisan', '19 Jan 2026', 'Active', '17'],
        ['Kunle Ade', 'kunle.a@example.com', 'Customer', '05 Jan 2026', 'Active', '1'],
      ];
      return AdminFrame(
        section: 'Users',
        title: 'Users',
        subtitle: 'Customers and artisans',
        panel: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const HtAvatar(name: 'Emeka Okafor', size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Emeka Okafor', style: HtType.cardTitle(p.textPrimary)),
                Text('emeka.o@example.com', style: HtType.small(p.textSecondary)),
              ]),
            ),
            _pill('Suspended', HtTone.danger),
          ]),
          const SizedBox(height: 18),
          HtCard(
            radius: HtRadius.inner,
            color: p.surfaceRaised,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              htKv(context, 'Role', 'Customer'),
              htKv(context, 'Joined', '28 Jan 2026'),
              htKv(context, 'Suspension type', 'Administrative'),
              htKv(context, 'Access', 'Existing jobs, chat and payments only'),
            ]),
          ),
          const SizedBox(height: 14),
          const HtToggleRow(title: 'Beta tester', subtitle: 'Early access flag', value: false, icon: Icons.science_outlined),
          const SizedBox(height: 18),
          Text('ACTIVITY', style: HtType.caps(p.textMuted)),
          const SizedBox(height: 8),
          htKv(context, 'Jobs posted', '3'),
          htKv(context, 'Payments', '2'),
          const SizedBox(height: 20),
          HtPrimaryButton(label: 'Unsuspend user', onPressed: () {}),
          const SizedBox(height: 10),
          const HtDangerButton(label: 'Delete user…', icon: Icons.delete_outline_rounded),
          const SizedBox(height: 8),
          Text('Deletion asks for confirmation and is recorded in the audit log.', style: HtType.small(p.textMuted), textAlign: TextAlign.center),
        ]),
        children: [
          HtFilterBar(hint: 'Search name or email', chips: const ['All', 'Customers', 'Artisans', 'Suspended'], counts: const [1284, 972, 312, 6]),
          const SizedBox(height: 16),
          HtDataTable(
            selected: 2,
            columns: const [HtColumn('Name', flex: 4), HtColumn('Role'), HtColumn('Joined'), HtColumn('Status', flex: 3), HtColumn('Jobs', numeric: true)],
            rows: [
              for (final r in rows)
                [
                  tPerson(context, r[0], r[1]),
                  tCell(context, r[2]),
                  tCell(context, r[3], muted: true),
                  _pill(r[4], r[4] == 'Active' ? HtTone.success : HtTone.danger),
                  tCell(context, r[5], strong: true),
                ],
            ],
          ),
        ],
      );
    });

Widget adVerifications() => Builder(builder: (context) {
      final p = context.ht;
      return AdminFrame(
        section: 'Verifications',
        title: 'Verifications',
        subtitle: 'Identity documents awaiting review',
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 320,
              child: Column(children: [
                HtListCard(leading: const HtAvatar(name: 'Aisha Bello', size: 42), title: 'Aisha Bello', subtitle: 'Electrician · Ibadan', meta: 'Submitted 3 h ago', trailing: _pill('Pending', HtTone.warning)),
                const SizedBox(height: 10),
                HtListCard(leading: const HtAvatar(name: 'Kola Ade', size: 42), title: 'Kola Ade', subtitle: 'Carpenter · Lagos', meta: 'Submitted 1 d ago', trailing: _pill('Pending', HtTone.warning)),
              ]),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: HtCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const HtAvatar(name: 'Aisha Bello', size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Aisha Bello', style: HtType.cardTitle(p.textPrimary)),
                        Text('Electrician · Ibadan · artisan since Sep 2026', style: HtType.small(p.textSecondary)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  Row(children: const [
                    Expanded(child: HtPhotoTile(label: 'Government ID (front)', height: 220, icon: Icons.badge_outlined)),
                    SizedBox(width: 14),
                    Expanded(child: HtPhotoTile(label: 'Selfie', height: 220, icon: Icons.face_outlined)),
                  ]),
                  const SizedBox(height: 12),
                  const HtInfoBanner(icon: Icons.lock_outline_rounded, tone: HtTone.neutral, text: 'Images are visible to administrators only. Tap an image to zoom.'),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Expanded(child: HtDangerButton(label: 'Reject…', icon: Icons.close_rounded)),
                    const SizedBox(width: 12),
                    Expanded(child: HtPrimaryButton(label: 'Approve', leadingIcon: Icons.check_rounded, height: 46, onPressed: () {})),
                  ]),
                ]),
              ),
            ),
          ]),
        ],
      );
    });

Widget adJobs() => Builder(builder: (context) {
      final p = context.ht;
      final rows = [
        ['#HT-0B8491', 'Painting', 'Funke Adeyemi', 'Tunde Balogun', 'In progress', '₦85,000'],
        ['#HT-3A9115', 'Plumbing', 'Aisha Bello', 'Kola Ade', 'Disputed', '₦24,500'],
        ['#HT-5D7720', 'Electrical', 'Kunle Ade', '—', 'Requested', '—'],
        ['#HT-7C2210', 'Plumbing', 'Emeka Okafor', 'Tunde Balogun', 'Completed', '₦32,000'],
      ];
      HtTone tone(String s) => switch (s) { 'Completed' => HtTone.success, 'Disputed' => HtTone.danger, 'Requested' => HtTone.neutral, _ => HtTone.warning };
      return AdminFrame(
        section: 'Jobs',
        title: 'Jobs',
        subtitle: 'All bookings and requests',
        panel: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('#HT-3A9115 · Plumbing', style: HtType.cardTitle(p.textPrimary))),
            _pill('Disputed', HtTone.danger),
          ]),
          const SizedBox(height: 14),
          HtCard(
            radius: HtRadius.inner,
            color: p.surfaceRaised,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              htKv(context, 'Customer', 'Aisha Bello'),
              htKv(context, 'Artisan', 'Kola Ade'),
              htKv(context, 'Agreed price', '₦24,500', strong: true),
              htKv(context, 'Escrow', 'Funded · payout on hold'),
              htKv(context, 'Quotes', '3'),
              htKv(context, 'Chat', 'Started'),
            ]),
          ),
          const SizedBox(height: 14),
          const HtTimeline(entries: [
            ('Requested', '10 Oct', true),
            ('Quote accepted · escrow funded', '12 Oct', true),
            ('Work submitted', '15 Oct', true),
            ('Dispute raised by customer', '17 Oct', true),
            ('Awaiting admin resolution', 'Open', false),
          ]),
          const SizedBox(height: 10),
          HtSecondaryButton(label: 'Open dispute', icon: Icons.arrow_forward_rounded, onPressed: () {}),
          const SizedBox(height: 18),
          HtInfoBanner(
            icon: Icons.inventory_2_outlined,
            tone: HtTone.neutral,
            title: 'Deletion unavailable',
            text: 'This job has a payment and a dispute. Its chat, photos and financial history are kept as evidence.',
          ),
        ]),
        children: [
          HtFilterBar(hint: 'Search job, person or reference', chips: const ['All', 'Requested', 'Active', 'Disputed', 'Completed']),
          const SizedBox(height: 16),
          HtDataTable(
            selected: 1,
            columns: const [HtColumn('Job', flex: 2), HtColumn('Category'), HtColumn('Customer', flex: 3), HtColumn('Artisan', flex: 3), HtColumn('Status', flex: 3), HtColumn('Amount', numeric: true)],
            rows: [
              for (final r in rows)
                [tCell(context, r[0], strong: true), tCell(context, r[1]), tCell(context, r[2]), tCell(context, r[3], muted: r[3] == '—'), _pill(r[4], tone(r[4])), tCell(context, r[5], strong: true)],
            ],
          ),
          const SizedBox(height: 14),
          HtInfoBanner(
            icon: Icons.delete_outline_rounded,
            tone: HtTone.neutral,
            text: 'Delete Job Request is offered only for unpaid jobs (Requested, Matched, In chat, or Cancelled without payment). The job is checked before anything is removed.',
          ),
        ],
      );
    });

Widget adDisputes() => Builder(builder: (context) {
      final p = context.ht;
      return AdminFrame(
        section: 'Disputes',
        title: 'Disputes',
        subtitle: 'Escrow disputes awaiting a decision',
        overlay: HtDialogCard(title: 'Resolve dispute #HT-3A9115', children: [
          Text('Agreed price ₦24,500 · held in escrow', style: HtType.small(p.textSecondary)),
          const SizedBox(height: 16),
          Row(children: [
            HtChip(label: 'Release to artisan', selected: false, onTap: () {}),
            const SizedBox(width: 8),
            HtChip(label: 'Full refund', selected: false, onTap: () {}),
            const SizedBox(width: 8),
            HtChip(label: 'Split', selected: true, onTap: () {}),
          ]),
          Row(children: [
            Expanded(child: htField(context, 'To artisan (₦)', '15,000')),
            const SizedBox(width: 12),
            Expanded(child: htField(context, 'Refund to customer (₦)', '9,500')),
          ]),
          htField(context, 'Reason (required)', 'Work partly completed; second coat missing.', lines: 2),
          const SizedBox(height: 12),
          Text('Amounts are validated by the server. The decision is recorded in the audit log.', style: HtType.small(p.textMuted)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: HtSecondaryButton(label: 'Cancel', onPressed: () {})),
            const SizedBox(width: 12),
            Expanded(child: HtPrimaryButton(label: 'Confirm split', height: 46, onPressed: () {})),
          ]),
        ]),
        children: [
          HtCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('#HT-3A9115 · Plumbing', style: HtType.cardTitle(p.textPrimary))),
                _pill('Open · 2 days', HtTone.danger),
              ]),
              const SizedBox(height: 8),
              Text('“The pipe still leaks after the repair.”', style: HtType.body(p.textPrimary)),
              const SizedBox(height: 12),
              Row(children: const [
                Expanded(child: HtPhotoTile(label: 'Customer evidence')),
                SizedBox(width: 10),
                Expanded(child: HtPhotoTile(label: 'Completion photo')),
                SizedBox(width: 10),
                Expanded(child: HtPhotoTile(label: 'Completion photo')),
              ]),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerRight, child: HtSmallPrimaryButton(label: 'Resolve', onPressed: () {})),
            ]),
          ),
        ],
      );
    });

Widget adFinance({bool freezeDialog = false}) => Builder(builder: (context) {
      final p = context.ht;
      final rows = [
        ['CB-81273', '#HT-0B8491', 'Open', 'Paid out', '₦89,250', '22 Oct 2026'],
        ['CB-80911', '#HT-3A9115', 'Open · investigating', 'In escrow', '₦25,725', '18 Oct 2026'],
        ['CB-79002', '#HT-1F4407', 'Closed · merchant won', 'Released', '₦42,000', '02 Oct 2026'],
      ];
      return AdminFrame(
        section: 'Finance',
        title: 'Finance',
        subtitle: 'Read-only financial records',
        overlay: freezeDialog
            ? HtDialogCard(title: 'Freeze payout for job #HT-3A9115?', children: [
                Text('The artisan will not be paid for this job until the freeze is lifted. Nothing is charged or refunded.', style: HtType.body(p.textSecondary)),
                htField(context, 'Reason (required, at least 10 characters)', 'Chargeback under investigation with Paystack.', lines: 2),
                const SizedBox(height: 12),
                const HtInfoBanner(icon: Icons.history_rounded, tone: HtTone.neutral, text: 'Recorded in the audit log with your name and reason.'),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: HtSecondaryButton(label: 'Cancel', onPressed: () {})),
                  const SizedBox(width: 12),
                  Expanded(child: HtPrimaryButton(label: 'Freeze payout', leadingIcon: Icons.ac_unit_rounded, height: 46, onPressed: () {})),
                ]),
              ])
            : null,
        panel: freezeDialog
            ? null
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Chargeback CB-80911', style: HtType.cardTitle(p.textPrimary))),
                  _pill('Open · investigating', HtTone.warning),
                ]),
                const SizedBox(height: 14),
                HtCard(
                  radius: HtRadius.inner,
                  color: p.surfaceRaised,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(children: [
                    htKv(context, 'Job', '#HT-3A9115'),
                    htKv(context, 'Payment reference', 'HT_3A9115_1729'),
                    htKv(context, 'Charged amount', '₦25,725', strong: true),
                    htKv(context, 'Payout state at open', 'In escrow'),
                    htKv(context, 'Opened', '18 Oct 2026'),
                  ]),
                ),
                const SizedBox(height: 18),
                Text('PAYOUT FREEZE', style: HtType.caps(p.textMuted)),
                const SizedBox(height: 8),
                HtCard(
                  radius: HtRadius.inner,
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      htIconTile(context, Icons.ac_unit_rounded, tone: HtTone.neutral, size: 38),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Payout for this job is not frozen', style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5))),
                    ]),
                    const SizedBox(height: 12),
                    HtSecondaryButton(label: 'Freeze payout…', onPressed: () {}),
                  ]),
                ),
              ]),
        children: [
          Row(children: [
            HtChip(label: 'Chargebacks', count: 3, selected: true, onTap: () {}),
            const SizedBox(width: 8),
            HtChip(label: 'Platform losses', count: 1, selected: false, onTap: () {}),
            const SizedBox(width: 8),
            HtChip(label: 'Refunds', count: 5, selected: false, onTap: () {}),
            const SizedBox(width: 8),
            HtChip(label: 'Settlements', count: 12, selected: false, onTap: () {}),
          ]),
          const SizedBox(height: 16),
          HtDataTable(
            selected: 1,
            columns: const [HtColumn('Chargeback'), HtColumn('Job'), HtColumn('Status', flex: 4), HtColumn('Payout at open'), HtColumn('Charged', numeric: true), HtColumn('Opened')],
            rows: [
              for (final r in rows)
                [
                  tCell(context, r[0], strong: true),
                  tCell(context, r[1]),
                  _pill(r[2], r[2] == 'Open' ? HtTone.danger : (r[2].startsWith('Open ·') ? HtTone.warning : HtTone.success)),
                  tCell(context, r[3]),
                  tCell(context, r[4], strong: true),
                  tCell(context, r[5], muted: true),
                ],
            ],
          ),
          const SizedBox(height: 14),
          const HtInfoBanner(
            icon: Icons.visibility_outlined,
            tone: HtTone.neutral,
            text: 'Read-only. Amounts are shown exactly as stored. Closing a chargeback is not available in this view.',
          ),
        ],
      );
    });

Widget adAuditLogs() => Builder(builder: (context) {
      final rows = [
        ['24 Oct · 10:14', 'Ada (admin)', 'Dispute resolved · split', '#HT-3A9115', 'Work partly completed'],
        ['24 Oct · 09:02', 'Ada (admin)', 'Verification approved', 'Aisha Bello', '—'],
        ['23 Oct · 17:45', 'Musa (admin)', 'User suspended · administrative', 'Emeka Okafor', '—'],
        ['23 Oct · 11:20', 'Musa (admin)', 'Payout frozen', '#HT-3A9115', 'Chargeback under investigation'],
        ['22 Oct · 15:03', 'Ada (admin)', 'Review deleted', 'Review on Kola Ade', '—'],
      ];
      return AdminFrame(
        section: 'Audit logs',
        title: 'Audit logs',
        subtitle: 'Every admin action, newest first (read-only)',
        children: [
          HtFilterBar(hint: 'Search target or reason', chips: const ['All actions', 'Users', 'Finance', 'Disputes', 'Verifications']),
          const SizedBox(height: 16),
          HtDataTable(
            columns: const [HtColumn('Time'), HtColumn('Admin'), HtColumn('Action', flex: 3), HtColumn('Target', flex: 2), HtColumn('Reason', flex: 3)],
            rows: [for (final r in rows) [tCell(context, r[0], muted: true), tCell(context, r[1]), tCell(context, r[2], strong: true), tCell(context, r[3]), tCell(context, r[4], muted: r[4] == '—')]],
          ),
        ],
      );
    });

Widget adSettings() => Builder(builder: (context) {
      final p = context.ht;
      return AdminFrame(
        section: 'Settings',
        title: 'Settings',
        alerts: 0,
        children: [
          SizedBox(
            width: 620,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HtCard(
                child: Row(children: [
                  const HtAvatar(name: 'Ada Obi', size: 56, ring: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Ada Obi', style: HtType.cardTitle(p.textPrimary)),
                      Text('ada.obi@example.com', style: HtType.small(p.textSecondary)),
                    ]),
                  ),
                  const HtStatusPill(label: 'Administrator', tone: HtTone.accent, icon: Icons.admin_panel_settings_outlined),
                ]),
              ),
              const SizedBox(height: 14),
              HtCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  HtMenuRow(icon: Icons.dark_mode_outlined, title: 'Dark mode', subtitle: 'Applies to the admin dashboard and the app', showChevron: false, trailing: Switch(value: p.isDark, onChanged: (_) {}), onTap: () {}),
                  HtMenuRow(icon: Icons.logout_rounded, title: 'Sign out', destructive: true, onTap: () {}),
                ]),
              ),
            ]),
          ),
        ],
      );
    });
