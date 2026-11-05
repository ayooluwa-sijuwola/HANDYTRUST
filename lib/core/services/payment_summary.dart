import '../../models/payment_model.dart';

/// Stage 8: what the customer Payments screen shows, derived only from the
/// customer's real payment records. There is no stored-value wallet:
/// nothing here is withdrawable, and no balance is invented.
class PaymentSummary {
  const PaymentSummary({required this.heldInEscrow, required this.released, required this.refunded, required this.heldCount});

  /// Charged amounts currently held in escrow (escrowHeld, releasing, settling).
  final double heldInEscrow;
  /// Charged amounts whose escrow has been released or settled.
  final double released;
  /// Refunded or charged-back amounts.
  final double refunded;
  final int heldCount;

  static const heldStatuses = {PaymentStatus.escrowHeld, PaymentStatus.releasing, PaymentStatus.settling};
  static const releasedStatuses = {PaymentStatus.released, PaymentStatus.settled};
  static const refundedStatuses = {PaymentStatus.refunded, PaymentStatus.chargedBack};

  /// The amount the customer was charged (service price + platform fee);
  /// legacy records without a fee breakdown charged exactly [PaymentModel.amount].
  static double charged(PaymentModel p) => p.totalCharged ?? p.amount;

  static PaymentSummary of(List<PaymentModel> payments) {
    var held = 0.0, released = 0.0, refunded = 0.0;
    var count = 0;
    for (final p in payments) {
      if (heldStatuses.contains(p.status)) {
        held += charged(p);
        count++;
      } else if (releasedStatuses.contains(p.status)) {
        released += charged(p);
      } else if (refundedStatuses.contains(p.status)) {
        refunded += charged(p);
      }
    }
    return PaymentSummary(heldInEscrow: held, released: released, refunded: refunded, heldCount: count);
  }

  /// Label shown under a transaction amount.
  static String statusLabel(PaymentStatus s) => switch (s) {
        PaymentStatus.pending || PaymentStatus.processing => 'PENDING',
        PaymentStatus.escrowHeld => 'IN ESCROW',
        PaymentStatus.releasing => 'RELEASING',
        PaymentStatus.released => 'RELEASED',
        PaymentStatus.refundPending => 'REFUND PENDING',
        PaymentStatus.refunded => 'REFUNDED',
        PaymentStatus.settling => 'SETTLING',
        PaymentStatus.settled => 'SETTLED',
        PaymentStatus.failed => 'FAILED',
        PaymentStatus.abandoned => 'EXPIRED',
        PaymentStatus.requiresRefund => 'REFUND DUE',
        PaymentStatus.chargedBack => 'CHARGED BACK',
      };
}
