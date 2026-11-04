import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../core/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../theme/app_theme.dart';

class JobCompletionScreen extends ConsumerStatefulWidget {
  final String jobId;

  const JobCompletionScreen({super.key, required this.jobId});

  @override
  ConsumerState<JobCompletionScreen> createState() =>
      _JobCompletionScreenState();
}

class _JobCompletionScreenState extends ConsumerState<JobCompletionScreen> {
  // Photos taken on arrival, before work starts
  final List<Uint8List> _beforeImages = [];
  // Photos of the completed work
  final List<Uint8List> _afterImages = [];
  final _notesController = TextEditingController();
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Submit Completion')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoCard(),
            const SizedBox(height: 24),
            // ── Before photos ──────────────────────────────────────
            const Text(
              'Arrival Photos (Before Work) *',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Take at least 1 photo when you arrive, before starting work.',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 12),
            _imageGrid(_beforeImages, onAdd: () => _pickImage(_beforeImages)),
            const SizedBox(height: 24),
            // ── After photos ───────────────────────────────────────
            const Text(
              'Completion Photos (After Work) *',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Upload at least 1 photo of the completed work.',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 12),
            _imageGrid(_afterImages, onAdd: () => _pickImage(_afterImages)),
            const SizedBox(height: 24),
            const Text(
              'Notes (optional)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Describe what was done…',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color: context.colors.error, fontFamily: 'Inter')),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _uploading ? null : _submit,
              child: _uploading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit for Review'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 18, color: context.colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Upload arrival photos (before work) and completion photos (after work). '
                'The customer then has 14 days to confirm or raise a dispute.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.primary,
                  fontFamily: 'Inter',
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _imageGrid(List<Uint8List> images, {required VoidCallback onAdd}) =>
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: images.length + 1,
        itemBuilder: (ctx, i) {
          if (i == images.length) {
            return GestureDetector(
              onTap: onAdd,
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: context.colors.border,
                      style: BorderStyle.solid),
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
                child: Image.memory(images[i], fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => images.removeAt(i)),
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

  Future<void> _pickImage(List<Uint8List> target) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final raw = await picked.readAsBytes();
    Uint8List bytes = raw;
    if (raw.lengthInBytes > 500 * 1024) {
      final compressed =
          await FlutterImageCompress.compressWithList(raw, quality: 70);
      bytes = Uint8List.fromList(compressed);
    }
    setState(() => target.add(bytes));
  }

  Future<void> _submit() async {
    if (_beforeImages.isEmpty) {
      setState(
          () => _error = 'Please add at least one arrival photo (before work).');
      return;
    }
    if (_afterImages.isEmpty) {
      setState(
          () => _error = 'Please add at least one completion photo (after work).');
      return;
    }
    final userId = ref.read(authStateChangesProvider).value?.uid ?? '';
    if (userId.isEmpty) {
      setState(() => _error = 'Not signed in.');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final storage = StorageService();

      // Upload before photos
      final beforeUrls = <String>[];
      for (int i = 0; i < _beforeImages.length; i++) {
        final url = await storage.uploadJobImageBytes(
          jobId: widget.jobId,
          userId: userId,
          index: i,
          bytes: _beforeImages[i],
          subfolder: 'before',
        );
        beforeUrls.add(url);
      }

      // Upload after photos
      final afterUrls = <String>[];
      for (int i = 0; i < _afterImages.length; i++) {
        final url = await storage.uploadJobImageBytes(
          jobId: widget.jobId,
          userId: userId,
          index: i,
          bytes: _afterImages[i],
          subfolder: 'after',
        );
        afterUrls.add(url);
      }

      await ref.read(escrowNotifierProvider.notifier).submitCompletion(
            widget.jobId,
            imageUrls: afterUrls,
            beforePhotoUrls: beforeUrls,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      // Prefer popping back to the job detail screen that pushed this one
      // (from job_detail_screen.dart or all_jobs_screen.dart, both use
      // context.push) — preserves its state and the rest of the
      // navigation stack, so Android system back keeps working correctly.
      // go() is kept only as a fallback if there's nothing to pop.
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/job/${widget.jobId}');
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}
