import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../core/constants/service_categories.dart';
import '../../providers/ai_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/job_provider.dart';
import '../../providers/platform_config_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';
import '../../widgets/web_content_wrapper.dart';

class ServiceRequestScreen extends ConsumerStatefulWidget {
  final String? initialCategory;

  const ServiceRequestScreen({super.key, this.initialCategory});

  @override
  ConsumerState<ServiceRequestScreen> createState() =>
      _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends ConsumerState<ServiceRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _budgetMinController = TextEditingController();
  final _budgetMaxController = TextEditingController();
  final _picker = ImagePicker();

  final List<Uint8List> _images = [];
  String? _selectedCategory;
  double? _lat;
  double? _lng;
  bool _fetchingLocation = false;
  String _urgency = 'asap';
  DateTime? _scheduledDate;

  bool _analyzing = false;
  JobAiSuggestion? _aiSuggestion;
  bool _aiAccepted = false;

  static const int _maxImages = 5;

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null &&
        ServiceCategories.all.contains(widget.initialCategory)) {
      _selectedCategory = widget.initialCategory;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    _budgetMinController.dispose();
    _budgetMaxController.dispose();
    super.dispose();
  }

  Future<void> _selectImages() async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) {
      showErrorSnackbar(context, 'Maximum of $_maxImages images allowed.');
      return;
    }
    try {
      final picked =
          await _picker.pickMultiImage(imageQuality: 70, limit: remaining);
      if (picked.isEmpty) return;

      final bytesList = await Future.wait(
        picked.map((image) async {
          final bytes = await image.readAsBytes();
          if (bytes.lengthInBytes <= 500 * 1024) return bytes;
          return FlutterImageCompress.compressWithList(
            bytes,
            quality: 70,
            format: CompressFormat.jpeg,
          );
        }),
      );

      if (mounted) setState(() => _images.addAll(bytesList));
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Could not load the selected photos. Please try again.');
      }
    }
  }

  void _removeImage(int index) => setState(() => _images.removeAt(index));

  Future<void> _analyzeWithAi() async {
    final description = _descriptionController.text.trim();
    if (description.length < 10) {
      showErrorSnackbar(
          context, 'Write a few more words about the job first.');
      return;
    }

    setState(() {
      _analyzing = true;
      _aiSuggestion = null;
      _aiAccepted = false;
    });

    try {
      final suggestion = await ref.read(aiServiceProvider).analyzeJob(
            description: description,
            imagesBase64: _images.take(3).map(base64Encode).toList(),
          );
      if (mounted) setState(() => _aiSuggestion = suggestion);
    } catch (e) {
      // AiService.analyzeJob throws AiServiceException with an
      // already-friendly message — show it directly.
      if (mounted) {
        showErrorSnackbar(context, '$e');
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _acceptAiSuggestion() {
    final suggestion = _aiSuggestion;
    if (suggestion == null) return;
    setState(() {
      if (ServiceCategories.all.contains(suggestion.suggestedCategory)) {
        _selectedCategory = suggestion.suggestedCategory;
      }
      _descriptionController.text = suggestion.enhancedDescription;
      _aiAccepted = true;
    });
  }

  void _dismissAiSuggestion() => setState(() {
        _aiSuggestion = null;
        _aiAccepted = false;
      });

  Future<void> _fetchLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      // Checked separately from permission: on iOS/Android, Location
      // Services can be off system-wide independent of this app's own
      // permission grant. Checking this first gives a clearer, more
      // actionable message than letting getCurrentPosition() below throw a
      // generic LocationServiceDisabledException into the catch-all.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          showErrorSnackbar(context,
              'Location services are turned off. Enable them in Settings, or enter your address manually.');
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          showErrorSnackbar(context,
              'Location permission was permanently denied. Enable it in Settings, or enter your address manually.');
        }
        return;
      }
      if (permission == LocationPermission.denied) {
        if (mounted) {
          showErrorSnackbar(
              context, 'Location permission denied. Enter address manually.');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.subLocality, p.locality, p.administrativeArea]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList();
        setState(() {
          _lat = position.latitude;
          _lng = position.longitude;
          _addressController.text = parts.join(', ');
        });
      }
    } catch (_) {
      // Deliberately broad: covers LocationServiceDisabledException (a race
      // where services are disabled between the check above and
      // getCurrentPosition below), platform channel errors, and geocoding
      // failures alike — the app must never crash or hang here, only ever
      // fall back to manual address entry.
      if (mounted) {
        showErrorSnackbar(
            context, 'Could not get location. Enter address manually.');
      }
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  Future<void> _pickScheduledDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'Select the date you need this done',
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_images.isEmpty) {
      showErrorSnackbar(
          context, 'Please attach at least one photo of the work needed.');
      return;
    }

    if (_urgency == 'scheduled' && _scheduledDate == null) {
      showErrorSnackbar(context, 'Please select the date you need this done.');
      return;
    }

    final profile = ref.read(currentUserProvider).asData?.value;
    if (profile == null) {
      showErrorSnackbar(context, 'Unable to submit: user profile not found.');
      return;
    }

    final budgetMin = _budgetMinController.text.trim().isEmpty
        ? null
        : double.tryParse(_budgetMinController.text.trim());
    final budgetMax = _budgetMaxController.text.trim().isEmpty
        ? null
        : double.tryParse(_budgetMaxController.text.trim());

    await ref.read(jobRequestNotifierProvider.notifier).submitRequest(
          customerId: profile.uid,
          category: _selectedCategory!,
          description: _descriptionController.text.trim(),
          images: _images,
          customerLat: _lat,
          customerLng: _lng,
          customerAddress: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          budgetMin: budgetMin,
          budgetMax: budgetMax,
          urgency: _urgency,
          scheduledDate: _scheduledDate,
          aiSuggestion: _aiAccepted ? _aiSuggestion?.toJson() : null,
        );

    final state = ref.read(jobRequestNotifierProvider);
    if (state.error != null) {
      if (!mounted) return;
      // Network/Firestore failures are usually transient — offer a one-tap
      // retry instead of leaving the customer to re-fill the whole form.
      showErrorSnackbar(
        context,
        "Couldn't post your job: ${state.error}",
        onRetry: _submitRequest,
      );
      return;
    }

    if (state.success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.failedImageCount > 0
                ? 'Job posted! ${state.failedImageCount} photo'
                    '${state.failedImageCount == 1 ? '' : 's'} failed to upload '
                    'but your request was still submitted.'
                : 'Job posted! Choose an artisan.',
          ),
        ),
      );
      context.push(
        '/artisans/${state.createdJobId}',
        extra: {
          'category': _selectedCategory,
          'lat': _lat,
          'lng': _lng,
        },
      );
    }
  }

  /// Required-field completion, for the progress bar only — purely visual,
  /// doesn't gate submission (the Form's own validators still do that).
  double get _completionFraction {
    var done = 0;
    if (_selectedCategory != null) done++;
    if (_descriptionController.text.trim().length >= 20) done++;
    if (_images.isNotEmpty) done++;
    return done / 3;
  }

  @override
  Widget build(BuildContext context) {
    final jobState = ref.watch(jobRequestNotifierProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        title: const Text(
          'Post a New Job',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: WebContentWrapper(
          maxWidth: 640,
          child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _ProgressBar(fraction: _completionFraction),
              const SizedBox(height: 20),
              _SectionLabel('Select Category',
                  icon: Icons.category_outlined,
                  complete: _selectedCategory != null),
              const SizedBox(height: 8),
              // Pixel-matched to the reference's pill-chip row (Welding/
              // Plumbing/Carpentry) — light-gray fill on the selected
              // chip, outlined on the rest, black text either way. This
              // is a different selected-state treatment than Home's
              // category chips (black fill/white text) since that's what
              // this screen's own reference specifically shows.
              FormField<String>(
                initialValue: _selectedCategory,
                validator: (v) =>
                    v == null ? 'Please select a service category' : null,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: ServiceCategories.all.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (ctx, i) {
                          final c = ServiceCategories.all[i];
                          final selected = _selectedCategory == c;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedCategory = c);
                              field.didChange(c);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? context.colors.surfaceVariant
                                    : context.colors.surface,
                                borderRadius: BorderRadius.circular(AppRadius.full),
                                border: Border.all(
                                  color: selected
                                      ? Colors.transparent
                                      : context.colors.border,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                c,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Inter',
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (field.hasError) ...[
                      const SizedBox(height: 6),
                      Text(
                        field.errorText!,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.error,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _SectionLabel('Describe the work needed',
                  icon: Icons.description_outlined,
                  complete: _descriptionController.text.trim().length >= 20),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText:
                      'Describe the problem, size of the job, and any relevant details…',
                  hintStyle: TextStyle(
                      fontSize: 13, color: context.colors.textTertiary),
                  filled: true,
                  fillColor: context.colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.border),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 20) {
                    return 'Please describe the job (at least 20 characters)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _analyzing ? null : _analyzeWithAi,
                icon: _analyzing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(_analyzing ? 'Analyzing…' : 'Analyze with AI'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.colors.primary),
                  foregroundColor: context.colors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              if (_aiSuggestion != null) ...[
                const SizedBox(height: 12),
                _AiSuggestionCard(
                  suggestion: _aiSuggestion!,
                  accepted: _aiAccepted,
                  onAccept: _acceptAiSuggestion,
                  onDismiss: _dismissAiSuggestion,
                ),
              ],
              const SizedBox(height: 24),

              Row(
                children: [
                  _SectionLabel('Photos', icon: Icons.image_outlined, complete: _images.isNotEmpty),
                  const SizedBox(width: 8),
                  Text(
                    '${_images.length}/$_maxImages',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textTertiary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_images.isNotEmpty) ...[
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, i) => const SizedBox(width: 10),
                    itemBuilder: (ctx, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            _images[i],
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(i),
                            child: Container(
                              decoration: BoxDecoration(
                                color: context.colors.error,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(3),
                              child: const Icon(Icons.close,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_images.length < _maxImages)
                OutlinedButton.icon(
                  onPressed: _selectImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_images.isEmpty
                      ? 'Add Photos (required)'
                      : 'Add More Photos'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.colors.primary),
                    foregroundColor: context.colors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              const SizedBox(height: 24),

              _SectionLabel('Location', icon: Icons.location_on_outlined),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _addressController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Victoria Island, Lagos',
                        prefixIcon: Icon(
                          _lat != null
                              ? Icons.location_on
                              : Icons.location_on_outlined,
                          color: _lat != null ? context.colors.accent : null,
                        ),
                        filled: true,
                        fillColor: context.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                      ),
                      onChanged: (_) {
                        if (_lat != null) {
                          setState(() {
                            _lat = null;
                            _lng = null;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Use my current location',
                    onPressed: _fetchingLocation ? null : _fetchLocation,
                    icon: _fetchingLocation
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.my_location),
                    style: IconButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              _SectionLabel('Budget (optional)', icon: Icons.payments_outlined),
              const SizedBox(height: 4),
              // Policy D1: shown before the job is posted, so the customer
              // knows the smallest price that can be paid online.
              Text(
                'Minimum job value for secure payment: ${ref.watch(platformConfigProvider).minJobValueLabel}',
                style: TextStyle(fontSize: 12, color: context.colors.textSecondary, fontFamily: 'Inter'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _budgetMinController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: InputDecoration(
                        labelText: 'Min (₦)',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        filled: true,
                        fillColor: context.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final min = double.tryParse(v);
                        if (min == null || min <= 0) {
                          return 'Enter a valid amount';
                        }
                        final max =
                            double.tryParse(_budgetMaxController.text.trim());
                        if (max != null && min > max) {
                          return 'Must be ≤ max';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _budgetMaxController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: InputDecoration(
                        labelText: 'Max (₦)',
                        filled: true,
                        fillColor: context.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.border),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final max = double.tryParse(v);
                        if (max == null || max <= 0) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              _SectionLabel('Schedule', icon: Icons.calendar_month_outlined),
              const SizedBox(height: 8),
              // Dropdown-styled selector — matches the Stitch reference's
              // "As soon as possible ⌄" single-row field. Same underlying
              // state (_urgency/_scheduledDate) as the previous two-tile
              // picker; only the presentation changed.
              PopupMenuButton<String>(
                initialValue: _urgency,
                onSelected: (value) async {
                  if (value == 'asap') {
                    setState(() {
                      _urgency = 'asap';
                      _scheduledDate = null;
                    });
                  } else {
                    setState(() => _urgency = 'scheduled');
                    await _pickScheduledDate();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'asap', child: Text('As soon as possible')),
                  PopupMenuItem(value: 'scheduled', child: Text('Specific date')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _urgency == 'asap' ? Icons.bolt_rounded : Icons.event_outlined,
                        size: 18,
                        color: context.colors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _urgency == 'asap' ? 'As soon as possible' : 'Specific date',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                      Icon(Icons.expand_more_rounded, size: 20, color: context.colors.textTertiary),
                    ],
                  ),
                ),
              ),
              if (_urgency == 'scheduled' && _scheduledDate != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _pickScheduledDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: context.colors.accentSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: context.colors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_available,
                            color: context.colors.accent, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('EEEE, d MMMM yyyy')
                              .format(_scheduledDate!),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.colors.accent,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.edit_outlined,
                            size: 16, color: context.colors.accent),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),

              // Black "commitment" button — posting a job is a one-time,
              // high-commitment action in the same category as Lock Funds
              // in Escrow / Book Now, which is what Stitch's "Post Job"
              // button uses.
              CommitButton(
                label: 'Post Job',
                icon: Icons.arrow_forward_rounded,
                loading: jobState.isSubmitting,
                onPressed: _submitRequest,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _AiSuggestionCard extends StatelessWidget {
  final JobAiSuggestion suggestion;
  final bool accepted;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _AiSuggestionCard({
    required this.suggestion,
    required this.accepted,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined,
                    size: 16, color: context.colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'AI-generated suggestion. Review before accepting.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.primary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
                Text(
                  '${(suggestion.confidence * 100).round()}% confident',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Category: ${suggestion.suggestedCategory}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontFamily: 'Inter')),
            const SizedBox(height: 6),
            Text(
              suggestion.enhancedDescription,
              style: TextStyle(
                  fontSize: 13, color: context.colors.textSecondary, fontFamily: 'Inter'),
            ),
            const SizedBox(height: 12),
            if (accepted)
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: context.colors.accent),
                  SizedBox(width: 6),
                  Text('Applied to your post',
                      style: TextStyle(
                          fontSize: 12,
                          color: context.colors.accent,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter')),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDismiss,
                      child: const Text('Keep my version'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onAccept,
                      child: const Text('Use this'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool? complete;
  // Leading section icon — matches the Stitch "Post a New Job" reference's
  // icon-prefixed section headers (📋 Job Details, 🖼 Photos, 📅 Schedule,
  // 💳 Budget). Optional so pre-existing call sites without a mapped icon
  // are unaffected.
  final IconData? icon;
  const _SectionLabel(this.text, {this.complete, this.icon});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: context.colors.textSecondary),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          if (complete == true) ...[
            const SizedBox(width: 6),
            Icon(Icons.check_circle_rounded, size: 15, color: context.colors.primary),
          ],
        ],
      );
}

/// Required-field completion at a glance — Category, Description, Photos.
/// Purely visual; Form validators are still what actually gates submission.
class _ProgressBar extends StatelessWidget {
  final double fraction;
  const _ProgressBar({required this.fraction});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Required details',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              Text(
                '${(fraction * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.colors.primary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: context.colors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(context.colors.primary),
            ),
          ),
        ],
      );
}

