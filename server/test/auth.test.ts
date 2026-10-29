import { describe, expect, it } from 'vitest';
import { register, setupTestApp } from './helpers.js';

const ctx = setupTestApp();

describe('POST /auth/register', () => {
  it('creates a user with a profile and returns tokens', async () => {
    const body = await register(ctx.app, 'Asha@Example.com');
    expect(body.user.email).toBe('asha@example.com');
    expect(body.tokens.accessToken).toBeTypeOf('string');

    const me = await ctx.app.inject({
      method: 'GET',
      url: '/me',
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    });
    expect(me.statusCode).toBe(200);
    expect(me.json().user.profile).toMatchObject({ displayName: 'Asha', timezone: 'Asia/Kolkata' });
    expect(await ctx.prisma.event.count({ where: { name: 'sign_up' } })).toBe(1);
  });

  it('rejects a duplicate email', async () => {
    await register(ctx.app);
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'asha@example.com', password: 'another-pass', displayName: 'A' },
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error.code).toBe('EMAIL_TAKEN');
  });

  it('validates input', async () => {
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'not-an-email', password: 'short', displayName: '' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('VALIDATION_ERROR');
  });
});

describe('POST /auth/login', () => {
  it('logs in with the right password', async () => {
    await register(ctx.app);
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { email: 'asha@example.com', password: 'correct-horse' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().tokens.refreshToken).toBeTypeOf('string');
  });

  it('gives the same error for a wrong password and an unknown email', async () => {
    await register(ctx.app);
    for (const payload of [
      { email: 'asha@example.com', password: 'wrong-password' },
      { email: 'nobody@example.com', password: 'correct-horse' },
    ]) {
      const res = await ctx.app.inject({ method: 'POST', url: '/auth/login', payload });
      expect(res.statusCode).toBe(401);
      expect(res.json().error.code).toBe('INVALID_CREDENTIALS');
    }
  });
});

describe('refresh token rotation', () => {
  it('rotates the refresh token', async () => {
    const { tokens } = await register(ctx.app);
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/auth/refresh',
      payload: { refreshToken: tokens.refreshToken },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().tokens.refreshToken).not.toBe(tokens.refreshToken);
  });

  it('revokes the whole session when a rotated token is reused', async () => {
    const { tokens } = await register(ctx.app);
    const first = await ctx.app.inject({
      method: 'POST',
      url: '/auth/refresh',
      payload: { refreshToken: tokens.refreshToken },
    });
    const next = first.json().tokens.refreshToken;

    const reuse = await ctx.app.inject({
      method: 'POST',
      url: '/auth/refresh',
      payload: { refreshToken: tokens.refreshToken },
    });
    expect(reuse.json().error.code).toBe('REFRESH_TOKEN_REUSED');

    // The legitimately rotated token is now dead too.
    const after = await ctx.app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken: next } });
    expect(after.statusCode).toBe(401);
  });

  it('logout revokes the refresh token', async () => {
    const { tokens } = await register(ctx.app);
    const out = await ctx.app.inject({
      method: 'POST',
      url: '/auth/logout',
      payload: { refreshToken: tokens.refreshToken },
    });
    expect(out.statusCode).toBe(204);
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/auth/refresh',
      payload: { refreshToken: tokens.refreshToken },
    });
    expect(res.statusCode).toBe(401);
  });
});

describe('POST /auth/google', () => {
  const idToken = JSON.stringify({ googleId: 'g-123', email: 'ravi@example.com', name: 'Ravi' });

  it('creates an account on first sign-in and reuses it afterwards', async () => {
    const first = await ctx.app.inject({ method: 'POST', url: '/auth/google', payload: { idToken } });
    expect(first.statusCode).toBe(201);
    expect(first.json().user.profile.displayName).toBe('Ravi');

    const second = await ctx.app.inject({ method: 'POST', url: '/auth/google', payload: { idToken } });
    expect(second.statusCode).toBe(200);
    expect(second.json().user.id).toBe(first.json().user.id);
  });

  it('links to an existing password account with the same email', async () => {
    const { user } = await register(ctx.app, 'ravi@example.com');
    const res = await ctx.app.inject({ method: 'POST', url: '/auth/google', payload: { idToken } });
    expect(res.json().user).toMatchObject({ id: user.id, hasGoogle: true, hasPassword: true });
  });

  it('rejects an unverifiable token', async () => {
    const res = await ctx.app.inject({ method: 'POST', url: '/auth/google', payload: { idToken: 'bad' } });
    expect(res.statusCode).toBe(401);
  });
});

describe('GET /me', () => {
  it('requires a valid access token', async () => {
    expect((await ctx.app.inject({ method: 'GET', url: '/me' })).statusCode).toBe(401);
    const res = await ctx.app.inject({ method: 'GET', url: '/me', headers: { authorization: 'Bearer nope' } });
    expect(res.json().error.code).toBe('INVALID_ACCESS_TOKEN');
  });
});
