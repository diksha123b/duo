import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

/// Words, emoji and buddy colours for each kind of duo.
class RelationshipStyle {
  const RelationshipStyle({
    required this.label,
    required this.emoji,
    required this.tagline,
    required this.left,
    required this.right,
  });

  final String label;
  final String emoji;

  /// Shown under your names on home.
  final String tagline;
  final Color left;
  final Color right;

  static RelationshipStyle of(Relationship r) => switch (r) {
    Relationship.partners => const RelationshipStyle(
      label: 'partners',
      emoji: '💞',
      tagline: 'your daily little ritual.',
      left: DuoColors.bubblegum,
      right: DuoColors.tomato,
    ),
    Relationship.bestFriends => const RelationshipStyle(
      label: 'best friends',
      emoji: '👯',
      tagline: 'bestie check-in. no excuses.',
      left: DuoColors.grape,
      right: DuoColors.sunflower,
    ),
    Relationship.friends => const RelationshipStyle(
      label: 'friends',
      emoji: '🙌',
      tagline: 'one tiny game a day, together.',
      left: DuoColors.mint,
      right: DuoColors.sky,
    ),
    Relationship.siblings => const RelationshipStyle(
      label: 'siblings',
      emoji: '🧃',
      tagline: 'settle it once and for all.',
      left: DuoColors.tangerine,
      right: DuoColors.mint,
    ),
    Relationship.colleagues => const RelationshipStyle(
      label: 'work buddies',
      emoji: '💼',
      tagline: 'the best part of the workday.',
      left: DuoColors.sky,
      right: DuoColors.tangerine,
    ),
    Relationship.parentChild => const RelationshipStyle(
      label: 'parent & child',
      emoji: '🫶',
      tagline: 'family game time, in your pocket.',
      left: DuoColors.sky,
      right: DuoColors.sunflower,
    ),
  };
}
