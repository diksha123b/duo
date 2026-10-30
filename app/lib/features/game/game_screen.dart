import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../ui/buddies.dart';
import '../../ui/game_style.dart';
import '../../ui/relationship_style.dart';
import '../../ui/sticker.dart';
import '../../ui/states.dart';
import '../../ui/theme.dart';
import '../home/home_screen.dart';
import '../pairing/pair_controller.dart';
import 'game_controller.dart';
import 'results_view.dart';

/// True while answers are picked but not yet submitted, so leaving can ask first.
final answersInProgress = ValueNotifier<bool>(false);

/// Asks before leaving a game with unsubmitted answers. Used by the router for
/// every way out: the back arrow, the browser's back button, Android back.
Future<bool> confirmLeaveGame(BuildContext context) async {
  if (!answersInProgress.value) return true;
  final quit = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('quit this game?'),
      content: const Text('your answers so far won’t be saved. you can start again any time today.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('quit')),
        FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('keep playing')),
      ],
    ),
  );
  if (quit == true) answersInProgress.value = false;
  return quit == true;
}

/// Today's game, or a bonus round when [bonusId] is given: play → waiting for
/// the other person → live reveal, all on one route so the reveal arrives in
/// place without navigation.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, this.bonusId});

  final String? bonusId;

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
    final id = widget.bonusId;
    final game = id == null ? ref.watch(todayGameProvider) : ref.watch(bonusGameProvider(id));
    PlayableGame notifier() =>
        id == null ? ref.read(todayGameProvider.notifier) : ref.read(bonusGameProvider(id).notifier);
    final pair = ref.watch(pairProvider).value;
    final partnerName = pair?.partner.displayName ?? 'Partner';
    final style = game.value == null ? null : GameStyle.of(game.value!.type);

    return Scaffold(
      appBar: AppBar(
        title: Text(style == null ? "today's game" : '${style.emoji} ${style.name}${id == null ? '' : ' · bonus'}'),
        // Opened directly (e.g. after a refresh) there's nothing to pop back to.
        leading: (GoRouter.maybeOf(context)?.canPop() ?? true)
            ? null
            : IconButton(icon: const Icon(Icons.home_rounded), onPressed: () => context.go('/home')),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AsyncView(
              value: game,
              onRetry: () => id == null ? ref.invalidate(todayGameProvider) : ref.invalidate(bonusGameProvider(id)),
              isEmpty: (g) => g.questions.isEmpty,
              empty: const EmptyView(message: "today's game is still baking. check back in a minute."),
              data: (g) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: switch (g) {
                  Game(completed: true) => ResultsView(
                    key: const ValueKey('results'),
                    game: g,
                    partnerName: partnerName,
                    celebrate: true,
                    onReact: (qid, emoji) => notifier().react(qid, emoji),
                    onComment: (text) => notifier().comment(text),
                  ),
                  Game(meSubmitted: true) => _Waiting(
                    key: const ValueKey('waiting'),
                    partnerName: partnerName,
                    relationship: pair?.relationship ?? Relationship.friends,
                  ),
                  _ => _Play(
                    key: const ValueKey('play'),
                    game: g,
                    partnerName: partnerName,
                    submit: (choices, rankings) => notifier().submit(choices, rankings: rankings),
                  ),
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
  const _Play({super.key, required this.game, required this.partnerName, required this.submit});

  final Game game;
  final String partnerName;
  final Future<void> Function(Map<String, int> choices, Map<String, List<int>> rankings) submit;

  @override
  ConsumerState<_Play> createState() => _PlayState();
}

class _PlayState extends ConsumerState<_Play> {
  final Map<String, int> _choices = {};
  final Map<String, List<int>> _rankings = {};
  int _index = 0;

  List<GameQuestion> get _questions => widget.game.questions;
  bool get _onReview => _index == _questions.length;

  @override
  void dispose() {
    // Submitted, revealed or quit: nothing left to lose.
    answersInProgress.value = false;
    super.dispose();
  }

  void _choose(int option) {
    HapticFeedback.selectionClick();
    answersInProgress.value = true;
    setState(() => _choices[_questions[_index].id] = option);
    // Let the selection show for a beat before moving on.
    final at = _index;
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted && _index == at) setState(() => _index++);
    });
  }

  void _lockRanking(List<int> order) {
    HapticFeedback.selectionClick();
    answersInProgress.value = true;
    setState(() {
      _rankings[_questions[_index].id] = order;
      _index++;
    });
  }

  Future<void> _submit() async {
    try {
      await widget.submit(_choices, _rankings);
      answersInProgress.value = false;
    } catch (e) {
      // Answers stay in place; tapping submit again reuses the same idempotency key.
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = GameStyle.of(widget.game.type);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressDots(count: _questions.length, current: _index, color: style.color),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                if (_index > 0)
                  TextButton.icon(
                    onPressed: () => setState(() => _index--),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('back'),
                  ),
                const Spacer(),
                Text(_onReview ? 'all done!' : '${_index + 1} of ${_questions.length}', style: text.labelLarge),
              ],
            ),
          ),
          if (_index == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(style.howTo, style: text.bodyMedium),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutBack,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
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
    final line = DuoColors.line(context);
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i < current ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: line, width: 1.5),
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
    final style = GameStyle.of(type);
    final hint = switch (type) {
      GameType.whoKnowsWhom when question.about == About.me => '🙋 about you',
      GameType.whoKnowsWhom => "🔍 guess $partnerName's answer",
      GameType.wouldYouRather => '⚖️ would you rather',
      GameType.sharedTrivia => '💡 team trivia',
      GameType.emojiDecode => '🎬 what could this be?',
      GameType.agreeOMeter => '🌶️ hot take',
      GameType.rankIt => '🏆 your order',
    };

    // The question sits on its own sticker in the game's colour; the emoji
    // puzzle brings its own.
    final ink = text.apply(bodyColor: DuoColors.ink, displayColor: DuoColors.ink);
    final prompt = switch (type) {
      GameType.emojiDecode => _EmojiPrompt(question.prompt),
      _ => Sticker(
        color: style.tint(context),
        pattern: style.pattern,
        tilt: -0.8,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tag(hint, color: Colors.white),
            const SizedBox(height: 12),
            Text(type == GameType.wouldYouRather ? 'would you rather…' : question.prompt, style: ink.headlineSmall),
          ],
        ),
      ),
    };

    final options = [
      for (var i = 0; i < question.options.length; i++)
        _OptionTile(
          label: question.options[i],
          selected: selected == i,
          color: style.color,
          big: type == GameType.wouldYouRather,
          onTap: () => onChoose(i),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        prompt,
        const SizedBox(height: 20),
        Expanded(
          child: switch (type) {
            GameType.wouldYouRather => Column(
              children: [
                Expanded(child: options[0]),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('or', style: text.headlineSmall?.copyWith(fontStyle: FontStyle.italic)),
                ),
                Expanded(child: options[1]),
              ],
            ),
            GameType.agreeOMeter => _AgreeScale(selected: selected, color: style.color, onChoose: onChoose),
            GameType.rankIt => _RankList(
              key: ValueKey(question.id),
              items: question.options,
              initial: ranking,
              color: style.color,
              onLock: onRank,
            ),
            _ => ListView(children: options),
          },
        ),
      ],
    );
  }
}

/// "🦁👑🌅 (movie)" → large emojis on a starry sticker, with the category.
class _EmojiPrompt extends StatelessWidget {
  const _EmojiPrompt(this.prompt);

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'^(.*?)\s*\(([^)]+)\)\s*$').firstMatch(prompt);
    final emojis = match?.group(1) ?? prompt;
    final category = match?.group(2);
    return Sticker(
      color: DuoColors.sunflower,
      pattern: StickerPattern.stars,
      tilt: -1.5,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
      child: Column(
        children: [
          Text(emojis, style: const TextStyle(fontSize: 54, letterSpacing: 6), textAlign: TextAlign.center),
          if (category != null) ...[
            const SizedBox(height: 6),
            Text('a $category', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: DuoColors.ink)),
          ],
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.big = false,
  });

  final String label;
  final bool selected;
  final Color color;
  final bool big;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = (big ? text.headlineSmall : text.titleMedium)?.copyWith(color: selected ? DuoColors.ink : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Sticker(
        color: selected ? color : null,
        tilt: selected ? -1.2 : 0,
        depth: 4,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          child: big
              ? Center(
                  child: Text(label, textAlign: TextAlign.center, style: style),
                )
              : Row(
                  children: [
                    Expanded(child: Text(label, style: style)),
                    if (selected) const Text('✔️'),
                  ],
                ),
        ),
      ),
    );
  }
}

const _agreeFaces = ['😖', '🙁', '😐', '🙂', '😍'];
const _agreeLabels = ['nope, never', 'not really', 'eh, maybe', 'yeah', 'absolutely'];

class _AgreeScale extends StatelessWidget {
  const _AgreeScale({required this.selected, required this.color, required this.onChoose});

  final int? selected;
  final Color color;
  final void Function(int) onChoose;

  @override
  Widget build(BuildContext context) {
    // Scrolls so all five fit on short screens.
    return ListView(
      children: [
        for (var i = 4; i >= 0; i--)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Sticker(
              color: selected == i ? color : null,
              depth: 3,
              tilt: selected == i ? -1 : 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              onTap: () => onChoose(i),
              child: Row(
                children: [
                  Text(_agreeFaces[i], style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 14),
                  Text(
                    _agreeLabels[i],
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: selected == i ? DuoColors.ink : null),
                  ),
                ],
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
  const _RankList({super.key, required this.items, required this.initial, required this.color, required this.onLock});

  final List<String> items;
  final List<int>? initial;
  final Color color;
  final void Function(List<int>) onLock;

  @override
  State<_RankList> createState() => _RankListState();
}

class _RankListState extends State<_RankList> {
  late final List<int> _order = [...(widget.initial ?? List.generate(widget.items.length, (i) => i))];
  static const _medals = ['🥇', '🥈', '🥉', '4'];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final line = DuoColors.line(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('drag to reorder. favourite on top.', style: text.bodySmall),
        const SizedBox(height: 8),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _order.length,
            // onReorderItem already adjusts `to` for the removed item.
            onReorderItem: (from, to) => setState(() => _order.insert(to, _order.removeAt(from))),
            proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
            itemBuilder: (context, i) => Padding(
              key: ValueKey(_order[i]),
              padding: const EdgeInsets.only(bottom: 10),
              child: ReorderableDragStartListener(
                index: i,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: i == 0 ? widget.color : Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: line, width: 2),
                    boxShadow: [BoxShadow(color: line, offset: const Offset(3, 3))],
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(_medals[i.clamp(0, 3)], style: text.titleLarge, textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.items[_order[i]],
                          style: text.titleMedium?.copyWith(color: i == 0 ? DuoColors.ink : null),
                        ),
                      ),
                      Icon(Icons.drag_indicator_rounded, color: i == 0 ? DuoColors.ink : line),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        StickerButton(
          label: 'lock in my order',
          color: widget.color,
          onPressed: () async => widget.onLock(List.of(_order)),
        ),
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
        const Center(child: Buddies(size: 100, mood: BuddyMood.happy)),
        const SizedBox(height: 16),
        Text('all answered!', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('answers lock once you submit. go back to change any.', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        BusyButton(label: 'lock it in', onPressed: onSubmit),
      ],
    );
  }
}

class _Waiting extends ConsumerWidget {
  const _Waiting({super.key, required this.partnerName, required this.relationship});

  final String partnerName;
  final Relationship relationship;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(realtimeProvider.select((r) => r.partnerPresence));
    final rel = RelationshipStyle.of(relationship);
    final line = switch (presence) {
      Presence.playing => '$partnerName is answering right now. no peeking.',
      Presence.online => '$partnerName is around. maybe give them a nudge?',
      Presence.offline => 'results land here the moment $partnerName finishes.',
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Buddies(
            size: 120,
            mood: presence == Presence.offline ? BuddyMood.sleepy : BuddyMood.waiting,
            left: rel.left,
            right: rel.right,
          ),
          const SizedBox(height: 20),
          Text('your turn’s done!', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          PresenceDot(presence: presence, name: partnerName),
          const SizedBox(height: 16),
          Text(line, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
