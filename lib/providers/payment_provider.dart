import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/safe_firestore.dart';
import '../models/payment_model.dart';

/// This user's payment history as a customer (payer) — feeds the Wallet
/// screen. Requires the payerId+createdAt composite index added to
/// firestore.indexes.json alongside this provider — needs an actual
/// `firebase deploy --only firestore:indexes` to take effect in the live
/// project, which is an ops step outside this codebase.
final customerPaymentsProvider = StreamProvider.family<List<PaymentModel>, String>((ref, uid) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('payments')
        .where('payerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true),
    (d) => PaymentModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'customerPayments:$uid',
  );
});

/// This user's payment history as an artisan (payee) — feeds the Wallet
/// screen. Same index-deployment note as [customerPaymentsProvider].
final artisanPaymentsProvider = StreamProvider.family<List<PaymentModel>, String>((ref, uid) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('payments')
        .where('artisanId', isEqualTo: uid)
        .orderBy('createdAt', descending: true),
    (d) => PaymentModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'artisanPayments:$uid',
  );
});
