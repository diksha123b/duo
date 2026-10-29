import 'package:duo/core/models.dart';
import 'package:duo/features/history/history_controller.dart';
import 'package:duo/features/history/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHistory extends HistoryController {
  FakeHistory(this.items);
  final List<HistoryItem> items;

  @override
  Future<HistoryState> build() async => HistoryState(items: items, nextCursor: null);
}

HistoryItem item(String day, {bool completed = true, bool meSubmitted = true}) => HistoryItem(
      id: day,
      day: day,
      type: GameType.wouldYouRather,
      title: 'Would You Rather',
      completed: completed,
      meSubmitted: meSubmitted,
      summary: completed ? const MatchSummary(3, 5) : null,
    );

Widget app(List<HistoryItem> items) => ProviderScope(
      overrides: [historyProvider.overrideWith(() => FakeHistory(items))],
      child: const MaterialApp(home: HistoryScreen()),
    );

void main() {
  testWidgets('lists past games with their results and missed days', (tester) async {
    await tester.pumpWidget(app([item('2026-10-28'), item('2026-10-27', completed: false)]));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-28 · 3 / 5 matched'), findsOneWidget);
    expect(find.text('2026-10-27 · Your partner missed this one'), findsOneWidget);
  });

  testWidgets('shows an empty state before the first game', (tester) async {
    await tester.pumpWidget(app([]));
    await tester.pumpAndSettle();
    expect(find.textContaining('No past games yet'), findsOneWidget);
  });
}
