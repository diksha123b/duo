import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { levelFor, moodFor, stageFor, xpForLevel } from '../src/modules/pet/pet.js';
import { auth, register, setupTestApp } from './helpers.js';

const sent: { title: string; url: string }[] = [];
const ctx = setupTestApp({
  pushSender: async (_sub, payload) => {
    sent.push({ title: payload.title, url: payload.url });
    return true;
  },
});

async function pairUp() {
  sent.length = 0;
  const a = (await register(ctx.app, 'asha@example.com', 'Asha')).tokens.accessToken;
  const b = (await register(ctx.app, 'ravi@example.com', 'Ravi')).tokens.accessToken;
  const inv = await ctx.app.inject({ method: 'POST', url: '/invites', headers: auth(a) });
  await ctx.app.inject({
    method: 'POST',
    url: '/invites/join',
    headers: auth(b),
    payload: { code: inv.json().invite.code },
  });
  return { a, b };
}

const pet = async (t: string) =>
  (await ctx.app.inject({ method: 'GET', url: '/pet', headers: auth(t) })).json().pet;
const pat = (t: string) => ctx.app.inject({ method: 'POST', url: '/pet/pat', headers: auth(t) });
const update = (t: string, payload: object) =>
  ctx.app.inject({ method: 'PATCH', url: '/pet', headers: auth(t), payload });

async function playToday(a: string, b: string) {
  const game = (await ctx.app.inject({ method: 'GET', url: '/games/today', headers: auth(a) })).json().game;
  for (const t of [a, b])
    await ctx.app.inject({
      method: 'POST',
      url: `/games/${game.id}/submit`,
      headers: { ...auth(t), 'idempotency-key': randomUUID() },
      payload: { answers: game.questions.map((q: { id: string }) => ({ questionId: q.id, choice: 0 })) },
    });
}

describe('pet rules', () => {
  it('levels get steadily further apart', () => {
    expect([1, 2, 3, 4, 5].map(xpForLevel)).toEqual([0, 30, 90, 180, 300]);
    expect(levelFor(0)).toBe(1);
    expect(levelFor(29)).toBe(1);
    expect(levelFor(30)).toBe(2);
    expect(levelFor(179)).toBe(3);
  });

  it('grows from an egg into a grown-up', () => {
    expect([1, 2, 3, 4, 6, 7, 12].map(stageFor)).toEqual([
      'egg',
      'baby',
      'baby',
      'kid',
      'kid',
      'grown',
      'grown',
    ]);
  });

  it('is happy after playing today, hungry after a day off, then sleepy', () => {
    expect(moodFor('2026-10-31', '2026-10-31', '2026-10-30')).toBe('happy');
    expect(moodFor('2026-10-30', '2026-10-31', '2026-10-30')).toBe('hungry');
    expect(moodFor('2026-10-20', '2026-10-31', '2026-10-30')).toBe('sleepy');
    expect(moodFor(null, '2026-10-31', '2026-10-30')).toBe('sleepy');
  });
});

describe('the pair’s pet', () => {
  it('starts as an egg and hatches when the pair plays together', async () => {
    const { a, b } = await pairUp();
    expect(await pet(a)).toMatchObject({ name: 'Mochi', level: 1, stage: 'egg', xp: 0, nextLevelXp: 30 });

    await playToday(a, b);
    const both = [await pet(a), await pet(b)];
    for (const p of both) expect(p).toMatchObject({ level: 2, stage: 'baby', xp: 30, mood: 'happy' });
  });

  it('takes one pat per person per day and tells the other person', async () => {
    const { a, b } = await pairUp();
    await ctx.app.inject({
      method: 'POST',
      url: '/push/subscribe',
      headers: auth(b),
      payload: { endpoint: 'https://push.example/b', keys: { p256dh: 'p', auth: 'a' } },
    });

    const res = await pat(a);
    expect(res.statusCode).toBe(200);
    expect(res.json().pet).toMatchObject({ xp: 5, patted: { me: true, partner: false } });
    expect((await pat(a)).json().error.code).toBe('ALREADY_PATTED');
    expect(await pet(b)).toMatchObject({ patted: { me: false, partner: true } });
    await new Promise((r) => setTimeout(r, 50));
    expect(sent).toContainEqual({ title: 'Asha patted Mochi 💕', url: '/#/home' });

    await pat(b);
    expect((await pet(a)).xp).toBe(10);
  });

  it('can be renamed and recoloured, but outfits unlock with levels', async () => {
    const { a, b } = await pairUp();
    const res = await update(a, { name: '  Pickle ', color: 'mint' });
    expect(res.json().pet).toMatchObject({ name: 'Pickle', color: 'mint' });
    expect((await pet(b)).name).toBe('Pickle');

    expect((await update(a, { outfit: 'bow' })).json().error.code).toBe('LOCKED');
    expect((await update(a, { name: '' })).statusCode).toBe(400);
    expect((await update(a, { outfit: 'cape' })).statusCode).toBe(400);
    expect((await pet(a)).nextUnlock).toEqual({ id: 'bow', level: 3 });
  });

  it('needs a pair', async () => {
    const solo = (await register(ctx.app, 'solo@example.com', 'Solo')).tokens.accessToken;
    const res = await ctx.app.inject({ method: 'GET', url: '/pet', headers: auth(solo) });
    expect(res.json().error.code).toBe('NOT_PAIRED');
  });
});
