import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Runs every widget test with the system "reduce motion" setting on, so
/// decorative loops (the buddies) stand still and pumpAndSettle can settle.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true);
  });
  await testMain();
}
