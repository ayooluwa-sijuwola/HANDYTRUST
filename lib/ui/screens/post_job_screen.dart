import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/service_categories.dart';
import '../../core/services/location_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/job_provider.dart';
import '../../providers/platform_config_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';

/// Post a Job — step 1 of 3 (references 3 dark, 17 light). Steps 2–3 are
/// the existing matched-artisans list and booking flow (no Stitch design).
/// Submits through jobRequestNotifierProvider (unchanged): photos are
/// metadata-stripped by StorageService, the exact location goes to the
/// job's private sub-document. No "Job title" field — jobs have no title
/// (design/STAGE8_SCREEN_INVENTORY.md).
class PostJobScreen extends ConsumerStatefulWidget {
  const PostJobScreen({super.key, this.initialCategory});

  /// Preselected category (from /request?category=…).
  final String? initialCategory;

  @override
  ConsumerState<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends ConsumerState<PostJobScreen> {
  static const _maxPhotos = 5;
  static const _maxDescription = 500;

  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _budget = TextEditingController();
  final List<Uint8List> _photos = [];
  String? _category;
  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initialCategory;
    if (c != null && ServiceCategories.all.contains(c)) _category = c;
  }

  @override
  void dispose() {
    _description.dispose();
    _address.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final remaining = _maxPhotos - _photos.length;
    if (remaining <= 0) return;
    try {
      final picked = await ImagePicker().pickMultiImage(limit: remaining);
      if (picked.isEmpty) return;
      final bytes = await Future.wait(picked.map((x) => x.readAsBytes()));
      if (mounted) setState(() => _photos.addAll(bytes.take(remaining)));
    } catch (_) {
      if (mounted) htSnack(context, 'Could not load the selected photos. Please try again.', error: true);
    }
  }

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    final r = await const LocationService().currentArea();
    if (!mounted) return;
    setState(() => _locating = false);
    switch (r) {
      case LocationFound(:final latitude, :final longitude, :final address):
        setState(() {
          _lat = latitude;
          _lng = longitude;
          if (address.isNotEmpty) _address.text = address;
        });
      case LocationUnavailable(:final message):
        htSnack(context, message, error: true);
    }
  }

  Future<void> _changeLocation() async {
    final p = context.ht;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HtRadius.card))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Job location', style: HtType.sectionTitle(p.textPrimary)),
            const SizedBox(height: 6),
            Text('Artisans only see the general area until you confirm a booking.', style: HtType.small(p.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: _address,
              autofocus: true,
              style: HtType.body(p.textPrimary),
              decoration: htInputDecoration(ctx, hint: 'e.g. Bodija, Ibadan'),
              onChanged: (_) => setState(() {
                // Typed address replaces any previously captured GPS point.
                _lat = null;
                _lng = null;
              }),
            ),
            const SizedBox(height: 12),
            HtSecondaryButton(
              label: _locating ? 'Locating…' : 'Use my current location',
              icon: Icons.my_location_rounded,
              onPressed: _locating
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      await _useLocation();
                    },
            ),
            const SizedBox(height: 12),
            HtPrimaryButton(label: 'Done', onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_photos.isEmpty) {
      htSnack(context, 'Please add at least one photo of the work needed.', error: true);
      return;
    }
    final profile = ref.read(currentUserProvider).asData?.value;
    if (profile == null) {
      htSnack(context, 'You need to be signed in to post a job.', error: true);
      return;
    }
    final budget = double.tryParse(_budget.text.replaceAll(',', '').trim());
    setState(() => _submitting = true);
    await ref.read(jobRequestNotifierProvider.notifier).submitRequest(
          customerId: profile.uid,
          category: _category!,
          description: _description.text.trim(),
          images: List.of(_photos),
          customerLat: _lat,
          customerLng: _lng,
          customerAddress: _address.text.trim().isEmpty ? null : _address.text.trim(),
          budgetMin: budget,
          budgetMax: budget,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    final state = ref.read(jobRequestNotifierProvider);
    if (state.error != null) {
      htSnack(context, "Couldn't post your job: ${state.error}", error: true);
      return;
    }
    if (state.success && state.createdJobId != null) {
      htSnack(
        context,
        state.failedImageCount > 0
            ? 'Job posted. ${state.failedImageCount} photo${state.failedImageCount == 1 ? '' : 's'} failed to upload.'
            : 'Job posted! Choose an artisan.',
      );
      context.pushReplacement('/artisans/${state.createdJobId}', extra: {'category': _category, 'lat': _lat, 'lng': _lng});
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final submitting = _submitting;
    final minJob = ref.watch(platformConfigProvider);

    return Scaffold(
      backgroundColor: p.isDark ? p.background : p.background,
      body: HtBackground(
        glow: !p.isDark,
        child: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                HtScreenHeader(
                  title: p.isDark ? 'Job Scope & Category' : 'Post a Job',
                  trailing: p.isDark
                      ? Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: p.headerAvatarFill, shape: BoxShape.circle),
                          child: Icon(Icons.person_outline_rounded, color: p.onHeaderAvatar),
                        )
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 10, HtSpace.gutter, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(p.isDark ? 'Step 1 of 3' : 'PROGRESS', style: p.isDark ? HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14) : HtType.caps(p.textSecondary)),
                          const Spacer(),
                          if (p.isDark) ...[
                            Container(width: 7, height: 7, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text('Job Details', style: HtType.smallStrong(p.accent)),
                          ] else
                            Text('Step 1 of 3', style: HtType.smallStrong(p.accentStrong).copyWith(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: 1 / 3,
                          minHeight: 5,
                          backgroundColor: p.isDark ? p.surfaceRaised : p.border,
                          valueColor: AlwaysStoppedAnimation(p.isDark ? p.accentStrong : p.accentStrong),
                        ),
                      ),
                      const SizedBox(height: 26),
                      _PhotoBox(photos: _photos, onAdd: _pickPhotos, onRemove: (i) => setState(() => _photos.removeAt(i)), max: _maxPhotos),
                      HtFieldLabel('Category'),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        isExpanded: true,
                        dropdownColor: p.surface,
                        borderRadius: BorderRadius.circular(HtRadius.inner),
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.textPrimary),
                        decoration: htInputDecoration(
                          context,
                          hint: 'Choose a category',
                          prefix: Padding(
                            padding: const EdgeInsets.only(left: 14, right: 8),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: p.accentSoft,
                              child: Icon(Icons.format_paint_outlined, size: 18, color: p.accentSoftText),
                            ),
                          ),
                        ),
                        style: HtType.body(p.textPrimary).copyWith(fontSize: 14.5),
                        items: [for (final c in ServiceCategories.all) DropdownMenuItem(value: c, child: Text(c))],
                        onChanged: (v) => setState(() => _category = v),
                        validator: (v) => v == null ? 'Choose a category' : null,
                      ),
                      HtFieldLabel('Describe the work', trailing: '${_description.text.length} / $_maxDescription'),
                      TextFormField(
                        controller: _description,
                        minLines: 4,
                        maxLines: 6,
                        maxLength: _maxDescription,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                        style: HtType.body(p.textPrimary).copyWith(fontSize: 14, height: 1.55),
                        decoration: htInputDecoration(context, hint: 'What needs doing? Include sizes, materials and access details.'),
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (v == null || v.trim().length < 10) ? 'Describe the work in at least 10 characters' : null,
                      ),
                      HtFieldLabel('Location'),
                      InkWell(
                        borderRadius: BorderRadius.circular(HtRadius.input),
                        onTap: _changeLocation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                          decoration: BoxDecoration(
                            color: p.input,
                            borderRadius: BorderRadius.circular(HtRadius.input),
                            border: Border.all(color: p.isDark ? Colors.transparent : p.border),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_on_outlined, color: p.isDark ? p.accent : p.accentStrong),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  HtFormat.area(_address.text) ?? (_address.text.trim().isEmpty ? 'Add the job location' : _address.text.trim()),
                                  style: _address.text.trim().isEmpty ? HtType.body(p.textMuted) : HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14.5),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_locating)
                                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              else
                                Text('Change', style: HtType.bodyStrong(p.isDark ? p.accent : p.accentStrong)),
                            ],
                          ),
                        ),
                      ),
                      HtFieldLabel('Estimated Budget'),
                      TextFormField(
                        controller: _budget,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: HtType.amount(p.textPrimary, size: 22.5),
                        decoration: htInputDecoration(
                          context,
                          hint: 'Optional',
                          prefix: Padding(
                            padding: const EdgeInsets.only(left: 16, right: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(HtRadius.pill)),
                              child: Text('NGN', style: HtType.smallStrong(p.accentSoftText)),
                            ),
                          ),
                          suffix: Padding(padding: const EdgeInsets.only(right: 14), child: Icon(Icons.payments_outlined, color: p.textMuted)),
                        ).copyWith(prefixText: '₦', prefixStyle: HtType.amount(p.textPrimary, size: 22.5)),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final amount = double.tryParse(v.trim());
                          if (amount == null || amount <= 0) return 'Enter a valid amount';
                          if (!minJob.meetsMinimum(amount)) return 'Minimum job value for secure payment is ${minJob.minJobValueLabel}';
                          return null;
                        },
                      ),
                      const SizedBox(height: 22),
                      HtInfoBanner(
                        icon: Icons.lock_outline_rounded,
                        text: 'Your payment is held in escrow, never paid upfront to the artisan.',
                        tone: p.isDark ? HtTone.neutral : HtTone.neutral,
                      ),
                      const SizedBox(height: 26),
                      HtPrimaryButton(label: 'Find Artisans', icon: Icons.arrow_forward_rounded, loading: submitting, onPressed: submitting ? null : _submit),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.photos, required this.onAdd, required this.onRemove, required this.max});
  final List<Uint8List> photos;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final int max;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: p.isDark ? p.surface : p.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: p.isDark ? p.border : const Color(0xFFD4D8C6)),
      ),
      child: Column(
        children: [
          if (photos.isEmpty) ...[
            const SizedBox(height: 18),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: p.isDark ? p.surfaceRaised : p.surface, shape: BoxShape.circle, boxShadow: p.cardShadow),
              child: Icon(Icons.photo_camera_outlined, size: 30, color: p.isDark ? p.accent : p.accentStrong),
            ),
            const SizedBox(height: 16),
            Text('Add a photo of the work', style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: p.isDark ? 19 : 15.5)),
            const SizedBox(height: 6),
            Text('Artisans can quote more accurately with clear photos', style: HtType.small(p.textSecondary).copyWith(fontSize: 12.5), textAlign: TextAlign.center),
            const SizedBox(height: 16),
          ] else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < photos.length; i++)
                  Stack(
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(HtRadius.tile), child: Image.memory(photos[i], width: 86, height: 86, fit: BoxFit.cover)),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: GestureDetector(
                          onTap: () => onRemove(i),
                          child: Container(
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            padding: const EdgeInsets.all(3),
                            child: const Icon(Icons.close_rounded, size: 15, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          if (photos.length < max) ...[
            if (photos.isNotEmpty) const SizedBox(height: 14),
            Material(
              color: p.surfaceRaised,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onAdd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline_rounded, size: 19, color: p.isDark ? p.accent : p.accentStrong),
                      const SizedBox(width: 8),
                      Text(photos.isEmpty ? 'Tap to browse files' : 'Add another photo', style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
