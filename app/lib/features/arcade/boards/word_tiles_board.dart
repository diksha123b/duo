import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/arcade_style.dart';
import '../../../ui/sticker.dart';
import '../../../ui/theme.dart';
import '../arcade_controller.dart';
import 'common.dart';

class WordTilesBoard extends StatefulWidget {
  const WordTilesBoard({super.key, required this.board});

  final Turn board;

  @override
  State<WordTilesBoard> createState() => _WordTilesBoardState();
}

class _WordTilesBoardState extends State<WordTilesBoard> {
  /// Rack positions waiting to be played, keyed by board cell index.
  final Map<int, int> _pending = {};
  int? _selected;
  List<int>? _order;

  Turn get b => widget.board;

  @override
  void didUpdateWidget(WordTilesBoard old) {
    super.didUpdateWidget(old);
    // A new board (their move, or ours accepted) clears anything half-placed.
    if (old.board.match.version != b.match.version) {
      _pending.clear();
      _selected = null;
      _order = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = b.match.view;
    final n = v['size'] as int;
    final board = (v['board'] as List).cast<String?>();
    final bonuses = Map<String, String>.from(v['bonuses'] as Map);
    final values = Map<String, int>.from(v['letterValues'] as Map);
    final rack = (v['rack'] as List).cast<String>();
    final order = _order ??= List.generate(rack.length, (i) => i);
    final scores = (v['scores'] as List).cast<int>();
    final last = v['last'] as Map?;
    final text = Theme.of(context).textTheme;
    final line = DuoColors.line(context);
    final placedRack = _pending.values.toSet();

    void tapCell(int i) {
      if (!b.myTurn) return;
      setState(() {
        if (_pending.containsKey(i)) {
          _pending.remove(i); // take it back
        } else if (_selected != null && board[i] == null) {
          _pending[i] = _selected!;
          _selected = null;
        }
      });
    }

    Future<void> play() async {
      final tiles = [
        for (final e in _pending.entries) {'r': e.key ~/ n, 'c': e.key % n, 'letter': rack[e.value]},
      ];
      await b.send({'type': 'place', 'tiles': tiles});
    }

    Future<void> swap() async {
      final picked = await showDialog<List<String>>(
        context: context,
        builder: (_) => _SwapDialog(rack: rack),
      );
      if (picked != null && picked.isNotEmpty) await b.send({'type': 'swap', 'letters': picked});
    }

    Widget tile(String letter, {bool pending = false, bool selected = false, double size = 40}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? DuoColors.tomato : (pending ? DuoColors.sunflower : const Color(0xFFFFE7B8)),
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(color: DuoColors.ink, width: 1.5),
        boxShadow: const [BoxShadow(color: DuoColors.ink, offset: Offset(1.5, 1.5))],
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              letter,
              style: TextStyle(fontSize: size * 0.5, fontWeight: FontWeight.w900, color: DuoColors.ink),
            ),
          ),
          Positioned(
            right: size * 0.08,
            bottom: size * 0.02,
            child: Text(
              '${values[letter] ?? ''}',
              style: TextStyle(fontSize: size * 0.22, color: DuoColors.ink),
            ),
          ),
        ],
      ),
    );

    return Column(
      children: [
        Row(
          children: [
            Tag('you ${scores[b.match.seat]}', color: youColor),
            const SizedBox(width: 8),
            Tag('them ${scores[1 - b.match.seat]}', color: themColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${v['bagCount']} in the bag',
                style: text.bodySmall,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: DuoColors.grape.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line, width: 2),
            ),
            child: GridView.count(
              crossAxisCount: n,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              children: [
                for (var i = 0; i < n * n; i++)
                  GestureDetector(
                    onTap: () => tapCell(i),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        if (board[i] != null) return tile(board[i]!, size: box.maxWidth);
                        if (_pending.containsKey(i)) return tile(rack[_pending[i]!], pending: true, size: box.maxWidth);
                        final bonus = bonuses['${i ~/ n},${i % n}'];
                        return Container(
                          decoration: BoxDecoration(
                            color: switch (bonus) {
                              'TW' => DuoColors.tomato,
                              'DW' => DuoColors.bubblegum,
                              'TL' => DuoColors.sky,
                              'DL' => const Color(0xFFD7EEFF),
                              _ => const Color(0xFFFFFBF2),
                            },
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.center,
                          child: bonus == null
                              ? null
                              : FittedBox(
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Text(
                                      i == (n * n) ~/ 2 ? '★' : bonus,
                                      style: const TextStyle(fontWeight: FontWeight.w800, color: DuoColors.ink),
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (last != null)
          Text(switch (last['kind']) {
            'place' =>
              '${b.isMine(last['seat']) ? 'you' : 'they'} played ${(last['words'] as List).join(', ')} for ${last['points']}',
            'swap' => '${b.isMine(last['seat']) ? 'you' : 'they'} swapped tiles',
            _ => '${b.isMine(last['seat']) ? 'you' : 'they'} passed',
          }, style: text.bodyMedium),
        if (last != null && last['kind'] == 'place')
          for (final word in (last['words'] as List).cast<String>().take(2)) _Meaning(word: word),
        const SizedBox(height: 10),
        // Your rack. Tap a tile, then a square.
        Wrap(
          spacing: 6,
          children: [
            for (final i in order)
              if (!placedRack.contains(i))
                GestureDetector(
                  onTap: b.myTurn ? () => setState(() => _selected = _selected == i ? null : i) : null,
                  child: tile(rack[i], selected: _selected == i, size: 42),
                ),
          ],
        ),
        const SizedBox(height: 12),
        if (b.myTurn)
          Row(
            children: [
              Expanded(
                child: StickerButton(label: 'play', onPressed: _pending.isEmpty ? null : play),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Recall tiles',
                onPressed: _pending.isEmpty ? null : () => setState(_pending.clear),
                icon: const Icon(Icons.undo_rounded),
              ),
              IconButton.outlined(
                tooltip: 'Shuffle',
                onPressed: () => setState(() => _order = [...order]..shuffle()),
                icon: const Icon(Icons.shuffle_rounded),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (v) => v == 'swap' ? swap() : b.send({'type': 'pass'}),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'swap', child: Text('swap tiles')),
                  PopupMenuItem(value: 'pass', child: Text('pass')),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class _SwapDialog extends StatefulWidget {
  const _SwapDialog({required this.rack});

  final List<String> rack;

  @override
  State<_SwapDialog> createState() => _SwapDialogState();
}

class _SwapDialogState extends State<_SwapDialog> {
  final Set<int> _picked = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('swap which tiles?'),
      content: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < widget.rack.length; i++)
            FilterChip(
              label: Text(widget.rack[i]),
              selected: _picked.contains(i),
              onSelected: (on) => setState(() => on ? _picked.add(i) : _picked.remove(i)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('cancel')),
        FilledButton(
          onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, [for (final i in _picked) widget.rack[i]]),
          child: const Text('swap'),
        ),
      ],
    );
  }
}

/// "QUAY · a platform where boats load and unload", so no word feels made up.
class _Meaning extends ConsumerWidget {
  const _Meaning({required this.word});

  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meaning = ref.watch(wordMeaningProvider(word)).value;
    if (meaning == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${word.toLowerCase()} · ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: meaning),
          ],
        ),
        style: text.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }
}
