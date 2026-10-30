import 'package:flutter/material.dart';

import '../core/models.dart';

/// How each game type looks and introduces itself. One place, so the home
/// card, game screen, results and history always agree.
class GameStyle {
  const GameStyle({
    required this.name,
    required this.emoji,
    required this.light,
    required this.dark,
    required this.howTo,
  });

  final String name;
  final String emoji;
  final Color light;
  final Color dark;
  final String howTo;

  /// Pastel tint for cards; deeper version in dark mode.
  Color tint(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;

  static GameStyle of(GameType type) => switch (type) {
    GameType.whoKnowsWhom => const GameStyle(
      name: 'Who knows whom',
      emoji: '💞',
      light: Color(0xFFEDE6F7),
      dark: Color(0xFF3A3346),
      howTo: 'Answer honestly about yourself, and guess your partner’s answers.',
    ),
    GameType.wouldYouRather => const GameStyle(
      name: 'Would you rather',
      emoji: '⚖️',
      light: Color(0xFFFBE7DA),
      dark: Color(0xFF473429),
      howTo: 'Pick one of two. See how often you choose the same.',
    ),
    GameType.sharedTrivia => const GameStyle(
      name: 'Team trivia',
      emoji: '💡',
      light: Color(0xFFE1EFE4),
      dark: Color(0xFF2C3D31),
      howTo: 'Answer together. Every right answer counts for the team.',
    ),
    GameType.emojiDecode => const GameStyle(
      name: 'Emoji decode',
      emoji: '🎬',
      light: Color(0xFFFBF1D5),
      dark: Color(0xFF453D25),
      howTo: 'Work out what each set of emojis stands for.',
    ),
    GameType.agreeOMeter => const GameStyle(
      name: 'Agree-o-meter',
      emoji: '🌡️',
      light: Color(0xFFDDEDF5),
      dark: Color(0xFF283B45),
      howTo: 'Rate each hot take. Find out how in tune you are.',
    ),
    GameType.rankIt => const GameStyle(
      name: 'Rank it',
      emoji: '🏅',
      light: Color(0xFFF7DFE3),
      dark: Color(0xFF462C32),
      howTo: 'Drag the items into your order, favourite first.',
    ),
  };
}
