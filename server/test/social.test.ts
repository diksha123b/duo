import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { auth, register, setupTestApp } from './helpers.js';

const sent: { endpoint: string; title: string; body: string; url: string }[] = [];
let alive = true;
const ctx = setupTestApp({
  pushSender: async (sub, payload) => {
    sent.push({ endpoint: sub.endpoint, title: payload.title, body: payload.body, url: payload.url });
    return alive;
  },
});

async function pairUp() {
  sent.length = 0;
  alive = true;
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

const today = async (t: string) =>
  (await ctx.app.inject({ method: 'GET', url: '/games/today', headers: auth(t) })).json().game;
const submit = (t: string, game: { id: string; questions: { id: string }[] }) =>
  ctx.app.inject({
    method: 'POST',
    url: `/games/${game.id}/submit`,
    headers: { ...auth(t), 'idempotency-key': randomUUID() },
    payload: { answers: game.questions.map((q) => ({ questionId: q.id, choice: 0 })) },
  });
const react = (t: string, gameId: string, qid: string, emoji: string | null) =>
  ctx.app.inject({
    method: 'PUT',
    url: `/games/${gameId}/questions/${qid}/reaction`,
    headers: auth(t),
    payload: { emoji },
  });
const comment = (t: string, gameId: string, text: string) =>
  ctx.app.inject({ method: 'POST', url: `/games/${gameId}/comments`, headers: auth(t), payload: { text } });
const subscribe = (t: string, endpoint: string) =>
  ctx.app.inject({
    method: 'POST',
    url: '/push/subscribe',
    headers: auth(t),
    payload: { endpoint, keys: { p256dh: 'p', auth: 'a' } },
  });

describe('reactions and comments', () => {
  it('only open once both have answered', async () => {
    const { a } = await pairUp();
    const game = await today(a);
    expect((await react(a, game.id, game.questions[0].id, '😂')).json().error.code).toBe('NOT_REVEALED');
    expect((await comment(a, game.id, 'hi')).json().error.code).toBe('NOT_REVEALED');
  });

  it('show each person their own and their partner’s, and can be removed', async () => {
    const { a, b } = await pairUp();
    const game = await today(a);
    await submit(a, game);
    await submit(b, game);
    const q = game.questions[0].id;

    await react(a, game.id, q, '😂');
    const fromB = (await react(b, game.id, q, '❤️')).json().game;
    expect(fromB.questions[0].reactions).toEqual({ mine: '❤️', partner: '😂' });

    const removed = (await react(a, game.id, q, null)).json().game;
    expect(removed.questions[0].reactions).toEqual({ mine: null, partner: '❤️' });
    expect((await react(a, game.id, q, '💩')).json().error.code).toBe('VALIDATION_ERROR');
  });

  it('keeps a short chat under the results', async () => {
    const { a, b } = await pairUp();
    const game = await today(a);
    await submit(a, game);
    await submit(b, game);
    await comment(a, game.id, 'pineapple?? really?');
    const view = (await comment(b, game.id, 'no regrets 🍍')).json().game;
    expect(view.comments.map((c: { mine: boolean; text: string }) => [c.mine, c.text])).toEqual([
      [false, 'pineapple?? really?'],
      [true, 'no regrets 🍍'],
    ]);
    expect((await comment(a, game.id, 'x'.repeat(201))).json().error.code).toBe('VALIDATION_ERROR');
  });
});

describe('push notifications', () => {
  it('serves no key when push is not configured', async () => {
    const res = (await ctx.app.inject({ method: 'GET', url: '/push/key' })).json();
    expect(res).toEqual({ key: null });
  });

  it('tells your partner it is their turn, unless they have the app open', async () => {
    const { a, b } = await pairUp();
    await subscribe(b, 'https://push.example/ravi');
    const game = await today(a);

    await submit(a, game);
    await new Promise((r) => setTimeout(r, 50));
    expect(sent).toContainEqual(
      expect.objectContaining({
        endpoint: 'https://push.example/ravi',
        title: 'Asha played ✨',
        url: '/#/game',
      }),
    );

    // Ravi opens the app: no more pushes for him.
    sent.length = 0;
    const ravi = await ctx.prisma.user.findFirstOrThrow({ where: { email: 'ravi@example.com' } });
    await ctx.redis.hset('presence:conns', ravi.id, '1');
    await submit(b, game);
    await comment(a, game.id, 'hello');
    await new Promise((r) => setTimeout(r, 50));
    expect(sent.filter((s) => s.endpoint.includes('ravi'))).toEqual([]);
  });

  it('sends chat messages and forgets subscriptions the browser dropped', async () => {
    const { a, b } = await pairUp();
    await subscribe(b, 'https://push.example/ravi-old');
    const game = await today(a);
    await submit(a, game);
    await submit(b, game);
    await new Promise((r) => setTimeout(r, 50)); // let the 'results are in' pushes finish
    sent.length = 0;

    alive = false; // the browser says this subscription is gone
    await comment(a, game.id, 'rematch?');
    await new Promise((r) => setTimeout(r, 50));
    expect(sent).toContainEqual(expect.objectContaining({ title: 'Asha', body: 'rematch?' }));
    expect(await ctx.prisma.pushSubscription.count()).toBe(0);
  });
});
