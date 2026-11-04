import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/service_categories.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/web_content_wrapper.dart';

/// Step 2 of artisan onboarding: professional details.
/// Reached after email verification when the user's role includes 'artisan'.
class ArtisanRegistrationScreen extends ConsumerStatefulWidget {
  const ArtisanRegistrationScreen({super.key});

  @override
  ConsumerState<ArtisanRegistrationScreen> createState() => _ArtisanRegistrationScreenState();
}

class _ArtisanRegistrationScreenState extends ConsumerState<ArtisanRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();
  final _skillsController = TextEditingController();
  final _locationController = TextEditingController();
  String? _selectedCategory;
  bool _isSaving = false;


  @override
  void dispose() {
    _bioController.dispose();
    _skillsController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final firebaseUser = ref.read(authStateChangesProvider).asData?.value;
    if (firebaseUser == null) return;

    // Fetch the user's display name from their existing users doc
    final userProfile = ref.read(currentUserProvider).asData?.value;
    final name = userProfile?.name ?? firebaseUser.displayName ?? '';

    setState(() => _isSaving = true);
    try {
      final artisanFields = {
        'bio': _bioController.text.trim(),
        'skills': _skillsController.text.trim(),
        'location': _locationController.text.trim(),
        'category': _selectedCategory,
        'approvalStatus': 'pending',
        'verificationStatus': 'unverified',
        'isAvailable': false,
        'rating': 0.0,
        'totalRatings': 0,
        'totalJobs': 0,
        'completedJobs': 0,
        'responseTimeMinutes': 30.0,
        'trustScore': 0.0,
        'portfolioImageUrls': <String>[],
      };

      // set(merge:true) instead of update() — update() throws "not-found" if
      // the /users doc hasn't landed yet (e.g. a slow write right after
      // email verification), which surfaced to the artisan as a confusing
      // "Failed to save profile" error with no way to recover except retry.
      await FirebaseFirestore.instance.collection('users').doc(firebaseUser.uid).set({
        ...artisanFields,
        // arrayUnion (not a plain overwrite) so an existing customer role
        // survives — accounts can hold both roles and switch between them.
        'roles': FieldValue.arrayUnion(['artisan']),
        'activeRole': 'artisan',
        'responseRatePercent': 100.0,
        'cancellationRatePercent': 0.0,
        'openDisputeCount': 0,
      }, SetOptions(merge: true));

      // Create the artisans collection document — includes name for display
      await FirebaseFirestore.instance.collection('artisans').doc(firebaseUser.uid).set({
        ...artisanFields,
        'uid': firebaseUser.uid,
        'name': name,
        'email': firebaseUser.email,
        'roles': ['artisan'],
        'activeRole': 'artisan',
        'isVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e'), backgroundColor: context.colors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        title: const Text('Set up your artisan profile'),
      ),
      body: SafeArea(
        child: WebContentWrapper(
          maxWidth: 640,
          child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.colors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: context.colors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your profile will be reviewed before appearing publicly. This usually takes 24–48 hours.',
                          style: TextStyle(color: context.colors.primary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Primary service category',
                    prefixIcon: Icon(Icons.handyman_outlined),
                  ),
                  items: ServiceCategories.all
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v),
                  validator: (v) => v == null ? 'Select a category' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _skillsController,
                  decoration: const InputDecoration(
                    labelText: 'Skills & specialisations',
                    hintText: 'e.g. Pipe fitting, water heater installation, drainage repair',
                    prefixIcon: Icon(Icons.build_outlined),
                  ),
                  minLines: 2,
                  maxLines: 4,
                  validator: (v) {
                    if (v == null || v.trim().length < 10) {
                      return 'Describe your skills (at least 10 characters)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _bioController,
                  decoration: const InputDecoration(
                    labelText: 'About you',
                    hintText: 'Tell customers about your experience and what makes you stand out…',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  minLines: 3,
                  maxLines: 6,
                  validator: (v) {
                    if (v == null || v.trim().length < 20) {
                      return 'Write a short bio (at least 20 characters)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Service area',
                    hintText: 'e.g. Lagos Island, Victoria Island',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter your service area';
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                AuthButton(
                  label: 'Submit for review',
                  loading: _isSaving,
                  onPressed: _save,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}
