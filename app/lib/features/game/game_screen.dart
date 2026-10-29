import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../ui/states.dart';
import '../home/home_screen.dart';
import '../pairing/pair_controller.dart';
import 'game_controller.dart';
import 'results_view.dart';

/// Today's game: play → waiting for partner → live reveal, all on one route
/// so the reveal arrives in place without navigation.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final RealtimeController _realtime = ref.read(realtimeProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _realtime.setPlaying(true));
  }

  @override
  void dispose() {
    _realtime.setPlaying(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(todayGameProvider);
    final partnerName = ref.watch(pairProvider).value?.partner.displayName ?? 'Partner';

    return Scaffold(
      appBar: AppBar(title: Text(game.value?.title ?? "Today's game")),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AsyncView(
              value: game,
              onRetry: () => ref.invalidate(todayGameProvider),
              isEmpty: (g) => g.questions.isEmpty,
              empty: const EmptyView(message: "Today's game isn't ready yet. Check back in a minute."),
              data: (g) => switch (g) {
                Game(completed: true) => ResultsView(game: g, partnerName: partnerName),
                Game(meSubmitted: true) => _Waiting(partnerName: partnerName),
                _ => _Play(game: g, partnerName: partnerName),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Play extends ConsumerStatefulWidget {
  const _Play({required this.game, required this.partnerName});

  final Game game;
  final String partnerName;

  @override
  ConsumerState<_Play> createState() => _PlayState();
}

class _PlayState extends ConsumerState<_Play> {
  final Map<String, int> _choices = {};
  int _index = 0;

  bool get _onReview => _index == widget.game.questions.length;

  void _choose(int option) {
    setState(() {
      _choices[widget.game.questions[_index].id] = option;
      _index++;
    });
  }

  Future<void> _submit() async {
    try {
      await ref.read(todayGameProvider.notifier).submit(_choices);
    } catch (e) {
      // Answers stay in place; tapping submit again reuses the same idempotency key.
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.game.questions;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: _index / questions.length, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 8),
          Row(children: [
            if (_index > 0)
              TextButton.icon(
                onPressed: () => setState(() => _index--),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back'),
              ),
            const Spacer(),
            Text(_onReview ? 'Ready!' : '${_index + 1} / ${questions.length}', style: text.labelLarge),
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _onReview
                  ? _Review(key: const ValueKey('review'), onSubmit: _submit)
                  : _QuestionCard(
                      key: ValueKey(questions[_index].id),
                      type: widget.game.type,
                      question: questions[_index],
                      partnerName: widget.partnerName,
                      selected: _choices[questions[_index].id],
                      onChoose: _choose,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.type,
    required this.question,
    required this.partnerName,
    required this.selected,
    required this.onChoose,
  });

  final GameType type;
  final GameQuestion question;
  final String partnerName;
  final int? selected;
  final void Function(int) onChoose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hint = switch (type) {
      GameType.whoKnowsWhom when question.about == About.me => 'About you: answer honestly',
      GameType.whoKnowsWhom => "Guess $partnerName's answer",
      GameType.wouldYouRather => 'Pick one. Will you match?',
      GameType.sharedTrivia => 'Team trivia: you both score together',
    };
    final twoUp = type == GameType.wouldYouRather;

    final options = [
      for (var i = 0; i < question.options.length; i++)
        _OptionTile(
          label: question.options[i],
          selected: selected == i,
          big: twoUp,
          onTap: () => onChoose(i),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(hint.toUpperCase(), style: text.labelMedium?.copyWith(color: scheme.primary)),
        const SizedBox(height: 8),
        Text(question.prompt, style: text.headlineSmall),
        const SizedBox(height: 24),
        if (twoUp)
          Expanded(
            child: Column(children: [
              Expanded(child: options[0]),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('or', style: text.titleMedium)),
              Expanded(child: options[1]),
            ]),
          )
        else
          ...options.expand((o) => [o, const SizedBox(height: 10)]),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.label, required this.selected, required this.onTap, this.big = false});

  final String label;
  final bool selected;
  final bool big;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          alignment: big ? Alignment.center : Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Text(
            label,
            textAlign: big ? TextAlign.center : TextAlign.start,
            style: big ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({super.key, required this.onSubmit});

  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_outline, size: 64),
        const SizedBox(height: 16),
        Text('All answered', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Answers lock once you submit. Go back to change any.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        BusyButton(label: 'Submit answers', onPressed: onSubmit),
      ],
    );
  }
}

class _Waiting extends ConsumerWidget {
  const _Waiting({required this.partnerName});

  final String partnerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(realtimeProvider.select((r) => r.partnerPresence));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(dimension: 48, child: CircularProgressIndicator()),
          const SizedBox(height: 24),
          Text('Waiting for $partnerName', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          PresenceDot(presence: presence),
          const SizedBox(height: 16),
          const Text('Results will appear here the moment they finish.', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
