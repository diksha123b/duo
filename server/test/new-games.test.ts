import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { dayToDate, localDay } from '../src/lib/time.js';
import { toContent } from '../src/modules/ai/provider.js';
import { bankGame } from '../src/modules/games/bank.js';
import { AGREE_SCALE, gameContentSchema, type GameTypeName } from '../src/modules/games/content.js';
import { rankingSimilarity } from '../src/modules/games/service.js';
import { auth, register, setupTestApp } from './helpers.js';

const ctx = setupTestApp();

async function pairWithGame(type: GameTypeName) {
  const a = (await register(ctx.app, 'asha@example.com', 'Asha')).tokens.accessToken;
  const b = (await register(ctx.app, 'ravi@example.com', 'Ravi')).tokens.accessToken;
  const inv = await ctx.app.inject({ method: 'POST', url: '/invites', headers: auth(a) });
  await ctx.app.inject({
    method: 'POST',
    url: '/invites/join',
    headers: auth(b),
    payload: { code: inv.json().invite.code },
  });
  const pair = await ctx.prisma.pair.findFirstOrThrow();
  const content = bankGame(type, 'seed');
  const game = await ctx.prisma.game.create({
    data: {
      pairId: pair.id,
      day: dayToDate(localDay(pair.timezone)),
      type,
      source: 'BANK',
      title: content.title,
      questions: {
        create: content.questions.map((q, position) => ({
          position,
          prompt: q.prompt,
          options: q.options,
          correctOption: q.correctOption ?? null,
        })),
      },
    },
    include: { questions: { orderBy: { position: 'asc' } } },
  });
  return { a, b, game };
}

type Answer = { questionId: string; choice?: number; ranking?: number[] };
const submit = (token: string, gameId: string, answers: Answer[]) =>
  ctx.app.inject({
    method: 'POST',
    url: `/games/${gameId}/submit`,
    headers: { ...auth(token), 'idempotency-key': randomUUID() },
    payload: { answers },
  });

describe('content rules for new types', () => {
  it('requires the standard agree scale', () => {
    const game = bankGame('AGREE_O_METER', 'x');
    const bad = { ...game, questions: game.questions.map((q) => ({ ...q, options: ['Yes', 'No'] })) };
    expect(gameContentSchema.safeParse(bad).success).toBe(false);
  });

  it('forces the standard scale onto generated agree-o-meter output', () => {
    const parsed = toContent('AGREE_O_METER', {
      title: 'Hot takes',
      questions: Array.from({ length: 5 }, (_, i) => ({
        prompt: `Take number ${i}`,
        options: [],
        correctOption: null,
        about: null,
      })),
    });
    expect(parsed.success).toBe(true);
    expect(parsed.data!.questions[0]!.options).toEqual(AGREE_SCALE);
  });

  it('requires 4 items to rank and an answer for emoji puzzles', () => {
    const rank = bankGame('RANK_IT', 'x');
    expect(
      gameContentSchema.safeParse({
        ...rank,
        questions: rank.questions.map((q) => ({ ...q, options: q.options.slice(0, 3) })),
      }).success,
    ).toBe(false);
    const emoji = bankGame('EMOJI_DECODE', 'x');
    expect(
      gameContentSchema.safeParse({
        ...emoji,
        questions: emoji.questions.map((q) => ({ ...q, correctOption: undefined })),
      }).success,
    ).toBe(false);
  });
});

describe('ranking similarity', () => {
  it('is 1 for the same order and 0 for the reverse', () => {
    expect(rankingSimilarity([0, 1, 2, 3], [0, 1, 2, 3])).toBe(1);
    expect(rankingSimilarity([0, 1, 2, 3], [3, 2, 1, 0])).toBe(0);
    expect(rankingSimilarity([0, 1, 2, 3], [1, 0, 2, 3])).toBe(0.75);
  });
});

describe('Rank it', () => {
  it('rejects anything that is not a full ranking', async () => {
    const { a, game } = await pairWithGame('RANK_IT');
    const answers = (ranking: number[]) => game.questions.map((q) => ({ questionId: q.id, ranking }));
    for (const bad of [
      [0, 1, 2],
      [0, 0, 1, 2],
      [0, 1, 2, 9],
    ]) {
      expect((await submit(a, game.id, answers(bad))).json().error.code).toBe('INVALID_RANKING');
    }
  });

  it('reveals both rankings and scores how similar they are', async () => {
    const { a, b, game } = await pairWithGame('RANK_IT');
    await submit(
      a,
      game.id,
      game.questions.map((q) => ({ questionId: q.id, ranking: [0, 1, 2, 3] })),
    );
    const res = (
      await submit(
        b,
        game.id,
        game.questions.map((q) => ({ questionId: q.id, ranking: [1, 0, 2, 3] })),
      )
    ).json().game;

    expect(res.questions[0]).toMatchObject({
      myRanking: [1, 0, 2, 3],
      partnerRanking: [0, 1, 2, 3],
      myChoice: 1,
    });
    expect(res.summary).toEqual({ kind: 'rank', percent: 75, sameTop: 0, total: 5 });
  });
});

describe('Agree-o-meter', () => {
  it('scores closeness on the 5-point scale', async () => {
    const { a, b, game } = await pairWithGame('AGREE_O_METER');
    await submit(
      a,
      game.id,
      game.questions.map((q) => ({ questionId: q.id, choice: 4 })),
    );
    // Partner: exact on 3 questions, opposite end on 2.
    const res = (
      await submit(
        b,
        game.id,
        game.questions.map((q, i) => ({ questionId: q.id, choice: i < 3 ? 4 : 0 })),
      )
    ).json().game;
    expect(res.summary).toEqual({ kind: 'closeness', percent: 60, exact: 3, total: 5 });
  });
});

describe('Emoji decode', () => {
  it('scores like trivia and reveals the answers', async () => {
    const { a, b, game } = await pairWithGame('EMOJI_DECODE');
    const right = game.questions.map((q) => ({ questionId: q.id, choice: q.correctOption! }));
    await submit(a, game.id, right);
    const res = (
      await submit(
        b,
        game.id,
        right.map((x, i) => (i === 0 ? { ...x, choice: (x.choice + 1) % 4 } : x)),
      )
    ).json().game;
    expect(res.summary).toEqual({ kind: 'trivia', myScore: 4, partnerScore: 5, total: 5 });
    expect(res.questions[0].correctOption).toBe(game.questions[0]!.correctOption);
  });
});
