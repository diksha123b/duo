import { describe, expect, it } from 'vitest';
import { bankGame } from '../src/modules/games/bank.js';
import { GAME_TYPES } from '../src/modules/games/content.js';
import { auth, register, setupTestApp } from './helpers.js';

const ctx = setupTestApp();

async function pairAs(payload: Record<string, unknown>) {
  const a = (await register(ctx.app, 'asha@example.com', 'Asha')).tokens.accessToken;
  const b = (await register(ctx.app, 'ravi@example.com', 'Ravi')).tokens.accessToken;
  const inv = await ctx.app.inject({ method: 'POST', url: '/invites', headers: auth(a), payload });
  await ctx.app.inject({
    method: 'POST',
    url: '/invites/join',
    headers: auth(b),
    payload: { code: inv.json().invite.code },
  });
  return { a, b, invite: inv.json().invite };
}

const pairOf = async (t: string) =>
  (await ctx.app.inject({ method: 'GET', url: '/pair', headers: auth(t) })).json().pair;

describe('relationships', () => {
  it('defaults to friends', async () => {
    const { a } = await pairAs({});
    expect(await pairOf(a)).toMatchObject({ relationship: 'FRIENDS', myRole: null });
  });

  it('carries the relationship from the invite to the pair', async () => {
    const { a, b, invite } = await pairAs({ relationship: 'SIBLINGS' });
    expect(invite.relationship).toBe('SIBLINGS');
    expect((await pairOf(a)).relationship).toBe('SIBLINGS');
    expect((await pairOf(b)).relationship).toBe('SIBLINGS');
  });

  it('records who is the parent', async () => {
    const { a, b } = await pairAs({ relationship: 'PARENT_CHILD', iAm: 'CHILD' });
    expect((await pairOf(a)).myRole).toBe('CHILD');
    expect((await pairOf(b)).myRole).toBe('PARENT');
  });

  it('requires a role for parent and child', async () => {
    const a = (await register(ctx.app)).tokens.accessToken;
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/invites',
      headers: auth(a),
      payload: { relationship: 'PARENT_CHILD' },
    });
    expect(res.json().error.code).toBe('VALIDATION_ERROR');
  });

  it('can be changed later by either person', async () => {
    const { a, b } = await pairAs({ relationship: 'FRIENDS' });
    const res = await ctx.app.inject({
      method: 'PATCH',
      url: '/pair',
      headers: auth(b),
      payload: { relationship: 'PARENT_CHILD', iAm: 'PARENT' },
    });
    expect(res.statusCode).toBe(200);
    expect(await pairOf(a)).toMatchObject({ relationship: 'PARENT_CHILD', myRole: 'CHILD' });
  });
});

describe('content per relationship', () => {
  it('never gives non-partners partners-only questions', () => {
    for (const rel of ['SIBLINGS', 'PARENT_CHILD', 'FRIENDS', 'BEST_FRIENDS'] as const) {
      for (const type of GAME_TYPES) {
        for (let i = 0; i < 30; i++) {
          const prompts = bankGame(type, `s${i}`, rel).questions.map((q) => q.prompt + q.options.join());
          expect(prompts.join()).not.toMatch(/date ideas|surprise date/i);
        }
      }
    }
  });

  it('can give partners their own questions', () => {
    const seen = Array.from({ length: 60 }, (_, i) => bankGame('RANK_IT', `s${i}`, 'PARTNERS'))
      .flatMap((g) => g.questions.map((q) => q.prompt))
      .join();
    expect(seen).toMatch(/date ideas/);
  });
});

describe('weekly lineup', () => {
  it("comes with today's game", async () => {
    const { a } = await pairAs({});
    const res = (await ctx.app.inject({ method: 'GET', url: '/games/today', headers: auth(a) })).json();
    expect(res.lineup).toHaveLength(6);
    expect(GAME_TYPES).toContain(res.lineup[0].type);
  });
});

describe('custom relationship labels', () => {
  it('stores any label alongside the tone', async () => {
    const { a, b } = await pairAs({ relationship: 'SIBLINGS', label: 'cousins' });
    expect(await pairOf(b)).toMatchObject({ relationship: 'SIBLINGS', relationshipLabel: 'cousins' });
    await ctx.app.inject({
      method: 'PATCH',
      url: '/pair',
      headers: auth(a),
      payload: { relationship: 'COLLEAGUES', label: 'desk neighbours' },
    });
    expect(await pairOf(b)).toMatchObject({
      relationship: 'COLLEAGUES',
      relationshipLabel: 'desk neighbours',
    });
  });

  it('rejects overly long labels', async () => {
    const a = (await register(ctx.app)).tokens.accessToken;
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/invites',
      headers: auth(a),
      payload: { relationship: 'FRIENDS', label: 'x'.repeat(31) },
    });
    expect(res.json().error.code).toBe('VALIDATION_ERROR');
  });
});
