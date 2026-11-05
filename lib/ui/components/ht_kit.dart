import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/ht_theme.dart';
import 'ht_components.dart';

/// Stage 8.1 shared kit: functional versions of the components approved in
/// the previews (design/STAGE8_ARTISAN_REDESIGN_PREVIEW.md), used by the
/// artisan experience and available to the remaining role replacements.

/// Icon in a rounded, tone-tinted tile (list leading, status icons).
Widget htIconTile(BuildContext context, IconData icon, {HtTone tone = HtTone.accent, double size = 42}) {
  final p = context.ht;
  final (bg, fg) = switch (tone) {
    HtTone.success => (p.successSoft, p.success),
    HtTone.warning => (p.warningSoft, p.warning),
    HtTone.danger => (p.dangerSoft, p.danger),
    HtTone.neutral => (p.surfaceRaised, p.textSecondary),
    HtTone.accent => (p.accentSoft, p.accentSoftText),
  };
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.32)),
    child: Icon(icon, size: size * 0.48, color: fg),
  );
}

/// Key / value row.
Widget htKv(BuildContext context, String k, String v, {bool strong = false}) {
  final p = context.ht;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(k, style: HtType.small(p.textSecondary).copyWith(fontSize: 13))),
      const SizedBox(width: 12),
      Flexible(
        child: Text(v,
            textAlign: TextAlign.right,
            style: strong ? HtType.bodyStrong(p.textPrimary) : HtType.small(p.textPrimary).copyWith(fontSize: 13)),
      ),
    ]),
  );
}

/// Vertical event timeline: (title, subtitle, done).
class HtTimeline extends StatelessWidget {
  const HtTimeline({super.key, required this.entries});
  final List<(String, String, bool)> entries;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Column(children: [
      for (var i = 0; i < entries.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 22,
              child: Column(children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: entries[i].$3 ? (p.isDark ? p.accent : p.accentStrong) : p.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: entries[i].$3 ? Colors.transparent : p.textMuted, width: 2),
                  ),
                ),
                if (i < entries.length - 1) Expanded(child: Container(width: 2, color: p.border)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entries[i].$1, style: HtType.bodyStrong(entries[i].$3 ? p.textPrimary : p.textSecondary).copyWith(fontSize: 13.5)),
                  Text(entries[i].$2, style: HtType.small(p.textMuted).copyWith(fontSize: 11.5)),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// Danger-tone pill button for destructive actions.
class HtDangerButton extends StatelessWidget {
  const HtDangerButton({super.key, required this.label, required this.onPressed, this.icon, this.loading = false, this.height = 46});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final double height;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Material(
      color: p.dangerSoft,
      shape: StadiumBorder(side: BorderSide(color: p.danger.withValues(alpha: 0.4))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: loading ? null : onPressed,
        child: SizedBox(
          height: height,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (loading)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.danger))
            else ...[
              if (icon != null) ...[Icon(icon, size: 18, color: p.danger), const SizedBox(width: 8)],
              Flexible(child: Text(label, style: HtType.bodyStrong(p.danger).copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Pill search field.
class HtSearchField extends StatelessWidget {
  const HtSearchField({super.key, required this.controller, required this.hint, required this.onChanged});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5),
      decoration: htInputDecoration(context, hint: hint, prefix: Icon(Icons.search_rounded, size: 20, color: p.textMuted)).copyWith(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(HtRadius.pill), borderSide: BorderSide(color: p.isDark ? Colors.transparent : p.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(HtRadius.pill), borderSide: BorderSide(color: p.isDark ? Colors.transparent : p.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(HtRadius.pill), borderSide: BorderSide(color: p.accentStrong, width: 1.4)),
      ),
    );
  }
}

/// Square photo tile: network URL or local bytes, optional remove button.
class HtPhotoTile extends StatelessWidget {
  const HtPhotoTile({super.key, this.url, this.bytes, this.onRemove, this.onTap, this.height = 96, this.label});
  final String? url;
  final Uint8List? bytes;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  final double height;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final Widget image = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.cover)
        : url != null
            ? Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Center(child: Icon(Icons.broken_image_outlined, color: p.textMuted)))
            : Center(child: Icon(Icons.image_outlined, color: p.accentSoftText));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.tile), border: Border.all(color: p.border)),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          image,
          if (label != null)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(6)),
                child: Text(label!, style: HtType.small(Colors.white).copyWith(fontSize: 10.5)),
              ),
            ),
          if (onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: Semantics(
                button: true,
                label: 'Remove photo',
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Dashed-feel "add photo" tile.
class HtAddPhotoTile extends StatelessWidget {
  const HtAddPhotoTile({super.key, required this.onTap, this.height = 96, this.label = 'Add'});
  final VoidCallback? onTap;
  final double height;
  final String label;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final a = p.isDark ? p.accent : p.accentStrong;
    return Semantics(
      button: true,
      label: 'Add photo',
      child: InkWell(
        borderRadius: BorderRadius.circular(HtRadius.tile),
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(HtRadius.tile), border: Border.all(color: a, width: 1.4)),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_a_photo_outlined, color: a), Text(label, style: HtType.smallStrong(a))])),
        ),
      ),
    );
  }
}

/// Photo grid (3 per row) with an add tile while below [max].
class HtPhotoGrid extends StatelessWidget {
  const HtPhotoGrid({super.key, this.urls = const [], this.bytes = const [], this.onAdd, this.onRemoveUrl, this.onRemoveBytes, this.max = 5, this.tileHeight = 96});
  final List<String> urls;
  final List<Uint8List> bytes;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemoveUrl;
  final ValueChanged<int>? onRemoveBytes;
  final int max;
  final double tileHeight;
  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      for (var i = 0; i < urls.length; i++) HtPhotoTile(url: urls[i], height: tileHeight, onRemove: onRemoveUrl == null ? null : () => onRemoveUrl!(i)),
      for (var i = 0; i < bytes.length; i++) HtPhotoTile(bytes: bytes[i], height: tileHeight, onRemove: onRemoveBytes == null ? null : () => onRemoveBytes!(i)),
      if (onAdd != null && urls.length + bytes.length < max) HtAddPhotoTile(onTap: onAdd, height: tileHeight),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 3) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          for (var j = 0; j < 3; j++) ...[
            if (j > 0) const SizedBox(width: 8),
            Expanded(child: i + j < tiles.length ? tiles[i + j] : const SizedBox()),
          ],
        ]),
      ));
    }
    return Column(children: rows);
  }
}

/// Modal bottom sheet in the design language.
Future<T?> htShowSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  final p = context.ht;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: p.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HtRadius.card))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 22 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(top: false, child: builder(ctx)),
    ),
  );
}

/// Labelled switch with an explanation line.
class HtToggleRow extends StatelessWidget {
  const HtToggleRow({super.key, required this.title, required this.subtitle, required this.value, required this.onChanged, this.icon = Icons.bolt_rounded, this.busy = false});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Row(children: [
      htIconTile(context, icon, tone: value ? HtTone.success : HtTone.neutral, size: 40),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)),
          Text(subtitle, style: HtType.small(p.textSecondary)),
        ]),
      ),
      if (busy)
        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: p.accentStrong))
      else
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: p.isDark ? p.onPrimary : Colors.white,
          activeTrackColor: p.isDark ? p.accent : p.accentStrong,
        ),
    ]);
  }
}

/// Styled text input with a label above (forms).
class HtTextField extends StatelessWidget {
  const HtTextField({super.key, required this.label, required this.controller, this.hint, this.lines = 1, this.keyboard, this.validator, this.maxLength, this.trailingLabel, this.prefixText, this.onChanged});
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int lines;
  final TextInputType? keyboard;
  final FormFieldValidator<String>? validator;
  final int? maxLength;
  final String? trailingLabel;
  final String? prefixText;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      HtFieldLabel(label, trailing: trailingLabel),
      TextFormField(
        controller: controller,
        minLines: lines,
        maxLines: lines,
        keyboardType: keyboard,
        validator: validator,
        maxLength: maxLength,
        onChanged: onChanged,
        style: HtType.body(p.textPrimary),
        decoration: htInputDecoration(context, hint: hint).copyWith(prefixText: prefixText, counterText: ''),
      ),
    ]);
  }
}

/// Full-screen photo viewer (swipe between photos). Black backdrop in both
/// themes so photos display neutrally.
Future<void> showHtPhotoViewer(BuildContext context, List<String> urls, {int initial = 0, String? title}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _PhotoViewer(urls: urls, initial: initial, title: title),
  ));
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initial, this.title});
  final List<String> urls;
  final int initial;
  final String? title;
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _c = PageController(initialPage: widget.initial);
  late int _i = widget.initial;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          PageView.builder(
            controller: _c,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => InteractiveViewer(
              child: Center(
                child: Image.network(widget.urls[i], fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 12,
            child: HtIconCircle(icon: Icons.close_rounded, tooltip: 'Close', fill: Colors.white.withValues(alpha: 0.12), iconColor: Colors.white, onTap: () => Navigator.of(context).maybePop()),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.title != null) Text(widget.title!, style: HtType.cardTitle(Colors.white)),
              Text('${_i + 1} of ${widget.urls.length}', style: HtType.small(Colors.white70)),
            ]),
          ),
        ]),
      ),
    );
  }
}
