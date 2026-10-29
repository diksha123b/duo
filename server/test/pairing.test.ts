import { describe, expect, it } from 'vitest';
import { auth, register, setupTestApp } from './helpers.js';

const ctx = setupTestApp();

async function createInvite(token: string) {
  const res = await ctx.app.inject({ method: 'POST', url: '/invites', headers: auth(token) });
  return res.json().invite as { code: string; expiresAt: string };
}

const join = (token: string, code: string) =>
  ctx.app.inject({ method: 'POST', url: '/invites/join', headers: auth(token), payload: { code } });

async function pairUp() {
  const a = await register(ctx.app, 'asha@example.com', 'Asha');
  const b = await register(ctx.app, 'ravi@example.com', 'Ravi');
  const { code } = await createInvite(a.tokens.accessToken);
  const res = await join(b.tokens.accessToken, code);
  expect(res.statusCode).toBe(200);
  return { a, b, pairId: res.json().pair.id as string };
}

describe('profile', () => {
  it('updates interests, normalising and de-duplicating them', async () => {
    const { tokens } = await register(ctx.app);
    const res = await ctx.app.inject({
      method: 'PATCH',
      url: '/me/profile',
      headers: auth(tokens.accessToken),
      payload: { interests: ['Cricket ', 'cricket', 'Bollywood'], timezone: 'Europe/London' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().user.profile).toMatchObject({
      interests: ['cricket', 'bollywood'],
      timezone: 'Europe/London',
    });
  });

  it('rejects an unknown timezone', async () => {
    const { tokens } = await register(ctx.app);
    const res = await ctx.app.inject({
      method: 'PATCH',
      url: '/me/profile',
      headers: auth(tokens.accessToken),
      payload: { timezone: 'Mars/Olympus' },
    });
    expect(res.statusCode).toBe(400);
  });
});

describe('invites and pairing', () => {
  it('pairs two users and shows each the other as partner', async () => {
    const { a, b, pairId } = await pairUp();

    const fromA = (
      await ctx.app.inject({ method: 'GET', url: '/pair', headers: auth(a.tokens.accessToken) })
    ).json();
    const fromB = (
      await ctx.app.inject({ method: 'GET', url: '/pair', headers: auth(b.tokens.accessToken) })
    ).json();
    expect(fromA.pair).toMatchObject({
      id: pairId,
      partner: { displayName: 'Ravi' },
      streak: { current: 0 },
    });
    expect(fromB.pair.partner.displayName).toBe('Asha');
    // Pair day uses the inviter's timezone.
    expect(fromA.pair.timezone).toBe('Asia/Kolkata');
  });

  it('returns the same live invite instead of creating a new one', async () => {
    const { tokens } = await register(ctx.app);
    const first = await createInvite(tokens.accessToken);
    const second = await createInvite(tokens.accessToken);
    expect(second.code).toBe(first.code);
    expect(first.code).toMatch(/^[A-Z2-9]{6}$/);
  });

  it('accepts codes typed in lower case with spaces', async () => {
    const a = await register(ctx.app, 'asha@example.com');
    const b = await register(ctx.app, 'ravi@example.com');
    const { code } = await createInvite(a.tokens.accessToken);
    const messy = ` ${code.slice(0, 3).toLowerCase()} ${code.slice(3)} `;
    expect((await join(b.tokens.accessToken, messy)).statusCode).toBe(200);
  });

  it('rejects invalid, own, used, and expired codes', async () => {
    const a = await register(ctx.app, 'asha@example.com');
    const b = await register(ctx.app, 'ravi@example.com');
    const c = await register(ctx.app, 'meera@example.com');
    const { code } = await createInvite(a.tokens.accessToken);

    expect((await join(b.tokens.accessToken, 'ZZZZZZ')).json().error.code).toBe('INVITE_INVALID');
    expect((await join(a.tokens.accessToken, code)).json().error.code).toBe('OWN_INVITE');

    await join(b.tokens.accessToken, code);
    const used = await join(c.tokens.accessToken, code);
    expect(used.statusCode).toBe(410);
    expect(used.json().error.code).toBe('INVITE_USED');

    const d = await register(ctx.app, 'dev@example.com');
    const { code: stale } = await createInvite(c.tokens.accessToken);
    await ctx.prisma.invite.update({
      where: { code: stale },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });
    expect((await join(d.tokens.accessToken, stale)).json().error.code).toBe('INVITE_EXPIRED');
  });

  it('blocks already-paired users from creating or joining invites', async () => {
    const { a } = await pairUp();
    const c = await register(ctx.app, 'meera@example.com');

    const create = await ctx.app.inject({
      method: 'POST',
      url: '/invites',
      headers: auth(a.tokens.accessToken),
    });
    expect(create.json().error.code).toBe('ALREADY_PAIRED');

    const { code } = await createInvite(c.tokens.accessToken);
    expect((await join(a.tokens.accessToken, code)).json().error.code).toBe('ALREADY_PAIRED');
  });

  it('only lets one of two concurrent joiners win', async () => {
    const a = await register(ctx.app, 'asha@example.com');
    const b = await register(ctx.app, 'ravi@example.com');
    const c = await register(ctx.app, 'meera@example.com');
    const { code } = await createInvite(a.tokens.accessToken);

    const results = await Promise.all([join(b.tokens.accessToken, code), join(c.tokens.accessToken, code)]);
    expect(results.map((r) => r.statusCode).sort()).toEqual([200, 410]);
    expect(await ctx.prisma.pair.count()).toBe(1);
  });

  it('unpairs both users and lets them pair again', async () => {
    const { a, b } = await pairUp();
    const res = await ctx.app.inject({ method: 'DELETE', url: '/pair', headers: auth(b.tokens.accessToken) });
    expect(res.statusCode).toBe(204);

    const fromA = await ctx.app.inject({ method: 'GET', url: '/pair', headers: auth(a.tokens.accessToken) });
    expect(fromA.json().pair).toBeNull();
    expect((await ctx.prisma.pair.findFirstOrThrow()).endedAt).not.toBeNull();

    const { code } = await createInvite(a.tokens.accessToken);
    expect((await join(b.tokens.accessToken, code)).statusCode).toBe(200);
  });

  it('logs a paired event', async () => {
    const { pairId } = await pairUp();
    expect(await ctx.prisma.event.count({ where: { name: 'paired', pairId } })).toBe(1);
  });
});

describe('rate limiting', () => {
  it('limits invite join attempts per user', async () => {
    const { tokens } = await register(ctx.app);
    const statuses: number[] = [];
    for (let i = 0; i < 11; i++) statuses.push((await join(tokens.accessToken, 'ZZZZZZ')).statusCode);
    expect(statuses.slice(0, 10).every((s) => s === 404)).toBe(true);

    const limited = await join(tokens.accessToken, 'ZZZZZZ');
    expect(limited.statusCode).toBe(429);
    expect(limited.json().error.code).toBe('RATE_LIMITED');
    expect(Number(limited.headers['retry-after'])).toBeGreaterThan(0);
  });

  it('limits login attempts per IP', async () => {
    const payload = { email: 'x@example.com', password: 'whatever' };
    for (let i = 0; i < 10; i++) await ctx.app.inject({ method: 'POST', url: '/auth/login', payload });
    const res = await ctx.app.inject({ method: 'POST', url: '/auth/login', payload });
    expect(res.statusCode).toBe(429);
  });
});
