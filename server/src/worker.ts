// Background worker: pre-generates daily games. Runs as its own process so
// slow LLM calls never compete with API requests.
import { Redis } from 'ioredis';
import pino from 'pino';
import { loadConfig } from './config.js';
import { createPrisma } from './lib/prisma.js';
import { createGameProvider } from './lib/providers.js';
import {
  createQueue,
  createWorker,
  enqueuePlanned,
  planPregeneration,
  scheduleHourlyPlanning,
} from './jobs/pregen.js';
import { GameService } from './modules/games/service.js';

const config = loadConfig();
const log = pino({ name: 'worker' });
const prisma = createPrisma(config.DATABASE_URL);
const redis = new Redis(config.REDIS_URL);
// BullMQ requires blocking connections that never give up on retries.
const connection = new Redis(config.REDIS_URL, { maxRetriesPerRequest: null });

const games = new GameService(
  prisma,
  createGameProvider(config, { prisma, redis, log }, config.LLM_JOB_TIMEOUT_MS),
);
const queue = createQueue(connection);
const worker = createWorker(connection, { prisma, games, queue, log });

await scheduleHourlyPlanning(queue);
// Catch up immediately on boot instead of waiting for the next hour.
await enqueuePlanned(queue, await planPregeneration(prisma));
log.info('worker started');

const shutdown = async () => {
  await worker.close();
  await queue.close();
  await prisma.$disconnect();
  redis.disconnect();
  connection.disconnect();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
