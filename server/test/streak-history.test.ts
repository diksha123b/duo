import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { applyCompletion, displayStreak, type StreakState } from '../src/lib/streak.js';
import { addDays, dayToDate, localDay } from '../src/lib/time.js';
import { bankGame } from '../src/modules/games/bank.js';
import { auth, register, setupTestApp } from './helpers.js';

const ctx = setupTestApp();
const empty: StreakState = { current: 0, longest: 0, lastCompletedDay: null };

describe('streak rules', () => {
  it('counts consecutive days and resets after a gap', () => {
    let s = applyCompletion(empty, '2026-10-27');
    s = applyCompletion(s, '2026-10-28');
    s = applyCompletion(s, '2026-10-29');
    expect(s).toEqual({ current: 3, longest: 3, lastCompletedDay: '2026-10-29' });

    s = applyCompletion(s, '2026-10-31');
    expect(s).toEqual({ current: 1, longest: 3, lastCompletedDay: '2026-10-31' });
  });

  it('ignores repeats and late completions of older days', () => {
    const s = applyCompletion(applyCompletion(empty, '2026-10-29'), '2026-10-29');
    expect(s.current).toBe(1);
    expect(applyCompletion(s, '2026-10-20')).toBe(s);
  });

  it('crosses month, year, and DST boundaries by calendar day', () => {
    expect(
      applyCompletion({ current: 4, longest: 4, lastCompletedDay: '2026-12-31' }, '2027-01-01').current,
    ).toBe(5);
    // US DST ends 2026-11-01; the day is 25 hours long but still one day.
    expect(
      applyCompletion({ current: 1, longest: 1, lastCompletedDay: '2026-10-31' }, '2026-11-01').current,
    ).toBe(2);
    expect(
      applyCompletion({ current: 1, longest: 1, lastCompletedDay: '2026-11-01' }, '2026-11-02').current,
    ).toBe(2);
  });

  it('shows a streak until the day after the last completion', () => {
    const s = { current: 5, longest: 5, lastCompletedDay: '2026-10-28' };
    expect(displayStreak(s, '2026-10-28')).toBe(5);
    expect(displayStreak(s, '2026-10-29')).toBe(5);
    expect(displayStreak(s, '2026-10-30')).toBe(0);
  });

  it("uses each pair's own calendar day", () => {
    // 23:30 UTC on the 29th is already the 30th in Kolkata.
    const instant = new Date('2026-10-29T23:30:00Z');
    expect(localDay('Asia/Kolkata', instant)).toBe('2026-10-30');
    expect(localDay('America/Los_Angeles', instant)).toBe('2026-10-29');
  });
});

async function pairUp() {
  const a = await register(ctx.app, 'asha@example.com', 'Asha');
  const b = await register(ctx.app, 'ravi@example.com', 'Ravi');
  const inv = await ctx.app.inject({ method: 'POST', url: '/invites', headers: auth(a.tokens.accessToken) });
  await ctx.app.inject({
    method: 'POST',
    url: '/invites/join',
    headers: auth(b.tokens.accessToken),
    payload: { code: inv.json().invite.code },
  });
  return { a: a.tokens.accessToken, b: b.tokens.accessToken, pair: await ctx.prisma.pair.findFirstOrThrow() };
}

async function seedGame(pairId: string, day: string) {
  const content = bankGame('WOULD_YOU_RATHER', day);
  return ctx.prisma.game.create({
    data: {
      pairId,
      day: dayToDate(day),
      type: 'WOULD_YOU_RATHER',
      source: 'BANK',
      title: content.title,
      questions: {
        create: content.questions.map((q, position) => ({ position, prompt: q.prompt, options: q.options })),
      },
    },
    include: { questions: true },
  });
}

async function playBoth(tokens: string[], game: { id: string; questions: { id: string }[] }) {
  for (const t of tokens) {
    await ctx.app.inject({
      method: 'POST',
      url: `/games/${game.id}/submit`,
      headers: { ...auth(t), 'idempotency-key': randomUUID() },
      payload: { answers: game.questions.map((q) => ({ questionId: q.id, choice: 0 })) },
    });
  }
}

const getPair = async (t: string) =>
  (await ctx.app.inject({ method: 'GET', url: '/pair', headers: auth(t) })).json().pair;

describe('streaks end to end', () => {
  it('grows when both partners finish on consecutive days', async () => {
    const { a, b, pair } = await pairUp();
    const today = localDay(pair.timezone);
    await playBoth([a, b], await seedGame(pair.id, addDays(today, -1)));
    await playBoth([a, b], await seedGame(pair.id, today));

    expect((await getPair(a)).streak).toMatchObject({ current: 2, longest: 2, lastCompletedDay: today });
  });

  it('does not count a game only one partner finished', async () => {
    const { a, pair } = await pairUp();
    await playBoth([a], await seedGame(pair.id, localDay(pair.timezone)));
    expect((await getPair(a)).streak.current).toBe(0);
  });

  it('shows 0 once a day has been missed, but keeps the longest', async () => {
    const { a, b, pair } = await pairUp();
    const today = localDay(pair.timezone);
    await playBoth([a, b], await seedGame(pair.id, addDays(today, -3)));
    await playBoth([a, b], await seedGame(pair.id, addDays(today, -2)));
    expect((await getPair(a)).streak).toMatchObject({ current: 0, longest: 2 });
  });
});

describe('GET /games/history', () => {
  it('lists past games newest first with summaries, paginated', async () => {
    const { a, b, pair } = await pairUp();
    const today = localDay(pair.timezone);
    for (let n = 1; n <= 3; n++) await playBoth([a, b], await seedGame(pair.id, addDays(today, -n)));
    await seedGame(pair.id, today); // unplayed today: must not appear

    const first = (
      await ctx.app.inject({ method: 'GET', url: '/games/history?limit=2', headers: auth(a) })
    ).json();
    expect(first.items.map((g: { day: string }) => g.day)).toEqual([addDays(today, -1), addDays(today, -2)]);
    expect(first.items[0].summary).toMatchObject({ kind: 'match' });
    expect(first.nextCursor).toBe(addDays(today, -2));

    const second = (
      await ctx.app.inject({
        method: 'GET',
        url: `/games/history?limit=2&before=${first.nextCursor}`,
        headers: auth(a),
      })
    ).json();
    expect(second.items.map((g: { day: string }) => g.day)).toEqual([addDays(today, -3)]);
    expect(second.nextCursor).toBeNull();
  });

  it('includes missed days without revealing anything', async () => {
    const { a, pair } = await pairUp();
    await seedGame(pair.id, addDays(localDay(pair.timezone), -1));
    const res = (await ctx.app.inject({ method: 'GET', url: '/games/history', headers: auth(a) })).json();
    expect(res.items[0]).toMatchObject({ completed: false, summary: null, meSubmitted: false });
  });
});
