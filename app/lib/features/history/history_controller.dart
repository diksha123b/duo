import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../auth/auth_controller.dart';

class HistoryState {
  const HistoryState({required this.items, required this.nextCursor, this.loadingMore = false, this.moreError});

  final List<HistoryItem> items;
  final String? nextCursor;
  final bool loadingMore;
  final Object? moreError;

  bool get hasMore => nextCursor != null;
}

final historyProvider = AsyncNotifierProvider<HistoryController, HistoryState>(HistoryController.new);

class HistoryController extends AsyncNotifier<HistoryState> {
  ApiClient get _api => ref.read(apiProvider);

  @override
  Future<HistoryState> build() async {
    ref.watch(authProvider.select((a) => a.value?.pairId));
    final page = await _page(null);
    return HistoryState(items: page.$1, nextCursor: page.$2);
  }

  Future<(List<HistoryItem>, String?)> _page(String? before) async {
    final res = await _api.get('/games/history?limit=20${before == null ? '' : '&before=$before'}');
    final items = (res['items'] as List).map((j) => HistoryItem.fromJson(j as Map<String, dynamic>)).toList();
    return (items, res['nextCursor'] as String?);
  }

  /// Appends the next page. Errors stay on the list footer, not the whole screen.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(HistoryState(items: current.items, nextCursor: current.nextCursor, loadingMore: true));
    try {
      final (items, next) = await _page(current.nextCursor);
      state = AsyncData(HistoryState(items: [...current.items, ...items], nextCursor: next));
    } catch (e) {
      state = AsyncData(HistoryState(items: current.items, nextCursor: current.nextCursor, moreError: e));
    }
  }
}

final gameByIdProvider = FutureProvider.autoDispose.family<Game, String>((ref, id) async {
  final res = await ref.read(apiProvider).get('/games/$id');
  return Game.fromJson(res['game'] as Map<String, dynamic>);
});
