import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:handy_trust/models/portfolio_project_model.dart';
import 'package:handy_trust/screens/artisan/portfolio_project_screen.dart';
import 'package:handy_trust/widgets/cannot_open_directly_screen.dart';

/// Regression test for P0-4 (design/FULL_PRODUCTION_QA_AUDIT.md) /
/// design/P0_REMEDIATION_PLAN.md §5: `/portfolio-project` crashed on any
/// direct/deep navigation (Flutter Web browser refresh, typed/bookmarked
/// URL, back/forward history restore) because `state.extra` is null in
/// those cases and the route builder did a non-nullable `as String` cast
/// on `extra['artisanId']`.
///
/// This repo has no GoRouter-specific test harness for the real app router
/// (which needs Firebase/Riverpod bootstrap) — see
/// test/admin_exit_navigation_test.dart's header comment for the same
/// disclosure. This route's builder needs neither, so it's tested here in
/// an isolated `GoRouter` containing only this one route, mirroring the
/// exact fixed builder logic in lib/routes/router.dart.
GoRouter _buildTestRouter(String initialLocation, {Object? extra}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/portfolio-project',
        builder: (context, state) {
          final e = state.extra as Map<String, dynamic>? ?? {};
          final artisanId = e['artisanId'] as String?;
          if (artisanId == null) {
            return const CannotOpenDirectlyScreen(returnPath: '/portfolio');
          }
          return PortfolioProjectScreen(
            artisanId: artisanId,
            existing: e['existing'] as PortfolioProjectModel?,
          );
        },
      ),
      GoRoute(
        path: '/portfolio',
        builder: (context, state) => const Scaffold(body: Text('Portfolio Manager')),
      ),
    ],
  );
}

Widget _wrap(GoRouter router) => ProviderScope(
      child: MaterialApp.router(routerConfig: router),
    );

void main() {
  testWidgets(
    'direct navigation to /portfolio-project with no extra does not crash '
    'and shows the graceful fallback (P0-4 repro)',
    (tester) async {
      final router = _buildTestRouter('/portfolio-project');
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'this is exactly what threw '
              '"type \'Null\' is not a subtype of type \'String\'" before the fix');
      expect(find.byType(CannotOpenDirectlyScreen), findsOneWidget);
      expect(find.text("This page can't be opened directly"), findsOneWidget);
    },
  );

  testWidgets(
    'navigation with extra: {artisanId} renders create mode',
    (tester) async {
      final router = _buildTestRouter(
        '/portfolio-project',
        extra: {'artisanId': 'artisan-uid-123'},
      );
      // GoRouter's initialLocation doesn't carry `extra`, so push it
      // explicitly the way the real call sites do (context.push(..., extra: {...})).
      router.go('/portfolio-project', extra: {'artisanId': 'artisan-uid-123'});
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final screen = tester.widget<PortfolioProjectScreen>(find.byType(PortfolioProjectScreen));
      expect(screen.artisanId, 'artisan-uid-123');
      expect(screen.existing, isNull);
      expect(find.text('Add Project'), findsOneWidget);
    },
  );

  testWidgets(
    'navigation with extra: {artisanId, existing} renders edit mode with fields pre-filled',
    (tester) async {
      final existing = PortfolioProjectModel(
        id: 'proj1',
        artisanId: 'artisan-uid-123',
        title: 'Kitchen Renovation',
        description: 'Full kitchen remodel',
        category: 'Carpentry',
        createdAt: DateTime(2025, 1, 1),
      );
      final router = _buildTestRouter('/portfolio-project');
      router.go('/portfolio-project', extra: {
        'artisanId': 'artisan-uid-123',
        'existing': existing,
      });
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final screen = tester.widget<PortfolioProjectScreen>(find.byType(PortfolioProjectScreen));
      expect(screen.artisanId, 'artisan-uid-123');
      expect(screen.existing?.title, 'Kitchen Renovation');
      expect(find.text('Edit Project'), findsOneWidget);
      expect(find.text('Kitchen Renovation'), findsOneWidget);
    },
  );
}
