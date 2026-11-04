import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/portfolio_service.dart';
import '../../models/portfolio_project_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';
import '../../widgets/portfolio_viewer.dart';

class PortfolioManagerScreen extends ConsumerStatefulWidget {
  const PortfolioManagerScreen({super.key});

  @override
  ConsumerState<PortfolioManagerScreen> createState() =>
      _PortfolioManagerScreenState();
}

class _PortfolioManagerScreenState
    extends ConsumerState<PortfolioManagerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _picker = ImagePicker();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<Uint8List> _compress(Uint8List bytes) async {
    if (bytes.lengthInBytes <= 800 * 1024) return bytes;
    return FlutterImageCompress.compressWithList(
      bytes,
      quality: 75,
      format: CompressFormat.jpeg,
    );
  }

  Future<void> _addPhoto(String artisanId) async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _compress(await picked.readAsBytes());
      await ref
          .read(portfolioServiceProvider)
          .addImage(artisanId: artisanId, bytes: bytes);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(String artisanId, String url) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(portfolioServiceProvider)
          .removeImage(artisanId: artisanId, url: url);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorder(
    String artisanId,
    List<String> urls,
    int oldIndex,
    int newIndex,
  ) async {
    final updated = List<String>.from(urls);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    try {
      await ref
          .read(portfolioServiceProvider)
          .reorder(artisanId: artisanId, orderedUrls: updated);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
    }
  }

  Future<void> _deleteProject(String projectId) async {
    setState(() => _busy = true);
    try {
      await ref.read(portfolioServiceProvider).deleteProject(projectId);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).asData?.value;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final artisanAsync = ref.watch(artisanProfileProvider(user.uid));
    final viewCountAsync = ref.watch(portfolioViewCountProvider(user.uid));
    final projectsAsync = ref.watch(portfolioProjectsProvider(user.uid));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Manage Portfolio'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Projects'), Tab(text: 'Photos')],
        ),
      ),
      body: artisanAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (artisan) {
          if (artisan == null) return const SizedBox();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined,
                        size: 16, color: context.colors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '${viewCountAsync.asData?.value ?? 0} profile views',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _ProjectsTab(
                      artisanId: artisan.uid,
                      projectsAsync: projectsAsync,
                      busy: _busy,
                      onDelete: _deleteProject,
                    ),
                    _PhotosTab(
                      artisanId: artisan.uid,
                      urls: artisan.portfolioImageUrls,
                      busy: _busy,
                      onAdd: () => _addPhoto(artisan.uid),
                      onRemove: (url) => _removePhoto(artisan.uid, url),
                      onReorder: (old, neo) =>
                          _reorder(artisan.uid, artisan.portfolioImageUrls, old, neo),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Projects tab ─────────────────────────────────────────────────────────────

class _ProjectsTab extends ConsumerWidget {
  final String artisanId;
  final AsyncValue<List<PortfolioProjectModel>> projectsAsync;
  final bool busy;
  final void Function(String projectId) onDelete;

  const _ProjectsTab({
    required this.artisanId,
    required this.projectsAsync,
    required this.busy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        projectsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (projects) => projects.isEmpty
              ? Center(
                  child: Text(
                    'No projects yet — add your first one!',
                    style: TextStyle(
                      color: context.colors.textTertiary,
                      fontFamily: 'Inter',
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: projects.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ProjectTile(
                    project: projects[i],
                    artisanId: artisanId,
                    busy: busy,
                    onDelete: () => onDelete(projects[i].id),
                  ),
                ),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: ElevatedButton.icon(
            onPressed: busy
                ? null
                : () => context.push('/portfolio-project',
                    extra: {'artisanId': artisanId}),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Project'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: context.colors.textInverse,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  final PortfolioProjectModel project;
  final String artisanId;
  final bool busy;
  final VoidCallback onDelete;

  const _ProjectTile({
    required this.project,
    required this.artisanId,
    required this.busy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: project.imageUrls.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  project.imageUrls.first,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              )
            : Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.photo_library_outlined,
                    color: context.colors.primary),
              ),
        title: Text(
          project.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: context.colors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
        subtitle: Text(
          project.category,
          style: TextStyle(
            fontSize: 12,
            color: context.colors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 20, color: context.colors.primary),
              onPressed: busy
                  ? null
                  : () => context.push('/portfolio-project',
                      extra: {'artisanId': artisanId, 'existing': project}),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 20, color: context.colors.error),
              onPressed: busy ? null : onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Photos tab (unchanged behaviour) ────────────────────────────────────────

class _PhotosTab extends StatelessWidget {
  final String artisanId;
  final List<String> urls;
  final bool busy;
  final VoidCallback onAdd;
  final void Function(String url) onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _PhotosTab({
    required this.artisanId,
    required this.urls,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: urls.isEmpty
              ? Center(
                  child: Text(
                    'No portfolio photos yet',
                    style: TextStyle(
                      color: context.colors.textTertiary,
                      fontFamily: 'Inter',
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  itemCount: urls.length,
                  onReorder: onReorder,
                  itemBuilder: (ctx, i) => Container(
                    key: ValueKey(urls[i]),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.colors.borderLight),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => showPortfolioViewer(
                            ctx,
                            imageUrls: urls,
                            initialIndex: i,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              urls[i],
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Photo ${i + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.textPrimary,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: context.colors.error),
                          onPressed: busy ? null : () => onRemove(urls[i]),
                        ),
                        Icon(Icons.drag_handle,
                            color: context.colors.textTertiary),
                      ],
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: busy || urls.length >= PortfolioService.maxImages
                  ? null
                  : onAdd,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(urls.length >= PortfolioService.maxImages
                  ? 'Limit reached'
                  : 'Add Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primary,
                foregroundColor: context.colors.textInverse,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
