// Plain models mirroring the API's JSON. Hand-written rather than generated
// so there's no build_runner step.

class Profile {
  const Profile({required this.displayName, required this.interests, required this.timezone, this.avatarUrl});

  final String displayName;
  final List<String> interests;
  final String timezone;
  final String? avatarUrl;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    displayName: j['displayName'] as String,
    interests: List<String>.from(j['interests'] as List),
    timezone: j['timezone'] as String,
    avatarUrl: j['avatarUrl'] as String?,
  );
}

class Me {
  const Me({required this.id, required this.email, required this.profile, this.pairId});

  final String id;
  final String email;
  final Profile profile;
  final String? pairId;

  bool get onboarded => profile.interests.isNotEmpty;
  bool get paired => pairId != null;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    id: j['id'] as String,
    email: j['email'] as String,
    pairId: j['pairId'] as String?,
    profile: Profile.fromJson(j['profile'] as Map<String, dynamic>),
  );
}

class Partner {
  const Partner({required this.id, required this.displayName, required this.interests, this.avatarUrl});

  final String id;
  final String displayName;
  final List<String> interests;
  final String? avatarUrl;

  factory Partner.fromJson(Map<String, dynamic> j) => Partner(
    id: j['id'] as String,
    displayName: j['displayName'] as String,
    interests: List<String>.from(j['interests'] as List),
    avatarUrl: j['avatarUrl'] as String?,
  );
}

/// Who the two people are to each other.
enum Relationship {
  partners('PARTNERS'),
  bestFriends('BEST_FRIENDS'),
  friends('FRIENDS'),
  siblings('SIBLINGS'),
  parentChild('PARENT_CHILD'),
  colleagues('COLLEAGUES');

  const Relationship(this.wire);
  final String wire;

  static Relationship parse(String? s) => values.firstWhere((r) => r.wire == s, orElse: () => friends);
}

enum FamilyRole { parent, child }

class PairInfo {
  const PairInfo({
    required this.id,
    required this.partner,
    required this.currentStreak,
    required this.longestStreak,
    this.relationship = Relationship.friends,
    this.relationshipLabel,
    this.myRole,
  });

  final String id;
  final Partner partner;
  final int currentStreak;
  final int longestStreak;
  final Relationship relationship;

  /// What they call each other ("cousins", "grandma & me"), if they said.
  final String? relationshipLabel;

  /// Parent & child only.
  final FamilyRole? myRole;

  factory PairInfo.fromJson(Map<String, dynamic> j) {
    final streak = j['streak'] as Map<String, dynamic>;
    return PairInfo(
      id: j['id'] as String,
      partner: Partner.fromJson(j['partner'] as Map<String, dynamic>),
      currentStreak: streak['current'] as int,
      longestStreak: streak['longest'] as int,
      relationship: Relationship.parse(j['relationship'] as String?),
      relationshipLabel: j['relationshipLabel'] as String?,
      myRole: switch (j['myRole']) {
        'PARENT' => FamilyRole.parent,
        'CHILD' => FamilyRole.child,
        _ => null,
      },
    );
  }
}

class LineupDay {
  const LineupDay(this.day, this.type);

  final DateTime day;
  final GameType type;

  factory LineupDay.fromJson(Map<String, dynamic> j) =>
      LineupDay(DateTime.parse(j['day'] as String), GameType.parse(j['type'] as String));
}

class Invite {
  const Invite({required this.code, required this.expiresAt, this.label});

  final String code;
  final DateTime expiresAt;
  final String? label;

  factory Invite.fromJson(Map<String, dynamic> j) => Invite(
    code: j['code'] as String,
    expiresAt: DateTime.parse(j['expiresAt'] as String),
    label: j['label'] as String?,
  );
}

enum GameType {
  whoKnowsWhom('WHO_KNOWS_WHOM'),
  wouldYouRather('WOULD_YOU_RATHER'),
  sharedTrivia('SHARED_TRIVIA'),
  emojiDecode('EMOJI_DECODE'),
  agreeOMeter('AGREE_O_METER'),
  rankIt('RANK_IT');

  const GameType(this.wire);
  final String wire;

  static GameType parse(String s) => values.firstWhere((t) => t.wire == s);
}

enum About { me, partner }

class GameQuestion {
  const GameQuestion({
    required this.id,
    required this.prompt,
    required this.options,
    this.about,
    this.myChoice,
    this.partnerChoice,
    this.correctOption,
    this.myRanking,
    this.partnerRanking,
  });

  final String id;
  final String prompt;
  final List<String> options;
  final About? about;
  final int? myChoice;
  final int? partnerChoice;
  final int? correctOption;

  /// Rank it only: option indexes, first to last.
  final List<int>? myRanking;
  final List<int>? partnerRanking;

  factory GameQuestion.fromJson(Map<String, dynamic> j) => GameQuestion(
    id: j['id'] as String,
    prompt: j['prompt'] as String,
    options: List<String>.from(j['options'] as List),
    about: switch (j['about']) {
      'me' => About.me,
      'partner' => About.partner,
      _ => null,
    },
    myChoice: j['myChoice'] as int?,
    partnerChoice: j['partnerChoice'] as int?,
    correctOption: j['correctOption'] as int?,
    myRanking: (j['myRanking'] as List?)?.cast<int>(),
    partnerRanking: (j['partnerRanking'] as List?)?.cast<int>(),
  );
}

sealed class GameSummary {
  const GameSummary();

  static GameSummary? fromJson(Map<String, dynamic>? j) => switch (j?['kind']) {
    'match' => MatchSummary(j!['matches'] as int, j['total'] as int),
    'knows' => KnowsSummary(
      myCorrect: j!['myCorrect'] as int,
      partnerCorrect: j['partnerCorrect'] as int,
      aboutPartner: j['aboutPartner'] as int,
      aboutMe: j['aboutMe'] as int,
    ),
    'trivia' => TriviaSummary(j!['myScore'] as int, j['partnerScore'] as int, j['total'] as int),
    'closeness' => ClosenessSummary(j!['percent'] as int, j['exact'] as int, j['total'] as int),
    'rank' => RankSummary(j!['percent'] as int, j['sameTop'] as int, j['total'] as int),
    _ => null,
  };
}

class MatchSummary extends GameSummary {
  const MatchSummary(this.matches, this.total);
  final int matches;
  final int total;
}

class KnowsSummary extends GameSummary {
  const KnowsSummary({
    required this.myCorrect,
    required this.partnerCorrect,
    required this.aboutPartner,
    required this.aboutMe,
  });
  final int myCorrect;
  final int partnerCorrect;
  final int aboutPartner;
  final int aboutMe;
}

class TriviaSummary extends GameSummary {
  const TriviaSummary(this.myScore, this.partnerScore, this.total);
  final int myScore;
  final int partnerScore;
  final int total;
}

class ClosenessSummary extends GameSummary {
  const ClosenessSummary(this.percent, this.exact, this.total);
  final int percent;
  final int exact;
  final int total;
}

class RankSummary extends GameSummary {
  const RankSummary(this.percent, this.sameTop, this.total);
  final int percent;
  final int sameTop;
  final int total;
}

class Game {
  const Game({
    required this.id,
    required this.day,
    required this.type,
    required this.title,
    required this.meSubmitted,
    required this.partnerSubmitted,
    required this.completed,
    required this.questions,
    this.summary,
  });

  final String id;
  final String day;
  final GameType type;
  final String title;
  final bool meSubmitted;
  final bool partnerSubmitted;
  final bool completed;
  final List<GameQuestion> questions;
  final GameSummary? summary;

  factory Game.fromJson(Map<String, dynamic> j) => Game(
    id: j['id'] as String,
    day: j['day'] as String,
    type: GameType.parse(j['type'] as String),
    title: j['title'] as String,
    meSubmitted: (j['me'] as Map)['submitted'] as bool,
    partnerSubmitted: (j['partner'] as Map)['submitted'] as bool,
    completed: j['completed'] as bool,
    questions: (j['questions'] as List).map((q) => GameQuestion.fromJson(q as Map<String, dynamic>)).toList(),
    summary: GameSummary.fromJson(j['summary'] as Map<String, dynamic>?),
  );

  Game copyWith({bool? partnerSubmitted}) => Game(
    id: id,
    day: day,
    type: type,
    title: title,
    meSubmitted: meSubmitted,
    partnerSubmitted: partnerSubmitted ?? this.partnerSubmitted,
    completed: completed,
    questions: questions,
    summary: summary,
  );
}

enum Presence { online, playing, offline }

class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.day,
    required this.type,
    required this.title,
    required this.completed,
    required this.meSubmitted,
    this.summary,
  });

  final String id;
  final String day;
  final GameType type;
  final String title;
  final bool completed;
  final bool meSubmitted;
  final GameSummary? summary;

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
    id: j['id'] as String,
    day: j['day'] as String,
    type: GameType.parse(j['type'] as String),
    title: j['title'] as String,
    completed: j['completed'] as bool,
    meSubmitted: j['meSubmitted'] as bool,
    summary: GameSummary.fromJson(j['summary'] as Map<String, dynamic>?),
  );
}

/// Live, turn-by-turn games the pair can play any time.
enum ArcadeKind {
  chess('CHESS'),
  ludo('LUDO'),
  wordTiles('WORD_TILES'),
  fourInARow('FOUR_IN_A_ROW'),
  dotsAndBoxes('DOTS_AND_BOXES'),
  ticTacToe('TIC_TAC_TOE');

  const ArcadeKind(this.wire);
  final String wire;

  static ArcadeKind parse(String s) => values.firstWhere((k) => k.wire == s);
}

enum MatchResult { won, lost, draw }

class MatchInfo {
  const MatchInfo({
    required this.id,
    required this.kind,
    required this.active,
    required this.yourTurn,
    this.result,
    this.version = 0,
    this.seat = 0,
    this.view = const {},
  });

  final String id;
  final ArcadeKind kind;
  final bool active;
  final bool yourTurn;
  final MatchResult? result;
  final int version;

  /// 0 moves first (white in chess).
  final int seat;

  /// Game-specific board state from the server, already stripped of anything
  /// this player may not see.
  final Map<String, dynamic> view;

  factory MatchInfo.fromJson(Map<String, dynamic> j) => MatchInfo(
    id: j['id'] as String,
    kind: ArcadeKind.parse(j['kind'] as String),
    active: j['status'] == 'ACTIVE',
    yourTurn: j['yourTurn'] as bool,
    result: switch (j['result']) {
      'won' => MatchResult.won,
      'lost' => MatchResult.lost,
      'draw' => MatchResult.draw,
      _ => null,
    },
    version: j['version'] as int? ?? 0,
    seat: j['seat'] as int? ?? 0,
    view: Map<String, dynamic>.from(j['view'] as Map? ?? const {}),
  );
}

class ArcadeRecord {
  const ArcadeRecord(this.you, this.them, this.draws);

  final int you;
  final int them;
  final int draws;
}

class ArcadeLobby {
  const ArcadeLobby({required this.active, required this.recent, required this.record});

  final List<MatchInfo> active;
  final List<MatchInfo> recent;
  final Map<ArcadeKind, ArcadeRecord> record;

  MatchInfo? activeOf(ArcadeKind kind) => active.where((m) => m.kind == kind).firstOrNull;

  factory ArcadeLobby.fromJson(Map<String, dynamic> j) => ArcadeLobby(
    active: (j['active'] as List).map((m) => MatchInfo.fromJson(m as Map<String, dynamic>)).toList(),
    recent: (j['recent'] as List).map((m) => MatchInfo.fromJson(m as Map<String, dynamic>)).toList(),
    record: {
      for (final e in (j['record'] as Map<String, dynamic>).entries)
        ArcadeKind.parse(e.key): ArcadeRecord(e.value['you'] as int, e.value['them'] as int, e.value['draws'] as int),
    },
  );
}
