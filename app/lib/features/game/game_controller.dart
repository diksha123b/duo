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

/// Submitting answers and taking live updates, shared by today's game and bonus rounds.
mixin PlayableGame on AsyncNotifier<Game> {
  ApiClient get _api => ref.read(apiProvider);

  /// Reused across retries of the same submission so a timeout-then-retry
  /// (or a double tap) can't create a second submission.
  String? _pendingKey;

  Future<Game> fetch();

  Future<void> refresh() async {
    state = AsyncData(await fetch());
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

  /// Puts your emoji on a revealed answer; null takes it off.
  Future<void> react(String questionId, String? emoji) async {
    final game = state.requireValue;
    final res = await _api.put('/games/${game.id}/questions/$questionId/reaction', body: {'emoji': emoji});
    _apply(Game.fromJson(res['game'] as Map<String, dynamic>));
  }

  Future<void> comment(String text) async {
    final game = state.requireValue;
    final res = await _api.post('/games/${game.id}/comments', body: {'text': text});
    _apply(Game.fromJson(res['game'] as Map<String, dynamic>));
  }

  /// Applies a game pushed over the socket. Ignores pushes for other games.
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

class TodayGameController extends AsyncNotifier<Game> with PlayableGame {
  @override
  Future<Game> build() async {
    ref.watch(authProvider.select((a) => a.value?.pairId));
    return fetch();
  }

  @override
  Future<Game> fetch() async {
    final res = await _api.get('/games/today');
    final lineup = (res['lineup'] as List? ?? const [])
        .map((j) => LineupDay.fromJson(j as Map<String, dynamic>))
        .toList();
    // Deferred so it never updates another provider mid-build.
    Future.microtask(() => ref.read(lineupProvider.notifier).set(lineup));
    return Game.fromJson(res['game'] as Map<String, dynamic>);
  }
}

/// A bonus round: any game type, any time, no streak.
final bonusGameProvider = AsyncNotifierProvider.family<BonusGameController, Game, String>(BonusGameController.new);

class BonusGameController extends AsyncNotifier<Game> with PlayableGame {
  BonusGameController(this.id);

  final String id;

  @override
  Future<Game> build() => fetch();

  @override
  Future<Game> fetch() async => Game.fromJson((await _api.get('/games/$id'))['game'] as Map<String, dynamic>);
}

/// An open bonus round: who has answered so far.
class OpenBonus {
  const OpenBonus(this.id, this.type, this.meSubmitted, this.partnerSubmitted);

  final String id;
  final GameType type;
  final bool meSubmitted;
  final bool partnerSubmitted;
}

final openBonusProvider = AsyncNotifierProvider<OpenBonusController, List<OpenBonus>>(OpenBonusController.new);

class OpenBonusController extends AsyncNotifier<List<OpenBonus>> {
  @override
  Future<List<OpenBonus>> build() async {
    ref.watch(authProvider.select((a) => a.value?.pairId));
    final res = await ref.read(apiProvider).get('/games/bonus');
    return [
      for (final g in (res['games'] as List).cast<Map>())
        OpenBonus(
          g['id'] as String,
          GameType.parse(g['type'] as String),
          g['meSubmitted'] as bool,
          g['partnerSubmitted'] as bool,
        ),
    ];
  }

  /// Starts a round of [type] (or joins the open one) and returns its id.
  Future<String> start(GameType type) async {
    final res = await ref.read(apiProvider).post('/games/bonus', body: {'type': type.wire});
    ref.invalidateSelf();
    return (res['game'] as Map)['id'] as String;
  }
}
