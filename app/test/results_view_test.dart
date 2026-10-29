import 'package:duo/core/models.dart';
import 'package:duo/features/game/results_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('would-you-rather shows both answers side by side and the match count', (tester) async {
    final game = Game.fromJson(gameJson(
      meSubmitted: true,
      partnerSubmitted: true,
      completed: true,
      summary: {'kind': 'match', 'matches': 1, 'total': 2},
    ));
    await tester.pumpWidget(wrap(ResultsView(game: game, partnerName: 'Ravi')));

    expect(find.text('1 / 2 matched'), findsOneWidget);
    expect(find.text('💞 match'), findsOneWidget);
    expect(find.text('Ravi'), findsNWidgets(2));
    expect(find.text('Beach'), findsOneWidget);
    expect(find.text('Mountains'), findsOneWidget);
  });

  testWidgets('who-knows-whom announces who knows whom better', (tester) async {
    final game = Game.fromJson(gameJson(
      type: 'WHO_KNOWS_WHOM',
      meSubmitted: true,
      partnerSubmitted: true,
      completed: true,
      summary: {'kind': 'knows', 'myCorrect': 2, 'partnerCorrect': 1, 'aboutPartner': 3, 'aboutMe': 3},
    ));
    await tester.pumpWidget(wrap(ResultsView(game: game, partnerName: 'Ravi')));
    expect(find.text('You know Ravi better!'), findsOneWidget);
  });

  testWidgets('trivia shows the team score and the right answer', (tester) async {
    final game = Game.fromJson(gameJson(
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
    ));
    await tester.pumpWidget(wrap(ResultsView(game: game, partnerName: 'Ravi')));
    expect(find.text('Team score: 2 / 2'), findsOneWidget);
    expect(find.text('Answer: Mars'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));
  });
}
