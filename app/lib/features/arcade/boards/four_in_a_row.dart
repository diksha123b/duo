import 'package:flutter/material.dart';

import '../../../core/models.dart';
import '../../../ui/arcade_style.dart';
import '../../../ui/theme.dart';
import 'common.dart';

/// Your discs are pink, theirs yellow (the board itself is blue).
const _theirDisc = DuoColors.sunflower;

class FourInARowBoard extends StatefulWidget {
  const FourInARowBoard({super.key, required this.match, required this.send, this.otherName = 'them'});

  final MatchInfo match;
  final SendMove send;
  final String otherName;

  @override
  State<FourInARowBoard> createState() => _FourInARowBoardState();
}

class _FourInARowBoardState extends State<FourInARowBoard> {
  /// The column under the finger or mouse, to preview where the disc will land.
  int? _aim;

  Turn get t => Turn(widget.match, widget.send);

  @override
  Widget build(BuildContext context) {
    final v = t.match.view;
    final rows = v['rows'] as int;
    final cols = v['cols'] as int;
    final board = (v['board'] as List).cast<int?>();
    final winning = (v['winningLine'] as List?)?.cast<int>().toSet() ?? const <int>{};
    final last = v['last'] as int?;
    final line = DuoColors.line(context);
    final text = Theme.of(context).textTheme;
    final myTurn = t.myTurn;

    /// Lowest empty row in a column, or null when it's full.
    int? landing(int c) {
      for (var r = rows - 1; r >= 0; r--) {
        if (board[r * cols + c] == null) return r;
      }
      return null;
    }

    Color discColor(int seat) => t.isMine(seat) ? youColor : _theirDisc;

    void drop(int c) {
      setState(() => _aim = null);
      if (myTurn && landing(c) != null) widget.send({'col': c});
    }

    return Column(
      children: [
        // Who is which colour, and how to win, always in view.
        Row(
          children: [
            _Legend(color: youColor, label: 'you'),
            const SizedBox(width: 10),
            _Legend(color: _theirDisc, label: widget.otherName.toLowerCase()),
            const Spacer(),
            Text('4 in a line wins', style: text.labelLarge),
          ],
        ),
        const SizedBox(height: 10),
        // Arrows above each column: tap one (or the column) to drop a disc.
        Row(
          children: [
            const SizedBox(width: 8),
            for (var c = 0; c < cols; c++)
              Expanded(
                child: GestureDetector(
                  onTap: () => drop(c),
                  child: SizedBox(
                    height: 30,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: !myTurn || landing(c) == null ? 0 : (_aim == c ? 1 : 0.35),
                      child: Icon(Icons.arrow_drop_down_rounded, size: 34, color: line),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
        AspectRatio(
          aspectRatio: cols / rows,
          child: Container(
            padding: const EdgeInsets.all(8),
            // New discs fall in from the top edge, not from outside the board.
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: DuoColors.sky,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: line, width: 2),
              boxShadow: [BoxShadow(color: line, offset: const Offset(5, 5))],
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final cellH = box.maxHeight / rows;
                return Row(
                  children: [
                    for (var c = 0; c < cols; c++)
                      Expanded(
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _aim = c),
                          onExit: (_) => setState(() => _aim = _aim == c ? null : _aim),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (_) => setState(() => _aim = c),
                            onTapCancel: () => setState(() => _aim = null),
                            // Tap anywhere in a column: the disc falls to its lowest empty spot.
                            onTap: () => drop(c),
                            child: Column(
                              children: [
                                for (var r = 0; r < rows; r++)
                                  Expanded(
                                    child: _Cell(
                                      seat: board[r * cols + c],
                                      color: board[r * cols + c] == null ? null : discColor(board[r * cols + c]!),
                                      // Where your disc would land if you let go here.
                                      ghost: myTurn && _aim == c && landing(c) == r ? youColor : null,
                                      winning: winning.contains(r * cols + c),
                                      dimmed: winning.isNotEmpty && !winning.contains(r * cols + c),
                                      // The newest disc falls in from above the board.
                                      dropFrom: last == r * cols + c ? (r + 1) * cellH : null,
                                      dropKey: '${t.match.version}',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          winning.isNotEmpty
              ? '${t.isMine(board[winning.first]) ? 'you' : widget.otherName.toLowerCase()} connected four! ✨'
              : myTurn
              ? 'tap a column to drop your disc'
              : 'waiting for ${widget.otherName.toLowerCase()} to drop…',
          style: text.titleMedium,
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: DuoColors.line(context), width: 2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.seat,
    required this.color,
    required this.ghost,
    required this.winning,
    required this.dimmed,
    required this.dropFrom,
    required this.dropKey,
  });

  final int? seat;
  final Color? color;
  final Color? ghost;
  final bool winning;
  final bool dimmed;
  final double? dropFrom;
  final String dropKey;

  @override
  Widget build(BuildContext context) {
    final line = DuoColors.line(context);
    final hole = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ghost?.withValues(alpha: 0.45) ?? Colors.white,
        border: Border.all(color: line, width: 2),
      ),
    );
    Widget disc = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: line, width: winning ? 4 : 2),
      ),
      child: winning ? const Center(child: Text('✨', style: TextStyle(fontSize: 18))) : null,
    );
    if (dropFrom != null && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      disc = TweenAnimationBuilder<double>(
        key: ValueKey(dropKey),
        tween: Tween(begin: -dropFrom!, end: 0),
        duration: Duration(milliseconds: 250 + (dropFrom! / 2).round()),
        curve: Curves.bounceOut,
        builder: (_, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
        child: disc,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(3),
      child: AnimatedOpacity(
        opacity: dimmed && seat != null ? 0.45 : 1,
        duration: const Duration(milliseconds: 400),
        child: Stack(fit: StackFit.expand, children: [hole, if (seat != null) disc]),
      ),
    );
  }
}
