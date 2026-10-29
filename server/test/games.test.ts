import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { bankGame } from '../src/modules/games/bank.js';
import { gameContentSchema, GAME_TYPES } from '../src/modules/games/content.js';
import { typeForDay } from '../src/modules/games/service.js';
import { addDays, localDay } from '../src/lib/time.js';
import { auth, register, setupTestApp } from './helpers.js';

const ctx = setupTestApp();

async function pairUp() {
  const a = await register(ctx.app, 'asha@example.com', 'Asha');
  const b = await register(ctx.app, 'ravi@example.com', 'Ravi');
  const invite = await ctx.app.inject({
    method: 'POST',
    url: '/invites',
    headers: auth(a.tokens.accessToken),
  });
  await ctx.app.inject({
    method: 'POST',
    url: '/invites/join',
    headers: auth(b.tokens.accessToken),
    payload: { code: invite.json().invite.code },
  });
  return { a: a.tokens.accessToken, b: b.tokens.accessToken };
}

const today = async (token: string) =>
  (await ctx.app.inject({ method: 'GET', url: '/games/today', headers: auth(token) })).json().game;

const submit = (
  token: string,
  gameId: string,
  answers: { questionId: string; choice: number }[],
  key = randomUUID(),
) =>
  ctx.app.inject({
    method: 'POST',
    url: `/games/${gameId}/submit`,
    headers: { ...auth(token), 'idempotency-key': key },
    payload: { answers },
  });

const allFirst = (game: { questions: { id: string }[] }) =>
  game.questions.map((q) => ({ questionId: q.id, choice: 0 }));

describe('content and bank', () => {
  it('bank games for every type pass the content schema', () => {
    for (const type of GAME_TYPES) {
      for (let i = 0; i < 20; i++) {
        expect(gameContentSchema.safeParse(bankGame(type, `seed-${i}`)).success).toBe(true);
      }
    }
  });

  it('is deterministic per seed', () => {
    expect(bankGame('SHARED_TRIVIA', 'x')).toEqual(bankGame('SHARED_TRIVIA', 'x'));
  });

  it('rejects malformed content', () => {
    const bad = {
      type: 'SHARED_TRIVIA',
      title: 'Quiz',
      questions: [{ prompt: 'What?', options: ['a', 'a'] }],
    };
    expect(gameContentSchema.safeParse(bad).success).toBe(false);
  });

  it('rotates through all three types on consecutive days', () => {
    const types = new Set([0, 1, 2].map((n) => typeForDay(addDays('2026-10-29', n))));
    expect(types.size).toBe(3);
  });

  it('computes the local day in the given timezone', () => {
    const instant = new Date('2026-10-29T20:00:00Z');
    expect(localDay('Asia/Kolkata', instant)).toBe('2026-10-30');
    expect(localDay('America/New_York', instant)).toBe('2026-10-29');
  });
});

describe('GET /games/today', () => {
  it('gives both partners the same game and hides answers', async () => {
    const { a, b } = await pairUp();
    const [ga, gb] = await Promise.all([today(a), today(b)]);
    expect(ga.id).toBe(gb.id);
    expect(await ctx.prisma.game.count()).toBe(1);
    expect(ga.questions.every((q: { correctOption: unknown }) => q.correctOption === null)).toBe(true);
    expect(await ctx.prisma.event.count({ where: { name: 'game_started' } })).toBe(2);
  });

  it('requires a pair', async () => {
    const { tokens } = await register(ctx.app);
    const res = await ctx.app.inject({
      method: 'GET',
      url: '/games/today',
      headers: auth(tokens.accessToken),
    });
    expect(res.json().error.code).toBe('NOT_PAIRED');
  });
});

describe('POST /games/:id/submit', () => {
  it('shows waiting until the partner submits, then reveals results to both', async () => {
    const { a, b } = await pairUp();
    const game = await today(a);

    const first = (await submit(a, game.id, allFirst(game))).json().game;
    expect(first).toMatchObject({ me: { submitted: true }, partner: { submitted: false }, completed: false });
    expect(first.questions[0].partnerChoice).toBeNull();

    // B cannot see A's answers before submitting.
    const peek = await today(b);
    expect(peek.partner.submitted).toBe(true);
    expect(peek.questions.every((q: { partnerChoice: unknown }) => q.partnerChoice === null)).toBe(true);

    const second = (await submit(b, game.id, allFirst(game))).json().game;
    expect(second.completed).toBe(true);
    expect(second.questions[0]).toMatchObject({ myChoice: 0, partnerChoice: 0 });
    expect(second.summary).not.toBeNull();

    const fromA = await today(a);
    expect(fromA.completed).toBe(true);
    expect(await ctx.prisma.event.count({ where: { name: 'game_completed' } })).toBe(1);
  });

  it('is idempotent: a double tap with the same key returns the original result', async () => {
    const { a } = await pairUp();
    const game = await today(a);
    const key = randomUUID();

    const [r1, r2] = await Promise.all([
      submit(a, game.id, allFirst(game), key),
      submit(a, game.id, allFirst(game), key),
    ]);
    expect([r1.statusCode, r2.statusCode]).toEqual([200, 200]);
    expect([r1.json().replayed, r2.json().replayed].sort()).toEqual([false, true]);
    expect(await ctx.prisma.submission.count()).toBe(1);
    expect(await ctx.prisma.answer.count()).toBe(game.questions.length);
  });

  it('rejects a second submission with a new key', async () => {
    const { a } = await pairUp();
    const game = await today(a);
    await submit(a, game.id, allFirst(game));
    const again = await submit(a, game.id, allFirst(game));
    expect(again.statusCode).toBe(409);
    expect(again.json().error.code).toBe('ALREADY_SUBMITTED');
  });

  it('requires an idempotency key', async () => {
    const { a } = await pairUp();
    const game = await today(a);
    const res = await ctx.app.inject({
      method: 'POST',
      url: `/games/${game.id}/submit`,
      headers: auth(a),
      payload: { answers: allFirst(game) },
    });
    expect(res.json().error.code).toBe('IDEMPOTENCY_KEY_REQUIRED');
  });

  it('validates answers', async () => {
    const { a } = await pairUp();
    const game = await today(a);
    const partial = allFirst(game).slice(1);
    expect((await submit(a, game.id, partial)).json().error.code).toBe('INCOMPLETE');

    const outOfRange = allFirst(game).map((x) => ({ ...x, choice: 9 }));
    expect((await submit(a, game.id, outOfRange)).json().error.code).toBe('INVALID_CHOICE');
  });

  it("does not let outsiders read or answer another pair's game", async () => {
    const { a } = await pairUp();
    const game = await today(a);
    const c = await register(ctx.app, 'meera@example.com');
    const d = await register(ctx.app, 'dev@example.com');
    const inv = await ctx.app.inject({
      method: 'POST',
      url: '/invites',
      headers: auth(c.tokens.accessToken),
    });
    await ctx.app.inject({
      method: 'POST',
      url: '/invites/join',
      headers: auth(d.tokens.accessToken),
      payload: { code: inv.json().invite.code },
    });

    const res = await submit(c.tokens.accessToken, game.id, allFirst(game));
    expect(res.json().error.code).toBe('GAME_NOT_FOUND');
  });
});

describe('scoring', () => {
  it('scores who-knows-whom guesses per partner', async () => {
    const { a, b } = await pairUp();
    const game = await today(a);
    // Force this pair's game to be who-knows-whom regardless of the date.
    const pair = await ctx.prisma.pair.findFirstOrThrow();
    await ctx.prisma.game.delete({ where: { id: game.id } });
    const wkw = bankGame('WHO_KNOWS_WHOM', 'fixed');
    await ctx.prisma.game.create({
      data: {
        pairId: pair.id,
        day: new Date(`${game.day}T00:00:00Z`),
        type: 'WHO_KNOWS_WHOM',
        source: 'BANK',
        title: wkw.title,
        questions: {
          create: wkw.questions.map((q, position) => ({
            position,
            prompt: q.prompt,
            options: q.options,
            meta: { about: q.about === 'A' ? pair.userAId : pair.userBId },
          })),
        },
      },
    });
    const g = await today(a);
    // A answers 0 everywhere. B answers 0 only on questions about A (guesses right),
    // and 1 on questions about B (its own truthful answers, which A guessed wrong).
    await submit(a, g.id, allFirst(g));
    const bAnswers = g.questions.map((q: { id: string; about: string }) => ({
      questionId: q.id,
      choice: q.about === 'me' ? 0 : 1,
    }));
    const result = (await submit(b, g.id, bAnswers)).json().game;
    expect(result.summary).toEqual({
      kind: 'knows',
      myCorrect: 3,
      partnerCorrect: 0,
      aboutPartner: 3,
      aboutMe: 3,
    });
  });
});
