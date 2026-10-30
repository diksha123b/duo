import 'package:flutter/material.dart';

import '../../../ui/arcade_style.dart';
import '../../../ui/theme.dart';
import 'common.dart';

class FourInARowBoard extends BoardWidget {
  const FourInARowBoard({super.key, required super.match, required super.send});

  @override
  Widget build(BuildContext context) {
    final v = match.view;
    final rows = v['rows'] as int;
    final cols = v['cols'] as int;
    final board = (v['board'] as List).cast<int?>();
    final winning = (v['winningLine'] as List?)?.cast<int>().toSet() ?? const {};
    final last = v['last'] as int?;
    final line = DuoColors.line(context);

    return AspectRatio(
      aspectRatio: cols / (rows + 0.6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: DuoColors.sky,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: line, width: 2),
          boxShadow: [BoxShadow(color: line, offset: const Offset(5, 5))],
        ),
        child: Row(
          children: [
            for (var c = 0; c < cols; c++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Tap anywhere in a column to drop a disc in it.
                  onTap: myTurn && board[c] == null ? () => send({'col': c}) : null,
                  child: Column(
                    children: [
                      for (var r = 0; r < rows; r++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: switch (board[r * cols + c]) {
                                  null => Colors.white,
                                  final s => isMine(s) ? youColor : DuoColors.sunflower,
                                },
                                border: Border.all(
                                  color: line,
                                  width: winning.contains(r * cols + c) || last == r * cols + c ? 3.5 : 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
