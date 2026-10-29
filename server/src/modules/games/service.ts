import { Prisma, type Game, type Pair, type PrismaClient, type Question } from '@prisma/client';
import { badRequest, conflict, notFound } from '../../lib/errors.js';
import { track } from '../../lib/events.js';
import { dateToDay, dayToDate, localDay } from '../../lib/time.js';
import { bankGame } from './bank.js';
import { GAME_TYPES, type GameContent, type GameTypeName } from './content.js';

export interface ProvidedGame {
  content: GameContent;
  source: 'AI' | 'BANK';
}

// Where game content comes from. Day 3 uses the bank; Day 5 swaps in the LLM
// with the bank as fallback, without touching anything below.
export type GameProvider = (args: { pair: Pair; day: string; type: GameTypeName }) => Promise<ProvidedGame>;

export const bankProvider: GameProvider = async ({ pair, day, type }) => ({
  content: bankGame(type, `${pair.id}:${day}`),
  source: 'BANK',
});

// Rotate through the types so consecutive days feel different.
export function typeForDay(day: string): GameTypeName {
  const n = Math.floor(dayToDate(day).getTime() / 86_400_000);
  return GAME_TYPES[n % GAME_TYPES.length]!;
}

export interface SubmittedAnswer {
  questionId: string;
  choice: number;
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

  // Returns the pair's game for `day`, creating it on first request. The
  // nightly job (Day 5) normally creates it ahead of time.
  async ensureGame(pair: Pair, day: string): Promise<GameWithQuestions> {
    const where = { pairId_day: { pairId: pair.id, day: dayToDate(day) } };
    const existing = await this.prisma.game.findUnique({ where, include: { questions: true } });
    if (existing) return existing;

    const type = typeForDay(day);
    const { content, source } = await this.provider({ pair, day, type });
    try {
      return await this.prisma.game.create({
        data: {
          pairId: pair.id,
          day: dayToDate(day),
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
    } catch (err) {
      // Both partners opened the app at once; the other request created it.
      if (!isUniqueViolation(err)) throw err;
      return this.prisma.game.findUniqueOrThrow({ where, include: { questions: true } });
    }
  }

  async today(userId: string) {
    const pair = await this.activePairFor(userId);
    const game = await this.ensureGame(pair, localDay(pair.timezone));
    return this.view(game.id, userId);
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
    this.validateAnswers(questions, answers);

    try {
      await this.prisma.$transaction(async (tx) => {
        await tx.submission.create({ data: { gameId, userId, idempotencyKey } });
        await tx.answer.createMany({
          data: answers.map((a) => ({ gameId, userId, questionId: a.questionId, choice: a.choice })),
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
        await track(this.prisma, 'game_completed', {
          pairId: game.pairId,
          props: { gameId, type: game.type },
        });
      }
    }
    return { game: await this.view(gameId, userId), justCompleted, replayed: false };
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

  private validateAnswers(questions: Question[], answers: SubmittedAnswer[]) {
    const byId = new Map(questions.map((q) => [q.id, q]));
    const seen = new Set<string>();
    for (const a of answers) {
      const q = byId.get(a.questionId);
      if (!q) throw badRequest('UNKNOWN_QUESTION', 'Answer refers to a question not in this game');
      if (seen.has(a.questionId)) throw badRequest('DUPLICATE_ANSWER', 'Each question can be answered once');
      if (a.choice >= q.options.length) throw badRequest('INVALID_CHOICE', 'Choice is out of range');
      seen.add(a.questionId);
    }
    if (seen.size !== questions.length)
      throw badRequest('INCOMPLETE', 'Answer every question before submitting');
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
    const choice = (questionId: string, mine: boolean) =>
      game.answers.find((a) => a.questionId === questionId && (a.userId === userId) === mine)?.choice ?? null;
    const aboutOf = (q: Question) => {
      const about = (q.meta as { about?: string }).about;
      return about ? (about === userId ? 'me' : 'partner') : null;
    };

    return {
      id: game.id,
      day: dateToDay(game.day),
      type: game.type,
      title: game.title,
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
        correctOption: completed ? q.correctOption : null,
      })),
      summary: completed ? summarise(game, userId) : null,
    };
  }
}

function summarise(
  game: GameWithQuestions & { answers: { questionId: string; userId: string; choice: number }[] },
  userId: string,
) {
  const pick = (qid: string, mine: boolean) =>
    game.answers.find((a) => a.questionId === qid && (a.userId === userId) === mine)?.choice;

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
    case 'SHARED_TRIVIA': {
      const score = (mine: boolean) =>
        game.questions.filter((q) => pick(q.id, mine) === q.correctOption).length;
      const myScore = score(true);
      const partnerScore = score(false);
      return { kind: 'trivia' as const, myScore, partnerScore, total: game.questions.length };
    }
  }
}

export type GameView = Awaited<ReturnType<GameService['view']>>;
