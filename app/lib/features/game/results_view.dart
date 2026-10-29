import 'package:flutter/material.dart';

import '../../core/models.dart';

/// Side-by-side comparison of both partners' answers, used by the live reveal
/// and by history.
class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.game, required this.partnerName});

  final Game game;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SummaryHeader(summary: game.summary, partnerName: partnerName),
        const SizedBox(height: 20),
        for (final q in game.questions) ...[
          _AnswerRow(type: game.type, question: q, partnerName: partnerName),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.summary, required this.partnerName});

  final GameSummary? summary;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (headline, detail) = switch (summary) {
      MatchSummary(:final matches, :final total) => (
          '$matches / $total matched',
          matches == total ? 'Perfectly in sync! 💞' : matches >= total / 2 ? 'Pretty in sync.' : 'Opposites attract?',
        ),
      KnowsSummary(:final myCorrect, :final partnerCorrect, :final aboutPartner, :final aboutMe) => (
          myCorrect == partnerCorrect
              ? "It's a tie!"
              : myCorrect > partnerCorrect
                  ? 'You know $partnerName better!'
                  : '$partnerName knows you better!',
          'You guessed $myCorrect/$aboutPartner · $partnerName guessed $partnerCorrect/$aboutMe',
        ),
      TriviaSummary(:final myScore, :final partnerScore, :final total) => (
          'Team score: ${myScore + partnerScore} / ${total * 2}',
          'You $myScore · $partnerName $partnerScore',
        ),
      null => ('Results', ''),
    };
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Text(headline, style: text.headlineSmall, textAlign: TextAlign.center),
          if (detail.isNotEmpty) ...[const SizedBox(height: 6), Text(detail, textAlign: TextAlign.center)],
        ]),
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({required this.type, required this.question, required this.partnerName});

  final GameType type;
  final GameQuestion question;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final q = question;
    String opt(int? i) => i == null || i >= q.options.length ? '—' : q.options[i];

    final (myGood, partnerGood) = switch (type) {
      GameType.sharedTrivia => (q.myChoice == q.correctOption, q.partnerChoice == q.correctOption),
      // In who-knows-whom only the guesser can be right or wrong.
      GameType.whoKnowsWhom => (
          q.about == About.partner ? q.myChoice == q.partnerChoice : null,
          q.about == About.me ? q.myChoice == q.partnerChoice : null,
        ),
      GameType.wouldYouRather => (null, null),
    };
    final matched = type == GameType.wouldYouRather && q.myChoice == q.partnerChoice;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(q.prompt, style: text.titleMedium)),
              if (matched) const Text('💞 match'),
            ]),
            if (type == GameType.wouldYouRather) Text(q.options.join('  vs  '), style: text.bodySmall),
            if (type == GameType.whoKnowsWhom)
              Text(q.about == About.me ? 'About you' : 'About $partnerName', style: text.bodySmall),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Answer(who: 'You', answer: opt(q.myChoice), good: myGood)),
                const SizedBox(width: 12),
                Expanded(child: _Answer(who: partnerName, answer: opt(q.partnerChoice), good: partnerGood)),
              ],
            ),
            if (type == GameType.sharedTrivia && q.correctOption != null) ...[
              const SizedBox(height: 8),
              Text('Answer: ${opt(q.correctOption)}', style: text.bodySmall),
            ],
          ],
        ),
      ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: good == null ? null : Border.all(color: good! ? Colors.green : scheme.error, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text(answer, style: Theme.of(context).textTheme.bodyLarge)),
            if (good != null) Icon(good! ? Icons.check : Icons.close, size: 18, color: good! ? Colors.green : scheme.error),
          ]),
        ],
      ),
    );
  }
}
