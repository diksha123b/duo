import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../ui/game_style.dart';
import '../../ui/states.dart';
import '../game/results_view.dart';
import '../pairing/pair_controller.dart';
import 'history_controller.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('history'),
        leading: (GoRouter.maybeOf(context)?.canPop() ?? true)
            ? null
            : IconButton(icon: const Icon(Icons.home_rounded), onPressed: () => context.go('/home')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AsyncView(
            value: history,
            onRetry: () => ref.invalidate(historyProvider),
            isEmpty: (h) => h.items.isEmpty,
            empty: const EmptyView(message: 'no past games yet.\nplay today and it shows up here tomorrow.'),
            data: (h) => RefreshIndicator(
              onRefresh: () => ref.refresh(historyProvider.future),
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 300) ref.read(historyProvider.notifier).loadMore();
                  return false;
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: h.items.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i < h.items.length) return _HistoryTile(item: h.items[i]);
                    if (h.moreError != null) {
                      return TextButton(
                        onPressed: () => ref.read(historyProvider.notifier).loadMore(),
                        child: const Text("Couldn't load more. Tap to retry"),
                      );
                    }
                    return h.hasMore
                        ? const Padding(padding: EdgeInsets.all(16), child: LoadingView())
                        : const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String summaryLine(HistoryItem item) {
  if (!item.completed) return item.meSubmitted ? 'Your partner missed this one' : 'Missed';
  return switch (item.summary) {
    MatchSummary(:final matches, :final total) => '$matches / $total matched',
    KnowsSummary(:final myCorrect, :final partnerCorrect) => 'You $myCorrect · Partner $partnerCorrect',
    TriviaSummary(:final myScore, :final partnerScore, :final total) => 'Team ${myScore + partnerScore} / ${total * 2}',
    ClosenessSummary(:final percent) => '$percent% in tune',
    RankSummary(:final percent) => '$percent% alike',
    null => 'Completed',
  };
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final style = GameStyle.of(item.type);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: style.tint(context),
          child: Text(style.emoji, style: const TextStyle(fontSize: 20)),
        ),
        title: Text(item.title),
        subtitle: Text('${item.day} · ${summaryLine(item)}'),
        trailing: item.completed ? const Icon(Icons.chevron_right) : null,
        enabled: item.completed,
        onTap: item.completed ? () => context.push('/history/${item.id}') : null,
      ),
    );
  }
}

class HistoryDetailScreen extends ConsumerWidget {
  const HistoryDetailScreen({super.key, required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameByIdProvider(gameId));
    final partner = ref.watch(pairProvider).value?.partner.displayName ?? 'Partner';
    return Scaffold(
      appBar: AppBar(
        title: Text(game.value?.day ?? 'game'),
        leading: (GoRouter.maybeOf(context)?.canPop() ?? true)
            ? null
            : IconButton(icon: const Icon(Icons.home_rounded), onPressed: () => context.go('/home')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AsyncView(
            value: game,
            onRetry: () => ref.invalidate(gameByIdProvider(gameId)),
            isEmpty: (g) => !g.completed,
            empty: const EmptyView(message: 'This game was never finished, so there are no results.'),
            data: (g) => ResultsView(game: g, partnerName: partner),
          ),
        ),
      ),
    );
  }
}
