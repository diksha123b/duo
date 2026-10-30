import 'package:flutter/material.dart';

import '../core/models.dart';
import 'sticker.dart';
import 'theme.dart';

class ArcadeStyle {
  const ArcadeStyle(this.name, this.emoji, this.color, this.pattern, this.tagline);

  final String name;
  final String emoji;
  final Color color;
  final StickerPattern pattern;
  final String tagline;

  /// How to play, in a few short lines (shown from the ⓘ button).
  List<String> get rules => _rules[name]!;

  static const _rules = {
    'chess': [
      'You each have 16 pieces. Whoever starts plays white and moves first.',
      'Tap one of your pieces: the squares it can move to light up. Tap one to move.',
      'Win by checkmate: their king is under attack and has no way out.',
      'Stalemate or repeating positions is a draw. Pawns reaching the far side become queens.',
    ],
    'ludo': [
      'The die rolls itself on your turn. You just pick which token to move.',
      'A 6 brings a token out of base. While all yours are in base, you get 3 tries for a 6.',
      'Land on their token (not on a ★ or a start square) to send it back to base.',
      'A 6, a capture or reaching home gives you another turn.',
      'Win by getting all 4 tokens home to the centre, using an exact roll.',
    ],
    'word tiles': [
      'You each get 7 letter tiles. Tap a tile, then a square, to place it.',
      'Place tiles in one line, joined to what’s on the board. The first word covers ★.',
      'Every word your tiles make (across and down) must be a real English word.',
      'Score = letter points. DL/TL double/triple a letter; DW/TW double/triple the word.',
      'Use all 7 tiles in one go for +35. Highest score when the tiles run out wins.',
    ],
    'four in a row': [
      'Tap a column to drop a disc. It falls to the lowest empty spot.',
      'Pink is you. Yellow is them. Take turns.',
      'Win by getting 4 of your discs in a line: across, up-down, or diagonal.',
      'Block their lines while building yours. A full board with no line is a draw.',
    ],
    'dots & boxes': [
      'Take turns drawing one line between two neighbouring dots.',
      'Draw the 4th side of a box and it’s yours. Then you go again.',
      'When every box is taken, whoever owns more boxes wins.',
      'Tip: avoid drawing the 3rd side of a box. It hands it to them.',
    ],
    'tic-tac-toe': [
      'Take turns marking a square. Whoever starts is ✕.',
      'Get 3 in a row (across, down or diagonal) to win.',
      'A full board with no line is a draw.',
    ],
  };

  static ArcadeStyle of(ArcadeKind kind) => switch (kind) {
    ArcadeKind.chess => const ArcadeStyle(
      'chess',
      '♟️',
      DuoColors.mint,
      StickerPattern.grid,
      'the long game. very long.',
    ),
    ArcadeKind.ludo => const ArcadeStyle(
      'ludo',
      '🎲',
      DuoColors.sunflower,
      StickerPattern.dots,
      'friendship, tested by dice.',
    ),
    ArcadeKind.wordTiles => const ArcadeStyle(
      'word tiles',
      '🔤',
      DuoColors.grape,
      StickerPattern.stars,
      'spell it. score it. gloat.',
    ),
    ArcadeKind.fourInARow => const ArcadeStyle(
      'four in a row',
      '🔴',
      DuoColors.bubblegum,
      StickerPattern.zigzag,
      'drop, stack, connect, celebrate.',
    ),
    ArcadeKind.dotsAndBoxes => const ArcadeStyle(
      'dots & boxes',
      '🟧',
      DuoColors.tangerine,
      StickerPattern.stripes,
      'one line at a time. sneaky.',
    ),
    ArcadeKind.ticTacToe => const ArcadeStyle(
      'tic-tac-toe',
      '❌',
      DuoColors.sky,
      StickerPattern.waves,
      'thirty seconds of glory.',
    ),
  };
}

/// The two players' colours on every board: you are always pink.
const youColor = DuoColors.bubblegum;
const themColor = DuoColors.sky;
