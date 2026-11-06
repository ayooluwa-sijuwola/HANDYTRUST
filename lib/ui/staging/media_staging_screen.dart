import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/emulator_config.dart';
import '../../core/services/media_service.dart';
import '../../models/media_ref.dart';
import '../../providers/media_provider.dart';
import '../components/ht_components.dart';
import '../settings/settings_screens.dart';
import '../theme/ht_theme.dart';

/// RumptyCloud staging media test (EMULATOR MODE ONLY; the route exists only
/// when [EmulatorConfig.enabled], which is never true in release builds).
/// Uploads only images generated here — never a photo from the device — so
/// no personal data can reach the bucket.
class MediaStagingScreen extends ConsumerStatefulWidget {
  const MediaStagingScreen({super.key});

  @override
  ConsumerState<MediaStagingScreen> createState() => _MediaStagingScreenState();
}

/// Image formats the staging backend accepts.
enum SyntheticFormat {
  jpeg('JPEG', 'image/jpeg'),
  png('PNG', 'image/png'),
  webp('WebP', 'image/webp');

  const SyntheticFormat(this.label, this.mimeType);
  final String label;
  final String mimeType;
}

/// A synthetic PNG drawn on the device (gradient + "SYNTHETIC TEST" label).
/// Images produced this way carry no camera metadata or location.
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

/// A synthetic image in [format]: drawn as PNG, then (for JPEG/WebP)
/// re-encoded on the device without any metadata.
Future<Uint8List> generateSyntheticImage(SyntheticFormat format, {int size = 256}) async {
  final png = await generateSyntheticPng(size: size);
  return switch (format) {
    SyntheticFormat.png => png,
    SyntheticFormat.jpeg => FlutterImageCompress.compressWithList(png, format: CompressFormat.jpeg, quality: 90, keepExif: false),
    SyntheticFormat.webp => FlutterImageCompress.compressWithList(png, format: CompressFormat.webp, quality: 90, keepExif: false),
  };
}

class _MediaStagingScreenState extends ConsumerState<MediaStagingScreen> {
  String _kind = 'test-portfolio';
  SyntheticFormat _format = SyntheticFormat.jpeg;
  Uint8List? _image;
  SyntheticFormat? _imageFormat;
  MediaUploadProgress? _progress;
  bool _busy = false;
  String? _lastResult;
  bool _lastOk = false;

  Future<void> _generate() async {
    if (_busy) return;
    try {
      final bytes = await generateSyntheticImage(_format, size: _kind == 'test-thumb' ? 128 : 256);
      if (mounted) {
        setState(() {
          _image = bytes;
          _imageFormat = _format;
          _lastResult = null;
        });
      }
    } catch (e) {
      if (mounted) htSnack(context, 'Could not create a ${_format.label} image on this device.', error: true);
    }
  }

  Future<void> _upload() async {
    final bytes = _image;
    final format = _imageFormat;
    if (bytes == null || format == null || _busy) return;
    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final r = await ref.read(mediaServiceProvider).upload(
            kind: _kind,
            mimeType: format.mimeType,
            bytes: bytes,
            onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          );
      if (!mounted) return;
      final path = r.mode == 'presigned' ? 'directly to RumptyCloud (presigned link)' : 'through the Firebase function';
      setState(() {
        _lastOk = true;
        _lastResult = 'Stored and verified by the server.\nUploaded $path.\nMedia id: ${r.mediaId}';
      });
      htSnack(context, '${format.label} upload verified');
    } on MediaFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _lastOk = false;
        _lastResult = e.message;
      });
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
        MediaUploadStage.requesting => 'Asking the server for an upload…',
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
              Text('Media type', style: HtType.body(p.textSecondary)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final k in MediaService.stagingKinds)
                  HtChip(label: k, selected: _kind == k, onTap: () => _busy ? null : setState(() => _kind = k)),
              ]),
              const SizedBox(height: 12),
              Text('Image format', style: HtType.body(p.textSecondary)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final f in SyntheticFormat.values)
                  HtChip(label: f.label, selected: _format == f, onTap: () => _busy ? null : setState(() => _format = f)),
              ]),
              const SizedBox(height: 12),
              if (_image != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_image!, height: 128, width: 128, fit: BoxFit.cover, semanticLabel: 'Synthetic test image'),
                ),
              if (_image != null)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('${_imageFormat!.label} · ${_image!.length} bytes', style: HtType.body(p.textMuted))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: HtSecondaryButton(label: _image == null ? 'Create image' : 'New image', icon: Icons.auto_awesome_outlined, onPressed: _generate)),
                const SizedBox(width: 10),
                Expanded(child: HtPrimaryButton(label: 'Upload', icon: Icons.cloud_upload_outlined, loading: _busy, onPressed: _image == null || _busy ? null : _upload)),
              ]),
              if (_progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress!.stage == MediaUploadStage.uploading && (_progress!.fraction ?? 0) > 0 ? _progress!.fraction : null),
                const SizedBox(height: 6),
                Text(_stageLabel(_progress!), style: HtType.body(p.textSecondary)),
              ],
              if (_lastResult != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: HtInfoBanner(icon: _lastOk ? Icons.verified_outlined : Icons.error_outline, tone: _lastOk ? HtTone.success : HtTone.danger, text: _lastResult!),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        SettingsGroup(label: 'My test media', children: [
          media.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: HtLoadingView()),
            error: (e, _) => HtErrorView(message: 'Could not load your media records.', onRetry: () => ref.invalidate(myMediaProvider)),
            data: (items) => items.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: HtEmptyView(icon: Icons.photo_library_outlined, title: 'No test media yet', message: 'Create a test image and upload it.'))
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
    await showDialog<void>(context: context, builder: (_) => _MediaViewer(media: media));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await htConfirm(context, title: 'Delete this test image?', message: 'The file is removed from the staging bucket.', confirmLabel: 'Delete');
    if (!ok || !context.mounted) return;
    final service = ref.read(mediaServiceProvider);
    try {
      final r = await service.delete(media.id);
      if (!context.mounted) return;
      if (!r.deleted) {
        htSnack(context, 'Deletion is pending (${r.status}); the server will retry it.', error: true);
        return;
      }
      // Ask the server for the image again: it must refuse.
      try {
        await service.readUrl(media.id, forceRefresh: true);
        if (context.mounted) htSnack(context, 'Deleted, but the server still offered a link — please report this.', error: true);
      } on MediaFailure {
        if (context.mounted) htSnack(context, 'Deleted from the bucket and confirmed: no longer available.');
      }
    } on MediaFailure catch (e) {
      if (context.mounted) htSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final kb = (media.sizeBytes / 1024).toStringAsFixed(1);
    final type = media.mimeType.replaceFirst('image/', '').toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$type · ${media.kind} · $kb KB${media.width != null ? ' · ${media.width}×${media.height}' : ''}', style: HtType.body(p.textPrimary)),
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

/// Shows a verified image through a temporary URL. "Refresh link" fetches a
/// new URL from the server and loads the image again.
class _MediaViewer extends ConsumerStatefulWidget {
  const _MediaViewer({required this.media});
  final MediaRef media;

  @override
  ConsumerState<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends ConsumerState<_MediaViewer> {
  Future<MediaUrl>? _url;
  int _loads = 0;

  @override
  void initState() {
    super.initState();
    _load(force: false);
  }

  void _load({required bool force}) {
    setState(() {
      _loads++;
      _url = ref.read(mediaServiceProvider).readUrl(widget.media.id, forceRefresh: force);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return AlertDialog(
      backgroundColor: p.surface,
      title: Text('Private image (temporary link)', style: HtType.cardTitle(p.textPrimary)),
      content: SizedBox(
        width: 300,
        child: FutureBuilder<MediaUrl>(
          future: _url,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 220, child: HtLoadingView(label: 'Requesting a temporary link…'));
            }
            if (snap.hasError) {
              final e = snap.error;
              return HtErrorView(message: e is MediaFailure ? e.message : 'Could not get a temporary link.', onRetry: () => _load(force: true));
            }
            final u = snap.data!;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Image.network(
                u.url,
                key: ValueKey('${widget.media.id}-$_loads'),
                height: 220,
                fit: BoxFit.contain,
                semanticLabel: 'Private test image from RumptyCloud',
                loadingBuilder: (_, child, progress) => progress == null ? child : const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
                errorBuilder: (_, _, _) => HtErrorView(message: 'The image could not be loaded (the link may have expired).', onRetry: () => _load(force: true)),
              ),
              const SizedBox(height: 8),
              Text('Loaded ${_loads == 1 ? 'once' : '$_loads times'} · link expires ${TimeOfDay.fromDateTime(u.expiresAt).format(context)} · never stored',
                  style: HtType.body(p.textMuted), textAlign: TextAlign.center),
            ]);
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => _load(force: true), child: const Text('Refresh link')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
