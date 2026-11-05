import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/artisan_work_logic.dart';
import '../../providers/auth_provider.dart';
import '../../ui/artisan/artisan_shell.dart';
import '../../ui/screens/customer_shell.dart';

/// `/home`. Customers get the Stitch customer shell (Stage 8); Artisan Mode
/// gets the HandyTrust Pro artisan shell (Stage 8.1). Mode follows the
/// active role (F-11), so dual-role users see one role's work at a time.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).asData?.value;
    if (user != null && ArtisanWorkLogic.isArtisanMode(isArtisan: user.isArtisan, activeRole: user.activeRole)) {
      return const ArtisanShell();
    }
    return const CustomerShell();
  }
}
