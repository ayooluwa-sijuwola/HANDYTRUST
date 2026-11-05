import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/service_categories.dart';
import '../../../core/services/artisan_profile_service.dart';
import '../../../providers/auth_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';

/// AU-06 Artisan registration (`/register/artisan`): primary category,
/// skills, bio, service area → submitted for HandyTrust review. Same fields,
/// validation and writes as before (via ArtisanProfileService).
class ArtisanRegistrationScreen extends ConsumerStatefulWidget {
  const ArtisanRegistrationScreen({super.key});
  @override
  ConsumerState<ArtisanRegistrationScreen> createState() => _ArtisanRegistrationScreenState();
}

class _ArtisanRegistrationScreenState extends ConsumerState<ArtisanRegistrationScreen> {
  final _form = GlobalKey<FormState>();
  final _skills = TextEditingController();
  final _bio = TextEditingController();
  final _location = TextEditingController();
  String? _category;
  bool _saving = false;

  @override
  void dispose() {
    _skills.dispose();
    _bio.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final firebaseUser = ref.read(authStateChangesProvider).asData?.value;
    if (firebaseUser == null) return;
    final profile = ref.read(currentUserProvider).asData?.value;
    setState(() => _saving = true);
    try {
      await ref.read(artisanProfileServiceProvider).registerArtisan(
            uid: firebaseUser.uid,
            name: profile?.name ?? firebaseUser.displayName ?? '',
            email: firebaseUser.email,
            bio: _bio.text,
            skills: _skills.text,
            location: _location.text,
            category: _category!,
          );
      if (mounted) context.go('/home');
    } catch (_) {
      if (mounted) htSnack(context, 'Could not save your profile. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return ArtisanPage(
      title: 'Artisan profile',
      bottomBar: ProActionBar(label: 'Submit for review', loading: _saving, onPressed: _saving ? null : _save),
      children: [
        Text('Set up your artisan profile', style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 23)),
        const SizedBox(height: 4),
        Text('Your profile will be reviewed by HandyTrust before appearing publicly.', style: HtType.body(p.textSecondary)),
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const HtFieldLabel('Primary service category'),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              dropdownColor: p.surface,
              style: HtType.body(p.textPrimary),
              decoration: htInputDecoration(context, hint: 'Select your main trade'),
              items: [for (final c in ServiceCategories.all) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _category = v),
              validator: (v) => v == null ? 'Select a category' : null,
            ),
            HtTextField(
              label: 'Skills & specialisations',
              controller: _skills,
              hint: 'e.g. Pipe fitting, water heater installation, drainage repair',
              lines: 2,
              validator: (v) => (v == null || v.trim().length < 10) ? 'Describe your skills (at least 10 characters)' : null,
            ),
            HtTextField(
              label: 'About you',
              controller: _bio,
              hint: 'Tell customers about your experience and what makes you stand out…',
              lines: 4,
              validator: (v) => (v == null || v.trim().length < 20) ? 'Write a short bio (at least 20 characters)' : null,
            ),
            HtTextField(
              label: 'Service area',
              controller: _location,
              hint: 'e.g. Lagos Island, Victoria Island',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your service area' : null,
            ),
          ]),
        ),
        const SizedBox(height: 14),
        const HtInfoBanner(icon: Icons.verified_user_outlined, tone: HtTone.neutral, text: 'After approval, verify your identity and add your payout account to start quoting.'),
      ],
    );
  }
}
