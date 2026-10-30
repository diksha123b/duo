import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../ui/arcade_style.dart';
import '../../ui/buddies.dart';
import '../../ui/sticker.dart';
import '../../ui/states.dart';
import '../../ui/theme.dart';
import '../pairing/pair_controller.dart';
import 'arcade_controller.dart';
import 'boards/chess_board.dart';
import 'boards/common.dart';
import 'boards/dots_and_boxes.dart';
import 'boards/four_in_a_row.dart';
import 'boards/ludo_board.dart';
import 'boards/tic_tac_toe.dart';
import 'boards/word_tiles_board.dart';

class MatchScreen extends ConsumerWidget {
  const MatchScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(matchProvider(matchId));
    final them = ref.watch(pairProvider).value?.partner.displayName ?? 'them';
    final style = match.value == null ? null : ArcadeStyle.of(match.value!.kind);

    Future<void> send(Map<String, dynamic> move) async {
      try {
        await ref.read(matchProvider(matchId).notifier).play(move);
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    Future<void> resign() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('give up?'),
          content: Text('$them wins this one.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('keep playing')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('resign')),
          ],
        ),
      );
      if (ok == true) await ref.read(matchProvider(matchId).notifier).resign();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(style == null ? 'arcade' : '${style.emoji} ${style.name}'),
        leading: (GoRouter.maybeOf(context)?.canPop() ?? true)
            ? null
            : IconButton(icon: const Icon(Icons.home_rounded), onPressed: () => context.go('/home')),
        actions: [
          if (style != null)
            IconButton(
              tooltip: 'How to play',
              icon: const Icon(Icons.help_outline_rounded),
              onPressed: () => showHowToPlay(context, style),
            ),
          if (match.value?.active ?? false)
            IconButton(tooltip: 'Resign', icon: const Icon(Icons.flag_outlined), onPressed: resign),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AsyncView(
              value: match,
              onRetry: () => ref.invalidate(matchProvider(matchId)),
              data: (m) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _TurnBanner(match: m, them: them),
                  const SizedBox(height: 14),
                  switch (m.kind) {
                    ArcadeKind.ticTacToe => TicTacToeBoard(match: m, send: send),
                    ArcadeKind.fourInARow => FourInARowBoard(match: m, send: send, otherName: them),
                    ArcadeKind.dotsAndBoxes => DotsAndBoxesBoard(match: m, send: send),
                    ArcadeKind.chess => ChessBoard(board: Turn(m, send)),
                    ArcadeKind.ludo => LudoBoard(match: m, send: send, otherName: them),
                    ArcadeKind.wordTiles => WordTilesBoard(board: Turn(m, send)),
                  },
                  if (!m.active) ...[
                    const SizedBox(height: 18),
                    StickerButton(
                      label: 'rematch',
                      color: style!.color,
                      onPressed: () async {
                        final id = await ref.read(arcadeProvider.notifier).start(m.kind);
                        if (context.mounted) context.pushReplacement('/arcade/$id');
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({required this.match, required this.them});

  final MatchInfo match;
  final String them;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.apply(bodyColor: DuoColors.ink, displayColor: DuoColors.ink);
    final (label, color, mood) = switch (match) {
      MatchInfo(active: false, result: MatchResult.won) => ('you won! 🎉', DuoColors.sunflower, BuddyMood.celebrating),
      MatchInfo(active: false, result: MatchResult.lost) => ('$them won this one', DuoColors.sky, BuddyMood.happy),
      MatchInfo(active: false) => ('it’s a draw 🤝', DuoColors.mint, BuddyMood.happy),
      MatchInfo(yourTurn: true) => ('your turn', youColor, BuddyMood.happy),
      _ => ('$them’s turn…', themColor, BuddyMood.waiting),
    };
    return Sticker(
      color: color,
      depth: 4,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.headlineSmall)),
          Buddies(size: 44, mood: mood),
        ],
      ),
    );
  }
}

/// The rules of a game, in a bottom sheet.
void showHowToPlay(BuildContext context, ArcadeStyle style) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final text = Theme.of(ctx).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${style.emoji}  how to play ${style.name}', style: text.headlineSmall),
              const SizedBox(height: 14),
              for (final (i, rule) in style.rules.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tag('${i + 1}', color: style.color),
                      const SizedBox(width: 10),
                      Expanded(child: Text(rule, style: text.bodyLarge)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
