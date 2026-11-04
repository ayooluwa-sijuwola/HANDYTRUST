import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../core/utils/geo.dart';
import '../models/artisan_model.dart';
import '../providers/platform_config_provider.dart';
import '../theme/app_theme.dart';
import 'error_snackbar.dart';

/// Stage 6 (policy D8): the artisan's service area — GPS captured once, only
/// when they tap the button (no background tracking), a manually entered
/// service address, and a service radius bounded by backend config. Used for
/// distance-first matching and the nearby-jobs feed. Rules validate ranges.
class ServiceAreaCard extends ConsumerStatefulWidget {
  final ArtisanModel artisan;
  const ServiceAreaCard({super.key, required this.artisan});

  @override
  ConsumerState<ServiceAreaCard> createState() => _ServiceAreaCardState();
}

class _ServiceAreaCardState extends ConsumerState<ServiceAreaCard> {
  late final TextEditingController _addressCtrl;
  double? _lat;
  double? _lng;
  double? _radius;
  bool _locating = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.artisan;
    _addressCtrl = TextEditingController(text: a.serviceAddress ?? a.location ?? '');
    _lat = a.latitude;
    _lng = a.longitude;
    _radius = a.serviceRadiusKm;
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) showErrorSnackbar(context, 'Turn on location services, then try again.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) showErrorSnackbar(context, 'Location permission is needed to set your service area.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not get your location. Please try again.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save(PlatformConfig cfg) async {
    if (_lat == null || _lng == null) {
      showErrorSnackbar(context, 'Tap "Use my current location" first.');
      return;
    }
    final radius = (_radius ?? cfg.defaultServiceRadiusKm).clamp(1, cfg.maxServiceRadiusKm).toDouble();
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('artisans').doc(widget.artisan.uid).update({
        'latitude': _lat,
        'longitude': _lng,
        'serviceGeohash3': Geo.geohash(_lat!, _lng!, 3),
        'serviceGeohash4': Geo.geohash(_lat!, _lng!, 4),
        'serviceAddress': _addressCtrl.text.trim(),
        'serviceRadiusKm': radius,
        'serviceLocationUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service area saved.')));
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not save your service area.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(platformConfigProvider);
    final radii = <double>{5, 10, 15, 25, cfg.defaultServiceRadiusKm}
        .where((r) => r <= cfg.maxServiceRadiusKm)
        .toList()
      ..sort();
    final selected = _radius ?? cfg.defaultServiceRadiusKm;
    final small = TextStyle(fontSize: 12, color: context.colors.textSecondary, fontFamily: 'Inter', height: 1.4);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Service area',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.colors.textPrimary, fontFamily: 'Inter')),
          const SizedBox(height: 6),
          Text(
            'Used only to match you with nearby jobs and to show customers your general area. '
            'Your location is read once, when you tap the button below — never in the background.',
            style: small,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _locating ? null : _useCurrentLocation,
            icon: _locating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded, size: 18),
            label: Text(_lat == null ? 'Use my current location' : 'Location set — update it'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Service address (e.g. area, city)'),
          ),
          Text('How far will you travel?', style: small),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final r in radii)
                ChoiceChip(
                  label: Text('${r.toStringAsFixed(0)} km'),
                  selected: selected == r,
                  onSelected: (_) => setState(() => _radius = r),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : () => _save(cfg),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save service area'),
          ),
        ],
      ),
    );
  }
}
