import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/artisan_profile_service.dart';
import '../../../models/artisan_model.dart';
import '../../../providers/platform_config_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';

/// AR-06 Business profile (`/business-profile`): individual / business
/// details and the service area used for job matching.
class BusinessProfileScreen extends ConsumerStatefulWidget {
  const BusinessProfileScreen({super.key});
  @override
  ConsumerState<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _reg = TextEditingController();
  final _address = TextEditingController();
  final _serviceAddress = TextEditingController();
  bool _business = false;
  bool _seeded = false;
  bool _saving = false;
  bool _savingArea = false;
  bool _locating = false;
  double? _lat;
  double? _lng;
  double? _radius;

  @override
  void dispose() {
    _name.dispose();
    _reg.dispose();
    _address.dispose();
    _serviceAddress.dispose();
    super.dispose();
  }

  void _seed(ArtisanModel a) {
    if (_seeded) return;
    _seeded = true;
    _business = a.accountType == 'business';
    _name.text = a.businessName ?? '';
    _reg.text = a.businessRegistrationNumber ?? '';
    _address.text = a.businessAddress ?? '';
    _serviceAddress.text = a.serviceAddress ?? '';
    _lat = a.latitude;
    _lng = a.longitude;
    _radius = a.serviceRadiusKm;
  }

  Future<void> _saveBusiness(String uid) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(artisanProfileServiceProvider).saveBusinessProfile(uid, isBusiness: _business, businessName: _name.text, registrationNumber: _reg.text, businessAddress: _address.text);
      if (!mounted) return;
      htSnack(context, 'Business profile saved.');
      if (context.canPop()) context.pop();
    } catch (_) {
      if (mounted) htSnack(context, 'Could not save your business profile. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) htSnack(context, 'Turn on location services, then try again.', error: true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) htSnack(context, 'Location permission is needed to set your service area.', error: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
        });
      }
    } catch (_) {
      if (mounted) htSnack(context, 'Could not get your location. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _saveArea(String uid, PlatformConfig cfg) async {
    if (_lat == null || _lng == null) {
      htSnack(context, 'Tap “Use my location” first.', error: true);
      return;
    }
    final radius = (_radius ?? cfg.defaultServiceRadiusKm).clamp(1, cfg.maxServiceRadiusKm).toDouble();
    setState(() => _savingArea = true);
    try {
      await ref.read(artisanProfileServiceProvider).saveServiceArea(uid, lat: _lat!, lng: _lng!, address: _serviceAddress.text, radiusKm: radius);
      if (mounted) htSnack(context, 'Service area saved.');
    } catch (_) {
      if (mounted) htSnack(context, 'Could not save your service area.', error: true);
    } finally {
      if (mounted) setState(() => _savingArea = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final ctx = ref.watch(artisanContextProvider).asData?.value;
    final a = ctx?.artisan;
    if (ctx == null || a == null) return const ArtisanPage(title: 'Business profile', children: [SizedBox(height: 80), HtLoadingView()]);
    _seed(a);
    final cfg = ref.watch(platformConfigProvider);
    final radii = <double>{5, 10, 15, 25, cfg.defaultServiceRadiusKm}.where((r) => r <= cfg.maxServiceRadiusKm).toList()..sort();
    final selectedRadius = _radius ?? cfg.defaultServiceRadiusKm;

    return ArtisanPage(
      title: 'Business profile',
      bottomBar: ProActionBar(label: 'Save business details', loading: _saving, onPressed: _saving ? null : () => _saveBusiness(ctx.uid)),
      children: [
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ProSegments(labels: const ['Individual', 'Business'], selected: _business ? 1 : 0, onSelected: (i) => setState(() => _business = i == 1)),
            if (_business) ...[
              HtTextField(label: 'Business name', controller: _name, hint: 'Shown to customers instead of your personal name', validator: (v) => _business && (v == null || v.trim().isEmpty) ? 'Enter the business name' : null),
              HtTextField(label: 'Business registration number (optional)', controller: _reg, hint: 'e.g. RC 1234567'),
              HtTextField(label: 'Business address (optional)', controller: _address, hint: 'Registered office or shop address'),
            ] else
              Padding(padding: const EdgeInsets.only(top: 14), child: Text('Customers see your personal name. Switch to Business to show a registered business name.', style: HtType.small(p.textSecondary))),
          ]),
        ),
        const ProSection('Service area'),
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.my_location_rounded, color: proAccent(p), size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_lat == null ? 'Location not set' : 'Location captured', style: HtType.bodyStrong(p.textPrimary))),
              HtSecondaryButton(label: _locating ? 'Locating…' : 'Use my location', dense: true, height: 36, onPressed: _locating ? null : _locate),
            ]),
            HtTextField(label: 'Area name (shown on your profile)', controller: _serviceAddress, hint: 'e.g. Bodija, Ibadan'),
            const HtFieldLabel('Matching radius'),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final r in radii) HtChip(label: '${r.round()} km', selected: selectedRadius == r, onTap: () => setState(() => _radius = r))]),
            const SizedBox(height: 14),
            HtPrimaryButton(label: 'Save service area', loading: _savingArea, height: 46, onPressed: _savingArea ? null : () => _saveArea(ctx.uid, cfg)),
            const SizedBox(height: 8),
            Text('Your location is captured only when you tap the button — never in the background.', style: HtType.small(p.textMuted)),
          ]),
        ),
      ],
    );
  }
}
