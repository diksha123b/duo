import { describe, expect, it } from 'vitest';
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
  return { a, b };
}

const start = (t: string, kind: string) =>
  ctx.app.inject({ method: 'POST', url: '/arcade/matches', headers: auth(t), payload: { kind } });
const move = (t: string, id: string, version: number, m: unknown) =>
  ctx.app.inject({
    method: 'POST',
    url: `/arcade/matches/${id}/moves`,
    headers: auth(t),
    payload: { version, move: m },
  });

describe('arcade API', () => {
  it('starts one game per kind; the starter moves first', async () => {
    const { a, b } = await pairUp();
    const first = await start(a, 'TIC_TAC_TOE');
    expect(first.statusCode).toBe(201);
    expect(first.json().match).toMatchObject({ yourTurn: true, seat: 0, status: 'ACTIVE' });

    const again = await start(b, 'TIC_TAC_TOE');
    expect(again.statusCode).toBe(200);
    expect(again.json().match).toMatchObject({ id: first.json().match.id, yourTurn: false, seat: 1 });
  });

  it('enforces turns and rejects stale or illegal moves', async () => {
    const { a, b } = await pairUp();
    const m = (await start(a, 'TIC_TAC_TOE')).json().match;

    expect((await move(b, m.id, 0, { cell: 0 })).json().error.code).toBe('NOT_YOUR_TURN');
    expect((await move(a, m.id, 0, { cell: 42 })).json().error.code).toBe('ILLEGAL_MOVE');
    expect((await move(a, m.id, 0, { cell: 4 })).statusCode).toBe(200);
    // Same version again (double tap / second device): rejected, nothing applied twice.
    expect((await move(a, m.id, 0, { cell: 5 })).json().error.code).toBe('STALE_MATCH');
    const taken = await move(b, m.id, 1, { cell: 4 });
    expect(taken.json().error).toMatchObject({ code: 'ILLEGAL_MOVE', message: 'That square is taken' });
  });

  it('finishes a game, records the winner, and keeps score head-to-head', async () => {
    const { a, b } = await pairUp();
    const m = (await start(a, 'TIC_TAC_TOE')).json().match;
    const script: [string, number][] = [
      [a, 0],
      [b, 3],
      [a, 1],
      [b, 4],
      [a, 2],
    ];
    let last;
    for (const [i, [t, cell]] of script.entries()) last = (await move(t, m.id, i, { cell })).json().match;
    expect(last).toMatchObject({ status: 'FINISHED', result: 'won' });

    const fromB = (await ctx.app.inject({ method: 'GET', url: '/arcade', headers: auth(b) })).json();
    expect(fromB.record.TIC_TAC_TOE).toEqual({ you: 0, them: 1, draws: 0 });
    expect((await move(b, m.id, 5, { cell: 8 })).json().error.code).toBe('MATCH_OVER');

    // A new game can start once the old one is over.
    expect((await start(b, 'TIC_TAC_TOE')).statusCode).toBe(201);
  });

  it('lets either player resign', async () => {
    const { a, b } = await pairUp();
    const m = (await start(a, 'CHESS')).json().match;
    const res = await ctx.app.inject({
      method: 'POST',
      url: `/arcade/matches/${m.id}/resign`,
      headers: auth(b),
    });
    expect(res.json().match).toMatchObject({ status: 'FINISHED', result: 'lost' });
  });

  it('hides the other word-tiles rack', async () => {
    const { a, b } = await pairUp();
    const m = (await start(a, 'WORD_TILES')).json().match;
    const mine = m.view.rack as string[];
    const theirs = (
      await ctx.app.inject({ method: 'GET', url: `/arcade/matches/${m.id}`, headers: auth(b) })
    ).json().match.view;
    expect(mine).toHaveLength(7);
    expect(theirs.otherRackCount).toBe(7);
    expect(theirs.rack).not.toEqual(mine);
  });

  it("does not let outsiders see another pair's game", async () => {
    const { a } = await pairUp();
    const m = (await start(a, 'LUDO')).json().match;
    const c = (await register(ctx.app, 'meera@example.com')).tokens.accessToken;
    const res = await ctx.app.inject({ method: 'GET', url: `/arcade/matches/${m.id}`, headers: auth(c) });
    expect(res.json().error.code).toBe('NOT_PAIRED');
  });
});

describe('ludo over the API', () => {
  it('the starter is already rolled for; the other player cannot move', async () => {
    const { a, b } = await pairUp();
    const m = (await start(a, 'LUDO')).json().match;
    expect(m.view.dice[0]).not.toBeNull();
    const fromB = (
      await ctx.app.inject({ method: 'GET', url: `/arcade/matches/${m.id}`, headers: auth(b) })
    ).json().match;
    // B sees A's die too.
    expect(fromB.view.dice[0]).toEqual(m.view.dice[0]);
    expect((await move(b, m.id, fromB.version, { type: 'roll' })).json().error.code).toMatch(
      /NOT_YOUR_TURN|ILLEGAL_MOVE/,
    );
  });
});
