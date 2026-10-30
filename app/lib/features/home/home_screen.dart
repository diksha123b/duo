import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../ui/buddies.dart';
import '../../ui/game_style.dart';
import '../../ui/relationship_style.dart';
import '../../ui/states.dart';
import '../../ui/sticker.dart';
import '../../ui/theme.dart';
import '../auth/auth_controller.dart';
import '../game/game_controller.dart';
import '../pairing/pair_controller.dart';
import '../pairing/relationship_picker.dart';

const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _confirmUnpair(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('unpair?'),
        content: const Text('your streak ends and you’ll both need a new invite code to pair again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('unpair')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(pairProvider.notifier).unpair();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = ref.watch(pairProvider);
    final game = ref.watch(todayGameProvider);
    final lineup = ref.watch(lineupProvider);
    final realtime = ref.watch(realtimeProvider);
    final me = ref.watch(authProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('duo'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: () => context.push('/history'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (v) => switch (v) {
              'who' => _pickRelationship(context, ref, pair.value),
              'interests' => context.push('/interests'),
              'unpair' => _confirmUnpair(context, ref),
              _ => ref.read(authProvider.notifier).logout(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'who', child: Text('change who we are')),
              PopupMenuItem(value: 'interests', child: Text('edit my interests')),
              PopupMenuItem(value: 'unpair', child: Text('unpair')),
              PopupMenuItem(value: 'logout', child: Text('sign out')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(pairProvider);
          await ref.read(todayGameProvider.notifier).refresh().catchError((_) {});
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                if (!realtime.connected) const _OfflineBanner(),
                AsyncView(
                  value: pair,
                  onRetry: () => ref.invalidate(pairProvider),
                  isEmpty: (p) => p == null,
                  data: (p) => FadeIn(
                    child: _Hero(
                      myName: me?.profile.displayName ?? 'you',
                      pair: p!,
                      presence: realtime.partnerPresence,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 270,
                  child: AsyncView(
                    value: game,
                    onRetry: () => ref.invalidate(todayGameProvider),
                    data: (g) => FadeIn(
                      delay: const Duration(milliseconds: 120),
                      child: _TodayCard(game: g, otherName: pair.value?.partner.displayName ?? 'them'),
                    ),
                  ),
                ),
                if (lineup.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  FadeIn(
                    delay: const Duration(milliseconds: 240),
                    child: _Lineup(days: lineup),
                  ),
                ],
                const SizedBox(height: 26),
                const FadeIn(delay: Duration(milliseconds: 360), child: _GameShelf()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickRelationship(BuildContext context, WidgetRef ref, PairInfo? pair) async {
    if (pair == null) return;
    final choice = await showModalBottomSheet<RelationshipChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _RelationshipSheet(otherName: pair.partner.displayName),
    );
    if (choice == null) return;
    try {
      await ref.read(pairProvider.notifier).setRelationship(choice.tone, iAm: choice.role, label: choice.label);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _RelationshipSheet extends StatefulWidget {
  const _RelationshipSheet({required this.otherName});

  final String otherName;

  @override
  State<_RelationshipSheet> createState() => _RelationshipSheetState();
}

class _RelationshipSheetState extends State<_RelationshipSheet> {
  RelationshipChoice? _choice;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('who are you two?', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            RelationshipPicker(otherName: widget.otherName, onChanged: (c) => setState(() => _choice = c)),
            const SizedBox(height: 16),
            StickerButton(
              label: 'save',
              onPressed: (_choice?.complete ?? false) ? () async => Navigator.pop(context, _choice) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Sticker(
        color: DuoColors.sunflower,
        depth: 3,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 18, color: DuoColors.ink),
            SizedBox(width: 10),
            Expanded(
              child: Text('reconnecting… live updates paused', style: TextStyle(color: DuoColors.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

class PresenceDot extends StatelessWidget {
  const PresenceDot({super.key, required this.presence, this.name});

  final Presence presence;

  /// When given, reads as a sentence: "Ravi is playing now".
  final String? name;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (presence) {
      Presence.playing => (DuoColors.tangerine, 'playing now'),
      Presence.online => (DuoColors.mint, 'online'),
      Presence.offline => (Theme.of(context).colorScheme.outline, 'offline'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: DuoColors.line(context), width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(name == null ? label : '$name is $label', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.myName, required this.pair, required this.presence});

  final String myName;
  final PairInfo pair;
  final Presence presence;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rel = RelationshipStyle.of(pair.relationship);
    final partner = pair.partner;
    final streak = pair.currentStreak;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tag(
                    '${describePair(pair.relationship, pair.relationshipLabel).$1} '
                    '${describePair(pair.relationship, pair.relationshipLabel).$2}',
                    color: rel.left,
                  ),
                  const SizedBox(height: 10),
                  Text('${myName.toLowerCase()} & ${partner.displayName.toLowerCase()}', style: text.headlineLarge),
                  const SizedBox(height: 4),
                  Text(rel.tagline, style: text.bodyLarge),
                  const SizedBox(height: 8),
                  PresenceDot(presence: presence, name: partner.displayName),
                ],
              ),
            ),
            Buddies(
              size: 90,
              mood: presence == Presence.offline ? BuddyMood.sleepy : BuddyMood.happy,
              left: rel.left,
              right: rel.right,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Sticker(
                color: streak > 0 ? DuoColors.sunflower : null,
                tilt: -1.5,
                depth: 4,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(streak > 0 ? '🔥' : '🌱', style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            streak > 0 ? '$streak day streak' : 'no streak yet',
                            style: text.titleMedium?.copyWith(color: streak > 0 ? DuoColors.ink : null),
                          ),
                          Text(
                            streak > 0
                                ? (pair.longestStreak > streak ? 'best ever: ${pair.longestStreak}' : 'your best yet!')
                                : 'play today to start one',
                            style: text.bodySmall?.copyWith(color: streak > 0 ? DuoColors.ink : null),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (partner.interests.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Sticker(
                  tilt: 1.2,
                  depth: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${partner.displayName.toLowerCase()} is into', style: text.bodySmall),
                      Text(
                        partner.interests.take(3).join(', '),
                        style: text.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.game, required this.otherName});

  final Game game;
  final String otherName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.apply(bodyColor: DuoColors.ink, displayColor: DuoColors.ink);
    final style = GameStyle.of(game.type);
    final (status, action) = switch (game) {
      Game(completed: true) => ('the results are in 👀', 'see results'),
      Game(meSubmitted: true) => ('waiting on $otherName…', 'peek at mine'),
      Game(partnerSubmitted: true) => ('$otherName already played. your move!', 'play now'),
      _ => ('${game.questions.length} questions\n~2 minutes', 'play now'),
    };
    return Sticker(
      color: style.tint(context),
      pattern: style.pattern,
      depth: 6,
      padding: const EdgeInsets.all(22),
      onTap: () => context.push('/game'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Tag("today's game", color: Colors.white),
              const Spacer(),
              Transform.rotate(angle: 0.18, child: Text(style.emoji, style: const TextStyle(fontSize: 44))),
            ],
          ),
          const SizedBox(height: 4),
          Text(game.title.toLowerCase(), style: text.headlineMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          // Bank games are titled after their type, so don't say it twice.
          Text(
            game.title.toLowerCase() == style.name ? style.tagline : '${style.name} · ${style.tagline}',
            style: text.bodyMedium,
            maxLines: 2,
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(status, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: StickerButton(label: action, color: Colors.white, onPressed: () async => context.push('/game')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Lineup extends StatelessWidget {
  const _Lineup({required this.days});

  final List<LineupDay> days;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('coming up this week', style: text.titleLarge),
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            clipBehavior: Clip.none,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final d = days[i];
              final style = GameStyle.of(d.type);
              return SizedBox(
                width: 104,
                child: Sticker(
                  color: style.tint(context),
                  depth: 3,
                  tilt: i.isEven ? -1.5 : 1.5,
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i == 0 ? 'tomorrow' : _weekdays[d.day.weekday - 1],
                        style: text.labelMedium?.copyWith(color: DuoColors.ink),
                      ),
                      const Spacer(),
                      Text(style.emoji, style: const TextStyle(fontSize: 24)),
                      Text(
                        style.name,
                        style: text.labelLarge?.copyWith(color: DuoColors.ink, height: 1.1),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Every game, grouped like a little arcade shelf. Tapping one explains it.
class _GameShelf extends StatelessWidget {
  const _GameShelf();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('the games', style: text.titleLarge),
        Text('a new one lands every day. you never know which.', style: text.bodyMedium),
        const SizedBox(height: 12),
        for (final cat in GameCategory.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text('${cat.label} · ${cat.blurb}', style: text.labelMedium),
          ),
          // Same-height cards within a row.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final type in GameType.values.where((t) => GameStyle.of(t).category == cat))
                  Expanded(child: _ShelfCard(type: type)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ShelfCard extends StatelessWidget {
  const _ShelfCard({required this.type});

  final GameType type;

  @override
  Widget build(BuildContext context) {
    final style = GameStyle.of(type);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: Sticker(
        color: style.tint(context),
        pattern: style.pattern,
        depth: 4,
        padding: const EdgeInsets.all(14),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(style.emoji, style: const TextStyle(fontSize: 48)),
                  Text(style.name, style: Theme.of(ctx).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(style.tagline, style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Text(style.howTo, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(style.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(style.name, style: text.titleMedium?.copyWith(color: DuoColors.ink)),
            Text(style.tagline, style: text.bodySmall?.copyWith(color: DuoColors.ink), maxLines: 2),
          ],
        ),
      ),
    );
  }
}
