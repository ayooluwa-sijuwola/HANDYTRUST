import 'package:cloud_functions/cloud_functions.dart';
import '../../models/payment_model.dart';

/// Client-side facade over the Paystack-related Cloud Functions
/// (`initializePaystackTransaction`, `verifyPayment`).
///
/// Previously this class called the Paystack REST API directly from the
/// Flutter app using a secret key read out of a Firestore document
/// (`/config/paystack`), which any signed-in user could read per
/// `firestore.rules`. The secret key never reaches the client now — both
/// operations are Cloud Functions that hold the key as a Functions secret.
class PaystackService {
  final FirebaseFunctions _functions;

  PaystackService(this._functions);

  /// Server-computed price breakdown for the payment screen (Stage 3). The
  /// UI never computes the platform fee itself — this is the same
  /// calculation initializePaystackTransaction charges with.
  Future<PaymentBreakdown> getPaymentBreakdown(String jobId) async {
    final result = await _functions.httpsCallable('getPaymentBreakdown').call({'jobId': jobId});
    return PaymentBreakdown.fromMap(Map<String, dynamic>.from(result.data as Map));
  }

  /// Step 1: Initialize transaction → get authorization URL for WebView.
  ///
  /// Returns null when the server found that an earlier attempt for this
  /// job had in fact already been paid (it locks escrow itself) — the
  /// caller should go straight back to the job instead of opening checkout.
  /// The `amount`/`artisanId` sent are ignored by the server (it charges
  /// the frozen agreed price + platform fee); kept for wire compatibility.
  Future<PaymentModel?> initializeTransaction({
    required String jobId,
    required String payerId,
    required String artisanId,
    required double amountNaira,
    required String customerEmail,
  }) async {
    final result = await _functions.httpsCallable('initializePaystackTransaction').call({
      'jobId': jobId,
      'artisanId': artisanId,
      'amount': amountNaira,
      'email': customerEmail,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    if (data['alreadyPaid'] == true) return null;

    return PaymentModel(
      id: data['paymentId'] as String,
      jobId: jobId,
      payerId: payerId,
      artisanId: artisanId,
      amount: (data['serviceAmount'] as num?)?.toDouble() ?? amountNaira,
      platformFee: (data['platformFee'] as num?)?.toDouble(),
      totalCharged: (data['totalCharged'] as num?)?.toDouble(),
      status: PaymentStatus.pending,
      paystackReference: data['reference'] as String,
      paystackAccessCode: data['accessCode'] as String?,
      authorizationUrl: data['authorizationUrl'] as String,
      createdAt: DateTime.now(),
    );
  }

  /// Step 2: Verify transaction after the WebView callback. The Cloud
  /// Function locks escrow server-side on success — callers must NOT also
  /// transition the job client-side, or the second (redundant) transition
  /// will fail against the state machine.
  Future<bool> verifyTransaction({required String reference, required String jobId}) async {
    final result = await _functions.httpsCallable('verifyPayment').call({
      'reference': reference,
      'jobId': jobId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['success'] as bool? ?? false;
  }
}

/// Server-computed charge for a job: the artisan's agreed service price,
/// HandyTrust's platform fee on top, and the total the customer pays.
class PaymentBreakdown {
  final double serviceAmount;
  final double platformFee;
  final double totalCharged;
  final double platformFeePercent;

  const PaymentBreakdown({
    required this.serviceAmount,
    required this.platformFee,
    required this.totalCharged,
    required this.platformFeePercent,
  });

  factory PaymentBreakdown.fromMap(Map<String, dynamic> m) => PaymentBreakdown(
        serviceAmount: (m['serviceAmount'] as num).toDouble(),
        platformFee: (m['platformFee'] as num).toDouble(),
        totalCharged: (m['totalCharged'] as num).toDouble(),
        platformFeePercent: (m['platformFeePercent'] as num?)?.toDouble() ?? 0,
      );
}
