import 'package:duo/core/models.dart';
import 'package:duo/core/realtime.dart';
import 'package:duo/features/game/game_controller.dart';
import 'package:duo/features/game/game_screen.dart';
import 'package:duo/features/pairing/pair_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class FakeGame extends TodayGameController {
  FakeGame(this.initial);
  final Future<Game> Function() initial;
  Map<String, int>? submitted;

  @override
  Future<Game> build() => initial();

  @override
  Future<void> submit(Map<String, int> choices) async {
    submitted = choices;
    state = AsyncData(Game.fromJson(gameJson(meSubmitted: true)));
  }
}

class FakeRealtime extends RealtimeController {
  @override
  RealtimeState build() => const RealtimeState(connected: true, partnerPresence: Presence.playing);

  @override
  void setPlaying(bool playing) {}
}

class NoPair extends PairController {
  @override
  Future<PairInfo?> build() async => null;
}

Widget app(FakeGame game) => ProviderScope(
      overrides: [
        todayGameProvider.overrideWith(() => game),
        realtimeProvider.overrideWith(FakeRealtime.new),
        pairProvider.overrideWith(NoPair.new),
      ],
      child: const MaterialApp(home: GameScreen()),
    );

void main() {
  testWidgets('plays through questions, submits, then shows the waiting state', (tester) async {
    final game = FakeGame(() async => Game.fromJson(gameJson()));
    await tester.pumpWidget(app(game));
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.text('Coffee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beach'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit answers'));
    // The waiting state spins forever, so pump frames instead of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.submitted, {'q1': 1, 'q2': 0});
    expect(find.text('Waiting for Partner'), findsOneWidget);
    expect(find.text('playing now'), findsOneWidget);
  });

  testWidgets('shows an error with retry when loading fails', (tester) async {
    await tester.pumpWidget(app(FakeGame(() async => throw Exception('offline'))));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows results when the game is complete', (tester) async {
    final done = gameJson(
      meSubmitted: true,
      partnerSubmitted: true,
      completed: true,
      summary: {'kind': 'match', 'matches': 2, 'total': 2},
    );
    await tester.pumpWidget(app(FakeGame(() async => Game.fromJson(done))));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2 matched'), findsOneWidget);
  });
}
