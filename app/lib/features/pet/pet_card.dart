import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../ui/pet_sprite.dart';
import '../../ui/states.dart';
import '../../ui/sticker.dart';
import '../../ui/theme.dart';
import 'pet_controller.dart';

/// The pair's pet on the home screen: how it's doing, how close it is to the
/// next level, and a daily pat.
class PetCard extends ConsumerStatefulWidget {
  const PetCard({super.key, required this.otherName});

  final String otherName;

  @override
  ConsumerState<PetCard> createState() => _PetCardState();
}

class _PetCardState extends ConsumerState<PetCard> {
  int _pats = 0;

  /// Bumped on a level-up to replay the celebration.
  int _celebrations = 0;

  Future<void> _pat(PetInfo pet) async {
    setState(() => _pats++);
    if (pet.pattedByMe) return;
    try {
      await ref.read(petProvider.notifier).pat();
    } on ApiException catch (e) {
      // Already patted on another device: the next refresh shows it.
      if (e.code != 'ALREADY_PATTED' && mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Celebrate when the pet levels up (or hatches) while you're watching.
    ref.listen(petProvider, (prev, next) {
      final before = prev?.value?.level, after = next.value?.level;
      if (before != null && after != null && after > before) {
        setState(() => _celebrations++);
        final pet = next.value!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              before == 1
                  ? '${pet.name} hatched! 🐣'
                  : pet.unlocked.length > (prev!.value!.unlocked.length)
                  ? '${pet.name} reached level $after and unlocked a ${petOutfits[pet.unlocked.last]!.$2}! ✨'
                  : '${pet.name} reached level $after! ✨',
            ),
          ),
        );
      }
    });
    final pet = ref.watch(petProvider).value;
    if (pet == null) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    final other = widget.otherName.toLowerCase();
    final name = pet.name;
    final (moodLine, moodHint) = pet.stage == PetStage.egg
        ? ('an egg… something’s wiggling', 'finish a game together to hatch it')
        : switch (pet.mood) {
            PetMood.happy => ('full and happy', 'you played together today'),
            PetMood.hungry => ('a little hungry', 'play today’s game to feed $name'),
            PetMood.sleepy => ('sleepy and missing you', 'play together to wake $name up'),
          };

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Sticker(
          depth: 4,
          tilt: 0.8,
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Pat $name',
                child: GestureDetector(
                  onTap: () => _pat(pet),
                  child: PetSprite(
                    stage: pet.stage,
                    mood: pet.mood,
                    color: petColors[pet.color] ?? petColors['peach']!,
                    outfit: pet.outfit,
                    progress: pet.progress,
                    pats: _pats,
                    size: 112,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name.toLowerCase(), style: text.titleLarge, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Tag('lvl ${pet.level}', color: DuoColors.sunflower),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(moodLine, style: text.titleSmall),
                    Text(moodHint, style: text.bodySmall),
                    const SizedBox(height: 8),
                    _XpBar(pet: pet),
                    const SizedBox(height: 4),
                    Text(
                      pet.nextUnlock == null
                          ? '${pet.nextLevelXp - pet.xp} xp to level ${pet.level + 1}'
                          : '${pet.nextLevelXp - pet.xp} xp to level ${pet.level + 1} · '
                                '${petOutfits[pet.nextUnlock!.id]!.$1} at ${pet.nextUnlock!.level}',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (pet.pattedByMe)
                          Tag('patted today ✓', color: DuoColors.mint)
                        else
                          StickerButton(label: 'pat', emoji: '💕', onPressed: () => _pat(pet)),
                        TextButton(onPressed: () => showPetSheet(context), child: const Text('dress up')),
                      ],
                    ),
                    if (pet.pattedByPartner)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('$other gave a pat today 💕', style: text.bodySmall),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_celebrations > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: EmojiBurst(key: ValueKey(_celebrations), emojis: const ['✨', '💛', '🎉', '⭐']),
            ),
          ),
      ],
    );
  }
}

class _XpBar extends StatelessWidget {
  const _XpBar({required this.pet});

  final PetInfo pet;

  @override
  Widget build(BuildContext context) {
    final line = DuoColors.line(context);
    return Container(
      height: 14,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: line, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Align(
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: pet.progress),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => FractionallySizedBox(
            widthFactor: v,
            heightFactor: 1,
            child: const ColoredBox(color: DuoColors.tomato),
          ),
        ),
      ),
    );
  }
}

Future<void> showPetSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _PetSheet(),
);

/// Rename, recolour and dress up the pet. Outfits unlock as it levels up.
class _PetSheet extends ConsumerStatefulWidget {
  const _PetSheet();

  @override
  ConsumerState<_PetSheet> createState() => _PetSheetState();
}

class _PetSheetState extends ConsumerState<_PetSheet> {
  late final _name = TextEditingController(text: ref.read(petProvider).value?.name ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(PetController c) change) async {
    try {
      await change(ref.read(petProvider.notifier));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pet = ref.watch(petProvider).value;
    if (pet == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final line = DuoColors.line(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: PetSprite(
                stage: pet.stage,
                mood: pet.mood,
                color: petColors[pet.color] ?? petColors['peach']!,
                outfit: pet.outfit,
                progress: pet.progress,
                size: 140,
              ),
            ),
            const SizedBox(height: 12),
            Text('name', style: text.titleMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              maxLength: 16,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Save name',
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () => _saveName(pet),
                ),
              ),
              onSubmitted: (_) => _saveName(pet),
            ),
            const SizedBox(height: 16),
            Text('colour', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (final MapEntry(key: id, value: color) in petColors.entries)
                  Semantics(
                    button: true,
                    selected: pet.color == id,
                    label: id,
                    child: GestureDetector(
                      onTap: () => _run((c) => c.recolor(id)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: line, width: pet.color == id ? 4 : 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('outfits', style: text.titleMedium),
            Text('play together to unlock more', style: text.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('none'),
                  selected: pet.outfit == null,
                  onSelected: (_) => _run((c) => c.wear(null)),
                ),
                for (final MapEntry(key: id, value: (emoji, label)) in petOutfits.entries)
                  pet.unlocked.contains(id)
                      ? ChoiceChip(
                          label: Text('$emoji $label'),
                          selected: pet.outfit == id,
                          onSelected: (_) => _run((c) => c.wear(id)),
                        )
                      : Chip(
                          avatar: const Icon(Icons.lock_rounded, size: 16),
                          label: Text('$label · lvl ${_levelFor(id)}'),
                        ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'how ${pet.name} grows: daily game +30 xp · arcade game +15 · bonus round +10 · each pat +5',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _saveName(PetInfo pet) {
    final name = _name.text.trim();
    if (name.isEmpty || name == pet.name) return;
    FocusScope.of(context).unfocus();
    _run((c) => c.rename(name));
  }
}

/// The level each outfit unlocks at (mirrors the server's list).
int _levelFor(String outfit) => const {'bow': 3, 'flower': 4, 'cap': 5, 'party': 6, 'tophat': 7, 'crown': 9}[outfit]!;
