import 'package:duo/core/models.dart';
import 'package:duo/features/arcade/boards/chess_board.dart';
import 'package:duo/features/arcade/boards/common.dart';
import 'package:duo/features/arcade/boards/ludo_board.dart';
import 'package:duo/features/arcade/boards/tic_tac_toe.dart';
import 'package:duo/features/arcade/boards/word_tiles_board.dart';
import 'package:duo/ui/sticker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MatchInfo match(ArcadeKind kind, Map<String, dynamic> view, {bool yourTurn = true, int seat = 0}) =>
    MatchInfo(id: 'm1', kind: kind, active: true, yourTurn: yourTurn, seat: seat, view: view);

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: SizedBox(width: 400, child: child)),
  ),
);

void main() {
  testWidgets('tic-tac-toe sends the tapped cell, only on your turn', (tester) async {
    final sent = <Map<String, dynamic>>[];
    final view = {'board': List<int?>.filled(9, null)};
    await tester.pumpWidget(
      wrap(TicTacToeBoard(match: match(ArcadeKind.ticTacToe, view), send: (m) async => sent.add(m))),
    );
    await tester.tap(find.byType(Sticker).at(4));
    expect(sent, [
      {'cell': 4},
    ]);

    sent.clear();
    await tester.pumpWidget(
      wrap(TicTacToeBoard(match: match(ArcadeKind.ticTacToe, view, yourTurn: false), send: (m) async => sent.add(m))),
    );
    await tester.tap(find.byType(Sticker).at(4), warnIfMissed: false);
    expect(sent, isEmpty);
  });

  test('reads pieces from a FEN', () {
    final pieces = piecesFromFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1');
    expect(pieces['e4'], 'P');
    expect(pieces['e2'], isNull);
    expect(pieces['d8'], 'q');
  });

  testWidgets('chess: tap a piece, then a highlighted square, to move', (tester) async {
    final sent = <Map<String, dynamic>>[];
    final view = {
      'fen': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      'history': <String>[],
      'lastMove': null,
      'inCheck': false,
      'color': 'w',
      'legalMoves': [
        {'from': 'e2', 'to': 'e3', 'promotion': null},
        {'from': 'e2', 'to': 'e4', 'promotion': null},
      ],
    };
    await tester.pumpWidget(wrap(ChessBoard(board: Turn(match(ArcadeKind.chess, view), (m) async => sent.add(m)))));
    // White at the bottom: e2 is row 6, column 4.
    final squares = find.descendant(of: find.byType(GridView), matching: find.byType(GestureDetector));
    await tester.tap(squares.at(6 * 8 + 4));
    await tester.pump();
    await tester.tap(squares.at(4 * 8 + 4)); // e4
    expect(sent.single, {'from': 'e2', 'to': 'e4', 'promotion': 'q'});
  });

  testWidgets('ludo offers the roll on your turn', (tester) async {
    final sent = <Map<String, dynamic>>[];
    final view = {
      'tokens': [
        [-1, -1, -1, -1],
        [-1, -1, -1, -1],
      ],
      'roll': null,
      'last': null,
      'movable': <int>[],
    };
    await tester.pumpWidget(wrap(LudoBoard(match: match(ArcadeKind.ludo, view), send: (m) async => sent.add(m))));
    await tester.tap(find.text('🎲 roll'));
    await tester.pump();
    expect(sent.single, {'type': 'roll'});
  });

  testWidgets('word tiles: pick a rack tile, place it, and play', (tester) async {
    final sent = <Map<String, dynamic>>[];
    const n = 11;
    final view = {
      'size': n,
      'board': List<String?>.filled(n * n, null),
      'bonuses': <String, String>{},
      'letterValues': {'H': 4, 'I': 1},
      'rack': ['H', 'I'],
      'otherRackCount': 7,
      'bagCount': 80,
      'scores': [0, 0],
      'last': null,
    };
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(WordTilesBoard(board: Turn(match(ArcadeKind.wordTiles, view), (m) async => sent.add(m)))),
    );
    final cells = find.descendant(of: find.byType(GridView), matching: find.byType(GestureDetector));
    await tester.tap(find.text('H').last);
    await tester.pump();
    await tester.tap(cells.at(5 * n + 5));
    await tester.pump();
    await tester.tap(find.text('I').last);
    await tester.pump();
    await tester.tap(cells.at(5 * n + 6));
    await tester.pump();
    await tester.tap(find.text('play'));
    await tester.pump();
    expect(sent.single['type'], 'place');
    expect(sent.single['tiles'], [
      {'r': 5, 'c': 5, 'letter': 'H'},
      {'r': 5, 'c': 6, 'letter': 'I'},
    ]);
  });
}
