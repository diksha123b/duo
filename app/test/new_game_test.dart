import 'package:duo/core/models.dart';
import 'package:duo/features/arcade/arcade_controller.dart';
import 'package:duo/features/arcade/boards/common.dart';
import 'package:duo/features/arcade/boards/word_tiles_board.dart';
import 'package:duo/features/arcade/new_game.dart';
import 'package:duo/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'guest_test.dart' show FakeAuth, me;

class FakeArcade extends ArcadeController {
  final starts = <(ArcadeKind, bool?, String?)>[];

  @override
  Future<ArcadeLobby> build() async => ArcadeLobby.fromJson({'active': [], 'recent': [], 'record': {}});

  @override
  Future<String> start(ArcadeKind kind, {bool? quick, String? botLevel}) async {
    starts.add((kind, quick, botLevel));
    return 'm1';
  }
}

Future<FakeArcade> pumpLobby(WidgetTester tester, {required bool demo}) async {
  final arcade = FakeArcade();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              // The app always has the signed-in user loaded; so does this test.
              ref.watch(authProvider);
              return Column(
                children: [
                  TextButton(
                    onPressed: () => openGame(context, ref, ArcadeKind.wordTiles),
                    child: const Text('word tiles'),
                  ),
                  TextButton(onPressed: () => openGame(context, ref, ArcadeKind.chess), child: const Text('chess')),
                ],
              );
            },
          ),
        ),
      ),
      GoRoute(path: '/arcade/:id', builder: (_, s) => Text('match ${s.pathParameters['id']}')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        authProvider.overrideWith(() => FakeAuth(me(demo: demo))),
        arcadeProvider.overrideWith(() => arcade),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return arcade;
}

void main() {
  testWidgets('in the demo, a new game asks how good the bot should be, and how long word tiles lasts', (tester) async {
    final arcade = await pumpLobby(tester, demo: true);
    await tester.tap(find.text('word tiles'));
    await tester.pumpAndSettle();
    expect(find.text('how good should Duo Jr. play?'), findsOneWidget);
    await tester.tap(find.text('🔥 hard'));
    await tester.tap(find.text('📜 full · ~25 min'));
    await tester.pump();
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(arcade.starts.single, (ArcadeKind.wordTiles, false, 'hard'));
    expect(find.text('match m1'), findsOneWidget);
  });

  testWidgets('with a real partner, only word tiles asks a question (its length)', (tester) async {
    final arcade = await pumpLobby(tester, demo: false);
    await tester.tap(find.text('chess'));
    await tester.pumpAndSettle();
    expect(arcade.starts.single, (ArcadeKind.chess, null, null));

    final again = await pumpLobby(tester, demo: false);
    await tester.tap(find.text('word tiles'));
    await tester.pumpAndSettle();
    expect(find.text('how good should Duo Jr. play?'), findsNothing);
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(again.starts.single, (ArcadeKind.wordTiles, true, null));
  });

  testWidgets('word tiles explains what a word means', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final view = {
      'size': 11,
      'board': List<String?>.filled(121, null),
      'bonuses': <String, String>{},
      'letterValues': {'Q': 10},
      'rack': ['Q'],
      'otherRackCount': 7,
      'bagCount': 20,
      'scores': [0, 12],
      'last': {
        'seat': 1,
        'kind': 'place',
        'words': ['QUAY'],
        'points': 12,
        'tiles': <Map<String, dynamic>>[],
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [wordMeaningProvider.overrideWith((ref, word) async => 'a platform where boats dock')],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WordTilesBoard(
                board: Turn(
                  MatchInfo(id: 'm1', kind: ArcadeKind.wordTiles, active: true, yourTurn: true, view: view),
                  (m) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('they played QUAY for 12'), findsOneWidget);
    expect(find.text('quay · a platform where boats dock', findRichText: true), findsOneWidget);
  });
}
