import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { botMove, wordTilesMove } from '../src/modules/demo/botMoves.js';
import { ENGINES } from '../src/modules/arcade/engines/index.js';
import type { Rng } from '../src/modules/arcade/engines/types.js';
import { auth, setupTestApp } from './helpers.js';

const ctx = setupTestApp();
const rng: Rng = { int: (n) => Math.floor(Math.random() * n) };

async function startDemo() {
  const res = await ctx.app.inject({
    method: 'POST',
    url: '/auth/demo',
    payload: { displayName: 'Asha', timezone: 'Asia/Kolkata' },
  });
  expect(res.statusCode).toBe(201);
  return res.json() as {
    user: { id: string; demo: boolean; guest: boolean };
    tokens: { accessToken: string };
  };
}

describe('demo mode', () => {
  it('signs you in already paired with a bot, skipping onboarding', async () => {
    const { user, tokens } = await startDemo();
    expect(user).toMatchObject({ demo: true, guest: true, profile: { interests: expect.any(Array) } });
    const pair = (
      await ctx.app.inject({ method: 'GET', url: '/pair', headers: auth(tokens.accessToken) })
    ).json();
    expect(pair.pair.partner.displayName).toBe('Sam (bot)');
  });

  it('the bot answers after you, so the results appear, and then reacts and chats', async () => {
    const t = (await startDemo()).tokens.accessToken;
    const game = (await ctx.app.inject({ method: 'GET', url: '/games/today', headers: auth(t) })).json().game;
    await ctx.app.inject({
      method: 'POST',
      url: `/games/${game.id}/submit`,
      headers: { ...auth(t), 'idempotency-key': randomUUID() },
      payload: {
        answers: game.questions.map((q: { id: string; options: string[] }) =>
          game.type === 'RANK_IT'
            ? { questionId: q.id, ranking: q.options.map((_, i) => i) }
            : { questionId: q.id, choice: 0 },
        ),
      },
    });
    await ctx.app.demoBot.idle();
    const after = (await ctx.app.inject({ method: 'GET', url: `/games/${game.id}`, headers: auth(t) })).json()
      .game;
    expect(after.completed).toBe(true);
    expect(after.comments).toHaveLength(1);
    expect(after.questions.some((q: { reactions: { partner: string | null } }) => q.reactions.partner)).toBe(
      true,
    );
  });

  it('the bot makes its moves in the arcade', async () => {
    const t = (await startDemo()).tokens.accessToken;
    for (const kind of ['TIC_TAC_TOE', 'FOUR_IN_A_ROW', 'CHESS'] as const) {
      const match = (
        await ctx.app.inject({ method: 'POST', url: '/arcade/matches', headers: auth(t), payload: { kind } })
      ).json().match;
      const move =
        kind === 'TIC_TAC_TOE'
          ? { cell: 0 }
          : kind === 'FOUR_IN_A_ROW'
            ? { col: 0 }
            : { from: 'e2', to: 'e4' };
      await ctx.app.inject({
        method: 'POST',
        url: `/arcade/matches/${match.id}/moves`,
        headers: auth(t),
        payload: { version: match.version, move },
      });
      await ctx.app.demoBot.idle();
      const now = (
        await ctx.app.inject({ method: 'GET', url: `/arcade/matches/${match.id}`, headers: auth(t) })
      ).json().match;
      expect(now.version, kind).toBe(match.version + 2);
      expect(now.yourTurn, kind).toBe(true);
    }
  });

  it('the bot pats the pet back', async () => {
    const t = (await startDemo()).tokens.accessToken;
    await ctx.app.inject({ method: 'POST', url: '/pet/pat', headers: auth(t) });
    await ctx.app.demoBot.idle();
    const pet = (await ctx.app.inject({ method: 'GET', url: '/pet', headers: auth(t) })).json().pet;
    expect(pet.patted).toEqual({ me: true, partner: true });
  });

  it('a regular pair has no bot', async () => {
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/auth/guest',
      payload: { displayName: 'Ravi' },
    });
    expect(res.json().user.demo).toBe(false);
  });
});

describe('bot moves', () => {
  it('takes a win and blocks one at tic-tac-toe', () => {
    // Bot (seat 1) can win at 5; the human (seat 0) threatens 2.
    const win = { board: [0, 0, null, 1, 1, null, 0, null, null], turn: 1 };
    expect(botMove('TIC_TAC_TOE', win, 1, rng)).toEqual({ cell: 5 });
    const block = { board: [0, 0, null, null, 1, null, null, null, null], turn: 1 };
    expect(botMove('TIC_TAC_TOE', block, 1, rng)).toEqual({ cell: 2 });
  });

  it('always has a legal move in every arcade game from the start', () => {
    for (const kind of Object.keys(ENGINES) as (keyof typeof ENGINES)[]) {
      let state = ENGINES[kind].init(rng);
      // Let the human (seat 0) move first where it matters, using the bot logic for them too.
      for (let turn = 0; turn < 6; turn++) {
        const seat = ENGINES[kind].outcome(state).turn;
        if (seat === null) break;
        const move = botMove(kind, state, seat, rng);
        expect(move, kind).not.toBeNull();
        state = ENGINES[kind].apply(state, seat, ENGINES[kind].move.parse(move), rng);
      }
    }
  });

  it('finds a real word for word tiles', () => {
    let state = ENGINES.WORD_TILES.init(rng);
    state = { ...state, racks: [['C', 'A', 'T', 'S', 'E', 'R', 'D'], state.racks[1]] };
    const move = wordTilesMove(state, 0, 2000) as { type: string };
    expect(move.type).toBe('place');
  });
});

describe('bot levels and word tiles options', () => {
  const common = new Set(
    readFileSync(new URL('../data/common-words.txt', import.meta.url), 'utf8')
      .split('\n')
      .map((w) => w.trim().toUpperCase()),
  );

  it('hard always takes the win; easy sometimes misses it', () => {
    const win = { board: [0, 0, null, 1, 1, null, 0, null, null], turn: 1 };
    for (let i = 0; i < 30; i++) expect(botMove('TIC_TAC_TOE', win, 1, rng, 'hard')).toEqual({ cell: 5 });
    const easy = Array.from({ length: 60 }, () =>
      JSON.stringify(botMove('TIC_TAC_TOE', win, 1, rng, 'easy')),
    );
    expect(new Set(easy).size).toBeGreaterThan(1);
  });

  it('plays everyday words in word tiles unless it is on hard', () => {
    for (const level of ['easy', 'normal'] as const) {
      let state = ENGINES.WORD_TILES.init(rng);
      state = { ...state, racks: [['C', 'A', 'T', 'S', 'E', 'R', 'D'], state.racks[1]] };
      const move = wordTilesMove(state, 0, 2000, level) as {
        type: string;
        tiles: { letter: string; c: number }[];
      };
      expect(move.type).toBe('place');
      const word = [...move.tiles]
        .sort((a, b) => a.c - b.c)
        .map((t) => t.letter)
        .join('');
      expect(common.has(word), `${level}: ${word}`).toBe(true);
    }
  });

  it('a quick game has about half the tiles', () => {
    const full = ENGINES.WORD_TILES.init(rng);
    const quick = ENGINES.WORD_TILES.init(rng, { quick: true });
    expect(full.bag.length).toBe(94 - 14);
    expect(quick.bag.length).toBeLessThan(45);
  });

  it('never deals a rack without a vowel while the bag has one', () => {
    for (let i = 0; i < 100; i++) {
      const s = ENGINES.WORD_TILES.init(rng, { quick: i % 2 === 0 });
      for (const rack of s.racks)
        expect(
          rack.some((l: string) => 'AEIOU'.includes(l)),
          rack.join(''),
        ).toBe(true);
    }
  });

  it('remembers the options a game was started with', async () => {
    const t = (await startDemo()).tokens.accessToken;
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/arcade/matches',
      headers: auth(t),
      payload: { kind: 'WORD_TILES', quick: true, botLevel: 'easy' },
    });
    expect(res.json().match.settings).toEqual({ quick: true, botLevel: 'easy' });
    expect(res.json().match.view.bagCount).toBeLessThan(45);
  });

  it('looks up what a word means, once', async () => {
    const t = (await startDemo()).tokens.accessToken;
    const quay = await ctx.app.inject({ method: 'GET', url: '/words/quay', headers: auth(t) });
    expect(quay.json()).toEqual({ word: 'QUAY', meaning: 'a platform where boats load and unload' });
    expect(await ctx.redis.get('meaning:QUAY')).toBe('a platform where boats load and unload');
    const unknown = await ctx.app.inject({ method: 'GET', url: '/words/zzxq', headers: auth(t) });
    expect(unknown.json().meaning).toBeNull();
    expect((await ctx.app.inject({ method: 'GET', url: '/words/a1', headers: auth(t) })).statusCode).toBe(
      400,
    );
  });
});
