import { Redis } from 'ioredis';
import pino from 'pino';
import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { createGoogleVerifier } from './lib/google.js';
import { createPrisma } from './lib/prisma.js';
import { initSentry } from './lib/sentry.js';
import { createGameProvider } from './lib/providers.js';
import { attachRealtime, closeAdapterClients } from './modules/realtime/socket.js';

const config = loadConfig();
initSentry(config.SENTRY_DSN, config.NODE_ENV, 'api');
const log = pino();
const prisma = createPrisma(config.DATABASE_URL);
const redis = new Redis(config.REDIS_URL);
const app = await buildApp(
  {
    config,
    prisma,
    redis,
    verifyGoogle: createGoogleVerifier(config.GOOGLE_CLIENT_IDS),
    gameProvider: createGameProvider(config, { prisma, redis, log }, config.LLM_REQUEST_TIMEOUT_MS),
  },
  { logger: true },
);
const pubClient = redis.duplicate();
const subClient = redis.duplicate();
attachRealtime(app, { pubClient, subClient });

const shutdown = async () => {
  await app.close();
  await prisma.$disconnect();
  await closeAdapterClients(pubClient, subClient);
  await redis.quit();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

await app.listen({ port: config.PORT, host: '0.0.0.0' });
