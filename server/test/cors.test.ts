import { describe, expect, it } from 'vitest';
import { setupTestApp } from './helpers.js';

const ctx = setupTestApp();

// Browsers send a preflight before non-simple requests; the web app breaks if it fails.
describe('CORS preflight', () => {
  it.each(['GET', 'POST', 'PUT', 'PATCH', 'DELETE'])('allows %s from the web app', async (method) => {
    const res = await ctx.app.inject({
      method: 'OPTIONS',
      url: '/me/profile',
      headers: {
        origin: 'http://localhost:8080',
        'access-control-request-method': method,
        'access-control-request-headers': 'authorization,content-type,idempotency-key',
      },
    });
    expect(res.statusCode).toBe(204);
    expect(res.headers['access-control-allow-methods']).toContain(method);
    expect(res.headers['access-control-allow-headers']).toContain('idempotency-key');
  });
});
