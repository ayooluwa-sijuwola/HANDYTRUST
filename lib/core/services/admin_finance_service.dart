import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Client facade over the Stage 4 admin finance Cloud Functions. Every money
/// decision (refund, release, split, freeze) is made server-side: the
/// callables check `admins/{uid}`, validate amounts, write audit logs and
/// move money idempotently. Admin clients can no longer write these outcomes
/// to Firestore directly (firestore.rules).
class AdminFinanceService {
  final FirebaseFunctions _functions;
  AdminFinanceService(this._functions);

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    final result = await _functions.httpsCallable(name).call(data);
    return Map<String, dynamic>.from((result.data as Map?) ?? const {});
  }

  /// outcome: 'release' | 'full_refund' | 'split'. Amounts in naira, only
  /// used (and required) for 'split'.
  Future<Map<String, dynamic>> resolveDispute({
    required String jobId,
    required String disputeId,
    required String outcome,
    required String reason,
    double? artisanAmount,
    double? refundAmount,
  }) =>
      _call('adminResolveDispute', {
        'jobId': jobId,
        'disputeId': disputeId,
        'outcome': outcome,
        'reason': reason,
        'artisanAmount': ?artisanAmount,
        'refundAmount': ?refundAmount,
      });

  /// decision: 'decline' | 'full_refund' | 'split'.
  Future<Map<String, dynamic>> resolveCancellation({
    required String jobId,
    required String decision,
    required String reason,
    double? artisanAmount,
    double? refundAmount,
  }) =>
      _call('adminResolveCancellation', {
        'jobId': jobId,
        'decision': decision,
        'reason': reason,
        'artisanAmount': ?artisanAmount,
        'refundAmount': ?refundAmount,
      });

  Future<Map<String, dynamic>> refundCharge({required String reference, required String reason}) =>
      _call('adminRefundCharge', {'reference': reference, 'reason': reason});

  Future<Map<String, dynamic>> retryRefund({required String refundId, String? reason}) =>
      _call('adminRetryRefund', {'refundId': refundId, 'reason': ?reason});

  Future<Map<String, dynamic>> retryPayout({required String jobId, required String reason}) =>
      _call('adminRetryPayout', {'jobId': jobId, 'reason': reason});

  Future<Map<String, dynamic>> setPayoutFreeze({
    required String targetType,
    required String targetId,
    required bool frozen,
    required String reason,
  }) =>
      _call('adminSetPayoutFreeze', {
        'targetType': targetType,
        'targetId': targetId,
        'frozen': frozen,
        'reason': reason,
      });
}

final adminFinanceServiceProvider =
    Provider<AdminFinanceService>((ref) => AdminFinanceService(FirebaseFunctions.instance));
