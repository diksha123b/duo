import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../ui/game_style.dart';
import '../../ui/theme.dart';

/// Side-by-side comparison of both partners' answers, used by the live reveal
/// and by history. The summary arrives first, then each answer fades in.
class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.game, required this.partnerName});

  final Game game;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FadeIn(
          child: _SummaryHeader(game: game, partnerName: partnerName),
        ),
        const SizedBox(height: 20),
        for (final (i, q) in game.questions.indexed) ...[
          FadeIn(
            delay: Duration(milliseconds: 400 + 120 * i),
            child: _AnswerCard(type: game.type, question: q, partnerName: partnerName),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.game, required this.partnerName});

  final Game game;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = GameStyle.of(game.type);

    // (big number, suffix, headline, detail)
    final (int? value, String suffix, String headline, String detail) = switch (game.summary) {
      MatchSummary(:final matches, :final total) => (
        matches,
        ' / $total matched',
        matches == total
            ? 'Perfectly in sync 💞'
            : matches * 2 >= total
            ? 'Pretty in sync'
            : 'Opposites attract',
        '',
      ),
      KnowsSummary(:final myCorrect, :final partnerCorrect, :final aboutPartner, :final aboutMe) => (
        null,
        '',
        myCorrect == partnerCorrect
            ? "It's a tie!"
            : myCorrect > partnerCorrect
            ? 'You know $partnerName better!'
            : '$partnerName knows you better!',
        'You guessed $myCorrect/$aboutPartner · $partnerName guessed $partnerCorrect/$aboutMe',
      ),
      TriviaSummary(:final myScore, :final partnerScore, :final total) => (
        myScore + partnerScore,
        ' / ${total * 2}',
        'Team score',
        'You $myScore · $partnerName $partnerScore',
      ),
      ClosenessSummary(:final percent, :final exact, :final total) => (
        percent,
        '%',
        percent >= 80
            ? 'So in tune 💞'
            : percent >= 50
            ? 'Mostly on the same page'
            : 'Agree to disagree',
        'Exactly the same on $exact of $total',
      ),
      RankSummary(:final percent, :final sameTop, :final total) => (
        percent,
        '%',
        percent >= 80
            ? 'Practically the same list'
            : percent >= 50
            ? 'Similar tastes'
            : 'Very different priorities',
        'Same favourite on $sameTop of $total',
      ),
      null => (null, '', 'Results', ''),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(color: style.tint(context), borderRadius: BorderRadius.circular(28)),
      child: Column(
        children: [
          Text(style.emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          if (value != null)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text('${v.round()}$suffix', style: text.displaySmall),
            ),
          Text(headline, style: text.headlineSmall, textAlign: TextAlign.center),
          if (detail.isNotEmpty) ...[const SizedBox(height: 6), Text(detail, textAlign: TextAlign.center)],
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(q.prompt, style: type == GameType.emojiDecode ? text.headlineSmall : text.titleMedium),
                ),
                if (matched) const Text('💞'),
              ],
            ),
            if (type == GameType.wouldYouRather) Text(q.options.join('  or  '), style: text.bodySmall),
            if (type == GameType.whoKnowsWhom)
              Text(q.about == About.me ? 'About you' : 'About $partnerName', style: text.bodySmall),
            const SizedBox(height: 12),
            switch (type) {
              GameType.rankIt => _Rankings(question: q, partnerName: partnerName),
              GameType.agreeOMeter => _AgreeCompare(question: q, partnerName: partnerName),
              _ => _ChoicePair(type: type, question: q, partnerName: partnerName),
            },
          ],
        ),
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
              child: _Answer(who: 'You', answer: opt(q.myChoice), good: myGood),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Answer(who: partnerName, answer: opt(q.partnerChoice), good: partnerGood),
            ),
          ],
        ),
        if (hasKey && q.correctOption != null) ...[
          const SizedBox(height: 8),
          Text('Answer: ${opt(q.correctOption)}', style: Theme.of(context).textTheme.bodySmall),
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
    final scheme = Theme.of(context).colorScheme;
    const green = Color(0xFF6E9E7B);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: good == null ? null : Border.all(color: good! ? green : scheme.error, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text(answer, style: Theme.of(context).textTheme.bodyLarge)),
              if (good != null)
                Icon(good! ? Icons.check_rounded : Icons.close_rounded, size: 18, color: good! ? green : scheme.error),
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
          borderRadius: BorderRadius.circular(16),
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
                        ? FontWeight.w700
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
      children: [column('You', q.myRanking), const SizedBox(width: 10), column(partnerName, q.partnerRanking)],
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final me = question.myChoice;
    final partner = question.partnerChoice;

    Widget marker(int i) {
      final labels = [if (me == i) 'You', if (partner == i) partnerName];
      return Expanded(
        child: Column(
          children: [
            AnimatedOpacity(
              opacity: labels.isEmpty ? 0.35 : 1,
              duration: const Duration(milliseconds: 300),
              child: Text(_faces[i], style: const TextStyle(fontSize: 24)),
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
            Text('Disagree', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const Spacer(),
            Text('Agree', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}
