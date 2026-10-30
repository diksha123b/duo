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
  Map<String, List<int>>? submittedRankings;

  @override
  Future<Game> build() => initial();

  @override
  Future<void> submit(Map<String, int> choices, {Map<String, List<int>> rankings = const {}}) async {
    submitted = choices;
    submittedRankings = rankings;
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

    expect(find.text('1 of 2'), findsOneWidget);
    await tester.tap(find.text('Coffee'));
    // The selection shows briefly before advancing.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beach'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('lock it in'));
    // The waiting state spins forever, so pump frames instead of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.submitted, {'q1': 1, 'q2': 0});
    expect(find.text('your turn’s done!'), findsOneWidget);
    expect(find.text('Partner is playing now'), findsOneWidget);
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
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('perfectly in sync!'), findsOneWidget);
  });

  testWidgets('rank it submits a full ordering per question', (tester) async {
    final rank = gameJson(
      type: 'RANK_IT',
      questions: [
        {
          'id': 'q1',
          'prompt': 'Rank these snacks',
          'options': ['Samosa', 'Popcorn', 'Chips', 'Fruit'],
          'about': null,
          'myChoice': null,
          'partnerChoice': null,
          'correctOption': null,
        },
      ],
    );
    final game = FakeGame(() async => Game.fromJson(rank));
    await tester.pumpWidget(app(game));
    await tester.pumpAndSettle();
    expect(find.text('Samosa'), findsOneWidget);

    await tester.tap(find.text('lock in my order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lock it in'));
    await tester.pump();
    expect(game.submittedRankings, {
      'q1': [0, 1, 2, 3],
    });
  });

  testWidgets('agree-o-meter offers the five-point scale', (tester) async {
    final agree = gameJson(
      type: 'AGREE_O_METER',
      questions: [
        {
          'id': 'q1',
          'prompt': 'Rainy days are the best days.',
          'options': ['Strongly disagree', 'Disagree', 'Not sure', 'Agree', 'Strongly agree'],
          'about': null,
          'myChoice': null,
          'partnerChoice': null,
          'correctOption': null,
        },
      ],
    );
    final game = FakeGame(() async => Game.fromJson(agree));
    await tester.pumpWidget(app(game));
    await tester.pumpAndSettle();

    await tester.tap(find.text('absolutely'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lock it in'));
    await tester.pump();
    expect(game.submitted, {'q1': 4});
  });

  testWidgets('emoji decode shows the clue large with its category', (tester) async {
    final emoji = gameJson(
      type: 'EMOJI_DECODE',
      questions: [
        {
          'id': 'q1',
          'prompt': '🦁👑🌅 (movie)',
          'options': ['The Lion King', 'Madagascar', 'Jungle Book', 'Tarzan'],
          'about': null,
          'myChoice': null,
          'partnerChoice': null,
          'correctOption': null,
        },
      ],
    );
    await tester.pumpWidget(app(FakeGame(() async => Game.fromJson(emoji))));
    await tester.pumpAndSettle();
    expect(find.text('🦁👑🌅'), findsOneWidget);
    expect(find.text('a movie'), findsOneWidget);
  });
}
