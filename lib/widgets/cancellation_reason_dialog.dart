import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shows a role-specific cancellation reason picker.
/// Returns the selected/typed reason string, or null if the user dismissed.
Future<String?> showCancellationReasonDialog(
  BuildContext context, {
  required bool isArtisan,
}) {
  final reasons = isArtisan
      ? ['Unavailable on the scheduled date', 'Location is too far', 'Job is outside my expertise', 'Other']
      : ['Found another artisan', 'Price is too high', 'No longer need the service', 'Other'];

  String selected = reasons.first;
  final otherCtrl = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Cancel Job',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please select a reason:',
                  style: TextStyle(
                    fontSize: 13,
                    color: ctx.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v ?? selected),
                  child: Column(
                    children: reasons
                        .map(
                          (r) => RadioListTile<String>(
                            value: r,
                            title: Text(
                              r,
                              style: const TextStyle(
                                fontSize: 14,
                                fontFamily: 'Inter',
                              ),
                            ),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        )
                        .toList(),
                  ),
                ),
                if (selected == 'Other') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: otherCtrl,
                    autofocus: true,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Describe your reason…',
                      hintStyle:
                          TextStyle(color: ctx.colors.textTertiary, fontFamily: 'Inter'),
                      filled: true,
                      fillColor: ctx.colors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: ctx.colors.borderLight),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Keep Job',
                style: TextStyle(fontFamily: 'Inter'),
              ),
            ),
            FilledButton(
              onPressed: () {
                final reason = selected == 'Other'
                    ? (otherCtrl.text.trim().isNotEmpty
                        ? otherCtrl.text.trim()
                        : 'Other')
                    : selected;
                Navigator.of(ctx).pop(reason);
              },
              style: FilledButton.styleFrom(
                backgroundColor: ctx.colors.error,
              ),
              child: const Text(
                'Confirm Cancel',
                style: TextStyle(fontFamily: 'Inter'),
              ),
            ),
          ],
        );
      },
    ),
  );
}
