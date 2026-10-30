import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../ui/buddies.dart';
import '../../ui/game_style.dart';
import '../../ui/sticker.dart';
import '../../ui/theme.dart';

/// Side-by-side comparison of both people's answers, used by the live reveal
/// and by history. The summary lands first, then each answer drops in.
/// With [celebrate], a good result sets off an emoji burst.
class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.game, required this.partnerName, this.celebrate = false});

  final Game game;
  final String partnerName;
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final verdict = _Verdict.of(game.summary, partnerName);
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FadeIn(
              child: _SummaryHeader(game: game, verdict: verdict),
            ),
            const SizedBox(height: 18),
            for (final (i, q) in game.questions.indexed)
              FadeIn(
                delay: Duration(milliseconds: 450 + 130 * i),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AnswerCard(type: game.type, question: q, partnerName: partnerName),
                ),
              ),
          ],
        ),
        if (celebrate && verdict.great)
          Positioned.fill(child: EmojiBurst(emojis: [GameStyle.of(game.type).emoji, '✨', '🎉', '💛'])),
      ],
    );
  }
}

/// (big number, suffix, headline, detail, great?)
class _Verdict {
  const _Verdict(this.value, this.suffix, this.headline, this.detail, {this.great = false});

  final int? value;
  final String suffix;
  final String headline;
  final String detail;
  final bool great;

  static _Verdict of(GameSummary? s, String partner) => switch (s) {
    MatchSummary(:final matches, :final total) => _Verdict(
      matches,
      ' / $total',
      matches == total
          ? 'perfectly in sync!'
          : matches * 2 >= total
          ? 'pretty in sync.'
          : 'opposites attract?',
      'times you picked the same thing',
      great: matches * 2 >= total,
    ),
    KnowsSummary(:final myCorrect, :final partnerCorrect, :final aboutPartner, :final aboutMe) => _Verdict(
      null,
      '',
      myCorrect == partnerCorrect
          ? "it's a tie!"
          : myCorrect > partnerCorrect
          ? 'you know $partner better 😏'
          : '$partner knows you better 👀',
      'you guessed $myCorrect/$aboutPartner · $partner guessed $partnerCorrect/$aboutMe',
      great: myCorrect + partnerCorrect >= (aboutMe + aboutPartner) / 2,
    ),
    TriviaSummary(:final myScore, :final partnerScore, :final total) => _Verdict(
      myScore + partnerScore,
      ' / ${total * 2}',
      myScore + partnerScore >= total * 1.5 ? 'big brain duo.' : 'team effort. mostly.',
      'you $myScore · $partner $partnerScore',
      great: myScore + partnerScore >= total,
    ),
    ClosenessSummary(:final percent, :final exact, :final total) => _Verdict(
      percent,
      '%',
      percent >= 80
          ? 'basically the same brain.'
          : percent >= 50
          ? 'mostly on the same page.'
          : 'spicy disagreement.',
      'exactly the same on $exact of $total',
      great: percent >= 60,
    ),
    RankSummary(:final percent, :final sameTop, :final total) => _Verdict(
      percent,
      '%',
      percent >= 80
          ? 'practically the same list.'
          : percent >= 50
          ? 'similar tastes.'
          : 'very different priorities.',
      'same #1 on $sameTop of $total',
      great: percent >= 60,
    ),
    null => const _Verdict(null, '', 'results', ''),
  };
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.game, required this.verdict});

  final Game game;
  final _Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = GameStyle.of(game.type);
    final ink = text.apply(bodyColor: DuoColors.ink, displayColor: DuoColors.ink);

    return Sticker(
      color: style.tint(context),
      pattern: style.pattern,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      child: Column(
        children: [
          Buddies(size: 80, mood: verdict.great ? BuddyMood.celebrating : BuddyMood.happy),
          if (verdict.value != null)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: verdict.value!.toDouble()),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text('${v.round()}${verdict.suffix}', style: ink.displayMedium),
            ),
          Text(verdict.headline, style: ink.headlineSmall, textAlign: TextAlign.center),
          if (verdict.detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(verdict.detail, textAlign: TextAlign.center, style: ink.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.type, required this.question, required this.partnerName});

  final GameType type;
  final GameQuestion question;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final q = question;
    final matched = switch (type) {
      GameType.wouldYouRather || GameType.agreeOMeter => q.myChoice != null && q.myChoice == q.partnerChoice,
      GameType.rankIt => q.myRanking != null && q.myRanking?.join() == q.partnerRanking?.join(),
      _ => false,
    };

    return Sticker(
      depth: 3,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  type == GameType.wouldYouRather ? q.options.join('  or  ') : q.prompt,
                  style: type == GameType.emojiDecode ? text.headlineSmall : text.titleMedium,
                ),
              ),
              if (matched) const Tag('✨ same!', color: DuoColors.sunflower),
            ],
          ),
          if (type == GameType.whoKnowsWhom)
            Text(q.about == About.me ? 'about you' : 'about $partnerName', style: text.bodySmall),
          const SizedBox(height: 12),
          switch (type) {
            GameType.rankIt => _Rankings(question: q, partnerName: partnerName),
            GameType.agreeOMeter => _AgreeCompare(question: q, partnerName: partnerName),
            _ => _ChoicePair(type: type, question: q, partnerName: partnerName),
          },
        ],
      ),
    );
  }
}

class _ChoicePair extends StatelessWidget {
  const _ChoicePair({required this.type, required this.question, required this.partnerName});

  final GameType type;
  final GameQuestion question;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final q = question;
    String opt(int? i) => i == null || i >= q.options.length ? '—' : q.options[i];
    final hasKey = type == GameType.sharedTrivia || type == GameType.emojiDecode;

    final (myGood, partnerGood) = switch (type) {
      _ when hasKey => (q.myChoice == q.correctOption, q.partnerChoice == q.correctOption),
      // In who-knows-whom only the guesser can be right or wrong.
      GameType.whoKnowsWhom => (
        q.about == About.partner ? q.myChoice == q.partnerChoice : null,
        q.about == About.me ? q.myChoice == q.partnerChoice : null,
      ),
      _ => (null, null),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Answer(who: 'you', answer: opt(q.myChoice), good: myGood),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Answer(who: partnerName, answer: opt(q.partnerChoice), good: partnerGood),
            ),
          ],
        ),
        if (hasKey && q.correctOption != null) ...[
          const SizedBox(height: 8),
          Text('answer: ${opt(q.correctOption)}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.who, required this.answer, this.good});

  final String who;
  final String answer;
  final bool? good;

  @override
  Widget build(BuildContext context) {
    final fill = switch (good) {
      true => DuoColors.mint,
      false => DuoColors.bubblegum.withValues(alpha: 0.6),
      null => Theme.of(context).colorScheme.surfaceContainer,
    };
    final onFill = good == null ? null : DuoColors.ink;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DuoColors.line(context), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: onFill)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(answer, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: onFill)),
              ),
              if (good != null) Icon(good! ? Icons.check_rounded : Icons.close_rounded, size: 18, color: DuoColors.ink),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rankings extends StatelessWidget {
  const _Rankings({required this.question, required this.partnerName});

  final GameQuestion question;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final q = question;
    Widget column(String who, List<int>? order) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DuoColors.line(context), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(who, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),
            for (final (pos, item) in (order ?? const <int>[]).indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${pos + 1}. ${q.options[item]}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    // Bold where both put the item in the same place.
                    fontWeight:
                        q.myRanking != null && q.partnerRanking != null && q.myRanking![pos] == q.partnerRanking![pos]
                        ? FontWeight.w800
                        : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [column('you', q.myRanking), const SizedBox(width: 10), column(partnerName, q.partnerRanking)],
    );
  }
}

class _AgreeCompare extends StatelessWidget {
  const _AgreeCompare({required this.question, required this.partnerName});

  final GameQuestion question;
  final String partnerName;

  static const _faces = ['😖', '🙁', '😐', '🙂', '😍'];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final me = question.myChoice;
    final partner = question.partnerChoice;

    Widget marker(int i) {
      final labels = [if (me == i) 'you', if (partner == i) partnerName];
      return Expanded(
        child: Column(
          children: [
            AnimatedOpacity(
              opacity: labels.isEmpty ? 0.3 : 1,
              duration: const Duration(milliseconds: 300),
              child: Text(_faces[i], style: TextStyle(fontSize: labels.isEmpty ? 22 : 30)),
            ),
            const SizedBox(height: 4),
            Text(labels.join(' & '), style: text.labelSmall, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (var i = 0; i < 5; i++) marker(i)]),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('nope', style: text.bodySmall),
            const Spacer(),
            Text('absolutely', style: text.bodySmall),
          ],
        ),
      ],
    );
  }
}
