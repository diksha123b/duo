import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, beforeEach } from 'vitest';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { unauthorized } from '../src/lib/errors.js';
import type { GoogleIdentity } from '../src/lib/google.js';
import { createPrisma } from '../src/lib/prisma.js';
import { TEST_ENV } from './env.js';

// Fake Google: the "idToken" is a JSON-encoded identity, or "bad" to fail.
const fakeGoogle = async (idToken: string): Promise<GoogleIdentity> => {
  if (idToken === 'bad') throw unauthorized('INVALID_GOOGLE_TOKEN', 'bad token');
  return JSON.parse(idToken) as GoogleIdentity;
};

export function setupTestApp() {
  const ctx = {} as { app: FastifyInstance; prisma: ReturnType<typeof createPrisma> };

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, ...TEST_ENV });
    ctx.prisma = createPrisma(config.DATABASE_URL);
    ctx.app = await buildApp({ config, prisma: ctx.prisma, verifyGoogle: fakeGoogle });
  });

  beforeEach(async () => {
    const tables = await ctx.prisma.$queryRaw<{ tablename: string }[]>`
      SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> '_prisma_migrations'`;
    await ctx.prisma.$executeRawUnsafe(
      `TRUNCATE ${tables.map((t) => `"${t.tablename}"`).join(', ')} CASCADE`,
    );
  });

  afterAll(async () => {
    await ctx.app?.close();
    await ctx.prisma?.$disconnect();
  });

  return ctx;
}

export async function register(app: FastifyInstance, email = 'asha@example.com', displayName = 'Asha') {
  const res = await app.inject({
    method: 'POST',
    url: '/auth/register',
    payload: { email, password: 'correct-horse', displayName, timezone: 'Asia/Kolkata' },
  });
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.body}`);
  return res.json() as {
    user: { id: string; email: string };
    tokens: { accessToken: string; refreshToken: string };
  };
}
