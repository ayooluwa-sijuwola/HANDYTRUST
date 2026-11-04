import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../core/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dispute_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../theme/app_theme.dart';

class DisputeScreen extends ConsumerStatefulWidget {
  final String jobId;

  const DisputeScreen({super.key, required this.jobId});

  @override
  ConsumerState<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends ConsumerState<DisputeScreen> {
  final _reasonController = TextEditingController();
  String _selectedReason = 'Work not completed';
  bool _submitting = false;
  String? _error;
  final List<Uint8List> _evidenceImages = [];

  static const _reasons = [
    'Work not completed',
    'Work quality is poor',
    'Artisan is unresponsive',
    'Wrong service delivered',
    'Other',
  ];

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(jobStreamProvider(widget.jobId));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Raise Dispute')),
      body: jobAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (job) {
          if (job == null) return const Center(child: Text('Job not found'));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _warningCard(),
                const SizedBox(height: 24),
                const Text('Reason for Dispute',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    )),
                const SizedBox(height: 10),
                ..._reasons.map((r) => _reasonTile(r)),
                const SizedBox(height: 20),
                const Text('Additional Details',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: _reasonController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText:
                        'Describe the issue in detail. More evidence helps resolve faster.',
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Evidence Photos (optional)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    )),
                const SizedBox(height: 8),
                _evidenceGrid(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: context.colors.error, fontFamily: 'Inter')),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _submitting
                      ? null
                      : () => _submit(job.artisanId, job.customerId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.error,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit Dispute'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _warningCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.errorSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.error.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: context.colors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Raising a dispute will freeze the escrow. Our team will review evidence from both parties within 48 hours.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.error.withValues(alpha: 0.85),
                  fontFamily: 'Inter',
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _reasonTile(String reason) => GestureDetector(
        onTap: () => setState(() => _selectedReason = reason),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _selectedReason == reason
                ? context.colors.errorSurface
                : context.colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _selectedReason == reason
                  ? context.colors.error
                  : context.colors.borderLight,
              width: _selectedReason == reason ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _selectedReason == reason
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 18,
                color: _selectedReason == reason
                    ? context.colors.error
                    : context.colors.textTertiary,
              ),
              const SizedBox(width: 10),
              Text(
                reason,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: _selectedReason == reason
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: context.colors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      );

  Widget _evidenceGrid() => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _evidenceImages.length + 1,
        itemBuilder: (ctx, i) {
          if (i == _evidenceImages.length) {
            return GestureDetector(
              onTap: _pickEvidence,
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.colors.border),
                ),
                child: Center(
                  child: Icon(Icons.add_photo_alternate_outlined,
                      color: context.colors.textTertiary, size: 28),
                ),
              ),
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_evidenceImages[i], fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => _evidenceImages.removeAt(i)),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: context.colors.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      );

  Future<void> _pickEvidence() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final raw = await picked.readAsBytes();
    Uint8List bytes = raw;
    if (raw.lengthInBytes > 500 * 1024) {
      final compressed = await FlutterImageCompress.compressWithList(raw, quality: 70);
      bytes = Uint8List.fromList(compressed);
    }
    setState(() => _evidenceImages.add(bytes));
  }

  Future<void> _submit(String artisanId, String customerId) async {
    if (artisanId.isEmpty) {
      setState(() => _error = 'Cannot raise a dispute before an artisan is assigned.');
      return;
    }
    final uid = ref.read(authStateChangesProvider).value?.uid ?? '';
    if (uid.isEmpty) {
      setState(() => _error = 'Not signed in.');
      return;
    }
    final detail = _reasonController.text.trim();
    final fullReason = detail.isEmpty
        ? _selectedReason
        : '$_selectedReason: $detail';

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final disputeService = ref.read(disputeServiceProvider);
      final disputeId = disputeService.newDisputeId();

      final storage = StorageService();
      final evidenceUrls = <String>[];
      for (int i = 0; i < _evidenceImages.length; i++) {
        final url = await storage.uploadDisputeEvidence(
          disputeId: disputeId,
          userId: uid,
          index: i,
          bytes: _evidenceImages[i],
        );
        evidenceUrls.add(url);
      }

      // Stage 5 (D3): either party may raise; always against the other.
      final raisedByCustomer = uid == customerId;
      await disputeService.raiseDispute(
        disputeId: disputeId,
        jobId: widget.jobId,
        raisedBy: uid,
        againstUserId: raisedByCustomer ? artisanId : customerId,
        raisedByCustomer: raisedByCustomer,
        reason: fullReason,
        evidenceImageUrls: evidenceUrls,
      );

      if (mounted) {
        // Prefer popping back to the job detail screen that pushed this
        // one — preserves its existing state and the rest of the
        // navigation stack beneath it (Android system back then still
        // walks back through wherever the user actually came from, not
        // just "/job/:id"). go() is kept only as a fallback for the
        // unlikely case this screen was entered with nothing to pop
        // (e.g. a future deep link).
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/job/${widget.jobId}');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Dispute submitted. Our team will review within 48 hours.'),
            backgroundColor: context.colors.warning,
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
