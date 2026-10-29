import 'package:duo/core/models.dart';
import 'package:duo/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  const AsyncValue<Me?> loading = AsyncLoading();
  const AsyncValue<Me?> signedOut = AsyncData(null);

  test('shows the splash while the session is restoring', () {
    expect(redirectFor(loading, '/home'), '/splash');
    expect(redirectFor(loading, '/splash'), isNull);
  });

  test('signed-out users can only reach login and register', () {
    expect(redirectFor(signedOut, '/home'), '/login');
    expect(redirectFor(signedOut, '/register'), isNull);
  });

  test('new users go through onboarding, then pairing, then home', () {
    expect(redirectFor(AsyncData(me(onboarded: false, paired: false)), '/home'), '/onboarding');
    expect(redirectFor(AsyncData(me(paired: false)), '/onboarding'), '/pair');
    expect(redirectFor(AsyncData(me()), '/pair'), '/home');
    expect(redirectFor(AsyncData(me()), '/game'), isNull);
  });

  test('a failed restore stays on the splash to offer a retry', () {
    final failed = AsyncValue<Me?>.error(Exception('offline'), StackTrace.empty);
    expect(redirectFor(failed, '/home'), '/splash');
  });
}
