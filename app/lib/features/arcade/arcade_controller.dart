import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../auth/auth_controller.dart';

final arcadeProvider = AsyncNotifierProvider<ArcadeController, ArcadeLobby>(ArcadeController.new);

class ArcadeController extends AsyncNotifier<ArcadeLobby> {
  @override
  Future<ArcadeLobby> build() async {
    ref.watch(authProvider.select((a) => a.value?.pairId));
    return ArcadeLobby.fromJson(await ref.read(apiProvider).get('/arcade'));
  }

  /// Starts a game (or returns the one already running) and gives back its id.
  Future<String> start(ArcadeKind kind, {bool? quick, String? botLevel}) async {
    final res = await ref
        .read(apiProvider)
        .post('/arcade/matches', body: {'kind': kind.wire, 'quick': ?quick, 'botLevel': ?botLevel});
    ref.invalidateSelf();
    return (res['match'] as Map)['id'] as String;
  }
}

/// What a word means, for Word Tiles ("QUAY: a platform where boats dock").
final wordMeaningProvider = FutureProvider.family<String?, String>((ref, word) async {
  final res = await ref.read(apiProvider).get('/words/${Uri.encodeComponent(word)}');
  return res['meaning'] as String?;
});

final matchProvider = AsyncNotifierProvider.family<MatchController, MatchInfo, String>(MatchController.new);

class MatchController extends AsyncNotifier<MatchInfo> {
  MatchController(this.id);

  final String id;
  ApiClient get _api => ref.read(apiProvider);

  @override
  Future<MatchInfo> build() async =>
      MatchInfo.fromJson((await _api.get('/arcade/matches/$id'))['match'] as Map<String, dynamic>);

  /// Sends a move made against the version on screen. If the board moved on
  /// meanwhile, the server refuses and we reload the latest.
  Future<void> play(Map<String, dynamic> move) async {
    final current = state.requireValue;
    try {
      final res = await _api.post('/arcade/matches/$id/moves', body: {'version': current.version, 'move': move});
      _set(MatchInfo.fromJson(res['match'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (e.code == 'STALE_MATCH' || e.code == 'NOT_YOUR_TURN') ref.invalidateSelf();
      rethrow;
    }
  }

  Future<void> resign() async {
    final res = await _api.post('/arcade/matches/$id/resign');
    _set(MatchInfo.fromJson(res['match'] as Map<String, dynamic>));
  }

  /// A newer state pushed over the socket.
  void applyServer(Map<String, dynamic> json) => _set(MatchInfo.fromJson(json));

  void _set(MatchInfo next) {
    final current = state.value;
    // Ignore out-of-order pushes.
    if (current != null && next.version < current.version) return;
    state = AsyncData(next);
    ref.invalidate(arcadeProvider);
  }
}
