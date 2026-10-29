import type { PrismaClient } from '@prisma/client';
import { Queue, Worker, type ConnectionOptions, type Job } from 'bullmq';
import type { FastifyBaseLogger } from 'fastify';
import { addDays, dayToDate, localDay } from '../lib/time.js';
import { reportError } from '../lib/sentry.js';
import type { GameService } from '../modules/games/service.js';

export const QUEUE = 'game-generation';
export const ATTEMPTS = 3;

interface GenerateData {
  pairId: string;
  day: string;
}

/**
 * Which games should exist soon but don't: today's and tomorrow's for every
 * active pair, in that pair's timezone. Running this hourly means each pair's
 * game is generated well before its local midnight, wherever they live.
 */
export async function planPregeneration(prisma: PrismaClient, now = new Date()): Promise<GenerateData[]> {
  const pairs = await prisma.pair.findMany({ where: { endedAt: null } });
  const wanted = pairs.flatMap((p) => {
    const today = localDay(p.timezone, now);
    return [today, addDays(today, 1)].map((day) => ({ pairId: p.id, day }));
  });
  if (wanted.length === 0) return [];

  const existing = await prisma.game.findMany({
    where: { OR: wanted.map((w) => ({ pairId: w.pairId, day: dayToDate(w.day) })) },
    select: { pairId: true, day: true },
  });
  const have = new Set(existing.map((g) => `${g.pairId}|${g.day.toISOString().slice(0, 10)}`));
  return wanted.filter((w) => !have.has(`${w.pairId}|${w.day}`));
}

export async function processGeneration(
  deps: { prisma: PrismaClient; games: GameService },
  data: GenerateData,
  isLastAttempt: boolean,
): Promise<'created' | 'skipped'> {
  const pair = await deps.prisma.pair.findUnique({ where: { id: data.pairId } });
  if (!pair || pair.endedAt) return 'skipped';
  // Early attempts throw on AI failure so BullMQ retries with backoff;
  // the last one settles for the curated bank so the pair still gets a game.
  await deps.games.ensureGame(pair, data.day, { allowFallback: isLastAttempt });
  return 'created';
}

export function createQueue(connection: ConnectionOptions) {
  return new Queue(QUEUE, { connection });
}

export async function scheduleHourlyPlanning(queue: Queue) {
  await queue.upsertJobScheduler('plan-hourly', { pattern: '5 * * * *' }, { name: 'plan' });
}

export async function enqueuePlanned(queue: Queue, planned: GenerateData[]) {
  await queue.addBulk(
    planned.map((data) => ({
      name: 'generate',
      data,
      opts: {
        // Deduplicates: re-planning before the job finishes adds nothing.
        jobId: `gen-${data.pairId}-${data.day}`,
        attempts: ATTEMPTS,
        backoff: { type: 'exponential', delay: 30_000 },
        removeOnComplete: { age: 86_400 },
        removeOnFail: { age: 7 * 86_400 },
      },
    })),
  );
}

export function createWorker(
  connection: ConnectionOptions,
  deps: { prisma: PrismaClient; games: GameService; queue: Queue; log: FastifyBaseLogger },
) {
  const worker = new Worker(
    QUEUE,
    async (job: Job) => {
      if (job.name === 'plan') {
        const planned = await planPregeneration(deps.prisma);
        await enqueuePlanned(deps.queue, planned);
        return { planned: planned.length };
      }
      const isLast = job.attemptsMade + 1 >= (job.opts.attempts ?? 1);
      return processGeneration(deps, job.data as GenerateData, isLast);
    },
    { connection, concurrency: 4 },
  );
  worker.on('failed', (job, err) => {
    deps.log.warn({ jobId: job?.id, attempt: job?.attemptsMade, err: err.message }, 'generation job failed');
    // Earlier attempts are expected to fail sometimes; only report exhausted jobs.
    if (job && job.attemptsMade >= (job.opts.attempts ?? 1))
      reportError(err, { jobId: job.id, data: job.data });
  });
  return worker;
}
