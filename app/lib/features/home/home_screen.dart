import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../ui/states.dart';
import '../auth/auth_controller.dart';
import '../game/game_controller.dart';
import '../pairing/pair_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _confirmUnpair(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair?'),
        content: const Text('Your streak ends and you will both need a new invite code to pair again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unpair')),
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
    final realtime = ref.watch(realtimeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('duo', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'interests' => context.push('/interests'),
              'unpair' => _confirmUnpair(context, ref),
              _ => ref.read(authProvider.notifier).logout(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'interests', child: Text('Edit interests')),
              PopupMenuItem(value: 'unpair', child: Text('Unpair')),
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
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
              padding: const EdgeInsets.all(20),
              children: [
                if (!realtime.connected) const _OfflineBanner(),
                AsyncView(
                  value: pair,
                  onRetry: () => ref.invalidate(pairProvider),
                  isEmpty: (p) => p == null,
                  data: (p) => _PartnerCard(pair: p!, presence: realtime.partnerPresence),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: AsyncView(
                    value: game,
                    onRetry: () => ref.invalidate(todayGameProvider),
                    data: (g) => _TodayCard(game: g, partnerName: pair.value?.partner.displayName ?? 'your partner'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(Icons.wifi_off, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text('Reconnecting… live updates are paused')),
          ]),
        ),
      ),
    );
  }
}

class PresenceDot extends StatelessWidget {
  const PresenceDot({super.key, required this.presence});

  final Presence presence;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (presence) {
      Presence.playing => (Colors.orange, 'playing now'),
      Presence.online => (Colors.green, 'online'),
      Presence.offline => (Theme.of(context).colorScheme.outline, 'offline'),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({required this.pair, required this.presence});

  final PairInfo pair;
  final Presence presence;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final partner = pair.partner;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: partner.avatarUrl != null ? NetworkImage(partner.avatarUrl!) : null,
                child: partner.avatarUrl == null ? Text(partner.displayName.characters.first.toUpperCase()) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(partner.displayName, style: text.titleLarge),
                  const SizedBox(height: 4),
                  PresenceDot(presence: presence),
                ]),
              ),
              Column(children: [
                Text('🔥 ${pair.currentStreak}', style: text.headlineSmall),
                Text('day streak', style: text.bodySmall),
              ]),
            ]),
            if (partner.interests.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final i in partner.interests) Chip(label: Text(i), visualDensity: VisualDensity.compact),
              ]),
            ],
            if (pair.longestStreak > 0) ...[
              const SizedBox(height: 8),
              Text('Longest streak: ${pair.longestStreak} days', style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.game, required this.partnerName});

  final Game game;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (status, action) = switch (game) {
      Game(completed: true) => ('Results are in!', 'See results'),
      Game(meSubmitted: true) => ('Waiting for $partnerName to play', 'View your answers'),
      Game(partnerSubmitted: true) => ('$partnerName already played. Your turn!', 'Play now'),
      _ => ('${game.questions.length} quick questions', 'Play now'),
    };
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/game'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("TODAY'S GAME", style: text.labelMedium),
              const SizedBox(height: 4),
              Text(game.title, style: text.headlineSmall),
              const SizedBox(height: 4),
              Text(status),
              const Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: FilledButton(onPressed: () => context.push('/game'), child: Text(action)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
