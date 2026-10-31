import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { bankGame, POOLS, questionKey } from '../src/modules/games/bank.js';
import { GAME_TYPES, gameContentSchema } from '../src/modules/games/content.js';
import { auth, register, setupTestApp } from './helpers.js';

const RELATIONSHIPS = [
  'PARTNERS',
  'BEST_FRIENDS',
  'FRIENDS',
  'SIBLINGS',
  'PARENT_CHILD',
  'COLLEAGUES',
] as const;
// Each type comes round every 6 days, so ~15 games per type in three months.
const DAYS_PER_TYPE_IN_3_MONTHS = 15;

describe('the question bank', () => {
  it('has enough questions for three months of daily games without repeats, for every relationship', () => {
    for (const type of GAME_TYPES) {
      const perGame = type === 'WHO_KNOWS_WHOM' ? 6 : 5;
      for (const rel of RELATIONSHIPS) {
        const available = POOLS[type].filter((q) => !q.only || q.only.includes(rel)).length;
        expect(available, `${type} for ${rel}`).toBeGreaterThanOrEqual(perGame * DAYS_PER_TYPE_IN_3_MONTHS);
      }
    }
  });

  it('has no duplicate questions', () => {
    for (const type of GAME_TYPES) {
      const keys = POOLS[type].map(questionKey);
      const dupes = keys.filter((k, i) => keys.indexOf(k) !== i);
      expect(dupes, type).toEqual([]);
    }
  });

  it('explains every quiz answer, and every question passes the content rules', () => {
    for (const type of GAME_TYPES) {
      const pool = POOLS[type];
      for (let i = 0; i < pool.length; i += 3) {
        const questions = pool.slice(i, i + 3).map((q, j) => ({
          prompt: q.prompt,
          options: q.options,
          correctOption: q.correctOption,
          explanation: q.explanation,
          about: type === 'WHO_KNOWS_WHOM' ? (j % 2 === 0 ? 'A' : 'B') : undefined,
        }));
        while (questions.length < 3) questions.push(questions[0]!);
        const parsed = gameContentSchema.safeParse({ type, title: 'Check', questions });
        expect(
          parsed.success,
          `${type} #${i}: ${parsed.error?.issues.map((x) => x.message).join(', ')}`,
        ).toBe(true);
      }
    }
  });

  it('never repeats a question across three months of games', () => {
    for (const type of GAME_TYPES) {
      for (const rel of RELATIONSHIPS) {
        const seen: string[] = [];
        for (let day = 0; day < DAYS_PER_TYPE_IN_3_MONTHS; day++) {
          const keys = bankGame(type, `pair:${day}`, rel, seen).questions.map(questionKey);
          for (const k of keys) expect(seen, `${type}/${rel} day ${day}`).not.toContain(k);
          seen.unshift(...keys);
        }
      }
    }
  });

  it('brings back the questions seen longest ago once everything has been played', () => {
    const pool = POOLS.SHARED_TRIVIA;
    // Newest first: everything seen, with the first five in the pool the oldest.
    const seen = [...pool].reverse().map(questionKey);
    const next = bankGame('SHARED_TRIVIA', 'again', 'FRIENDS', seen).questions.map(questionKey);
    expect(new Set(next)).toEqual(new Set(pool.slice(0, 5).map(questionKey)));
  });

  it('moves the right answer around and keeps it pointing at the same option', () => {
    const positions = new Set<number>();
    for (let i = 0; i < 40; i++) {
      for (const q of bankGame('EMOJI_DECODE', `s${i}`).questions) {
        positions.add(q.correctOption!);
        const original = POOLS.EMOJI_DECODE.find((x) => x.prompt === q.prompt)!;
        expect(q.options[q.correctOption!]).toBe(original.options[original.correctOption!]);
      }
    }
    expect(positions).toEqual(new Set([0, 1, 2, 3]));
  });
});

describe('games from the bank', () => {
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
    return { a, b };
  }

  const playBonus = async (a: string, b: string) => {
    const game = (
      await ctx.app.inject({
        method: 'POST',
        url: '/games/bonus',
        headers: auth(a),
        payload: { type: 'EMOJI_DECODE' },
      })
    ).json().game;
    for (const t of [a, b]) {
      await ctx.app.inject({
        method: 'POST',
        url: `/games/${game.id}/submit`,
        headers: { ...auth(t), 'idempotency-key': randomUUID() },
        payload: { answers: game.questions.map((q: { id: string }) => ({ questionId: q.id, choice: 0 })) },
      });
    }
    return game;
  };

  it('don’t repeat questions the pair has already had, and explain answers after the reveal', async () => {
    const { a, b } = await pairUp();
    const first = await playBonus(a, b);
    expect(first.questions[0].explanation).toBeNull();

    const revealed = (
      await ctx.app.inject({ method: 'GET', url: `/games/${first.id}`, headers: auth(a) })
    ).json().game;
    expect(revealed.questions[0].explanation).toMatch(/\S/);

    const second = await playBonus(a, b);
    const prompts = (g: { questions: { prompt: string }[] }) => g.questions.map((q) => q.prompt);
    expect(prompts(second).filter((p) => prompts(first).includes(p))).toEqual([]);
  });
});
