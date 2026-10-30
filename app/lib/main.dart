import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'config.dart';
import 'core/realtime.dart';
import 'router.dart';
import 'ui/theme.dart';

Future<void> main() async {
  const app = ProviderScope(child: DuoApp());
  if (AppConfig.sentryDsn.isEmpty) return runApp(app);
  await SentryFlutter.init((options) {
    options.dsn = AppConfig.sentryDsn;
    options.tracesSampleRate = 0.1;
  }, appRunner: () => runApp(app));
}

class DuoApp extends ConsumerWidget {
  const DuoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the socket alive for the whole session, not just while a screen watches it.
    ref.watch(realtimeProvider);

    return MaterialApp.router(
      title: 'Duo',
      debugShowCheckedModeBanner: false,
      theme: DuoTheme.light(),
      darkTheme: DuoTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
