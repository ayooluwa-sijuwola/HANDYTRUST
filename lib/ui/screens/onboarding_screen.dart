import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/onboarding_provider.dart';
import '../components/ht_components.dart';
import '../theme/ht_theme.dart';

/// Onboarding (references 13 dark, 14 light). Only slide 1 has a design and
/// copy, so it is a single screen — the reference's pager dots are not
/// shown (they would promise slides that do not exist). The light hero
/// photo is taken from reference 14 (assets/images/stitch/onboarding_hero.jpg)
/// until the original asset is supplied. Removed unsupported claims:
/// "NIN VERIFIED", "12,400+ Vetted Artisans", "milestone" release.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  Future<void> _go(BuildContext context, WidgetRef ref, String route) async {
    await ref.read(onboardingSeenProvider.notifier).markSeen();
    if (context.mounted) context.go(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final headline = Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'Hire Trusted Hands,\n'),
        TextSpan(text: 'Pay With Confidence.', style: TextStyle(color: p.isDark ? p.accent : p.accentStrong)),
      ]),
      style: HtType.hero(p.textPrimary).copyWith(fontSize: p.isDark ? 34 : 30, height: 1.12),
    );
    final subtitle = Text(
      'Every artisan is ID-verified and your money stays safe in escrow until the job is done.',
      style: HtType.body(p.textSecondary).copyWith(fontSize: 14.5, height: 1.5),
    );
    final actions = Column(
      children: [
        HtPrimaryButton(label: 'Get Started', height: 62, onPressed: () => _go(context, ref, '/register')),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => _go(context, ref, '/login'),
          child: Text('Skip', style: HtType.body(p.textPrimary).copyWith(fontSize: 14.5)),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: p.backgroundDeep,
      body: HtBackground(
        deep: true,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!p.isDark) ...[
                        const _HeroCard(),
                        const SizedBox(height: 36),
                        _LogoPill(),
                      ] else ...[
                        SizedBox(height: c.maxHeight * 0.34),
                        Row(
                          children: [
                            HtIconCircle(icon: Icons.verified_user_outlined, square: true, size: 44, iconColor: p.accent),
                            const SizedBox(width: 12),
                            Text.rich(
                              TextSpan(children: [const TextSpan(text: 'Handy'), TextSpan(text: 'Trust', style: TextStyle(color: p.accent))]),
                              style: HtType.brand(p.textPrimary).copyWith(fontSize: 20.5),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 28),
                      headline,
                      const SizedBox(height: 18),
                      subtitle,
                      const SizedBox(height: 40),
                      actions,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.pill), boxShadow: p.cardShadow, border: Border.all(color: p.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.build_outlined, size: 22, color: p.textPrimary),
          const SizedBox(width: 10),
          Text('HandyTrust', style: HtType.brand(p.textPrimary).copyWith(fontSize: 19)),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return AspectRatio(
      aspectRatio: 0.98,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Image.asset('assets/images/stitch/onboarding_hero.jpg', fit: BoxFit.cover, alignment: Alignment.topCenter),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))]),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: Color(0xFFE4ECC0), shape: BoxShape.circle),
                    child: Icon(Icons.verified_user_outlined, color: p.accentStrong),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Smart Escrow Vault', style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 16.5)),
                        Text('Funds released when you approve the work', style: HtType.small(p.textSecondary).copyWith(fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: p.surfaceRaised, shape: BoxShape.circle),
                    child: Icon(Icons.lock_outline_rounded, size: 20, color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
