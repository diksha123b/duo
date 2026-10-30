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
