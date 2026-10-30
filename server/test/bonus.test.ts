import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { dayToDate, localDay } from '../src/lib/time.js';
import { auth, register, setupTestApp } from './helpers.js';

const ctx = setupTestApp();

async function pairUp() {
  const a = (await register(ctx.app, 'asha@example.com', 'Asha')).tokens.accessToken;
  const b = (await register(ctx.app, 'ravi@example.com', 'Ravi')).tokens.accessToken;
  const inv = await ctx.app.inject({ method: 'POST', url: '/invites', headers: auth(a) });
  await ctx.app.inject({
    method: 'POST',
    url: '/invites/join',
    headers: auth(b),
    payload: { code: inv.json().invite.code },
  });
  return { a, b, pair: await ctx.prisma.pair.findFirstOrThrow() };
}

const startBonus = (t: string, type: string) =>
  ctx.app.inject({ method: 'POST', url: '/games/bonus', headers: auth(t), payload: { type } });

async function finish(tokens: string[], game: { id: string; questions: { id: string }[] }) {
  for (const t of tokens) {
    await ctx.app.inject({
      method: 'POST',
      url: `/games/${game.id}/submit`,
      headers: { ...auth(t), 'idempotency-key': randomUUID() },
      payload: { answers: game.questions.map((q) => ({ questionId: q.id, choice: 0 })) },
    });
  }
}

describe('bonus rounds', () => {
  it('both partners land in the same round; a new one starts after it finishes', async () => {
    const { a, b } = await pairUp();
    const first = await startBonus(a, 'WOULD_YOU_RATHER');
    expect(first.statusCode).toBe(201);
    expect(first.json().game).toMatchObject({ type: 'WOULD_YOU_RATHER', daily: false });

    const joined = await startBonus(b, 'WOULD_YOU_RATHER');
    expect(joined.statusCode).toBe(200);
    expect(joined.json().game.id).toBe(first.json().game.id);

    const open = (await ctx.app.inject({ method: 'GET', url: '/games/bonus', headers: auth(b) })).json()
      .games;
    expect(open).toEqual([
      { id: first.json().game.id, type: 'WOULD_YOU_RATHER', meSubmitted: false, partnerSubmitted: false },
    ]);

    await finish([a, b], first.json().game);
    const again = await startBonus(a, 'WOULD_YOU_RATHER');
    expect(again.statusCode).toBe(201);
    expect(again.json().game.id).not.toBe(first.json().game.id);
  });

  it('never touches the streak or history', async () => {
    const { a, b } = await pairUp();
    await finish([a, b], (await startBonus(a, 'SHARED_TRIVIA')).json().game);
    const pair = (await ctx.app.inject({ method: 'GET', url: '/pair', headers: auth(a) })).json().pair;
    expect(pair.streak.current).toBe(0);
    const history = (await ctx.app.inject({ method: 'GET', url: '/games/history', headers: auth(a) })).json();
    expect(history.items).toEqual([]);
  });

  it("doesn't replace today's game", async () => {
    const { a } = await pairUp();
    const today = (await ctx.app.inject({ method: 'GET', url: '/games/today', headers: auth(a) })).json()
      .game;
    await startBonus(a, 'RANK_IT');
    const still = (await ctx.app.inject({ method: 'GET', url: '/games/today', headers: auth(a) })).json()
      .game;
    expect(still.id).toBe(today.id);
    expect(still.daily).toBe(true);
  });

  it('the database still allows only one daily game per day', async () => {
    const { pair } = await pairUp();
    const data = {
      pairId: pair.id,
      day: dayToDate(localDay(pair.timezone)),
      type: 'SHARED_TRIVIA' as const,
      source: 'BANK' as const,
      title: 't',
    };
    await ctx.prisma.game.create({ data });
    await expect(ctx.prisma.game.create({ data })).rejects.toThrow();
    // …but any number of bonus games.
    await ctx.prisma.game.create({ data: { ...data, isDaily: false } });
    await ctx.prisma.game.create({ data: { ...data, isDaily: false } });
  });
});
