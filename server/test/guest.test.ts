import { describe, expect, it } from 'vitest';
import { auth, register, setupTestApp } from './helpers.js';

const ctx = setupTestApp();

const guest = (displayName = 'Asha') =>
  ctx.app.inject({ method: 'POST', url: '/auth/guest', payload: { displayName, timezone: 'Asia/Kolkata' } });
const save = (token: string, email: string, password = 'correct-horse') =>
  ctx.app.inject({ method: 'POST', url: '/auth/save', headers: auth(token), payload: { email, password } });

describe('guest play', () => {
  it('starts with just a name', async () => {
    const res = await guest();
    expect(res.statusCode).toBe(201);
    expect(res.json().user).toMatchObject({ email: null, guest: true, profile: { displayName: 'Asha' } });
    expect(res.json().tokens.accessToken).toBeTruthy();
    expect((await guest('')).statusCode).toBe(400);
  });

  it('can pair and play like anyone else', async () => {
    const a = (await guest('Asha')).json().tokens.accessToken;
    const b = (await guest('Ravi')).json().tokens.accessToken;
    const inv = await ctx.app.inject({ method: 'POST', url: '/invites', headers: auth(a) });
    const join = await ctx.app.inject({
      method: 'POST',
      url: '/invites/join',
      headers: auth(b),
      payload: { code: inv.json().invite.code },
    });
    expect(join.statusCode).toBe(200);
    const today = await ctx.app.inject({ method: 'GET', url: '/games/today', headers: auth(a) });
    expect(today.statusCode).toBe(200);
  });

  it('saves the account with an email, keeping the same user, and can then log in', async () => {
    const res = (await guest()).json();
    const saved = await save(res.tokens.accessToken, 'Asha@Example.com');
    expect(saved.statusCode).toBe(200);
    expect(saved.json().user).toMatchObject({ id: res.user.id, email: 'asha@example.com', guest: false });

    const login = await ctx.app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { email: 'asha@example.com', password: 'correct-horse' },
    });
    expect(login.json().user.id).toBe(res.user.id);
    expect((await save(res.tokens.accessToken, 'other@example.com')).json().error.code).toBe('NOT_A_GUEST');
  });

  it('can’t save with an email someone already uses', async () => {
    await register(ctx.app, 'taken@example.com');
    const g = (await guest()).json().tokens.accessToken;
    expect((await save(g, 'taken@example.com')).json().error.code).toBe('EMAIL_TAKEN');
    expect((await save(g, 'new@example.com', 'short')).statusCode).toBe(400);
  });

  it('a regular account isn’t a guest', async () => {
    const r = await register(ctx.app);
    expect(r.user).toMatchObject({ guest: false });
  });
});
