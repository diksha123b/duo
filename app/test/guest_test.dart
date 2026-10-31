import 'package:duo/core/models.dart';
import 'package:duo/features/auth/auth_controller.dart';
import 'package:duo/features/auth/auth_screens.dart';
import 'package:duo/features/auth/save_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Me me({bool guest = true, bool demo = false}) => Me.fromJson({
  'id': 'u1',
  'email': guest ? null : 'asha@example.com',
  'guest': guest,
  'demo': demo,
  'pairId': null,
  'profile': {'displayName': 'Asha', 'interests': <String>[], 'timezone': 'UTC', 'avatarUrl': null},
});

class FakeAuth extends AuthController {
  FakeAuth([this.initial]);
  final Me? initial;
  String? guestName;
  String? demoName;
  String? savedEmail;
  int logouts = 0;

  @override
  Future<Me?> build() async => initial;

  @override
  Future<void> playAsGuest(String displayName) async {
    guestName = displayName;
    state = AsyncData(me());
  }

  @override
  Future<void> startDemo(String displayName) async {
    demoName = displayName;
    state = AsyncData(me(demo: true));
  }

  @override
  Future<void> saveAccount({required String email, required String password}) async {
    savedEmail = email;
    state = AsyncData(me(guest: false));
  }

  @override
  Future<void> logout() async => logouts++;
}

void main() {
  testWidgets('play as a guest with just a name', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(() => auth)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.ensureVisible(find.text('play as a guest, no sign-up'));
    await tester.tap(find.text('play as a guest, no sign-up'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('let’s play'));
    await tester.pump();
    expect(find.text('Pick a name'), findsOneWidget);
    expect(auth.guestName, isNull);

    await tester.enterText(find.widgetWithText(TextFormField, 'your name'), '  Asha ');
    await tester.tap(find.text('let’s play'));
    await tester.pumpAndSettle();
    expect(auth.guestName, 'Asha');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('try the demo with a bot partner', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(() => auth)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.ensureVisible(find.text('try the demo'));
    await tester.tap(find.text('try the demo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('paired with Duo Jr.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'your name'), 'Asha');
    await tester.tap(find.text('start the demo'));
    await tester.pumpAndSettle();
    expect(auth.demoName, 'Asha');
    expect(auth.guestName, isNull);
  });

  Future<FakeAuth> pumpHome(WidgetTester tester, {required bool guest, bool demo = false}) async {
    final auth = FakeAuth(me(guest: guest, demo: demo));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(() => auth)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Column(
                children: [
                  const SaveAccountBanner(),
                  DemoBanner(onPlayForReal: () async {}),
                  TextButton(onPressed: () => signOut(context, ref), child: const Text('sign out')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets('a guest is asked to save before signing out, and can save', (tester) async {
    final auth = await pumpHome(tester, guest: true);
    expect(find.textContaining('you’re playing as a guest'), findsOneWidget);

    await tester.tap(find.text('sign out'));
    await tester.pumpAndSettle();
    expect(find.text('sign out of a guest account?'), findsOneWidget);
    await tester.tap(find.text('save it first'));
    await tester.pumpAndSettle();
    expect(auth.logouts, 0);

    await tester.enterText(find.widgetWithText(TextFormField, 'email'), 'asha@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'password'), 'correct-horse');
    await tester.tap(find.text('save my account'));
    await tester.pumpAndSettle();
    expect(auth.savedEmail, 'asha@example.com');
    expect(find.textContaining('you’re playing as a guest'), findsNothing);
  });

  testWidgets('a saved account signs out straight away', (tester) async {
    final auth = await pumpHome(tester, guest: false);
    expect(find.textContaining('you’re playing as a guest'), findsNothing);
    await tester.tap(find.text('sign out'));
    await tester.pumpAndSettle();
    expect(auth.logouts, 1);
  });

  testWidgets('practice mode shows the Duo Jr. banner, not the save banner, and signs out without a warning', (
    tester,
  ) async {
    final auth = await pumpHome(tester, guest: true, demo: true);
    expect(find.textContaining('practice mode'), findsOneWidget);
    expect(find.textContaining('you’re playing as a guest'), findsNothing);
    await tester.tap(find.text('sign out'));
    await tester.pumpAndSettle();
    expect(auth.logouts, 1);
  });
}
