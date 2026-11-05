import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/paystack_service.dart';

/// Stage 8: shared (previously private to the old payment screen) so the
/// new Confirm & Pay screen and its tests use one provider. All amounts
/// are computed server-side (`getPaymentBreakdown`, Stage 3); the UI never
/// computes the platform fee.
final paystackServiceProvider = Provider<PaystackService>(
  (ref) => PaystackService(FirebaseFunctions.instance),
);

final paymentBreakdownProvider = FutureProvider.autoDispose.family<PaymentBreakdown, String>(
  (ref, jobId) => ref.watch(paystackServiceProvider).getPaymentBreakdown(jobId),
);
