import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../ui/arcade_style.dart';
import '../../ui/sticker.dart';
import '../../ui/states.dart';
import '../../ui/theme.dart';
import 'arcade_controller.dart';

/// The arcade: every live game, what's in progress, and the head-to-head record.
class ArcadeScreen extends ConsumerWidget {
  const ArcadeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lobby = ref.watch(arcadeProvider);
    final text = Theme.of(context).textTheme;

    Future<void> open(ArcadeKind kind) async {
      try {
        final id = await ref.read(arcadeProvider.notifier).start(kind);
        if (context.mounted) context.push('/arcade/$id');
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('arcade'),
        leading: (GoRouter.maybeOf(context)?.canPop() ?? true)
            ? null
            : IconButton(icon: const Icon(Icons.home_rounded), onPressed: () => context.go('/home')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AsyncView(
            value: lobby,
            onRetry: () => ref.invalidate(arcadeProvider),
            data: (l) => RefreshIndicator(
              onRefresh: () => ref.refresh(arcadeProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Text('play live, any time. your move goes straight to their phone.', style: text.bodyLarge),
                  const SizedBox(height: 18),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 0.92,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    children: [
                      for (final (i, kind) in ArcadeKind.values.indexed)
                        _GameCard(
                          kind: kind,
                          active: l.activeOf(kind),
                          record: l.record[kind],
                          tilt: i.isEven ? -1.2 : 1.2,
                          onTap: () => open(kind),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.kind,
    required this.active,
    required this.record,
    required this.tilt,
    required this.onTap,
  });

  final ArcadeKind kind;
  final MatchInfo? active;
  final ArcadeRecord? record;
  final double tilt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = ArcadeStyle.of(kind);
    final text = Theme.of(context).textTheme.apply(bodyColor: DuoColors.ink, displayColor: DuoColors.ink);
    final status = switch (active) {
      null => 'start a game',
      MatchInfo(yourTurn: true) => 'your turn!',
      _ => 'their turn',
    };
    return Sticker(
      color: style.color,
      pattern: style.pattern,
      tilt: tilt,
      depth: 5,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(style.emoji, style: const TextStyle(fontSize: 34)),
              const Spacer(),
              if (active?.yourTurn ?? false) const Tag('🔔', color: Colors.white),
            ],
          ),
          const Spacer(),
          Text(style.name, style: text.titleLarge),
          Text(style.tagline, style: text.bodySmall, maxLines: 2),
          const SizedBox(height: 8),
          Row(
            children: [
              Tag(status, color: Colors.white),
              const Spacer(),
              if (record != null) Text('${record!.you}–${record!.them}', style: text.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}
