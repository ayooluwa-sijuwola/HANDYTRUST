import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/emulator_config.dart';
import '../../core/services/media_service.dart';
import '../../models/media_ref.dart';
import '../../providers/media_provider.dart';
import '../components/ht_components.dart';
import '../settings/settings_screens.dart';
import '../theme/ht_theme.dart';

/// RumptyCloud staging media test (EMULATOR MODE ONLY; route registered only
/// when [EmulatorConfig.enabled]). Uploads only images generated here — never
/// a photo from the device — so no personal data can reach the bucket.
class MediaStagingScreen extends ConsumerStatefulWidget {
  const MediaStagingScreen({super.key});

  @override
  ConsumerState<MediaStagingScreen> createState() => _MediaStagingScreenState();
}

/// A synthetic PNG drawn on the device (gradient + "SYNTHETIC TEST" label).
/// PNGs produced this way carry no camera metadata or location.
Future<Uint8List> generateSyntheticPng({int size = 256, Random? random}) async {
  final rnd = random ?? Random();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  Color c() => Color.fromARGB(255, 40 + rnd.nextInt(180), 40 + rnd.nextInt(180), 40 + rnd.nextInt(180));
  final s = size.toDouble();
  canvas.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(s, s), [c(), c()]));
  final tp = TextPainter(
    text: TextSpan(text: 'SYNTHETIC TEST\n${DateTime.now().toUtc().toIso8601String()}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: s - 24);
  tp.paint(canvas, const Offset(12, 12));
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _MediaStagingScreenState extends ConsumerState<MediaStagingScreen> {
  String _kind = 'test-portfolio';
  Uint8List? _image;
  MediaUploadProgress? _progress;
  bool _busy = false;
  String? _lastResult;

  Future<void> _generate() async {
    final bytes = await generateSyntheticPng(size: _kind == 'test-thumb' ? 128 : 256);
    if (mounted) setState(() => _image = bytes);
  }

  Future<void> _upload() async {
    final bytes = _image;
    if (bytes == null || _busy) return;
    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final id = await ref.read(mediaServiceProvider).upload(
            kind: _kind,
            mimeType: 'image/png',
            bytes: bytes,
            onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          );
      if (!mounted) return;
      setState(() => _lastResult = 'Verified by the server: $id');
      htSnack(context, 'Upload verified');
    } on MediaFailure catch (e) {
      if (!mounted) return;
      setState(() => _lastResult = e.message);
      htSnack(context, e.message, error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  String _stageLabel(MediaUploadProgress p) => switch (p.stage) {
        MediaUploadStage.hashing => 'Preparing…',
        MediaUploadStage.requesting => 'Requesting upload…',
        MediaUploadStage.uploading => p.fraction == null || p.fraction == 0 ? 'Uploading…' : 'Uploading ${(p.fraction! * 100).round()}%…',
        MediaUploadStage.verifying => 'Server is verifying the stored file…',
        MediaUploadStage.done => 'Done',
      };

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final media = ref.watch(myMediaProvider);
    return SettingsPage(
      title: 'Media storage test',
      subtitle: 'Staging · synthetic images only',
      children: [
        HtInfoBanner(
          icon: Icons.science_outlined,
          tone: HtTone.warning,
          title: 'Emulator mode',
          text: 'Firebase: local emulators (${EmulatorConfig.projectId} at ${EmulatorConfig.host}). '
              'Files: RumptyCloud STAGING bucket. Only images generated on this screen are uploaded.',
        ),
        const SizedBox(height: 16),
        SettingsGroup(label: 'New upload', children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, children: [
                for (final k in MediaService.stagingKinds)
                  ChoiceChip(label: Text(k), selected: _kind == k, onSelected: _busy ? null : (_) => setState(() => _kind = k)),
              ]),
              const SizedBox(height: 12),
              if (_image != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_image!, height: 128, width: 128, fit: BoxFit.cover, semanticLabel: 'Synthetic test image'),
                ),
              if (_image != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${_image!.length} bytes · PNG', style: HtType.body(p.textMuted))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: HtSecondaryButton(label: _image == null ? 'Generate image' : 'New image', icon: Icons.auto_awesome_outlined, onPressed: _busy ? () {} : _generate)),
                const SizedBox(width: 10),
                Expanded(child: HtPrimaryButton(label: 'Upload', icon: Icons.cloud_upload_outlined, loading: _busy, onPressed: _image == null || _busy ? null : _upload)),
              ]),
              if (_progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress!.stage == MediaUploadStage.uploading ? (_progress!.fraction == 0 ? null : _progress!.fraction) : null),
                const SizedBox(height: 6),
                Text(_stageLabel(_progress!), style: HtType.body(p.textSecondary)),
              ],
              if (_lastResult != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_lastResult!, style: HtType.body(p.textPrimary))),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        SettingsGroup(label: 'My test media', children: [
          media.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: HtLoadingView()),
            error: (e, _) => HtErrorView(message: 'Could not load your media records.', onRetry: () => ref.invalidate(myMediaProvider)),
            data: (items) => items.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: HtEmptyView(icon: Icons.photo_library_outlined, title: 'No test media yet', message: 'Generate an image and upload it.'))
                : Column(children: [for (final m in items) _MediaTile(media: m)]),
          ),
        ]),
      ],
    );
  }
}

class _MediaTile extends ConsumerWidget {
  const _MediaTile({required this.media});
  final MediaRef media;

  HtTone get _tone => switch (media.status) {
        'verified' => HtTone.success,
        'rejected' || 'delete_failed' => HtTone.danger,
        'deleting' || 'pending' || 'uploading' || 'uploaded' || 'verifying' => HtTone.warning,
        _ => HtTone.neutral,
      };

  Future<void> _view(BuildContext context) async {
    await showDialog<void>(context: context, builder: (_) => _MediaViewer(mediaId: media.id));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await htConfirm(context, title: 'Delete this test image?', message: 'The file is removed from the staging bucket.', confirmLabel: 'Delete');
    if (!ok || !context.mounted) return;
    try {
      final r = await ref.read(mediaServiceProvider).delete(media.id);
      if (!context.mounted) return;
      htSnack(context, r.deleted ? 'Deleted from the bucket' : 'Deletion is pending (${r.status}); it will be retried', error: !r.deleted);
    } on MediaFailure catch (e) {
      if (context.mounted) htSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final kb = (media.sizeBytes / 1024).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${media.kind} · $kb KB${media.width != null ? ' · ${media.width}×${media.height}' : ''}', style: HtType.body(p.textPrimary)),
            const SizedBox(height: 4),
            Row(children: [
              HtStatusPill(label: media.status, tone: _tone),
              if (media.rejectedReason != null) ...[const SizedBox(width: 6), Flexible(child: Text(media.rejectedReason!, style: HtType.body(p.textMuted), overflow: TextOverflow.ellipsis))],
            ]),
          ]),
        ),
        if (media.isVerified) IconButton(tooltip: 'View', icon: const Icon(Icons.visibility_outlined), onPressed: () => _view(context)),
        if (!media.isGone) IconButton(tooltip: 'Delete', icon: Icon(Icons.delete_outline_rounded, color: p.danger), onPressed: () => _delete(context, ref)),
      ]),
    );
  }
}

/// Shows a verified image through a temporary URL; refreshes the URL when
/// it has expired or the image fails to load.
class _MediaViewer extends ConsumerWidget {
  const _MediaViewer({required this.mediaId});
  final String mediaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final url = ref.watch(mediaUrlProvider(mediaId));
    return AlertDialog(
      backgroundColor: p.surface,
      title: Text('Temporary view', style: HtType.cardTitle(p.textPrimary)),
      content: SizedBox(
        width: 280,
        child: url.when(
          loading: () => const SizedBox(height: 200, child: HtLoadingView(label: 'Requesting a temporary link…')),
          error: (e, _) => HtErrorView(message: e is MediaFailure ? e.message : 'Could not get a temporary link.', onRetry: () => ref.invalidate(mediaUrlProvider(mediaId))),
          data: (u) => Column(mainAxisSize: MainAxisSize.min, children: [
            Image.network(
              u.url,
              height: 220,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) => progress == null ? child : const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
              errorBuilder: (_, _, _) => HtErrorView(
                message: 'The image could not be loaded (the link may have expired).',
                onRetry: () async {
                  await ref.read(mediaServiceProvider).readUrl(mediaId, forceRefresh: true);
                  ref.invalidate(mediaUrlProvider(mediaId));
                },
              ),
            ),
            const SizedBox(height: 8),
            Text('Link expires at ${TimeOfDay.fromDateTime(u.expiresAt).format(context)} and is not stored.', style: HtType.body(p.textMuted)),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
