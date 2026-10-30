import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../ui/game_style.dart';
import '../../ui/states.dart';
import '../../ui/theme.dart';
import '../auth/auth_controller.dart';
import '../game/game_controller.dart';
import '../pairing/pair_controller.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

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
    final me = ref.watch(authProvider).value;
    final now = DateTime.now();
    final text = Theme.of(context).textTheme;

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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                if (!realtime.connected) const _OfflineBanner(),
                Text(
                  '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}'.toUpperCase(),
                  style: text.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                AsyncView(
                  value: pair,
                  onRetry: () => ref.invalidate(pairProvider),
                  isEmpty: (p) => p == null,
                  data: (p) => FadeIn(
                    child: _Couple(
                      myName: me?.profile.displayName ?? 'You',
                      pair: p!,
                      presence: realtime.partnerPresence,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 260,
                  child: AsyncView(
                    value: game,
                    onRetry: () => ref.invalidate(todayGameProvider),
                    data: (g) => FadeIn(
                      delay: const Duration(milliseconds: 150),
                      child: _TodayCard(game: g, partnerName: pair.value?.partner.displayName ?? 'your partner'),
                    ),
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
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Reconnecting… live updates are paused')),
            ],
          ),
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
      Presence.playing => (const Color(0xFFE0A458), 'playing now'),
      Presence.online => (const Color(0xFF7FB08C), 'online'),
      Presence.offline => (Theme.of(context).colorScheme.outline, 'offline'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.url, required this.color});

  final String name;
  final String? url;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
      child: CircleAvatar(
        radius: 28,
        backgroundColor: color,
        backgroundImage: url != null ? NetworkImage(url!) : null,
        child: url == null
            ? Text(name.characters.first.toUpperCase(), style: Theme.of(context).textTheme.titleLarge)
            : null,
      ),
    );
  }
}

class _Couple extends StatelessWidget {
  const _Couple({required this.myName, required this.pair, required this.presence});

  final String myName;
  final PairInfo pair;
  final Presence presence;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final partner = pair.partner;
    final streak = pair.currentStreak;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 108,
              height: 62,
              child: Stack(
                children: [
                  _Avatar(name: myName, color: const Color(0xFFF7DFE3)),
                  Positioned(
                    left: 44,
                    child: _Avatar(name: partner.displayName, url: partner.avatarUrl, color: const Color(0xFFEDE6F7)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You & ${partner.displayName}', style: text.headlineSmall),
                  const SizedBox(height: 2),
                  PresenceDot(presence: presence),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Text(streak > 0 ? '🔥' : '🌱', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  streak > 0
                      ? '$streak ${streak == 1 ? 'day' : 'days'} in a row'
                      : 'Play together today to start a streak',
                  style: text.titleMedium,
                ),
              ),
              if (pair.longestStreak > streak) Text('best ${pair.longestStreak}', style: text.bodySmall),
            ],
          ),
        ),
        if (partner.interests.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${partner.displayName} is into ${partner.interests.take(4).join(', ')}',
            style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ],
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
    final style = GameStyle.of(game.type);
    final (status, action) = switch (game) {
      Game(completed: true) => ('Your results are in', 'See results'),
      Game(meSubmitted: true) => ('Waiting for $partnerName to play', 'View your answers'),
      Game(partnerSubmitted: true) => ('$partnerName already played. Your turn!', 'Play now'),
      _ => ('${game.questions.length} questions · about 2 minutes', 'Play now'),
    };
    return Material(
      color: style.tint(context),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => context.push('/game'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text("TODAY'S GAME", style: text.labelMedium),
                  const Spacer(),
                  Text(style.emoji, style: const TextStyle(fontSize: 34)),
                ],
              ),
              const SizedBox(height: 4),
              Text(game.title, style: text.headlineMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(style.name, style: text.titleMedium),
              const Spacer(),
              Row(
                children: [
                  Expanded(child: Text(status)),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: () => context.push('/game'), child: Text(action)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
