import 'package:duo/core/models.dart';

Me me({bool onboarded = true, bool paired = true}) => Me(
      id: 'u1',
      email: 'asha@example.com',
      pairId: paired ? 'p1' : null,
      profile: Profile(displayName: 'Asha', interests: onboarded ? ['music', 'travel', 'food'] : [], timezone: 'UTC'),
    );

Map<String, dynamic> gameJson({
  String type = 'WOULD_YOU_RATHER',
  bool meSubmitted = false,
  bool partnerSubmitted = false,
  bool completed = false,
  Map<String, dynamic>? summary,
  List<Map<String, dynamic>>? questions,
}) =>
    {
      'id': 'g1',
      'day': '2026-10-29',
      'type': type,
      'title': 'Would You Rather',
      'source': 'BANK',
      'me': {'submitted': meSubmitted},
      'partner': {'submitted': partnerSubmitted},
      'completed': completed,
      'summary': summary,
      'questions': questions ??
          [
            {
              'id': 'q1',
              'prompt': 'Would you rather…',
              'options': ['Tea', 'Coffee'],
              'about': null,
              'myChoice': meSubmitted ? 0 : null,
              'partnerChoice': completed ? 0 : null,
              'correctOption': null,
            },
            {
              'id': 'q2',
              'prompt': 'Would you rather…',
              'options': ['Beach', 'Mountains'],
              'about': null,
              'myChoice': meSubmitted ? 1 : null,
              'partnerChoice': completed ? 0 : null,
              'correctOption': null,
            },
          ],
    };
