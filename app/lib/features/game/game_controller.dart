import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../auth/auth_controller.dart';

/// The next six days' game types, refreshed with today's game.
final lineupProvider = NotifierProvider<LineupNotifier, List<LineupDay>>(LineupNotifier.new);

class LineupNotifier extends Notifier<List<LineupDay>> {
  @override
  List<LineupDay> build() => const [];

  void set(List<LineupDay> days) => state = days;
}

final todayGameProvider = AsyncNotifierProvider<TodayGameController, Game>(TodayGameController.new);

class TodayGameController extends AsyncNotifier<Game> {
  ApiClient get _api => ref.read(apiProvider);

  /// Reused across retries of the same submission so a timeout-then-retry
  /// (or a double tap) can't create a second submission.
  String? _pendingKey;

  @override
  Future<Game> build() async {
    ref.watch(authProvider.select((a) => a.value?.pairId));
    return _fetch();
  }

  Future<Game> _fetch() async {
    final res = await _api.get('/games/today');
    final lineup = (res['lineup'] as List? ?? const [])
        .map((j) => LineupDay.fromJson(j as Map<String, dynamic>))
        .toList();
    // Deferred so it never updates another provider mid-build.
    Future.microtask(() => ref.read(lineupProvider.notifier).set(lineup));
    return Game.fromJson(res['game'] as Map<String, dynamic>);
  }

  Future<void> refresh() async {
    state = AsyncData(await _fetch());
  }

  /// [choices] holds one option per question; for Rank it, [rankings] holds
  /// each question's full order instead.
  Future<void> submit(Map<String, int> choices, {Map<String, List<int>> rankings = const {}}) async {
    final game = state.requireValue;
    final key = _pendingKey ??= const Uuid().v4();
    try {
      final res = await _api.post(
        '/games/${game.id}/submit',
        headers: {'Idempotency-Key': key},
        body: {
          'answers': [
            for (final q in game.questions)
              if (game.type == GameType.rankIt)
                {'questionId': q.id, 'ranking': rankings[q.id]}
              else
                {'questionId': q.id, 'choice': choices[q.id]},
          ],
        },
      );
      _pendingKey = null;
      _apply(Game.fromJson(res['game'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      // Submitted from another device or an earlier attempt: show the truth.
      if (e.code == 'ALREADY_SUBMITTED') {
        _pendingKey = null;
        await refresh();
        return;
      }
      rethrow;
    }
  }

  /// Applies a game pushed over the socket. Ignores stale pushes for other days.
  void applyServer(Map<String, dynamic> json) {
    final incoming = Game.fromJson(json);
    final current = state.value;
    if (current == null || current.id == incoming.id) _apply(incoming);
  }

  void markPartnerSubmitted(String gameId) {
    final current = state.value;
    if (current != null && current.id == gameId && !current.completed) {
      state = AsyncData(current.copyWith(partnerSubmitted: true));
    }
  }

  void _apply(Game game) {
    // Never move backwards: a late "waiting" response must not hide a reveal.
    final current = state.value;
    if (current != null && current.id == game.id && current.completed && !game.completed) return;
    state = AsyncData(game);
  }
}
