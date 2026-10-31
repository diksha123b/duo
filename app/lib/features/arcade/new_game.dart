import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../ui/arcade_style.dart';
import '../../ui/states.dart';
import '../../ui/sticker.dart';
import '../auth/auth_controller.dart';
import 'arcade_controller.dart';

typedef GameSettings = ({bool? quick, String? botLevel});

const botLevels = [('easy', '🐣 easy'), ('normal', '🙂 normal'), ('hard', '🔥 hard')];

/// Opens `kind`: the game already in progress, or a new one. New games ask
/// for the bot's level in demo mode, and how long a Word Tiles game should be.
/// `previous` (a finished game) makes a rematch with the same settings.
Future<void> openGame(BuildContext context, WidgetRef ref, ArcadeKind kind, {MatchInfo? previous}) async {
  final arcade = ref.read(arcadeProvider.notifier);
  final demo = ref.read(authProvider).value?.demo ?? false;
  final inProgress = ref.read(arcadeProvider).value?.activeOf(kind);
  try {
    GameSettings settings = (quick: null, botLevel: null);
    if (previous != null) {
      settings = (
        quick: kind == ArcadeKind.wordTiles ? previous.quick : null,
        botLevel: demo ? previous.botLevel : null,
      );
    } else if (inProgress == null && (demo || kind == ArcadeKind.wordTiles)) {
      final picked = await showModalBottomSheet<GameSettings>(
        context: context,
        showDragHandle: true,
        // Let it grow past half the screen on short phones; it scrolls if needed.
        isScrollControlled: true,
        builder: (_) => _NewGameSheet(kind: kind, vsBot: demo),
      );
      if (picked == null) return;
      settings = picked;
    }
    final id = await arcade.start(kind, quick: settings.quick, botLevel: settings.botLevel);
    if (!context.mounted) return;
    previous != null ? context.pushReplacement('/arcade/$id') : context.push('/arcade/$id');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _NewGameSheet extends StatefulWidget {
  const _NewGameSheet({required this.kind, required this.vsBot});

  final ArcadeKind kind;
  final bool vsBot;

  @override
  State<_NewGameSheet> createState() => _NewGameSheetState();
}

class _NewGameSheetState extends State<_NewGameSheet> {
  String _level = 'normal';
  bool _quick = true;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = ArcadeStyle.of(widget.kind);
    final words = widget.kind == ArcadeKind.wordTiles;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('new game of ${style.name}', style: text.headlineSmall),
          if (widget.vsBot) ...[
            const SizedBox(height: 16),
            Text('how good should Sam play?', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (id, label) in botLevels)
                  ChoiceChip(
                    label: Text(label),
                    selected: _level == id,
                    onSelected: (_) => setState(() => _level = id),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(switch (_level) {
              'easy' => words ? 'short, everyday words. a gentle game.' : 'makes plenty of mistakes.',
              'hard' => words ? 'any word in the dictionary, best score every time.' : 'always plays its best move.',
              _ => words ? 'everyday words, a fair fight.' : 'plays well, slips up now and then.',
            }, style: text.bodySmall),
          ],
          if (words) ...[
            const SizedBox(height: 16),
            Text('how long?', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('⚡ quick · ~10 min'),
                  selected: _quick,
                  onSelected: (_) => setState(() => _quick = true),
                ),
                ChoiceChip(
                  label: const Text('📜 full · ~25 min'),
                  selected: !_quick,
                  onSelected: (_) => setState(() => _quick = false),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          StickerButton(
            label: 'start',
            color: style.color,
            onPressed: () async => Navigator.pop<GameSettings>(context, (
              quick: words ? _quick : null,
              botLevel: widget.vsBot ? _level : null,
            )),
          ),
        ],
      ),
    );
  }
}
