import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/artisan_model.dart';
import '../../models/user_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/notification_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';
import 'components/pro_components.dart';
import 'screens/artisan_home_screen.dart';
import 'screens/artisan_profile_screen.dart';
import 'screens/earnings_screen.dart';
import 'screens/find_work_screen.dart';
import 'screens/my_jobs_screen.dart';

/// Artisan tabs (approved D-2): Home · Find Work · My Jobs · Earnings · Profile.
enum ArtisanTab { home, findWork, myJobs, earnings, profile }

final artisanTabProvider = StateProvider<ArtisanTab>((ref) => ArtisanTab.home);

/// The artisan experience root (`/home` in Artisan Mode; `/open-jobs`,
/// `/jobs`, `/wallet` and `/profile` open it on the matching tab).
class ArtisanShell extends ConsumerStatefulWidget {
  const ArtisanShell({super.key, this.initialTab});
  final ArtisanTab? initialTab;

  @override
  ConsumerState<ArtisanShell> createState() => _ArtisanShellState();
}

class _ArtisanShellState extends ConsumerState<ArtisanShell> {
  late ArtisanTab _tab;

  @override
  void initState() {
    super.initState();
    // The route's tab wins on entry; otherwise keep the last-used tab.
    _tab = widget.initialTab ?? ref.read(artisanTabProvider);
    if (widget.initialTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(artisanTabProvider.notifier).state = _tab;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    // Other artisan screens switch tabs through the provider (e.g. Home's
    // "My Jobs" link).
    ref.listen(artisanTabProvider, (_, next) {
      if (next != _tab) setState(() => _tab = next);
    });
    final tab = _tab;
    return Scaffold(
      backgroundColor: p.background,
      bottomNavigationBar: ProNavBar(
        current: tab.index,
        onTap: (i) {
          setState(() => _tab = ArtisanTab.values[i]);
          ref.read(artisanTabProvider.notifier).state = _tab;
        },
      ),
      body: HtBackground(
        glow: false,
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: tab.index,
            children: const [ArtisanHomeScreen(), FindWorkScreen(), MyJobsScreen(), EarningsScreen(), ArtisanProProfileScreen()],
          ),
        ),
      ),
    );
  }
}

/// The signed-in artisan: user profile + public artisan document.
class ArtisanContext {
  const ArtisanContext(this.user, this.artisan);
  final UserModel user;
  final ArtisanModel? artisan;
  String get uid => user.uid;
  String get name => artisan?.displayName ?? user.name;
  String get trade {
    final cat = artisan?.category ?? user.category;
    final area = HtFormat.area(artisan?.serviceAddress) ?? user.location;
    return [if (cat != null && cat.isNotEmpty) cat, if (area != null && area.isNotEmpty) area].join(' · ');
  }
}

final artisanContextProvider = Provider<AsyncValue<ArtisanContext?>>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (user) {
      if (user == null) return const AsyncValue.data(null);
      final artisanAsync = ref.watch(artisanProfileProvider(user.uid));
      return artisanAsync.when(
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
        data: (a) => AsyncValue.data(ArtisanContext(user, a)),
      );
    },
  );
});

/// Header for every artisan tab, with live unread counts.
class ArtisanTabHeader extends ConsumerWidget {
  const ArtisanTabHeader({super.key, this.title});
  final String? title;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = ref.watch(artisanContextProvider).asData?.value;
    if (ctx == null) return const SizedBox(height: 64);
    // Stage 8.2: artisan-side conversations only (role-separated).
    final messages = ref.watch(unreadMessagesTotalProvider((uid: ctx.uid, asArtisan: true)));
    final alerts = ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    return ProHeader(
      name: ctx.name,
      title: title,
      imageUrl: ctx.artisan?.profileImageUrl ?? ctx.user.photoUrl,
      trade: ctx.trade.isEmpty ? 'Artisan' : ctx.trade,
      available: ctx.artisan?.isAvailable ?? false,
      messages: messages,
      alerts: alerts,
      onMessages: () => context.push('/my-chats'),
      onAlerts: () => context.push('/notifications'),
    );
  }
}

/// Body of an artisan tab: header + scrolling content above the work bar.
class ArtisanTabBody extends ConsumerWidget {
  const ArtisanTabBody({super.key, required this.children, this.title, this.onRefresh});
  final List<Widget> children;
  final String? title;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 4, HtSpace.gutter, 28),
      children: children,
    );
    return Column(children: [
      ArtisanTabHeader(title: title),
      Expanded(child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list)),
    ]);
  }
}

/// Full-screen artisan page (pushed routes): back header, content, optional
/// sticky bottom bar.
class ArtisanPage extends StatelessWidget {
  const ArtisanPage({super.key, required this.title, required this.children, this.sub, this.onChat, this.bottomBar, this.padding});
  final String title;
  final String? sub;
  final VoidCallback? onChat;
  final List<Widget> children;
  final Widget? bottomBar;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Scaffold(
      backgroundColor: p.background,
      bottomNavigationBar: bottomBar,
      body: HtBackground(
        glow: false,
        child: SafeArea(
          bottom: bottomBar == null,
          child: Column(children: [
            ProBackHeader(title: title, sub: sub, onChat: onChat),
            Expanded(child: ListView(padding: padding ?? const EdgeInsets.fromLTRB(HtSpace.gutter, 4, HtSpace.gutter, 28), children: children)),
          ]),
        ),
      ),
    );
  }
}

/// Loading / error / empty frames shared by artisan screens.
class ArtisanState extends StatelessWidget {
  const ArtisanState.loading({super.key, this.label = 'Loading…'}) : error = null, onRetry = null;
  const ArtisanState.error(this.error, {super.key, this.onRetry}) : label = null;
  final String? label;
  final Object? error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return HtCard(child: HtErrorView(message: 'We couldn’t load this. Check your connection and try again.', onRetry: onRetry));
    }
    return HtLoadingView(label: label);
  }
}
