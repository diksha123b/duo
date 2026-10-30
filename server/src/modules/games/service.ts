import {
  Prisma,
  type Game,
  type GameType,
  type Pair,
  type PrismaClient,
  type Question,
} from '@prisma/client';
import { badRequest, conflict, notFound } from '../../lib/errors.js';
import { track } from '../../lib/events.js';
import { applyCompletion } from '../../lib/streak.js';
import { addDays, dateToDay, dayToDate, localDay } from '../../lib/time.js';
import { bankGame } from './bank.js';
import { AGREE_SCALE, GAME_TYPES, type GameContent, type GameTypeName } from './content.js';

export interface ProvidedGame {
  content: GameContent;
  source: 'AI' | 'BANK';
}

// Where game content comes from. Day 3 uses the bank; Day 5 swaps in the LLM
// with the bank as fallback, without touching anything below.
export type GameProvider = (args: {
  pair: Pair;
  day: string;
  type: GameTypeName;
  // False makes a provider throw instead of degrading, so a job can retry.
  allowFallback?: boolean;
}) => Promise<ProvidedGame>;

export const bankProvider: GameProvider = async ({ pair, day, type }) => ({
  content: bankGame(type, `${pair.id}:${day}`, pair.relationship),
  source: 'BANK',
});

// Rotate through the types so consecutive days feel different.
export function typeForDay(day: string): GameTypeName {
  const n = Math.floor(dayToDate(day).getTime() / 86_400_000);
  return GAME_TYPES[n % GAME_TYPES.length]!;
}

// RANK_IT answers send `ranking` (option indexes, first to last); every
// other type sends `choice`.
export interface SubmittedAnswer {
  questionId: string;
  choice?: number;
  ranking?: number[];
}

type GameWithQuestions = Game & { questions: Question[] };

const isUniqueViolation = (err: unknown) =>
  err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002';

export class GameService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly provider: GameProvider,
  ) {}

  async activePairFor(userId: string): Promise<Pair> {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: { currentPair: true },
    });
    if (!user.currentPair) throw notFound('NOT_PAIRED', 'Pair up with someone to play');
    return user.currentPair;
  }

  // Returns the pair's daily game for `day`, creating it on first request.
  // The nightly job (Day 5) normally creates it ahead of time.
  async ensureGame(
    pair: Pair,
    day: string,
    opts: { allowFallback?: boolean } = {},
  ): Promise<GameWithQuestions> {
    const where = { pairId: pair.id, day: dayToDate(day), isDaily: true };
    const existing = await this.prisma.game.findFirst({ where, include: { questions: true } });
    if (existing) return existing;

    const type = typeForDay(day);
    const { content, source } = await this.provider({ pair, day, type, allowFallback: opts.allowFallback });
    try {
      return await this.createGame(pair, day, content, source, true);
    } catch (err) {
      // Both partners opened the app at once; the other request created it.
      if (!isUniqueViolation(err)) throw err;
      return this.prisma.game.findFirstOrThrow({ where, include: { questions: true } });
    }
  }

  private createGame(pair: Pair, day: string, content: GameContent, source: 'AI' | 'BANK', isDaily: boolean) {
    return this.prisma.game.create({
      data: {
        pairId: pair.id,
        day: dayToDate(day),
        isDaily,
        type: content.type,
        source,
        title: content.title,
        questions: {
          create: content.questions.map((q, position) => ({
            position,
            prompt: q.prompt,
            options: q.options,
            correctOption: q.correctOption ?? null,
            meta: q.about ? { about: q.about === 'A' ? pair.userAId : pair.userBId } : {},
          })),
        },
      },
      include: { questions: true },
    });
  }

  /**
   * A bonus round of `type`, just for fun: no streak, any time, as many as
   * you like. Returns the one already in progress for that type if there is
   * one, so both partners end up in the same round.
   */
  async startBonus(userId: string, type: GameTypeName) {
    const pair = await this.activePairFor(userId);
    const open = await this.prisma.game.findFirst({
      where: { pairId: pair.id, isDaily: false, type, completedAt: null },
    });
    if (open) return { game: await this.view(open.id, userId), created: false };
    // Questions from the curated bank (instant and free), shuffled fresh each round.
    const content = bankGame(type, `${pair.id}:bonus:${Date.now()}:${Math.random()}`, pair.relationship);
    const game = await this.createGame(pair, localDay(pair.timezone), content, 'BANK', false);
    await track(this.prisma, 'game_started', {
      userId,
      pairId: pair.id,
      props: { gameId: game.id, type, bonus: true },
    });
    return { game: await this.view(game.id, userId), created: true };
  }

  /** Bonus rounds still in progress for the pair (someone hasn't answered yet). */
  async openBonus(userId: string) {
    const pair = await this.activePairFor(userId);
    const games = await this.prisma.game.findMany({
      where: { pairId: pair.id, isDaily: false, completedAt: null },
      include: { submissions: true },
      orderBy: { createdAt: 'desc' },
    });
    return games.map((g) => ({
      id: g.id,
      type: g.type,
      meSubmitted: g.submissions.some((s) => s.userId === userId),
      partnerSubmitted: g.submissions.some((s) => s.userId !== userId),
    }));
  }

  async today(userId: string) {
    const pair = await this.activePairFor(userId);
    const game = await this.ensureGame(pair, localDay(pair.timezone));
    return this.view(game.id, userId);
  }

  /** The game types coming up on the pair's next six days, for a "this week" strip. */
  async lineup(userId: string) {
    const pair = await this.activePairFor(userId);
    const today = localDay(pair.timezone);
    return [1, 2, 3, 4, 5, 6].map((n) => {
      const day = addDays(today, n);
      return { day, type: typeForDay(day) };
    });
  }

  async gameForUser(gameId: string, userId: string) {
    const pair = await this.activePairFor(userId);
    const game = await this.prisma.game.findUnique({ where: { id: gameId } });
    if (!game || game.pairId !== pair.id) throw notFound('GAME_NOT_FOUND', 'Game not found');
    return { game, pair };
  }

  async submit(userId: string, gameId: string, idempotencyKey: string, answers: SubmittedAnswer[]) {
    const replay = await this.replay(userId, gameId, idempotencyKey);
    if (replay) return replay;

    const { game } = await this.gameForUser(gameId, userId);
    const questions = await this.prisma.question.findMany({ where: { gameId } });
    const rows = this.validateAnswers(game.type, questions, answers);

    try {
      await this.prisma.$transaction(async (tx) => {
        await tx.submission.create({ data: { gameId, userId, idempotencyKey } });
        await tx.answer.createMany({
          data: rows.map((a) => ({ gameId, userId, ...a })),
        });
      });
    } catch (err) {
      if (!isUniqueViolation(err)) throw err;
      // A concurrent request with the same key won the race: return its result.
      const raced = await this.replay(userId, gameId, idempotencyKey);
      if (raced) return raced;
      throw conflict('ALREADY_SUBMITTED', 'You already submitted answers for this game');
    }

    // Exactly one of the two submitters flips completedAt; that request
    // triggers the live reveal.
    let justCompleted = false;
    const submitted = await this.prisma.submission.count({ where: { gameId } });
    if (submitted === 2) {
      const flipped = await this.prisma.game.updateMany({
        where: { id: gameId, completedAt: null },
        data: { completedAt: new Date() },
      });
      justCompleted = flipped.count === 1;
      if (justCompleted) {
        // Only the daily game counts towards the streak.
        if (game.isDaily) await this.recordStreak(game.pairId, dateToDay(game.day));
        await track(this.prisma, 'game_completed', {
          pairId: game.pairId,
          props: { gameId, type: game.type, bonus: !game.isDaily },
        });
      }
    }
    return { game: await this.view(gameId, userId), justCompleted, replayed: false };
  }

  // Row lock so two games completing at once (e.g. a late one) can't race.
  private async recordStreak(pairId: string, day: string) {
    await this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT 1 FROM streaks WHERE pair_id = ${pairId}::uuid FOR UPDATE`;
      const row = await tx.streak.upsert({ where: { pairId }, create: { pairId }, update: {} });
      const next = applyCompletion(
        {
          current: row.current,
          longest: row.longest,
          lastCompletedDay: row.lastCompletedDay ? dateToDay(row.lastCompletedDay) : null,
        },
        day,
      );
      await tx.streak.update({
        where: { pairId },
        data: {
          current: next.current,
          longest: next.longest,
          lastCompletedDay: next.lastCompletedDay ? dayToDate(next.lastCompletedDay) : null,
        },
      });
    });
  }

  // Past games for the user's pair, newest first. Today's game only appears
  // once it's complete, so history never spoils an unplayed game.
  async history(userId: string, opts: { before?: string; limit: number }) {
    const pair = await this.activePairFor(userId);
    const today = localDay(pair.timezone);
    const games = await this.prisma.game.findMany({
      where: {
        pairId: pair.id,
        isDaily: true,
        day: opts.before ? { lt: dayToDate(opts.before) } : undefined,
        OR: [{ day: { lt: dayToDate(today) } }, { completedAt: { not: null } }],
      },
      orderBy: { day: 'desc' },
      take: opts.limit + 1,
      include: { questions: true, answers: true, submissions: true },
    });
    const page = games.slice(0, opts.limit);
    return {
      items: page.map((g) => ({
        id: g.id,
        day: dateToDay(g.day),
        type: g.type,
        title: g.title,
        completed: g.completedAt !== null,
        meSubmitted: g.submissions.some((s) => s.userId === userId),
        partnerSubmitted: g.submissions.some((s) => s.userId !== userId),
        summary: g.completedAt ? summarise(g, userId) : null,
      })),
      nextCursor: games.length > opts.limit ? dateToDay(page[page.length - 1]!.day) : null,
    };
  }

  private async replay(userId: string, gameId: string, idempotencyKey: string) {
    const prior = await this.prisma.submission.findUnique({ where: { idempotencyKey } });
    if (!prior) {
      const other = await this.prisma.submission.findUnique({ where: { gameId_userId: { gameId, userId } } });
      if (other) throw conflict('ALREADY_SUBMITTED', 'You already submitted answers for this game');
      return null;
    }
    if (prior.userId !== userId || prior.gameId !== gameId) {
      throw conflict('IDEMPOTENCY_KEY_REUSED', 'This idempotency key was used for a different request');
    }
    return { game: await this.view(gameId, userId), justCompleted: false, replayed: true };
  }

  private validateAnswers(type: GameType, questions: Question[], answers: SubmittedAnswer[]) {
    const byId = new Map(questions.map((q) => [q.id, q]));
    const seen = new Set<string>();
    const rows = answers.map((a) => {
      const q = byId.get(a.questionId);
      if (!q) throw badRequest('UNKNOWN_QUESTION', 'Answer refers to a question not in this game');
      if (seen.has(a.questionId)) throw badRequest('DUPLICATE_ANSWER', 'Each question can be answered once');
      seen.add(a.questionId);

      if (type === 'RANK_IT') {
        const r = a.ranking ?? [];
        const isPermutation =
          r.length === q.options.length && [...r].sort((x, y) => x - y).every((v, i) => v === i);
        if (!isPermutation) throw badRequest('INVALID_RANKING', 'Rank every item exactly once');
        return { questionId: q.id, choice: r[0]!, ranking: r };
      }
      if (a.choice === undefined || a.choice >= q.options.length) {
        throw badRequest('INVALID_CHOICE', 'Choice is out of range');
      }
      return { questionId: q.id, choice: a.choice, ranking: [] };
    });
    if (seen.size !== questions.length)
      throw badRequest('INCOMPLETE', 'Answer every question before submitting');
    return rows;
  }

  // What `userId` is allowed to see. The partner's answers and trivia
  // solutions stay hidden until both have submitted.
  async view(gameId: string, userId: string) {
    const game = await this.prisma.game.findUniqueOrThrow({
      where: { id: gameId },
      include: {
        questions: { orderBy: { position: 'asc' } },
        answers: true,
        submissions: true,
      },
    });
    const meSubmitted = game.submissions.some((s) => s.userId === userId);
    const partnerSubmitted = game.submissions.some((s) => s.userId !== userId);
    const completed = game.completedAt !== null;
    const answerOf = (questionId: string, mine: boolean) =>
      game.answers.find((a) => a.questionId === questionId && (a.userId === userId) === mine);
    const choice = (questionId: string, mine: boolean) => answerOf(questionId, mine)?.choice ?? null;
    const ranking = (questionId: string, mine: boolean) => {
      const r = answerOf(questionId, mine)?.ranking;
      return r && r.length > 0 ? r : null;
    };
    const aboutOf = (q: Question) => {
      const about = (q.meta as { about?: string }).about;
      return about ? (about === userId ? 'me' : 'partner') : null;
    };

    return {
      id: game.id,
      day: dateToDay(game.day),
      type: game.type,
      title: game.title,
      daily: game.isDaily,
      source: game.source,
      me: { submitted: meSubmitted },
      partner: { submitted: partnerSubmitted },
      completed,
      questions: game.questions.map((q) => ({
        id: q.id,
        prompt: q.prompt,
        options: q.options,
        about: aboutOf(q),
        myChoice: meSubmitted ? choice(q.id, true) : null,
        partnerChoice: completed ? choice(q.id, false) : null,
        myRanking: meSubmitted ? ranking(q.id, true) : null,
        partnerRanking: completed ? ranking(q.id, false) : null,
        correctOption: completed ? q.correctOption : null,
      })),
      summary: completed ? summarise(game, userId) : null,
    };
  }
}

// Spearman footrule similarity of two rankings: 1 = identical order, 0 = reversed.
export function rankingSimilarity(a: number[], b: number[]): number {
  const n = a.length;
  const posB = new Map(b.map((item, i) => [item, i]));
  const distance = a.reduce((sum, item, i) => sum + Math.abs(i - (posB.get(item) ?? i)), 0);
  const max = Math.floor((n * n) / 2);
  return max === 0 ? 1 : 1 - distance / max;
}

function summarise(
  game: GameWithQuestions & {
    answers: { questionId: string; userId: string; choice: number; ranking: number[] }[];
  },
  userId: string,
) {
  const answer = (qid: string, mine: boolean) =>
    game.answers.find((a) => a.questionId === qid && (a.userId === userId) === mine);
  const pick = (qid: string, mine: boolean) => answer(qid, mine)?.choice;
  const percent = (x: number) => Math.round(x * 100);

  switch (game.type) {
    case 'WOULD_YOU_RATHER': {
      const matches = game.questions.filter((q) => pick(q.id, true) === pick(q.id, false)).length;
      return { kind: 'match' as const, matches, total: game.questions.length };
    }
    case 'WHO_KNOWS_WHOM': {
      // Each person answers questions about themselves truthfully and guesses
      // the ones about their partner; a guess scores if it matches.
      let myCorrect = 0;
      let partnerCorrect = 0;
      let aboutPartner = 0;
      let aboutMe = 0;
      for (const q of game.questions) {
        const same = pick(q.id, true) === pick(q.id, false);
        if ((q.meta as { about?: string }).about === userId) {
          aboutMe++;
          if (same) partnerCorrect++;
        } else {
          aboutPartner++;
          if (same) myCorrect++;
        }
      }
      return { kind: 'knows' as const, myCorrect, partnerCorrect, aboutPartner, aboutMe };
    }
    case 'SHARED_TRIVIA':
    case 'EMOJI_DECODE': {
      const score = (mine: boolean) =>
        game.questions.filter((q) => pick(q.id, mine) === q.correctOption).length;
      const myScore = score(true);
      const partnerScore = score(false);
      return { kind: 'trivia' as const, myScore, partnerScore, total: game.questions.length };
    }
    case 'AGREE_O_METER': {
      // Each step apart on the 5-point scale costs a quarter of the question.
      const steps = AGREE_SCALE.length - 1;
      const gaps = game.questions.map((q) => Math.abs((pick(q.id, true) ?? 0) - (pick(q.id, false) ?? 0)));
      const closeness = gaps.reduce((sum, g) => sum + (steps - g) / steps, 0) / game.questions.length;
      return {
        kind: 'closeness' as const,
        percent: percent(closeness),
        exact: gaps.filter((g) => g === 0).length,
        total: game.questions.length,
      };
    }
    case 'RANK_IT': {
      const sims = game.questions.map((q) =>
        rankingSimilarity(answer(q.id, true)?.ranking ?? [], answer(q.id, false)?.ranking ?? []),
      );
      return {
        kind: 'rank' as const,
        percent: percent(sims.reduce((a, b) => a + b, 0) / sims.length),
        sameTop: game.questions.filter((q) => pick(q.id, true) === pick(q.id, false)).length,
        total: game.questions.length,
      };
    }
  }
}

export type GameView = Awaited<ReturnType<GameService['view']>>;
