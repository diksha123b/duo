import { Redis } from 'ioredis';
import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { createGoogleVerifier } from './lib/google.js';
import { createPrisma } from './lib/prisma.js';

const config = loadConfig();
const prisma = createPrisma(config.DATABASE_URL);
const redis = new Redis(config.REDIS_URL);
const app = await buildApp(
  { config, prisma, redis, verifyGoogle: createGoogleVerifier(config.GOOGLE_CLIENT_IDS) },
  { logger: true },
);

const shutdown = async () => {
  await app.close();
  await prisma.$disconnect();
  redis.disconnect();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

await app.listen({ port: config.PORT, host: '0.0.0.0' });
