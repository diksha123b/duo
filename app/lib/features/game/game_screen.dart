import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../ui/game_style.dart';
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
    final style = game.value == null ? null : GameStyle.of(game.value!.type);

    return Scaffold(
      appBar: AppBar(title: Text(style == null ? "Today's game" : '${style.emoji}  ${style.name}')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AsyncView(
              value: game,
              onRetry: () => ref.invalidate(todayGameProvider),
              isEmpty: (g) => g.questions.isEmpty,
              empty: const EmptyView(message: "Today's game isn't ready yet. Check back in a minute."),
              data: (g) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: switch (g) {
                  Game(completed: true) => ResultsView(
                    key: const ValueKey('results'),
                    game: g,
                    partnerName: partnerName,
                  ),
                  Game(meSubmitted: true) => _Waiting(key: const ValueKey('waiting'), partnerName: partnerName),
                  _ => _Play(key: const ValueKey('play'), game: g, partnerName: partnerName),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Play extends ConsumerStatefulWidget {
  const _Play({super.key, required this.game, required this.partnerName});

  final Game game;
  final String partnerName;

  @override
  ConsumerState<_Play> createState() => _PlayState();
}

class _PlayState extends ConsumerState<_Play> {
  final Map<String, int> _choices = {};
  final Map<String, List<int>> _rankings = {};
  int _index = 0;

  List<GameQuestion> get _questions => widget.game.questions;
  bool get _onReview => _index == _questions.length;

  void _choose(int option) {
    HapticFeedback.selectionClick();
    setState(() => _choices[_questions[_index].id] = option);
    // Let the selection show for a beat before moving on.
    final at = _index;
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted && _index == at) setState(() => _index++);
    });
  }

  void _lockRanking(List<int> order) {
    HapticFeedback.selectionClick();
    setState(() {
      _rankings[_questions[_index].id] = order;
      _index++;
    });
  }

  Future<void> _submit() async {
    try {
      await ref.read(todayGameProvider.notifier).submit(_choices, rankings: _rankings);
    } catch (e) {
      // Answers stay in place; tapping submit again reuses the same idempotency key.
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = GameStyle.of(widget.game.type);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressDots(count: _questions.length, current: _index, color: scheme.primary),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                if (_index > 0)
                  TextButton.icon(
                    onPressed: () => setState(() => _index--),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Back'),
                  ),
                const Spacer(),
                Text(_onReview ? 'All done' : '${_index + 1} of ${_questions.length}', style: text.labelLarge),
              ],
            ),
          ),
          if (_index == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(style.howTo, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: _onReview
                  ? _Review(key: const ValueKey('review'), onSubmit: _submit)
                  : _QuestionCard(
                      key: ValueKey(_questions[_index].id),
                      type: widget.game.type,
                      question: _questions[_index],
                      partnerName: widget.partnerName,
                      selected: _choices[_questions[_index].id],
                      ranking: _rankings[_questions[_index].id],
                      onChoose: _choose,
                      onRank: _lockRanking,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.count, required this.current, required this.color});

  final int count;
  final int current;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i < current ? color : color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
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
    required this.ranking,
    required this.onChoose,
    required this.onRank,
  });

  final GameType type;
  final GameQuestion question;
  final String partnerName;
  final int? selected;
  final List<int>? ranking;
  final void Function(int) onChoose;
  final void Function(List<int>) onRank;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hint = switch (type) {
      GameType.whoKnowsWhom when question.about == About.me => 'About you',
      GameType.whoKnowsWhom => "Guess $partnerName's answer",
      GameType.wouldYouRather => 'Would you rather',
      GameType.sharedTrivia => 'Team trivia',
      GameType.emojiDecode => 'What could this be?',
      GameType.agreeOMeter => 'Hot take',
      GameType.rankIt => 'Your order',
    };

    final prompt = type == GameType.emojiDecode
        ? _EmojiPrompt(question.prompt)
        : Text(question.prompt, style: text.headlineSmall);

    final options = [
      for (var i = 0; i < question.options.length; i++)
        _OptionTile(
          label: question.options[i],
          selected: selected == i,
          big: type == GameType.wouldYouRather,
          onTap: () => onChoose(i),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(hint.toUpperCase(), style: text.labelMedium?.copyWith(color: scheme.primary)),
        const SizedBox(height: 8),
        prompt,
        const SizedBox(height: 24),
        Expanded(
          child: switch (type) {
            GameType.wouldYouRather => Column(
              children: [
                Expanded(child: options[0]),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('or', style: text.titleLarge?.copyWith(fontStyle: FontStyle.italic)),
                ),
                Expanded(child: options[1]),
              ],
            ),
            GameType.agreeOMeter => _AgreeScale(selected: selected, onChoose: onChoose),
            GameType.rankIt => _RankList(
              key: ValueKey(question.id),
              items: question.options,
              initial: ranking,
              onLock: onRank,
            ),
            _ => ListView(
              children: [for (final o in options) Padding(padding: const EdgeInsets.only(bottom: 10), child: o)],
            ),
          },
        ),
      ],
    );
  }
}

/// "🦁👑🌅 (movie)" → large emojis with the category as a caption.
class _EmojiPrompt extends StatelessWidget {
  const _EmojiPrompt(this.prompt);

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'^(.*?)\s*\(([^)]+)\)\s*$').firstMatch(prompt);
    final emojis = match?.group(1) ?? prompt;
    final category = match?.group(2);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: GameStyle.of(GameType.emojiDecode).tint(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(emojis, style: const TextStyle(fontSize: 52, letterSpacing: 6)),
          if (category != null) ...[
            const SizedBox(height: 6),
            Text('a $category', style: Theme.of(context).textTheme.titleMedium),
          ],
        ],
      ),
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
    final text = Theme.of(context).textTheme;
    return AnimatedScale(
      scale: selected ? 1.02 : 1,
      duration: const Duration(milliseconds: 200),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.14) : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              width: double.infinity,
              alignment: big ? Alignment.center : Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Text(
                label,
                textAlign: big ? TextAlign.center : TextAlign.start,
                style: big ? text.headlineSmall : text.titleMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _agreeFaces = ['😖', '🙁', '😐', '🙂', '😍'];
const _agreeLabels = ['Strongly disagree', 'Disagree', 'Not sure', 'Agree', 'Strongly agree'];

class _AgreeScale extends StatelessWidget {
  const _AgreeScale({required this.selected, required this.onChoose});

  final int? selected;
  final void Function(int) onChoose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Scrolls so all five fit on short screens.
    return ListView(
      children: [
        for (var i = 4; i >= 0; i--)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: selected == i ? scheme.primary.withValues(alpha: 0.14) : scheme.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: selected == i ? scheme.primary : scheme.outlineVariant,
                  width: selected == i ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onChoose(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    children: [
                      Text(_agreeFaces[i], style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 14),
                      Text(_agreeLabels[i], style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Drag to reorder, then lock in. Starts from the given order (when going
/// back) or the listed order.
class _RankList extends StatefulWidget {
  const _RankList({super.key, required this.items, required this.initial, required this.onLock});

  final List<String> items;
  final List<int>? initial;
  final void Function(List<int>) onLock;

  @override
  State<_RankList> createState() => _RankListState();
}

class _RankListState extends State<_RankList> {
  late final List<int> _order = [...(widget.initial ?? List.generate(widget.items.length, (i) => i))];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _order.length,
            // onReorderItem already adjusts `to` for the removed item.
            onReorderItem: (from, to) => setState(() => _order.insert(to, _order.removeAt(from))),
            proxyDecorator: (child, _, _) => Material(color: Colors.transparent, elevation: 6, child: child),
            itemBuilder: (context, i) => Padding(
              key: ValueKey(_order[i]),
              padding: const EdgeInsets.only(bottom: 10),
              child: ReorderableDragStartListener(
                index: i,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: GameStyle.of(GameType.rankIt).tint(context),
                        child: Text('${i + 1}', style: text.labelLarge),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Text(widget.items[_order[i]], style: text.titleMedium)),
                      Icon(Icons.drag_indicator_rounded, color: scheme.outline),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        FilledButton(onPressed: () => widget.onLock(List.of(_order)), child: const Text('Lock in my order')),
      ],
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
        const Text('✨', textAlign: TextAlign.center, style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text('All answered', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Answers lock once you submit. Go back to change any.', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        BusyButton(label: 'Submit answers', onPressed: onSubmit),
      ],
    );
  }
}

class _Waiting extends ConsumerWidget {
  const _Waiting({super.key, required this.partnerName});

  final String partnerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(realtimeProvider.select((r) => r.partnerPresence));
    final scheme = Theme.of(context).colorScheme;
    final line = switch (presence) {
      Presence.playing => '$partnerName is answering right now…',
      Presence.online => '$partnerName is around. Maybe give them a nudge?',
      Presence.offline => "We'll show your results the moment $partnerName finishes.",
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Breathing(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
              child: Text(
                partnerName.characters.first.toUpperCase(),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Waiting for $partnerName', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          PresenceDot(presence: presence),
          const SizedBox(height: 16),
          Text(line, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// A slow, endless scale pulse: calmer than a spinner.
class _Breathing extends StatefulWidget {
  const _Breathing({required this.child});

  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.94, end: 1.06).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}
