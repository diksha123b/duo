import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
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
