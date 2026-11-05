import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/service_categories.dart';
import '../../../core/services/portfolio_service.dart';
import '../../../models/portfolio_project_model.dart';
import '../../../providers/portfolio_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';

Future<Uint8List?> _pickPortfolioPhoto() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  if (bytes.lengthInBytes <= 800 * 1024) return bytes;
  return FlutterImageCompress.compressWithList(bytes, quality: 75, format: CompressFormat.jpeg);
}

/// AR-08 Portfolio (`/portfolio`): projects and profile photos.
class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});
  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  int _tab = 0;
  bool _busy = false;

  Future<void> _addPhoto(String uid) async {
    final bytes = await _pickPortfolioPhoto();
    if (bytes == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(portfolioServiceProvider).addImage(artisanId: uid, bytes: bytes);
    } catch (e) {
      if (mounted) htSnack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(String uid, String url) async {
    final ok = await htConfirm(context, title: 'Remove this photo?', message: 'It will no longer appear on your profile.', confirmLabel: 'Remove');
    if (!ok || !mounted) return;
    try {
      await ref.read(portfolioServiceProvider).removeImage(artisanId: uid, url: url);
    } catch (_) {
      if (mounted) htSnack(context, 'Could not remove the photo. Please try again.', error: true);
    }
  }

  Future<void> _reorder(String uid, List<String> urls, int oldIndex, int newIndex) async {
    final updated = List<String>.from(urls);
    if (newIndex > oldIndex) newIndex -= 1;
    updated.insert(newIndex, updated.removeAt(oldIndex));
    try {
      await ref.read(portfolioServiceProvider).reorder(artisanId: uid, orderedUrls: updated);
    } catch (_) {
      if (mounted) htSnack(context, 'Could not reorder photos. Please try again.', error: true);
    }
  }

  Future<void> _deleteProject(PortfolioProjectModel project) async {
    final ok = await htConfirm(context, title: 'Delete “${project.title}”?', message: 'The project and its photos are removed from your portfolio.', confirmLabel: 'Delete project');
    if (!ok || !mounted) return;
    try {
      await ref.read(portfolioServiceProvider).deleteProject(project.id);
      if (mounted) htSnack(context, 'Project deleted.');
    } catch (_) {
      if (mounted) htSnack(context, 'Could not delete the project. Please try again.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final ctx = ref.watch(artisanContextProvider).asData?.value;
    if (ctx == null) return const ArtisanPage(title: 'Portfolio', children: [SizedBox(height: 80), HtLoadingView()]);
    final projectsAsync = ref.watch(portfolioProjectsProvider(ctx.uid));
    final views = ref.watch(portfolioViewCountProvider(ctx.uid)).asData?.value;
    final photos = ctx.artisan?.portfolioImageUrls ?? const <String>[];
    final projects = projectsAsync.asData?.value ?? const <PortfolioProjectModel>[];

    return ArtisanPage(
      title: 'Portfolio',
      sub: [ '${projects.length} ${projects.length == 1 ? 'project' : 'projects'}', if (views != null) '$views views'].join(' · '),
      bottomBar: _tab == 0
          ? ProActionBar(label: 'Add project', onPressed: () => context.push('/portfolio-project', extra: {'artisanId': ctx.uid}))
          : ProActionBar(
              label: photos.length >= PortfolioService.maxImages ? 'Photo limit reached (${PortfolioService.maxImages})' : 'Add photo',
              loading: _busy,
              onPressed: _busy || photos.length >= PortfolioService.maxImages ? null : () => _addPhoto(ctx.uid),
            ),
      children: [
        ProSegments(labels: const ['Projects', 'Photos'], selected: _tab, counts: [projects.length, photos.length], onSelected: (i) => setState(() => _tab = i)),
        const SizedBox(height: 12),
        if (_tab == 0)
          projectsAsync.when(
            loading: () => const HtLoadingView(label: 'Loading projects…'),
            error: (e, _) => ArtisanState.error(e, onRetry: () => ref.invalidate(portfolioProjectsProvider(ctx.uid))),
            data: (list) => list.isEmpty
                ? const HtCard(child: HtEmptyView(icon: Icons.photo_library_outlined, title: 'No projects yet', message: 'Show customers your best work: add a project with photos.'))
                : Column(children: [
                    for (final pr in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: p.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HtRadius.inner), side: BorderSide(color: p.border)),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => context.push('/portfolio-project', extra: {'artisanId': ctx.uid, 'existing': pr}),
                            child: Row(children: [
                              SizedBox(
                                width: 110,
                                height: 86,
                                child: pr.imageUrls.isEmpty
                                    ? ColoredBox(color: p.surfaceRaised, child: Icon(Icons.image_outlined, color: p.textMuted))
                                    : GestureDetector(onTap: () => showHtPhotoViewer(context, pr.imageUrls, title: pr.title), child: Image.network(pr.imageUrls.first, fit: BoxFit.cover)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(pr.title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text('${pr.category} · ${pr.imageUrls.length} ${pr.imageUrls.length == 1 ? 'photo' : 'photos'}', style: HtType.small(p.textSecondary)),
                                ]),
                              ),
                              IconButton(tooltip: 'Delete project', onPressed: () => _deleteProject(pr), icon: Icon(Icons.delete_outline_rounded, color: p.textMuted)),
                            ]),
                          ),
                        ),
                      ),
                  ]),
          )
        else if (photos.isEmpty)
          const HtCard(child: HtEmptyView(icon: Icons.add_photo_alternate_outlined, title: 'No photos yet', message: 'Photos appear on your public profile. Drag to reorder.'))
        else ...[
          Text('Drag to reorder. Photos appear on your public profile.', style: HtType.small(p.textSecondary)),
          const SizedBox(height: 10),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorder: (o, n) => _reorder(ctx.uid, photos, o, n),
            children: [
              for (var i = 0; i < photos.length; i++)
                Padding(
                  key: ValueKey(photos[i]),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: HtCard(
                    radius: HtRadius.tile + 2,
                    padding: const EdgeInsets.all(8),
                    child: Row(children: [
                      SizedBox(width: 90, child: HtPhotoTile(url: photos[i], height: 64, onTap: () => showHtPhotoViewer(context, photos, initial: i, title: 'Portfolio'))),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Photo ${i + 1}', style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5))),
                      IconButton(tooltip: 'Remove photo', onPressed: () => _removePhoto(ctx.uid, photos[i]), icon: Icon(Icons.delete_outline_rounded, color: p.textMuted)),
                      Icon(Icons.drag_indicator_rounded, color: p.textMuted),
                    ]),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// AR-09 Portfolio project editor (`/portfolio-project`, `extra` carries
/// artisanId and optionally the project being edited).
class PortfolioProjectScreen extends ConsumerStatefulWidget {
  const PortfolioProjectScreen({super.key, required this.artisanId, this.existing});
  final String artisanId;
  final PortfolioProjectModel? existing;
  @override
  ConsumerState<PortfolioProjectScreen> createState() => _PortfolioProjectScreenState();
}

class _PortfolioProjectScreenState extends ConsumerState<PortfolioProjectScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  String? _category;
  List<String> _urls = [];
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = e.title;
      _desc.text = e.description;
      _category = e.category.isEmpty ? null : e.category;
      _urls = List.of(e.imageUrls);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final bytes = await _pickPortfolioPhoto();
    if (bytes == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final url = await ref.read(portfolioServiceProvider).addImageAndGetUrl(artisanId: widget.artisanId, bytes: bytes);
      if (mounted) setState(() => _urls.add(url));
    } catch (e) {
      if (mounted) htSnack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(portfolioServiceProvider);
      if (_isEdit) {
        await svc.updateProject(projectId: widget.existing!.id, title: _title.text.trim(), description: _desc.text.trim(), category: _category ?? '', imageUrls: _urls);
      } else {
        await svc.createProject(artisanId: widget.artisanId, title: _title.text.trim(), description: _desc.text.trim(), category: _category ?? '', imageUrls: _urls);
      }
      if (!mounted) return;
      htSnack(context, _isEdit ? 'Project updated.' : 'Project added.');
      if (context.canPop()) context.pop();
    } catch (_) {
      if (mounted) htSnack(context, 'Could not save the project. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return ArtisanPage(
      title: _isEdit ? 'Edit project' : 'Add project',
      sub: 'Portfolio',
      bottomBar: ProActionBar(label: _isEdit ? 'Update project' : 'Save project', loading: _busy, onPressed: _busy ? null : _save),
      children: [
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HtTextField(label: 'Project title', controller: _title, hint: 'e.g. Bathroom re-pipe', maxLength: 80, validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const HtFieldLabel('Category'),
            DropdownButtonFormField<String>(
              initialValue: ServiceCategories.all.contains(_category) ? _category : null,
              isExpanded: true,
              dropdownColor: p.surface,
              style: HtType.body(p.textPrimary),
              decoration: htInputDecoration(context, hint: 'Select a category'),
              items: [for (final c in ServiceCategories.all) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _category = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
            HtTextField(label: 'Description', controller: _desc, hint: 'Describe the project…', lines: 3, maxLength: 1000, validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
          ]),
        ),
        HtFieldLabel('Photos', trailing: '${_urls.length} / ${PortfolioService.maxImages}'),
        HtPhotoGrid(urls: _urls, max: PortfolioService.maxImages, onAdd: _busy ? null : _add, onRemoveUrl: _busy ? null : (i) => setState(() => _urls.removeAt(i))),
      ],
    );
  }
}
