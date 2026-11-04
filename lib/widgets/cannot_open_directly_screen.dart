import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Fallback shown when a route that requires in-app navigation `extra:`
/// data (a Dart object passed via [GoRouter.push]/[GoRouter.go]) is reached
/// some other way — a Flutter Web browser refresh, a typed/bookmarked URL,
/// or a back/forward history restore — where that `extra:` payload is
/// always null. Renders instead of letting the destination screen crash on
/// a missing required parameter (see design/P0_REMEDIATION_PLAN.md §5).
class CannotOpenDirectlyScreen extends StatelessWidget {
  final String returnPath;
  final String returnLabel;

  const CannotOpenDirectlyScreen({
    super.key,
    required this.returnPath,
    this.returnLabel = 'Go back',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_off_rounded,
                    size: 48, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                const Text(
                  "This page can't be opened directly",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please navigate here from within the app instead of using a direct link, refresh, or bookmark.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go(returnPath),
                  child: Text(returnLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
