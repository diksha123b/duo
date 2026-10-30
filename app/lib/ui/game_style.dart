import 'package:flutter/material.dart';

import '../core/models.dart';
import 'sticker.dart';
import 'theme.dart';

enum GameCategory {
  coop('co-op', 'work together'),
  versus('versus', 'may the best duo-half win'),
  talk('talk it out', 'starts conversations');

  const GameCategory(this.label, this.blurb);
  final String label;
  final String blurb;
}

/// How each game type looks and introduces itself. One place, so the home
/// card, game screen, results and history always agree.
class GameStyle {
  const GameStyle({
    required this.name,
    required this.emoji,
    required this.color,
    required this.pattern,
    required this.tagline,
    required this.howTo,
    required this.category,
  });

  final String name;
  final String emoji;
  final Color color;
  final StickerPattern pattern;

  /// The cheeky one-liner.
  final String tagline;
  final String howTo;
  final GameCategory category;

  /// Fill for cards. Bright on paper; slightly muted at night.
  Color tint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Color.lerp(color, DuoColors.nightCard, 0.35)! : color;

  static GameStyle of(GameType type) => switch (type) {
    GameType.whoKnowsWhom => const GameStyle(
      name: 'who knows whom',
      emoji: '🔍',
      color: DuoColors.grape,
      pattern: StickerPattern.dots,
      tagline: 'prove you actually listen.',
      howTo: 'answer honestly about yourself, and guess the other person’s answers.',
      category: GameCategory.versus,
    ),
    GameType.wouldYouRather => const GameStyle(
      name: 'would you rather',
      emoji: '⚖️',
      color: DuoColors.tangerine,
      pattern: StickerPattern.stripes,
      tagline: 'two doors. pick one. no take-backs.',
      howTo: 'pick one of two. see how often you choose the same.',
      category: GameCategory.talk,
    ),
    GameType.sharedTrivia => const GameStyle(
      name: 'team trivia',
      emoji: '💡',
      color: DuoColors.mint,
      pattern: StickerPattern.grid,
      tagline: 'work together. blame each other after.',
      howTo: 'answer together. every right answer counts for the team.',
      category: GameCategory.coop,
    ),
    GameType.emojiDecode => const GameStyle(
      name: 'emoji decode',
      emoji: '🎬',
      color: DuoColors.sunflower,
      pattern: StickerPattern.stars,
      tagline: '🦁👑 means one thing. probably.',
      howTo: 'work out what each set of emojis stands for.',
      category: GameCategory.coop,
    ),
    GameType.agreeOMeter => const GameStyle(
      name: 'agree-o-meter',
      emoji: '🌶️',
      color: DuoColors.sky,
      pattern: StickerPattern.waves,
      tagline: 'hot takes, served warm.',
      howTo: 'rate each hot take. find out how in tune you are.',
      category: GameCategory.talk,
    ),
    GameType.rankIt => const GameStyle(
      name: 'rank it',
      emoji: '🏆',
      color: DuoColors.bubblegum,
      pattern: StickerPattern.zigzag,
      tagline: 'agree to disagree, loudly.',
      howTo: 'drag the items into your order, favourite first.',
      category: GameCategory.versus,
    ),
  };
}
