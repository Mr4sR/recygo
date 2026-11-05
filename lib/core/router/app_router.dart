import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/env.dart';
import '../widgets/misc_pages.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/profile_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/community/presentation/community_feed_page.dart';
import '../../features/community/presentation/listing_detail_page.dart';
import '../../features/community/presentation/publish_page.dart';
import '../../features/fuse/presentation/fuse_result_page.dart';
import '../../features/fuse/presentation/fuse_select_page.dart';
import '../../features/inventory/presentation/home_page.dart';
import '../../features/inventory/presentation/inventory_page.dart';
import '../../features/inventory/presentation/item_detail_page.dart';
import '../../features/inventory/presentation/item_form_page.dart';
import '../../features/map_explore/presentation/explore_map_page.dart';
import '../../features/segment/presentation/segment_review_page.dart';
import '../../features/shell/presentation/main_shell.dart';
import '../../features/shell/presentation/splash_onboarding.dart';
import '../../features/wastebank/presentation/wastebank_pages.dart';

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, _, child) {
      final disable = MediaQuery.of(context).disableAnimations;
      if (disable) return child;
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
          child: child,
        ),
      );
    },
  );
}

GoRouter createRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      if (!Env.isConfigured && !Env.demoMode) {
        return state.matchedLocation == '/config-error'
            ? null
            : '/config-error';
      }
      final loggedIn = ref.read(authControllerProvider).isLoggedIn;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' || loc == '/register';
      final isPublic = isAuthRoute || loc == '/splash' || loc == '/onboarding';
      if (!loggedIn && !isPublic) return '/login';
      if (loggedIn && isAuthRoute) return '/home';
      return null;
    },
    errorBuilder: (_, _) => const NotFoundPage(),
    routes: [
      GoRoute(
        path: '/config-error',
        pageBuilder: (_, s) => _fadePage(s, const ConfigErrorPage()),
      ),
      GoRoute(
        path: '/splash',
        pageBuilder: (_, s) => _fadePage(s, const SplashPage()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, s) => _fadePage(s, const OnboardingPage()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, s) => _fadePage(s, const LoginPage()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, s) => _fadePage(s, const RegisterPage()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (_, s) => _fadePage(s, const HomePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/items',
                pageBuilder: (_, s) => _fadePage(s, const InventoryPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/fuse',
                pageBuilder: (_, s) => _fadePage(s, const FuseSelectPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/community',
                pageBuilder: (_, s) => _fadePage(
                  s,
                  CommunityFeedPage(
                    initialQuery: s.uri.queryParameters['q'],
                    initialCategory: s.uri.queryParameters['category'],
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                pageBuilder: (_, s) => _fadePage(s, const ExploreMapPage()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/items/new',
        pageBuilder: (_, s) => _fadePage(
          s,
          ItemFormPage(startScan: s.uri.queryParameters['scan'] == '1'),
        ),
      ),
      GoRoute(
        path: '/items/bulk-review',
        pageBuilder: (_, s) => _fadePage(s, const SegmentReviewPage()),
      ),
      GoRoute(
        path: '/items/:id',
        pageBuilder: (_, s) =>
            _fadePage(s, ItemDetailPage(itemId: s.pathParameters['id']!)),
        routes: [
          GoRoute(
            path: 'edit',
            pageBuilder: (_, s) =>
                _fadePage(s, ItemFormPage(itemId: s.pathParameters['id'])),
          ),
        ],
      ),
      GoRoute(
        path: '/fuse/result/:recipeId',
        pageBuilder: (_, s) => _fadePage(
          s,
          FuseResultPage(recipeId: s.pathParameters['recipeId']!),
        ),
      ),
      GoRoute(
        path: '/community/:listingId',
        pageBuilder: (_, s) => _fadePage(
          s,
          ListingDetailPage(listingId: s.pathParameters['listingId']!),
        ),
      ),
      GoRoute(
        path: '/publish/:itemId',
        pageBuilder: (_, s) =>
            _fadePage(s, PublishPage(itemId: s.pathParameters['itemId']!)),
      ),
      GoRoute(
        path: '/waste-banks',
        pageBuilder: (_, s) => _fadePage(s, const WasteBankListPage()),
      ),
      GoRoute(
        path: '/waste-banks/:id',
        pageBuilder: (_, s) =>
            _fadePage(s, WasteBankDetailPage(bankId: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (_, s) => _fadePage(s, const ProfilePage()),
      ),
      GoRoute(
        path: '/profile/edit',
        pageBuilder: (_, s) => _fadePage(s, const ProfileEditPage()),
      ),
    ],
  );
}

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) => createRouter(ref));
