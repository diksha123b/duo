import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/models.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_screens.dart';
import 'features/game/game_screen.dart';
import 'features/history/history_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/interests_screen.dart';
import 'features/pairing/pairing_screen.dart';
import 'ui/states.dart';

/// Where a user belongs given their auth state. Routes not listed for a
/// state redirect to its home; this is the only navigation guard.
///
/// While the session restores, users wait on the splash with the page they
/// asked for in `from`, so a refresh on /game comes back to /game.
String? redirectFor(AsyncValue auth, String location, {String? from}) {
  final restoring = (auth.isLoading || auth.hasError) && !auth.hasValue;
  if (restoring) {
    if (location == '/splash') return null;
    return Uri(path: '/splash', queryParameters: {'from': location}).toString();
  }

  final wanted = location == '/splash' && from != null ? from : location;
  final target = _destination(auth.value as Me?, wanted);
  if (target != null) return target;
  return wanted == location ? null : wanted;
}

String? _destination(Me? me, String location) {
  if (me == null) return const {'/login', '/register'}.contains(location) ? null : '/login';
  if (!me.onboarded) return location == '/onboarding' ? null : '/onboarding';
  if (!me.paired) return const {'/pair', '/interests'}.contains(location) ? null : '/pair';
  const allowed = {'/home', '/game', '/interests', '/history'};
  return allowed.contains(location) || location.startsWith('/history/') ? null : '/home';
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) =>
        redirectFor(ref.read(authProvider), state.matchedLocation, from: state.uri.queryParameters['from']),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const InterestsScreen()),
      GoRoute(path: '/interests', builder: (_, _) => const InterestsScreen(editing: true)),
      GoRoute(path: '/pair', builder: (_, _) => const PairingScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/game', builder: (_, _) => const GameScreen()),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(
        path: '/history/:id',
        builder: (_, state) => HistoryDetailScreen(gameId: state.pathParameters['id']!),
      ),
    ],
  );
});

class _Splash extends ConsumerWidget {
  const _Splash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: auth.hasError
          ? ErrorView(error: auth.error!, onRetry: () => ref.invalidate(authProvider))
          : const LoadingView(),
    );
  }
}
