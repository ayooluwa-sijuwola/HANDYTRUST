import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/models/admin_audit_log_model.dart';

/// Unit tests for the admin user-deletion audit trail
/// (design/ADMIN_USER_DELETION_AUDIT.md).
///
/// Scope, stated plainly, same standing disclosure as this repo's other
/// test files: functions/index.js's adminDeleteUser (the actual Firebase
/// Auth deletion, Storage cleanup, and Firestore cleanup) is server-side
/// Admin SDK code with no emulator harness in this repo — it cannot be
/// exercised by a Dart unit test. What IS tested here is the one thing
/// that silently breaks across the Dart/Node language boundary with no
/// compiler to catch it: AdminAction.userDeleted's serialized name is a
/// hardcoded string literal ('userDeleted') on the Cloud Functions side —
/// nothing type-checks that string against this enum. A rename on either
/// side without the other would silently make deleted-user audit entries
/// unreadable (falling back to a generic "Admin Override" label) without
/// any test ever failing to say why.
void main() {
  group('AdminAction.userDeleted — Dart/Cloud-Functions name contract', () {
    test('enum name is the exact string literal functions/index.js writes '
        'for adminDeleteUser\'s audit log entry', () {
      expect(AdminAction.userDeleted.name, 'userDeleted');
    });

    test('AdminAuditLogModel.fromJson resolves a userDeleted-shaped entry '
        'exactly as adminDeleteUser writes it', () {
      final json = {
        'id': 'log1',
        'action': 'userDeleted',
        'adminId': 'admin1',
        'targetId': 'uid1',
        'targetType': 'user',
        'timestamp': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'metadata': {'name': 'Ada', 'email': 'ada@example.com', 'wasArtisan': true},
      };
      final log = AdminAuditLogModel.fromJson(json);
      expect(log.action, AdminAction.userDeleted);
      expect(log.targetType, 'user');
      expect(log.metadata['wasArtisan'], isTrue);
      expect(log.actionLabel, 'User Deleted');
    });

    test('an unrecognized/legacy action string falls back to adminOverride '
        'rather than throwing — a future action rename must degrade '
        'gracefully in the admin activity history, not crash it', () {
      final log = AdminAuditLogModel.fromJson({
        'id': 'log2',
        'action': 'someFutureActionNotYetKnown',
        'adminId': 'admin1',
        'targetId': 'uid1',
        'targetType': 'user',
        'timestamp': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(log.action, AdminAction.adminOverride);
    });
  });

  // Beta Tester audit trail (design/BETA_TESTING_GUIDE.md, requirement 3).
  // betaTesterChanged is the one AdminAction that deliberately does NOT
  // serialize to its own .name — see AdminActionJson's doc comment — so
  // this contract is worth its own explicit round-trip test, same reason
  // as the userDeleted group above: nothing type-checks the literal string
  // 'beta_tester_changed' against this enum.
  group('AdminAction.betaTesterChanged — action-type contract', () {
    test('serializes to the required snake_case action type, not its '
        'camelCase enum name', () {
      expect(AdminAction.betaTesterChanged.toJsonValue(), 'beta_tester_changed');
      expect(AdminAction.betaTesterChanged.name, isNot('beta_tester_changed'));
    });

    test('fromJson resolves beta_tester_changed back to the enum correctly', () {
      final log = AdminAuditLogModel.fromJson({
        'id': 'log3',
        'action': 'beta_tester_changed',
        'adminId': 'admin1',
        'targetId': 'artisan1',
        'targetType': 'artisan',
        'timestamp': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'metadata': {'previousValue': false, 'newValue': true, 'name': 'Chidi'},
      });
      expect(log.action, AdminAction.betaTesterChanged);
      expect(log.actionLabel, 'Beta Tester Changed');
      expect(log.metadata['previousValue'], isFalse);
      expect(log.metadata['newValue'], isTrue);
    });

    test('toJson -> fromJson round-trips a betaTesterChanged entry losslessly', () {
      final original = AdminAuditLogModel(
        id: 'log4',
        action: AdminAction.betaTesterChanged,
        adminId: 'admin1',
        targetId: 'artisan1',
        targetType: 'artisan',
        timestamp: DateTime(2026, 1, 1),
        metadata: const {'previousValue': true, 'newValue': false, 'name': 'Chidi'},
      );
      final restored = AdminAuditLogModel.fromJson(original.toJson());
      expect(restored.action, AdminAction.betaTesterChanged);
      expect(restored.metadata['previousValue'], isTrue);
      expect(restored.metadata['newValue'], isFalse);
    });
  });
}
