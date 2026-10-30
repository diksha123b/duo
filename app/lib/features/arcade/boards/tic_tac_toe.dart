import 'package:flutter/material.dart';

import '../../../ui/arcade_style.dart';
import '../../../ui/sticker.dart';
import '../../../ui/theme.dart';
import 'common.dart';

class TicTacToeBoard extends BoardWidget {
  const TicTacToeBoard({super.key, required super.match, required super.send});

  @override
  Widget build(BuildContext context) {
    final board = (match.view['board'] as List).cast<int?>();
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 9; i++)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Sticker(
                depth: 3,
                color: board[i] == null ? null : (isMine(board[i]) ? youColor : themColor),
                padding: EdgeInsets.zero,
                onTap: myTurn && board[i] == null ? () => send({'cell': i}) : null,
                child: Center(
                  child: Text(
                    board[i] == null ? '' : (board[i] == 0 ? '✕' : '◯'),
                    style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: DuoColors.ink),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
