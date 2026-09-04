import 'package:canting/state/app_state.dart';
import 'package:canting/ui/history/history_page.dart';
import 'package:canting/ui/home/home_page.dart';
import 'package:canting/ui/manual_add/manual_add_page.dart';
import 'package:canting/ui/onboarding/onboarding_page.dart';
import 'package:canting/ui/recommendation/recommendation_detail_page.dart';
import 'package:canting/ui/record/record_detail_page.dart';
import 'package:canting/ui/settings/pet_settings.dart';
import 'package:canting/ui/settings/settings_page.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRouter {
  static GoRouter create(AppState appState) => GoRouter(
    initialLocation: appState.onboardingComplete ? '/home' : '/onboarding',
    refreshListenable: appState,
    redirect: (context, state) {
      final inOnboarding = state.uri.path == '/onboarding';
      final isSharedRecognition =
          state.uri.path == '/record_detail' &&
          state.uri.queryParameters['source'] == 'share';
      if (!appState.onboardingComplete &&
          !inOnboarding &&
          !isSharedRecognition) {
        return '/onboarding';
      }
      if (appState.onboardingComplete && inOnboarding) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            _AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomePage()),
          ),
          GoRoute(
            path: '/history',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HistoryPage()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsPage()),
          ),
        ],
      ),
      GoRoute(
        path: '/settings/pet',
        builder: (context, state) => const PetSettingsPage(),
      ),
      GoRoute(
        path: '/record_detail',
        builder: (context, state) => RecordDetailPage(
          mealId: state.uri.queryParameters['mealId'],
          initialDate: DateTime.tryParse(
            state.uri.queryParameters['date'] ?? '',
          ),
          isSharedRecognition: state.uri.queryParameters['source'] == 'share',
        ),
      ),
      GoRoute(
        path: '/manual_add',
        builder: (context, state) => const ManualAddPage(),
      ),
      GoRoute(
        path: '/recommendation',
        builder: (context, state) => const RecommendationDetailPage(),
      ),
    ],
  );
}

class _AppShell extends StatelessWidget {
  const _AppShell({required this.location, required this.child});

  final String location;
  final Widget child;

  int get _currentIndex {
    if (location.startsWith('/history')) return 1;
    if (location.startsWith('/settings')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border(top: BorderSide(color: scheme.outline, width: 2)),
          boxShadow: [
            BoxShadow(
              color: scheme.outline.withValues(alpha: 0.32),
              offset: const Offset(0, -3),
              blurRadius: 0,
            ),
          ],
        ),
        child: PixelContentWidth(
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              switch (index) {
                case 0:
                  context.go('/home');
                case 1:
                  context.go('/history');
                case 2:
                  context.go('/settings');
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '今日',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: '记录',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '我的',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
