import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/ht_bottom_nav.dart';
import '../theme/ht_theme.dart';
import 'bookings_screen.dart';
import 'discovery_screen.dart';
import 'payments_screen.dart';
import 'profile_screen.dart';

enum CustomerTab { discovery, bookings, wallet, profile }

/// Selected customer tab — shared so screens (e.g. Profile → My Jobs,
/// Discovery avatar → Profile) can switch tabs.
final customerTabProvider = StateProvider<CustomerTab>((ref) => CustomerTab.discovery);

/// Customer home (references: floating bottom nav Discovery · Bookings ·
/// Wallet · Profile). Tabs stay alive in an IndexedStack.
class CustomerShell extends ConsumerWidget {
  const CustomerShell({super.key});

  /// Bottom padding screens add so content scrolls clear of the floating nav.
  static const double bottomInset = 104;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(customerTabProvider);
    return Scaffold(
      backgroundColor: context.ht.background,
      extendBody: true,
      body: IndexedStack(
        index: tab.index,
        children: const [DiscoveryScreen(), BookingsScreen(), PaymentsScreen(), ProfileScreen()],
      ),
      bottomNavigationBar: HtBottomNav(
        items: HtBottomNav.customerItems,
        current: tab.index,
        onTap: (i) => ref.read(customerTabProvider.notifier).state = CustomerTab.values[i],
      ),
    );
  }
}
