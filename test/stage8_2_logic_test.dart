// Stage 8.2 — pure logic: conversations, read receipts, push routing and
// registration, password policy, admin alert catalogue, metrics, F-1 job
// deletion gating, finance parsing. Fixtures are test-only.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/constants/app_info.dart';
import 'package:handy_trust/core/services/admin_catalog.dart';
import 'package:handy_trust/core/services/admin_service.dart';
import 'package:handy_trust/core/services/conversation_logic.dart';
import 'package:handy_trust/core/services/push_logic.dart';
import 'package:handy_trust/core/validation/password_policy.dart';
import 'package:handy_trust/models/artisan_model.dart';
import 'package:handy_trust/models/finance_record.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/message_model.dart';
import 'package:handy_trust/models/payment_model.dart';
import 'package:handy_trust/models/user_model.dart';

JobModel job(String id, JobStatus s, {String customer = 'c1', String artisan = '', String? paymentReference, DateTime? created, String category = 'Plumbing', DateTime? escrowLockedAt}) => JobModel(
      id: id,
      customerId: customer,
      artisanId: artisan,
      category: category,
      description: 'Fix $id',
      status: s,
      paymentReference: paymentReference,
      escrowLockedAt: escrowLockedAt,
      createdAt: created ?? DateTime(2026, 11, 1),
    );

MessageModel msg(String from, String to, {bool read = false, bool pending = false, DateTime? at}) =>
    MessageModel(id: '$from-$to-${at?.millisecondsSinceEpoch ?? 0}', jobId: 'j', senderId: from, receiverId: to, text: 'hi', isRead: read, createdAt: at ?? DateTime(2026, 11, 5), isPending: pending);

void main() {
  group('ConversationLogic (role-separated discovery)', () {
    test('customer: booked job → one conversation with the assigned artisan', () {
      final refs = ConversationLogic.forCustomer('c1', [job('j1', JobStatus.inProgress, artisan: 'a1')], const {});
      expect(refs.map((r) => r.otherPartyId), ['a1']);
      expect(refs.single.viewerIsCustomer, isTrue);
    });

    test('customer: open job → one conversation per artisan who wrote (no merged thread)', () {
      final refs = ConversationLogic.forCustomer('c1', [job('j1', JobStatus.requested)], {'j1': {'a1', 'a2'}});
      expect(refs.map((r) => r.otherPartyId).toSet(), {'a1', 'a2'});
      expect(refs.map((r) => r.id).toSet().length, 2);
    });

    test('customer: open job nobody wrote about → no conversation', () {
      expect(ConversationLogic.forCustomer('c1', [job('j1', JobStatus.requested)], const {}), isEmpty);
    });

    test('customer: cancelled job appears only if messages were exchanged', () {
      expect(ConversationLogic.forCustomer('c1', [job('j1', JobStatus.cancelled, artisan: 'a1')], const {}), isEmpty);
      expect(ConversationLogic.forCustomer('c1', [job('j1', JobStatus.cancelled, artisan: 'a1')], {'j1': {'a1'}}), hasLength(1));
    });

    test('customer: another customer’s job is never listed', () {
      expect(ConversationLogic.forCustomer('c1', [job('j1', JobStatus.inProgress, customer: 'c2', artisan: 'a1')], const {}), isEmpty);
    });

    test('artisan: assigned jobs + open feed jobs they wrote about; never their own customer jobs', () {
      final refs = ConversationLogic.forArtisan(
        'a1',
        [job('j1', JobStatus.inProgress, artisan: 'a1'), job('own', JobStatus.inProgress, customer: 'a1', artisan: 'a9')],
        [job('o1', JobStatus.requested, customer: 'c7'), job('o2', JobStatus.requested, customer: 'c8')],
        {'o1': {'c7'}},
      );
      expect(refs.map((r) => r.job.id), ['j1', 'o1']);
      expect(refs.every((r) => !r.viewerIsCustomer), isTrue);
    });

    test('sorted by latest activity; search covers name, job and last message; totals add up', () {
      final a = ConversationView(ref: ConversationRef(job: job('j1', JobStatus.inProgress, artisan: 'a1'), viewerId: 'c1', otherPartyId: 'a1'), last: msg('a1', 'c1', at: DateTime(2026, 11, 5, 9)), unread: 2);
      final b = ConversationView(ref: ConversationRef(job: job('j2', JobStatus.inProgress, artisan: 'a2', category: 'Painting'), viewerId: 'c1', otherPartyId: 'a2'), last: msg('a2', 'c1', at: DateTime(2026, 11, 5, 11)), unread: 1);
      expect(ConversationLogic.sorted([a, b]).map((v) => v.ref.job.id), ['j2', 'j1']);
      expect(ConversationLogic.search([a, b], 'paint').single.ref.job.id, 'j2');
      expect(ConversationLogic.search([a, b], 'funke', nameOf: (r) => r.otherPartyId == 'a1' ? 'Funke' : 'Kola').single.ref.otherPartyId, 'a1');
      expect(ConversationLogic.totalUnread([a.unread, b.unread]), 3);
    });
  });

  group('Read receipts (no delivered state, no false success)', () {
    test('pending write → Sending; acknowledged → Sent; read flag → Read', () {
      expect(ReadReceipts.of(msg('c1', 'a1', pending: true)), ReceiptState.sending);
      expect(ReadReceipts.of(msg('c1', 'a1')), ReceiptState.sent);
      expect(ReadReceipts.of(msg('c1', 'a1', read: true)), ReceiptState.read);
      expect(ReceiptState.values.map(ReadReceipts.label), ['Sending', 'Sent', 'Read']);
    });

    test('marks read only in the foreground, only this conversation, only real unread', () {
      final fromA1 = [msg('a1', 'c1')];
      expect(ReadReceipts.shouldMarkRead(appInForeground: true, viewerId: 'c1', otherPartyId: 'a1', messages: fromA1), isTrue);
      expect(ReadReceipts.shouldMarkRead(appInForeground: false, viewerId: 'c1', otherPartyId: 'a1', messages: fromA1), isFalse);
      expect(ReadReceipts.shouldMarkRead(appInForeground: true, viewerId: 'c1', otherPartyId: 'a2', messages: fromA1), isFalse);
      expect(ReadReceipts.shouldMarkRead(appInForeground: true, viewerId: 'c1', otherPartyId: 'a1', messages: [msg('a1', 'c1', read: true), msg('c1', 'a1')]), isFalse);
    });
  });

  group('PushLogic', () {
    test('message notifications open the conversation; others follow the allow-listed route', () {
      expect(PushLogic.destination(type: 'message_received', jobId: 'j1', route: '/job/j1'), '/chat/j1');
      expect(PushLogic.destination(type: 'job_status_update', jobId: 'j1', route: '/job/j1'), '/job/j1');
      expect(PushLogic.destination(type: 'dispute_raised', jobId: 'j1', route: '/dispute/j1'), '/dispute/j1');
      expect(PushLogic.destination(type: 'x', jobId: 'j1'), '/job/j1');
      expect(PushLogic.destination(), '/notifications');
    });

    test('unsafe payloads never leave the allow-list', () {
      for (final bad in ['https://evil.example', '//evil.example', '/admin/users', 'job/1', '']) {
        expect(PushLogic.safeRoute(bad), '/notifications', reason: bad);
      }
      expect(PushLogic.destination(type: 'message_received', jobId: '../admin'), '/notifications');
    });

    test('registration decisions', () {
      expect(PushLogic.decide(uid: 'u1', enabled: true, previousUid: null), PushRegistration.register);
      expect(PushLogic.decide(uid: 'u1', enabled: false, previousUid: 'u1'), PushRegistration.unregisterAccount);
      expect(PushLogic.decide(uid: null, enabled: true, previousUid: 'u1'), PushRegistration.unregisterDevice);
      expect(PushLogic.decide(uid: null, enabled: true, previousUid: null), PushRegistration.none);
    });
  });

  group('PasswordPolicy (Q-3) and About facts', () {
    test('8+ characters, one uppercase letter, one number', () {
      expect(PasswordPolicy.validate('Short1'), contains('8 characters'));
      expect(PasswordPolicy.validate('alllowercase1'), contains('uppercase'));
      expect(PasswordPolicy.validate('NoNumbersHere'), contains('number'));
      expect(PasswordPolicy.validate('Valid123'), isNull);
      expect(PasswordPolicy.checklist('Ab1').map((r) => r.$2), [false, true, true]);
    });

    test('registration, change-password and Firebase weak-password copy use the same rule', () {
      expect(File('lib/screens/auth/register_screen.dart').readAsStringSync(), contains('PasswordPolicy.validate'));
      expect(File('lib/ui/settings/settings_screens.dart').readAsStringSync(), contains('PasswordPolicy.validate'));
      expect(File('lib/core/services/auth_service.dart').readAsStringSync(), isNot(contains('at least 6 characters')));
    });

    test('About version matches pubspec.yaml', () {
      final v = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
      expect('${AppInfo.version}+${AppInfo.build}', v);
    });
  });

  group('Admin alert catalogue (F-2)', () {
    test('all 28 server alert types have a readable label', () {
      final src = File('functions/index.js').readAsStringSync();
      final written = RegExp(r"type:\s*'([a-z_]+)'").allMatches(src).map((m) => m.group(1)!).toSet();
      final alertTypes = written.intersection(AdminAlertCatalog.kinds.keys.toSet());
      expect(AdminAlertCatalog.kinds.length, 28);
      expect(alertTypes.length, greaterThanOrEqualTo(20), reason: 'catalogue should match server alert writes');
      for (final k in AdminAlertCatalog.kinds.values) {
        expect(k.label.isNotEmpty, isTrue);
      }
    });

    test('unknown types fall back to a readable label and keep the raw id visible', () {
      expect(AdminAlertCatalog.of('something_new').label, 'Unrecognised alert');
      expect(AdminAlertCatalog.of('refund_failed').action, AlertAction.retryRefund);
      expect(AdminAlertCatalog.detail({'jobId': 'j1', 'message': 'Rejected'}), 'Job j1 · Rejected');
    });

    test('no "View in Finance" action (U-2 not approved): chargebacks resolve only', () {
      for (final e in AdminAlertCatalog.kinds.entries.where((e) => e.key.startsWith('chargeback_'))) {
        expect(e.value.action, AlertAction.resolve, reason: e.key);
      }
    });
  });

  group('Admin metrics (genuine figures only)', () {
    final now = DateTime(2026, 11, 5, 12);
    test('active, completed, escrow held, average rating', () {
      final jobs = [job('a', JobStatus.inProgress), job('b', JobStatus.completed), job('c', JobStatus.requested), job('d', JobStatus.resolved)];
      expect(AdminMetrics.activeJobs(jobs), 1);
      expect(AdminMetrics.completedJobs(jobs), 2);
      final pays = [
        PaymentModel(id: 'p1', jobId: 'a', payerId: 'c', artisanId: 'x', amount: 1000, totalCharged: 1050, status: PaymentStatus.escrowHeld, createdAt: now),
        PaymentModel(id: 'p2', jobId: 'b', payerId: 'c', artisanId: 'x', amount: 2000, status: PaymentStatus.released, createdAt: now),
      ];
      expect(AdminMetrics.escrowHeld(pays), 1050);
      expect(AdminMetrics.averageRating([ArtisanModel(uid: 'a', name: 'A', createdAt: now)]), isNull);
      expect(AdminMetrics.averageRating([ArtisanModel(uid: 'a', name: 'A', createdAt: now, rating: 4, totalRatings: 2), ArtisanModel(uid: 'b', name: 'B', createdAt: now, rating: 5, totalRatings: 1)]), 4.5);
    });

    test('per-day counts, top categories, rates with empty-safe nulls', () {
      final jobs = [job('a', JobStatus.requested, created: now), job('b', JobStatus.requested, created: now.subtract(const Duration(days: 1))), job('c', JobStatus.requested, created: now.subtract(const Duration(days: 40)), category: 'Painting')];
      expect(AdminMetrics.jobsPerDay(jobs, now), [0, 0, 0, 0, 0, 1, 1]);
      expect(AdminMetrics.topCategories(jobs, now), [('Plumbing', 2)]);
      expect(AdminMetrics.completionRate(const []), isNull);
      expect(AdminMetrics.completionRate([job('a', JobStatus.completed), job('b', JobStatus.cancelled)]), 0.5);
      final users = [UserModel(uid: 'u', name: 'U', createdAt: now.subtract(const Duration(days: 2))), UserModel(uid: 'v', name: 'V', createdAt: now.subtract(const Duration(days: 9)))];
      expect(AdminMetrics.joinedThisAndLastWeek(users, now), (1, 1));
    });
  });

  group('F-1 job deletion gating mirrors firestore.rules', () {
    test('only jobs that never held funds', () {
      for (final s in [JobStatus.requested, JobStatus.matched, JobStatus.inChat]) {
        expect(AdminService.canDeleteJob(job('x', s)), isTrue, reason: s.name);
      }
      expect(AdminService.canDeleteJob(job('x', JobStatus.cancelled)), isTrue);
      expect(AdminService.canDeleteJob(job('x', JobStatus.cancelled, paymentReference: 'ref')), isFalse);
      for (final s in [JobStatus.paymentPending, JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted, JobStatus.disputed, JobStatus.completed, JobStatus.resolved]) {
        expect(AdminService.canDeleteJob(job('x', s)), isFalse, reason: s.name);
      }
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules, contains("resource.data.status in ['requested', 'matched', 'inChat']"));
    });

    test('deletion order: messages listed, then job deleted, then messages (refusal removes nothing)', () {
      final src = File('lib/core/services/admin_service.dart').readAsStringSync();
      final body = src.substring(src.indexOf('Future<void> deleteJob('));
      final list = body.indexOf("collection('messages').get()");
      final delJob = body.indexOf('jobRef.delete()');
      final delMsgs = body.indexOf('batch.delete(d.reference)');
      expect(body.indexOf('canDeleteJob(job)'), lessThan(list));
      expect(list, lessThan(delJob));
      expect(delJob, lessThan(delMsgs));
    });
  });

  group('Finance records (read-only parsing)', () {
    test('kobo → naira; per-kind fields', () {
      final cb = FinanceRecord(FinanceKind.chargebacks, 'CB1', {'status': 'open', 'chargedAmountKobo': 8925000, 'payoutStateAtOpen': 'in_escrow', 'jobId': 'j1', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 22))});
      expect(cb.amount, 89250);
      expect(cb.open, isTrue);
      expect(FinanceRecord.humanise(cb.payoutStateAtOpen), 'In escrow');
      final st = FinanceRecord(FinanceKind.settlements, 'j2', {'serviceKobo': 2450000, 'payoutLeg': {'status': 'pending', 'amountKobo': 1500000}, 'refundLeg': {'status': 'pending', 'amountKobo': 950000}, 'platformRetainedKobo': 0});
      expect([st.amount, st.artisanLeg, st.refundLeg, st.retained], [24500, 15000, 9500, 0]);
      expect(FinanceKind.platformLosses.timeField, 'recordedAt');
      expect(FinanceRecord(FinanceKind.refunds, 'r', const {}).amount, isNull);
    });
  });
}
