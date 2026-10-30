import 'package:duo/core/models.dart';
import 'package:duo/features/game/results_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('would-you-rather shows both answers side by side and the match count', (tester) async {
    final game = Game.fromJson(
      gameJson(
        meSubmitted: true,
        partnerSubmitted: true,
        completed: true,
        summary: {'kind': 'match', 'matches': 1, 'total': 2},
      ),
    );
    await tester.pumpWidget(wrap(ResultsView(game: game, partnerName: 'Ravi')));
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('pretty in sync.'), findsOneWidget);
    expect(find.text('✨ same!'), findsOneWidget);
    expect(find.text('Ravi'), findsNWidgets(2));
    expect(find.text('Beach'), findsOneWidget);
    expect(find.text('Mountains'), findsOneWidget);
  });

  testWidgets('who-knows-whom announces who knows whom better', (tester) async {
    final game = Game.fromJson(
      gameJson(
        type: 'WHO_KNOWS_WHOM',
        meSubmitted: true,
        partnerSubmitted: true,
        completed: true,
        summary: {'kind': 'knows', 'myCorrect': 2, 'partnerCorrect': 1, 'aboutPartner': 3, 'aboutMe': 3},
      ),
    );
    await tester.pumpWidget(wrap(ResultsView(game: game, partnerName: 'Ravi')));
    await tester.pumpAndSettle();
    expect(find.text('you know Ravi better 😏'), findsOneWidget);
  });

  testWidgets('trivia shows the team score and the right answer', (tester) async {
    final game = Game.fromJson(
      gameJson(
        type: 'SHARED_TRIVIA',
        meSubmitted: true,
        partnerSubmitted: true,
        completed: true,
        summary: {'kind': 'trivia', 'myScore': 1, 'partnerScore': 1, 'total': 1},
        questions: [
          {
            'id': 'q1',
            'prompt': 'Red planet?',
            'options': ['Venus', 'Mars'],
            'about': null,
            'myChoice': 1,
            'partnerChoice': 1,
            'correctOption': 1,
          },
        ],
      ),
    );
    await tester.pumpWidget(wrap(ResultsView(game: game, partnerName: 'Ravi')));
    await tester.pumpAndSettle();
    expect(find.text('big brain duo.'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('answer: Mars'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
  });

  testWidgets('agree-o-meter shows how in tune you are and where each of you sits', (tester) async {
    final game = Game.fromJson(
      gameJson(
        type: 'AGREE_O_METER',
        meSubmitted: true,
        partnerSubmitted: true,
        completed: true,
        summary: {'kind': 'closeness', 'percent': 75, 'exact': 0, 'total': 1},
        questions: [
          {
            'id': 'q1',
            'prompt': 'Rainy days are the best days.',
            'options': ['Strongly disagree', 'Disagree', 'Not sure', 'Agree', 'Strongly agree'],
            'about': null,
            'myChoice': 4,
            'partnerChoice': 3,
            'correctOption': null,
          },
        ],
      ),
    );
    await tester.pumpWidget(wrap(ResultsView(game: game, partnerName: 'Ravi')));
    await tester.pumpAndSettle();
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('you'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
  });

  testWidgets('rank it shows both orders side by side', (tester) async {
    final game = Game.fromJson(
      gameJson(
        type: 'RANK_IT',
        meSubmitted: true,
        partnerSubmitted: true,
        completed: true,
        summary: {'kind': 'rank', 'percent': 75, 'sameTop': 0, 'total': 1},
        questions: [
          {
            'id': 'q1',
            'prompt': 'Rank these snacks',
            'options': ['Samosa', 'Popcorn', 'Chips', 'Fruit'],
            'about': null,
            'myChoice': 0,
            'partnerChoice': 1,
            'myRanking': [0, 1, 2, 3],
            'partnerRanking': [1, 0, 2, 3],
            'correctOption': null,
          },
        ],
      ),
    );
    await tester.pumpWidget(wrap(ResultsView(game: game, partnerName: 'Ravi')));
    await tester.pumpAndSettle();
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('similar tastes.'), findsOneWidget);
    expect(find.text('1. Samosa'), findsOneWidget);
    expect(find.text('1. Popcorn'), findsOneWidget);
  });

  testWidgets('reacting to an answer and chatting about the results', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final json = gameJson(
      meSubmitted: true,
      partnerSubmitted: true,
      completed: true,
      summary: {'kind': 'match', 'matches': 1, 'total': 2},
    );
    (json['questions'] as List)[0]['reactions'] = {'mine': null, 'partner': '🔥'};
    json['comments'] = [
      {'id': 'c1', 'mine': false, 'text': 'tea, always', 'createdAt': '2026-10-29T10:00:00Z'},
    ];
    final reacted = <(String, String?)>[];
    final sent = <String>[];
    await tester.pumpWidget(
      wrap(
        ResultsView(
          game: Game.fromJson(json),
          partnerName: 'Ravi',
          onReact: (q, e) async => reacted.add((q, e)),
          onComment: (t) async => sent.add(t),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ravi 🔥'), findsOneWidget);
    expect(find.text('tea, always'), findsOneWidget);

    await tester.tap(find.text('❤️').first);
    expect(reacted, [('q1', '❤️')]);

    await tester.enterText(find.byType(TextField), 'coffee gang');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(sent, ['coffee gang']);
    expect(find.text('coffee gang'), findsNothing, reason: 'the input clears after sending');
  });
}
