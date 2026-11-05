import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/service_categories.dart';
import '../../models/artisan_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';
import 'customer_shell.dart';

/// Discovery (references 8/9 dark, 15 light). Data: featuredArtisansProvider
/// (approved + ID-verified artisans, highest rated). Category chips and the
/// search field filter that real list on the device.
class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  String? _category;
  String _query = '';
  bool _showAll = false;

  static const _icons = <String, IconData>{
    'Plumbing': Icons.plumbing_rounded,
    'Electrical': Icons.bolt_rounded,
    'Carpentry': Icons.carpenter_rounded,
    'Painting': Icons.format_paint_outlined,
    'Cleaning': Icons.cleaning_services_outlined,
    'HVAC / AC Repair': Icons.ac_unit_rounded,
    'Welding': Icons.local_fire_department_outlined,
    'Tiling': Icons.grid_view_rounded,
    'Generator Repair': Icons.electrical_services_rounded,
    'Home Renovation': Icons.home_repair_service_outlined,
    'Security Systems': Icons.security_rounded,
    'Landscaping': Icons.grass_rounded,
    'Other': Icons.handyman_outlined,
  };

  List<ArtisanModel> _filter(List<ArtisanModel> all) {
    final q = _query.trim().toLowerCase();
    return all.where((a) {
      if (_category != null && a.category != _category) return false;
      if (q.isEmpty) return true;
      return [a.name, a.category ?? '', a.skills, a.businessName ?? ''].any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final user = ref.watch(currentUserProvider).asData?.value;
    final unread = ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    final artisans = ref.watch(featuredArtisansProvider);

    return HtBackground(
      deep: true,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header(context, user?.name, unread)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 18, HtSpace.gutter, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.isDark) ...[
                      const HtStatusPill(label: 'ESCROW-PROTECTED PAYMENTS', tone: HtTone.success, dot: true),
                      const SizedBox(height: 14),
                    ],
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Find '),
                        TextSpan(text: 'Trusted Experts', style: TextStyle(color: p.isDark ? p.accent : p.accentStrong)),
                        const TextSpan(text: ' for Your Home'),
                      ]),
                      style: HtType.hero(p.textPrimary).copyWith(fontSize: 29),
                    ),
                    if (!p.isDark) ...[
                      const SizedBox(height: 6),
                      Text('Escrow-backed artisan network in Nigeria', style: HtType.body(p.textSecondary).copyWith(fontSize: 12)),
                    ],
                    const SizedBox(height: 18),
                    _SearchField(onChanged: (v) => setState(() => _query = v)),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 16, HtSpace.gutter, 8),
                  itemCount: ServiceCategories.all.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final c = ServiceCategories.all[i];
                    return HtChip(
                      label: c,
                      icon: _icons[c],
                      selected: _category == c,
                      onTap: () => setState(() => _category = _category == c ? null : c),
                    );
                  },
                ),
              ),
            ),
            ...artisans.when(
              loading: () => [const SliverToBoxAdapter(child: HtLoadingView(label: 'Finding verified artisans…'))],
              error: (e, _) => [
                SliverToBoxAdapter(
                  child: HtErrorView(
                    message: 'Artisans could not be loaded. Check your connection.',
                    onRetry: () => ref.invalidate(featuredArtisansProvider),
                  ),
                ),
              ],
              data: (all) {
                final list = _filter(all);
                final shown = _showAll ? list : list.take(3).toList();
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 14, HtSpace.gutter, 14),
                      child: HtSectionHeader(
                        title: 'Featured Experts',
                        badge: p.isDark ? '${list.length} Available' : 'Top Rated',
                        trailing: list.length > 3 ? (_showAll ? 'Show less' : 'See all') : null,
                        onTrailing: list.length > 3 ? () => setState(() => _showAll = !_showAll) : null,
                      ),
                    ),
                  ),
                  if (list.isEmpty)
                    SliverToBoxAdapter(
                      child: HtEmptyView(
                        icon: Icons.person_search_outlined,
                        title: _category == null && _query.isEmpty ? 'No verified artisans yet' : 'No matching artisans',
                        message: 'Only ID-verified artisans approved by HandyTrust are featured here.',
                      ),
                    )
                  else
                    SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter),
                        child: ArtisanDiscoveryCard(artisan: shown[i]),
                      ),
                    ),
                ];
              },
            ),
            if (!p.isDark)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(HtSpace.gutter, 20, HtSpace.gutter, 0),
                  child: HtInfoBanner(
                    icon: Icons.verified_user_outlined,
                    title: 'Funds held securely in Escrow',
                    text: 'Released only when you approve the completed job',
                    tone: HtTone.neutral,
                    trailing: Icon(Icons.lock_outline_rounded, size: 20),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: CustomerShell.bottomInset)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String? name, int unread) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 10, HtSpace.gutter, 0),
      child: Row(
        children: [
          HtIconCircle(
            icon: Icons.handyman_outlined,
            square: true,
            size: 42,
            fill: p.isDark ? p.surface : p.surface,
            iconColor: p.isDark ? p.accent : p.accentStrong,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: p.isDark ? 'Handy ' : 'Handy'),
                    TextSpan(text: 'Trust', style: TextStyle(color: p.isDark ? p.accent : p.textPrimary)),
                  ]),
                  style: HtType.brand(p.textPrimary),
                ),
                if (p.isDark) Text('NIGERIA ESCROW', style: HtType.caps(p.textSecondary).copyWith(fontSize: 9.5)),
              ],
            ),
          ),
          HtIconCircle(
            icon: Icons.notifications_none_rounded,
            badge: unread > 0,
            tooltip: unread > 0 ? '$unread unread notifications' : 'Notifications',
            onTap: () => context.push('/notifications'),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => ref.read(customerTabProvider.notifier).state = CustomerTab.profile,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle, border: Border.all(color: p.border), boxShadow: p.cardShadow),
              child: Text(HtFormat.initials(name).substring(0, 1), style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: p.isDark ? p.surface : p.surface,
        borderRadius: BorderRadius.circular(HtRadius.pill),
        border: Border.all(color: p.border),
        boxShadow: p.isDark ? [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))] : p.cardShadow,
      ),
      padding: const EdgeInsets.only(left: 18, right: 8),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: p.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: HtType.body(p.textPrimary),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search electricians, plumbers, painters…',
                hintStyle: HtType.body(p.textSecondary).copyWith(fontSize: 13),
              ),
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: p.surfaceRaised, shape: BoxShape.circle),
            child: Icon(Icons.tune_rounded, size: 20, color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Artisan card (references 8/9/15). Price ("From ₦…") is omitted: the
/// backend stores no artisan rates.
class ArtisanDiscoveryCard extends StatelessWidget {
  const ArtisanDiscoveryCard({super.key, required this.artisan});
  final ArtisanModel artisan;

  static bool isIdVerified(ArtisanModel a) => a.verificationStatus == 'id_verified' || a.verificationStatus == 'trusted';

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final area = HtFormat.area(artisan.serviceAddress);
    final meta = [artisan.category ?? 'Artisan', ?area].join(' • ');
    return HtCard(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      onTap: () => context.push('/artisan/${artisan.uid}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HtAvatar(name: artisan.name, imageUrl: artisan.profileImageUrl, size: 48, online: artisan.isAvailable),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(artisan.displayName, style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 16.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(child: Text(meta, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isIdVerified(artisan)) ...[const SizedBox(width: 8), const HtVerifiedBadge()],
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.pill)),
            child: Row(
              children: [
                Icon(Icons.star_rounded, size: 18, color: p.isDark ? p.accent : p.accentStrong),
                const SizedBox(width: 4),
                Text(artisan.totalRatings > 0 ? artisan.rating.toStringAsFixed(1) : 'New', style: HtType.smallStrong(p.textPrimary).copyWith(fontSize: 12)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('•', style: HtType.small(p.textMuted))),
                Expanded(
                  child: Text('${artisan.completedJobs} jobs completed',
                      style: HtType.small(p.textSecondary).copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Icon(Icons.shield_outlined, size: 17, color: p.success),
                const SizedBox(width: 4),
                Text('Escrow', style: HtType.smallStrong(p.success)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: HtSmallPrimaryButton(label: 'View', icon: p.isDark ? null : Icons.arrow_forward_rounded, onPressed: () => context.push('/artisan/${artisan.uid}')),
          ),
        ],
      ),
    );
  }
}
