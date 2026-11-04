import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';
import '../../widgets/service_area_card.dart';

/// Lets an artisan register/operate under a business name instead of their
/// personal name. Public-facing — writes to /artisans/{uid}, the same doc
/// artisanProfileProvider, ArtisanCard and search results read from.
class BusinessProfileScreen extends ConsumerStatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  ConsumerState<BusinessProfileScreen> createState() =>
      _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _registrationNumberController = TextEditingController();
  final _businessAddressController = TextEditingController();
  String _accountType = 'individual';
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _registrationNumberController.dispose();
    _businessAddressController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final user = ref.read(currentUserProvider).asData?.value;
    if (user == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('artisans')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _accountType = data['accountType'] as String? ?? 'individual';
          _businessNameController.text = data['businessName'] as String? ?? '';
          _registrationNumberController.text =
              data['businessRegistrationNumber'] as String? ?? '';
          _businessAddressController.text =
              data['businessAddress'] as String? ?? '';
        });
      }
    } catch (_) {
      // Load failed — allow form to be filled from scratch
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider).asData?.value;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final isBusiness = _accountType == 'business';
      await FirebaseFirestore.instance.collection('artisans').doc(user.uid).update({
        'accountType': _accountType,
        'businessName': isBusiness ? _businessNameController.text.trim() : null,
        'businessRegistrationNumber':
            isBusiness ? _registrationNumberController.text.trim() : null,
        'businessAddress':
            isBusiness ? _businessAddressController.text.trim() : null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Business profile saved.'),
            backgroundColor: context.colors.accent,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed to save business profile: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isBusiness = _accountType == 'business';

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        title: const Text(
          'Business Profile',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.colors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: context.colors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_outlined,
                          color: context.colors.primary, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Operating as a business? Customers will see your business name instead of your personal name.',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.textSecondary,
                            fontFamily: 'Inter',
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'individual',
                      label: Text('Individual'),
                      icon: Icon(Icons.person_outline, size: 18),
                    ),
                    ButtonSegment(
                      value: 'business',
                      label: Text('Business'),
                      icon: Icon(Icons.storefront_outlined, size: 18),
                    ),
                  ],
                  selected: {_accountType},
                  onSelectionChanged: (s) =>
                      setState(() => _accountType = s.first),
                ),
                const SizedBox(height: 24),

                if (isBusiness) ...[
                  TextFormField(
                    controller: _businessNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Business Name',
                      hintText: 'e.g. Lekki Plumbing Services Ltd',
                      prefixIcon: const Icon(Icons.business_outlined),
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
                      if (!isBusiness) return null;
                      if (v == null || v.trim().length < 2) {
                        return 'Enter your business name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _registrationNumberController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Business Registration Number',
                      hintText: 'e.g. RC1234567 (CAC number)',
                      prefixIcon: const Icon(Icons.badge_outlined),
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
                      if (!isBusiness) return null;
                      if (v == null || v.trim().length < 4) {
                        return 'Enter a valid registration number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _businessAddressController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Business Address',
                      hintText: 'Registered office or shop address',
                      prefixIcon: const Icon(Icons.location_on_outlined),
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
                      if (!isBusiness) return null;
                      if (v == null || v.trim().length < 5) {
                        return 'Enter your business address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Save Business Profile',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Inter',
                          ),
                        ),
                ),
                // Stage 6 (policy D8): service area for distance-first
                // matching — saved independently of the business form.
                const SizedBox(height: 24),
                Consumer(builder: (context, ref, _) {
                  final uid = ref.watch(currentUserProvider).asData?.value?.uid;
                  final artisan = uid == null ? null : ref.watch(artisanProfileProvider(uid)).asData?.value;
                  return artisan == null ? const SizedBox.shrink() : ServiceAreaCard(artisan: artisan);
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
