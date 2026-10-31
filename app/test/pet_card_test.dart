import 'package:duo/core/models.dart';
import 'package:duo/features/pet/pet_card.dart';
import 'package:duo/features/pet/pet_controller.dart';
import 'package:duo/ui/pet_sprite.dart';
import 'package:duo/ui/sticker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> petJson({
  int xp = 40,
  int level = 2,
  String stage = 'baby',
  String mood = 'happy',
  bool me = false,
  bool partner = false,
  String? outfit,
}) => {
  'name': 'Mochi',
  'color': 'peach',
  'outfit': outfit,
  'xp': xp,
  'level': level,
  'stage': stage,
  'levelXp': 15 * level * (level - 1),
  'nextLevelXp': 15 * (level + 1) * level,
  'mood': mood,
  'patted': {'me': me, 'partner': partner},
  'unlocked': <String>[],
  'nextUnlock': {'id': 'bow', 'level': 3},
};

class FakePet extends PetController {
  FakePet(this.json);
  Map<String, dynamic> json;
  int pats = 0;

  @override
  Future<PetInfo> build() async => PetInfo.fromJson(json);

  @override
  Future<void> pat() async {
    pats++;
    state = AsyncData(
      PetInfo.fromJson({
        ...json,
        'xp': json['xp'] + 5,
        'patted': {'me': true, 'partner': false},
      }),
    );
  }
}

Future<FakePet> pumpCard(WidgetTester tester, Map<String, dynamic> json) async {
  final fake = FakePet(json);
  await tester.pumpWidget(
    ProviderScope(
      // A fresh scope each time, so a new fake replaces the old one.
      key: UniqueKey(),
      overrides: [petProvider.overrideWith(() => fake)],
      child: const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(20),
            child: PetCard(otherName: 'Ravi'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('every stage and mood fits on a phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (stage, level) in [('egg', 1), ('baby', 2), ('kid', 5), ('grown', 8)]) {
      for (final mood in ['happy', 'hungry', 'sleepy']) {
        await pumpCard(
          tester,
          petJson(
            stage: stage,
            level: level,
            xp: 15 * level * (level - 1) + 3,
            mood: mood,
            outfit: level >= 5 ? 'cap' : null,
          ),
        );
        expect(tester.takeException(), isNull, reason: '$stage/$mood');
        expect(find.byType(PetSprite), findsOneWidget);
      }
    }
    expect(find.text('sleepy and missing you'), findsOneWidget);
  });

  testWidgets('an egg asks you to play together to hatch it', (tester) async {
    await pumpCard(tester, petJson(stage: 'egg', level: 1, xp: 0, mood: 'sleepy'));
    expect(find.text('an egg… something’s wiggling'), findsOneWidget);
    expect(find.text('30 xp to level 2 · 🎀 at 3'), findsOneWidget);
  });

  testWidgets('a pat counts once and shows who patted', (tester) async {
    final fake = await pumpCard(tester, petJson(partner: true));
    expect(find.text('ravi gave a pat today 💕'), findsOneWidget);

    await tester.tap(find.byType(StickerButton));
    await tester.pumpAndSettle();
    expect(fake.pats, 1);
    expect(find.text('patted today ✓'), findsOneWidget);

    // Patting the pet itself again just plays the animation.
    await tester.tap(find.bySemanticsLabel('Pat Mochi'));
    await tester.pumpAndSettle();
    expect(fake.pats, 1);
  });
}
