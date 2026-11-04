import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/safe_firestore.dart';
import '../../models/artisan_model.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';

final _browseArtisansProvider = StreamProvider.autoDispose<List<ArtisanModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('artisans')
        .where('approvalStatus', isEqualTo: 'approved')
        .limit(300),
    (d) => ArtisanModel.fromJson({...d.data(), 'uid': d.id}),
    debugLabel: 'browseArtisans',
  );
});

const _kCategories = [
  'All', 'Plumbing', 'Electrical', 'Cleaning', 'Carpentry',
  'Painting', 'Welding', 'Tiling', 'Generator',
];

class BrowseArtisansScreen extends ConsumerStatefulWidget {
  const BrowseArtisansScreen({super.key});

  @override
  ConsumerState<BrowseArtisansScreen> createState() => _BrowseArtisansScreenState();
}

class _BrowseArtisansScreenState extends ConsumerState<BrowseArtisansScreen> {
  String _search = '';
  String _category = 'All';
  String _verificationFilter = 'all';
  String _sortBy = 'rating';

  List<ArtisanModel> _applyFilters(List<ArtisanModel> artisans) {
    final q = _search.toLowerCase();
    var filtered = artisans.where((a) {
      final matchSearch = q.isEmpty ||
          a.name.toLowerCase().contains(q) ||
          (a.category?.toLowerCase().contains(q) ?? false) ||
          a.skills.toLowerCase().contains(q) ||
          (a.username?.toLowerCase().contains(q) ?? false);
      final matchCategory = _category == 'All' || a.category == _category;
      final matchVerif = _verificationFilter == 'all' ||
          (_verificationFilter == 'verified' && a.verificationStatus == 'id_verified') ||
          (_verificationFilter == 'trusted' && a.verificationStatus == 'trusted');
      return matchSearch && matchCategory && matchVerif;
    }).toList();

    switch (_sortBy) {
      case 'rating':
        filtered.sort((a, b) => b.rating.compareTo(a.rating));
      case 'jobs':
        filtered.sort((a, b) => b.completedJobs.compareTo(a.completedJobs));
      case 'trust':
        filtered.sort((a, b) => b.trustScore.compareTo(a.trustScore));
      case 'newest':
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final artisansAsync = ref.watch(_browseArtisansProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text(
          'Browse Artisans',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        backgroundColor: context.colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: context.colors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: context.colors.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name, skill, or category...',
                    hintStyle: TextStyle(
                      color: context.colors.textTertiary,
                      fontSize: 14,
                      fontFamily: 'Inter',
                    ),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: context.colors.textTertiary),
                    filled: true,
                    fillColor: context.colors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _kCategories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final cat = _kCategories[i];
                      final selected = cat == _category;
                      return GestureDetector(
                        onTap: () => setState(() => _category = cat),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: selected
                                ? context.colors.primary
                                : context.colors.background,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color: selected
                                  ? context.colors.primary
                                  : context.colors.border,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : context.colors.textSecondary,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _DropdownFilter(
                        value: _verificationFilter,
                        items: const {
                          'all': 'Any Verification',
                          'verified': 'ID Verified',
                          'trusted': 'Trusted',
                        },
                        onChanged: (v) =>
                            setState(() => _verificationFilter = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DropdownFilter(
                        value: _sortBy,
                        items: const {
                          'rating': 'Sort: Rating',
                          'jobs': 'Sort: Jobs Done',
                          'trust': 'Sort: Trust Score',
                          'newest': 'Sort: Newest',
                        },
                        onChanged: (v) => setState(() => _sortBy = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: artisansAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: context.colors.primary),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Could not load artisans. Check your connection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),
              data: (artisans) {
                final filtered = _applyFilters(artisans);
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 56, color: context.colors.textTertiary),
                          const SizedBox(height: 12),
                          Text(
                            'No artisans found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textPrimary,
                              fontFamily: 'Inter',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try a different search or filter',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.textSecondary,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) =>
                      _ArtisanBrowseCard(artisan: filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownFilter extends StatelessWidget {
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  const _DropdownFilter({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
            fontFamily: 'Inter',
          ),
          dropdownColor: context.colors.surface,
          items: items.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _ArtisanBrowseCard extends StatelessWidget {
  final ArtisanModel artisan;

  const _ArtisanBrowseCard({required this.artisan});

  @override
  Widget build(BuildContext context) {
    final isVerified = artisan.verificationStatus == 'id_verified' ||
        artisan.verificationStatus == 'trusted';

    return GestureDetector(
      onTap: () => context.push('/artisan/${artisan.uid}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            UserAvatar(
              photoUrl: artisan.photoUrl ?? artisan.profileImageUrl,
              displayName: artisan.displayName,
              size: 52,
              borderWidth: 2,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          artisan.displayName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified_rounded,
                            size: 16, color: context.colors.primary),
                      ],
                    ],
                  ),
                  if (artisan.username != null &&
                      artisan.username!.isNotEmpty) ...[
                    Text(
                      '@${artisan.username}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.primary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                  Text(
                    artisan.category ?? 'General',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _stat(
                        context,
                        Icons.star_rounded,
                        artisan.rating.toStringAsFixed(1),
                        const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 12),
                      _stat(
                        context,
                        Icons.check_circle_outline_rounded,
                        '${artisan.completedJobs} jobs',
                        context.colors.accent,
                      ),
                      const SizedBox(width: 12),
                      _stat(
                        context,
                        Icons.shield_outlined,
                        '${artisan.trustScore.toStringAsFixed(0)}/100',
                        context.colors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: context.colors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: context.colors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}
