import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Stage 4 admin decision dialogs. They only COLLECT a decision; the money
/// rules (amount bounds, idempotency, freezes, audit) are enforced by the
/// Cloud Functions the caller invokes, never here.

/// An admin's settlement decision for a funded job. Amounts in naira; only
/// set for 'split'. outcome: 'release' | 'full_refund' | 'split' | 'decline'.
class SettlementDecision {
  final String outcome;
  final String reason;
  final double? artisanAmount;
  final double? refundAmount;
  const SettlementDecision({required this.outcome, required this.reason, this.artisanAmount, this.refundAmount});
}

const int _minReasonLength = 10;

String _ngn(num v) => '₦${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

/// Turns a Cloud Functions error into a short admin-readable message.
String adminFinanceErrorMessage(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? e.code;
  return e.toString();
}

Future<SettlementDecision?> showSettlementDialog(
  BuildContext context, {
  required String title,
  required String jobId,
  bool allowDecline = false,
  bool allowRelease = true,
  String initialOutcome = 'release',
}) async {
  // What the customer paid and what the artisan was promised — read for
  // display only (admins can read payments; the server re-derives both).
  final pays = await FirebaseFirestore.instance.collection('payments').where('jobId', isEqualTo: jobId).get();
  final held = pays.docs.map((d) => d.data()).where((p) => p['status'] == 'escrowHeld').toList();
  final pay = held.isNotEmpty ? held.first : null;
  final service = (pay?['serviceAmount'] as num?) ?? (pay?['amount'] as num?);
  final total = (pay?['totalCharged'] as num?) ?? service;
  if (!context.mounted) return null;

  String outcome = initialOutcome;
  final reasonCtrl = TextEditingController();
  final artisanCtrl = TextEditingController();
  final refundCtrl = TextEditingController();
  String? error;

  return showDialog<SettlementDecision>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Widget option(String value, String label, String help) => RadioListTile<String>(
              value: value,
              groupValue: outcome,
              onChanged: (v) => setState(() => outcome = v!),
              title: Text(label, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
              subtitle: Text(help, style: const TextStyle(fontFamily: 'Inter', fontSize: 12)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            );
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pay == null)
                  Text('No funds are currently held in escrow for this job.',
                      style: TextStyle(color: ctx.colors.error, fontFamily: 'Inter'))
                else
                  Text('Held in escrow: ${_ngn(total!)} (artisan price ${_ngn(service!)}, platform fee ${_ngn(total - service)})',
                      style: TextStyle(fontSize: 13, color: ctx.colors.textSecondary, fontFamily: 'Inter')),
                const SizedBox(height: 8),
                if (allowDecline)
                  option('decline', 'Decline request', 'The job continues; escrow is untouched.'),
                if (allowRelease)
                  option('release', 'Release to artisan', 'Artisan receives the full agreed price.'),
                option('full_refund', 'Full refund to customer', 'Customer gets back everything they paid, including the platform fee.'),
                option('split', 'Split settlement', 'Part to the artisan, part refunded; any remainder is retained and recorded.'),
                if (outcome == 'split') ...[
                  TextField(
                    controller: artisanCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Artisan receives (₦)', helperText: service != null ? 'At most ${_ngn(service)}' : null),
                  ),
                  TextField(
                    controller: refundCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Customer refund (₦)'),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason (required — recorded in the audit log and shown to both parties)',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: ctx.colors.error, fontFamily: 'Inter', fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: pay == null && outcome != 'decline'
                  ? null
                  : () {
                      final reason = reasonCtrl.text.trim();
                      if (reason.length < _minReasonLength) {
                        setState(() => error = 'Please give a reason of at least $_minReasonLength characters.');
                        return;
                      }
                      double? a;
                      double? r;
                      if (outcome == 'split') {
                        a = double.tryParse(artisanCtrl.text.trim());
                        r = double.tryParse(refundCtrl.text.trim());
                        if (a == null || r == null || a <= 0 || r <= 0) {
                          setState(() => error = 'Enter both split amounts.');
                          return;
                        }
                      }
                      Navigator.of(ctx).pop(SettlementDecision(outcome: outcome, reason: reason, artisanAmount: a, refundAmount: r));
                    },
              child: const Text('Confirm decision'),
            ),
          ],
        );
      },
    ),
  );
}

/// Asks for a mandatory reason before a sensitive admin action.
Future<String?> showAdminReasonDialog(BuildContext context, {required String title, required String message, String confirmLabel = 'Confirm'}) {
  final ctrl = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
            const SizedBox(height: 8),
            TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason (required)')),
            if (error != null) Text(error!, style: TextStyle(color: ctx.colors.error, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final reason = ctrl.text.trim();
              if (reason.length < _minReasonLength) {
                setState(() => error = 'Please give a reason of at least $_minReasonLength characters.');
                return;
              }
              Navigator.of(ctx).pop(reason);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

/// Policy D9 suspension types. fraud / safety / security freeze payouts for
/// the artisan's jobs (server-enforced); administrative / verification do not.
const suspensionTypes = <String, String>{
  'administrative': 'Administrative — existing jobs may be completed',
  'verification': 'Verification — existing jobs may be completed',
  'fraud': 'Fraud — freezes all payouts pending review',
  'safety': 'Safety — freezes all payouts pending review',
  'security': 'Security — freezes all payouts pending review',
};

Future<String?> showSuspensionTypeDialog(BuildContext context, {required String userName}) {
  String selected = 'administrative';
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Suspend Account?', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$userName will be blocked from new marketplace activity. Choose the suspension type:',
                style: const TextStyle(fontFamily: 'Inter')),
            for (final e in suspensionTypes.entries)
              RadioListTile<String>(
                value: e.key,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v!),
                title: Text(e.value, style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.colors.error),
            onPressed: () => Navigator.of(ctx).pop(selected),
            child: const Text('Suspend'),
          ),
        ],
      ),
    ),
  );
}
