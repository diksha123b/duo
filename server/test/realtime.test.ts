import { randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import { Redis } from 'ioredis';
import { io as connect, type Socket } from 'socket.io-client';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { attachRealtime } from '../src/modules/realtime/socket.js';
import { auth, register, setupTestApp } from './helpers.js';

const ctx = setupTestApp();
let url = '';
let pub: Redis;
let sub: Redis;
const open: Socket[] = [];

beforeAll(async () => {
  pub = ctx.redis.duplicate();
  sub = ctx.redis.duplicate();
  attachRealtime(ctx.app, { pubClient: pub, subClient: sub });
  await ctx.app.listen({ port: 0, host: '127.0.0.1' });
  url = `http://127.0.0.1:${(ctx.app.server.address() as AddressInfo).port}`;
});

afterEach(() => {
  open.splice(0).forEach((s) => s.disconnect());
});

afterAll(async () => {
  // Close sockets and the adapter before their Redis connections go away.
  await ctx.app.close();
  pub.disconnect();
  sub.disconnect();
});

function client(token: string) {
  const s = connect(url, { auth: { token }, transports: ['websocket'], reconnection: false });
  open.push(s);
  return s;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- socket payloads are untyped in tests
const next = <T = any>(s: Socket, event: string, ms = 3000) =>
  new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`timeout waiting for ${event}`)), ms);
    s.once(event, (data: T) => {
      clearTimeout(t);
      resolve(data);
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
  return { a, b };
}

const submitAll = (token: string, game: { id: string; questions: { id: string }[] }) =>
  ctx.app.inject({
    method: 'POST',
    url: `/games/${game.id}/submit`,
    headers: { ...auth(token), 'idempotency-key': randomUUID() },
    payload: { answers: game.questions.map((q) => ({ questionId: q.id, choice: 0 })) },
  });

describe('socket auth', () => {
  it('rejects connections without a valid token', async () => {
    const s = client('garbage');
    const err = await next<Error>(s, 'connect_error');
    expect(err.message).toBe('UNAUTHORIZED');
  });
});

describe('presence', () => {
  it('tells a partner when you come online, start playing, and leave', async () => {
    const { a, b } = await pairUp();
    const sa = client(a.tokens.accessToken);
    const sync = await next(sa, 'sync');
    expect(sync.partnerPresence).toEqual({ userId: b.user.id, state: 'offline' });

    const sb = client(b.tokens.accessToken);
    expect(await next(sa, 'presence')).toEqual({ userId: b.user.id, state: 'online' });
    await next(sb, 'sync');

    sb.emit('presence:set', { state: 'playing' });
    expect(await next(sa, 'presence')).toEqual({ userId: b.user.id, state: 'playing' });

    sb.disconnect();
    expect(await next(sa, 'presence')).toEqual({ userId: b.user.id, state: 'offline' });
  });
});

describe('live reveal', () => {
  it('notifies on partner submit and pushes tailored results to both', async () => {
    const { a, b } = await pairUp();
    const game = (
      await ctx.app.inject({ method: 'GET', url: '/games/today', headers: auth(a.tokens.accessToken) })
    ).json().game;
    const sa = client(a.tokens.accessToken);
    const sb = client(b.tokens.accessToken);
    await Promise.all([next(sa, 'sync'), next(sb, 'sync')]);

    const partnerSubmitted = next(sb, 'game:partner_submitted');
    await submitAll(a.tokens.accessToken, game);
    expect(await partnerSubmitted).toEqual({ gameId: game.id });

    const [ra, rb] = [next(sa, 'game:revealed'), next(sb, 'game:revealed')];
    await submitAll(b.tokens.accessToken, game);
    const [va, vb] = await Promise.all([ra, rb]);
    expect(va.game.completed).toBe(true);
    expect(vb.game.completed).toBe(true);
    expect(va.game.questions[0].partnerChoice).toBe(0);
    expect(va.game.summary).not.toBeNull();
  });

  it('catches up after a dropped connection', async () => {
    const { a, b } = await pairUp();
    const game = (
      await ctx.app.inject({ method: 'GET', url: '/games/today', headers: auth(a.tokens.accessToken) })
    ).json().game;
    await submitAll(a.tokens.accessToken, game);
    // A is offline while B submits, so A misses the live reveal...
    await submitAll(b.tokens.accessToken, game);
    // ...and gets the completed game in the sync on reconnect.
    const sa = client(a.tokens.accessToken);
    const sync = await next(sa, 'sync');
    expect(sync.game.completed).toBe(true);

    const acked = await sa.timeout(3000).emitWithAck('sync');
    expect(acked.game.id).toBe(game.id);
  });
});

describe('pair changes', () => {
  it('moves sockets into the new pair room', async () => {
    const a = await register(ctx.app, 'asha@example.com', 'Asha');
    const b = await register(ctx.app, 'ravi@example.com', 'Ravi');
    const sa = client(a.tokens.accessToken);
    await next(sa, 'sync');

    const changed = next(sa, 'pair:changed');
    const inv = await ctx.app.inject({
      method: 'POST',
      url: '/invites',
      headers: auth(a.tokens.accessToken),
    });
    await ctx.app.inject({
      method: 'POST',
      url: '/invites/join',
      headers: auth(b.tokens.accessToken),
      payload: { code: inv.json().invite.code },
    });
    await changed;

    const presence = next(sa, 'presence');
    const sb = client(b.tokens.accessToken);
    await next(sb, 'sync');
    expect(await presence).toEqual({ userId: b.user.id, state: 'online' });
  });
});
