import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/storage_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/escrow_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_format.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';
import 'work_ui.dart';

/// AR-04 Submit work (`/job/:jobId/submit`): before + after photos and
/// notes, then `submitCompletion` (starts the 14-day review). Same rules
/// as the previous screen: at least one photo of each.
class SubmitWorkScreen extends ConsumerStatefulWidget {
  const SubmitWorkScreen({super.key, required this.jobId});
  final String jobId;
  @override
  ConsumerState<SubmitWorkScreen> createState() => _SubmitWorkScreenState();
}

class _SubmitWorkScreenState extends ConsumerState<SubmitWorkScreen> {
  final List<Uint8List> _before = [];
  final List<Uint8List> _after = [];
  final _notes = TextEditingController();
  bool _uploading = false;

  static const _max = 5;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _add(List<Uint8List> target) async {
    final b = await pickWorkPhoto();
    if (b != null && mounted) setState(() => target.add(b));
  }

  Future<void> _submit() async {
    if (_before.isEmpty) {
      htSnack(context, 'Add at least one arrival photo (before work).', error: true);
      return;
    }
    if (_after.isEmpty) {
      htSnack(context, 'Add at least one completion photo (after work).', error: true);
      return;
    }
    final uid = ref.read(authStateChangesProvider).asData?.value?.uid ?? '';
    if (uid.isEmpty) {
      htSnack(context, 'You’re signed out. Sign in and try again.', error: true);
      return;
    }
    setState(() => _uploading = true);
    try {
      final storage = StorageService();
      final beforeUrls = <String>[];
      for (var i = 0; i < _before.length; i++) {
        beforeUrls.add(await storage.uploadJobImageBytes(jobId: widget.jobId, userId: uid, index: i, bytes: _before[i], subfolder: 'before'));
      }
      final afterUrls = <String>[];
      for (var i = 0; i < _after.length; i++) {
        afterUrls.add(await storage.uploadJobImageBytes(jobId: widget.jobId, userId: uid, index: i, bytes: _after[i], subfolder: 'after'));
      }
      await ref.read(escrowNotifierProvider.notifier).submitCompletion(
            widget.jobId,
            imageUrls: afterUrls,
            beforePhotoUrls: beforeUrls,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      // The notifier stores failures instead of throwing — never report a
      // submission that didn't happen.
      if (ref.read(escrowNotifierProvider).hasError) {
        htSnack(context, 'Could not submit the work. Please try again.', error: true);
        return;
      }
      htSnack(context, 'Work submitted. The customer has 14 days to review.');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/job/${widget.jobId}');
      }
    } catch (e) {
      if (mounted) htSnack(context, 'Upload failed: ${e.toString().replaceFirst('Exception: ', '')}', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final job = ref.watch(jobStreamProvider(widget.jobId)).asData?.value;
    Widget check(String t, String s, bool ok) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: ok ? p.success : p.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(t, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5))),
            Text(s, style: HtType.smallStrong(p.textSecondary)),
          ]),
        );
    return ArtisanPage(
      title: job?.reworkCount == null || job!.reworkCount == 0 ? 'Submit work' : 'Resubmit work',
      sub: job == null ? null : '${workTitle(job)} · #${HtFormat.bookingRef(job.id)}',
      bottomBar: ProActionBar(label: 'Submit for review', loading: _uploading, onPressed: _uploading ? null : _submit),
      children: [
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            check('Arrival photos (before work)', '${_before.length} of $_max', _before.isNotEmpty),
            check('Completion photos (after work)', '${_after.length} of $_max', _after.isNotEmpty),
            check('Notes', _notes.text.trim().isEmpty ? 'Optional' : 'Added', _notes.text.trim().isNotEmpty),
          ]),
        ),
        const ProSection('Before photos'),
        Text('Take at least one photo when you arrive, before starting work.', style: HtType.small(p.textSecondary)),
        const SizedBox(height: 10),
        HtPhotoGrid(bytes: _before, max: _max, onAdd: _uploading ? null : () => _add(_before), onRemoveBytes: _uploading ? null : (i) => setState(() => _before.removeAt(i))),
        const ProSection('After photos'),
        Text('Upload at least one photo of the completed work.', style: HtType.small(p.textSecondary)),
        const SizedBox(height: 10),
        HtPhotoGrid(bytes: _after, max: _max, onAdd: _uploading ? null : () => _add(_after), onRemoveBytes: _uploading ? null : (i) => setState(() => _after.removeAt(i))),
        HtTextField(label: 'What was done (optional)', controller: _notes, hint: 'Describe what was done…', lines: 3, maxLength: 1000, onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        const HtInfoBanner(icon: Icons.schedule_rounded, title: '14-day review', text: 'The customer has 14 days to approve or raise a dispute. Payment releases automatically when the period ends.'),
        const SizedBox(height: 10),
        const HtInfoBanner(icon: Icons.privacy_tip_outlined, tone: HtTone.neutral, text: 'Location data is removed from photos before upload.'),
      ],
    );
  }
}
