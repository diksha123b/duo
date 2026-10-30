import 'package:duo/features/game/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<bool?> tryLeave(WidgetTester tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              TextButton(onPressed: () async => result = await confirmLeaveGame(context), child: const Text('back')),
        ),
      ),
    );
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    return result;
  }

  tearDown(() => answersInProgress.value = false);

  testWidgets('leaves straight away when nothing has been answered', (tester) async {
    answersInProgress.value = false;
    expect(await tryLeave(tester), isTrue);
    expect(find.text('quit this game?'), findsNothing);
  });

  testWidgets('asks before throwing away answers', (tester) async {
    answersInProgress.value = true;
    await tryLeave(tester);
    expect(find.text('quit this game?'), findsOneWidget);

    await tester.tap(find.text('keep playing'));
    await tester.pumpAndSettle();
    expect(answersInProgress.value, isTrue); // still playing

    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('quit'));
    await tester.pumpAndSettle();
    expect(answersInProgress.value, isFalse);
  });
}
