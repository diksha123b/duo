import 'package:flutter/material.dart';

import '../../../ui/arcade_style.dart';
import '../../../ui/theme.dart';
import 'common.dart';

// U+FE0E asks for the plain text glyph; without it some browsers draw the
// black pawn as a grey emoji next to text-style pieces.
const _glyphs = {
  'K': '♔\uFE0E', 'Q': '♕\uFE0E', 'R': '♖\uFE0E', 'B': '♗\uFE0E', 'N': '♘\uFE0E', 'P': '♙\uFE0E',
  'k': '♚\uFE0E', 'q': '♛\uFE0E', 'r': '♜\uFE0E', 'b': '♝\uFE0E', 'n': '♞\uFE0E', 'p': '♟\uFE0E',
};

/// Square name → piece letter, from the board part of a FEN.
Map<String, String> piecesFromFen(String fen) {
  final pieces = <String, String>{};
  final rows = fen.split(' ').first.split('/');
  for (var r = 0; r < 8; r++) {
    var file = 0;
    for (final ch in rows[r].split('')) {
      final skip = int.tryParse(ch);
      if (skip != null) {
        file += skip;
      } else {
        pieces['${'abcdefgh'[file]}${8 - r}'] = ch;
        file++;
      }
    }
  }
  return pieces;
}

class ChessBoard extends StatefulWidget {
  const ChessBoard({super.key, required this.board});

  final Turn board;

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  String? _from;

  @override
  Widget build(BuildContext context) {
    final b = widget.board;
    final v = b.match.view;
    final pieces = piecesFromFen(v['fen'] as String);
    final white = v['color'] == 'w';
    final legal = (v['legalMoves'] as List).cast<Map>();
    final last = v['lastMove'] as Map?;
    final targets = {for (final m in legal.where((m) => m['from'] == _from)) m['to'] as String};
    bool myPiece(String? p) => p != null && (white ? p == p.toUpperCase() : p == p.toLowerCase());
    final line = DuoColors.line(context);

    void tap(String sq) {
      if (!b.myTurn) return;
      if (_from != null && targets.contains(sq)) {
        // Promotions default to a queen.
        b.send({'from': _from, 'to': sq, 'promotion': 'q'});
        setState(() => _from = null);
      } else if (myPiece(pieces[sq])) {
        setState(() => _from = _from == sq ? null : sq);
      } else {
        setState(() => _from = null);
      }
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: line, width: 2),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: line, offset: const Offset(5, 5))],
            ),
            clipBehavior: Clip.antiAlias,
            child: GridView.count(
              crossAxisCount: 8,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 64; i++)
                  Builder(
                    builder: (context) {
                      // You always sit at the bottom.
                      final row = white ? i ~/ 8 : 7 - i ~/ 8;
                      final col = white ? i % 8 : 7 - i % 8;
                      final sq = '${'abcdefgh'[col]}${8 - row}';
                      final dark = (row + col).isOdd;
                      final isLast = last != null && (last['from'] == sq || last['to'] == sq);
                      final piece = pieces[sq];
                      return GestureDetector(
                        onTap: () => tap(sq),
                        child: Container(
                          color: _from == sq
                              ? DuoColors.sunflower
                              : isLast
                              ? DuoColors.sunflower.withValues(alpha: 0.75)
                              : dark
                              ? const Color(0xFF8FC9A6)
                              : const Color(0xFFF4EBDC),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (targets.contains(sq))
                                Container(
                                  width: piece == null ? 14 : 40,
                                  height: piece == null ? 14 : 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: piece == null ? DuoColors.ink.withValues(alpha: 0.35) : null,
                                    border: piece == null ? null : Border.all(color: DuoColors.tomato, width: 3),
                                  ),
                                ),
                              if (piece != null)
                                FittedBox(
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Text(
                                      _glyphs[piece]!,
                                      style: TextStyle(
                                        fontSize: 40,
                                        color: DuoColors.ink,
                                        shadows: [
                                          Shadow(
                                            color: piece == piece.toUpperCase() ? Colors.white : youColor,
                                            blurRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        if (v['inCheck'] == true && b.match.active) ...[
          const SizedBox(height: 10),
          Text(b.myTurn ? 'you’re in check!' : 'check!', style: Theme.of(context).textTheme.titleMedium),
        ],
        const SizedBox(height: 8),
        Text(
          (v['history'] as List).isEmpty ? 'white moves first' : (v['history'] as List).join('  '),
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
