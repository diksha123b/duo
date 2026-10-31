import pino from 'pino';
import { describe, expect, it, vi } from 'vitest';
import { Queue } from 'bullmq';
import { Redis } from 'ioredis';
import { costUsd, type LlmClient, type LlmGame, type LlmResult } from '../src/modules/ai/llm.js';
import { createAiProvider, GenerationError } from '../src/modules/ai/provider.js';
import { GameService, typeForDay } from '../src/modules/games/service.js';
import { enqueuePlanned, planPregeneration, processGeneration } from '../src/jobs/pregen.js';
import { addDays, localDay } from '../src/lib/time.js';
import { auth, register, setupTestApp } from './helpers.js';
import { TEST_ENV } from './env.js';

const ctx = setupTestApp();
const log = pino({ level: 'silent' });

const wyr: LlmGame = {
  title: 'Cricket & Chai',
  questions: Array.from({ length: 5 }, (_, i) => ({
    prompt: `Would you rather… (${i})`,
    options: [`Option A${i}`, `Option B${i}`],
    correctOption: null,
    about: null,
    explanation: null,
  })),
};

const result = (output: LlmGame | null, extra: Partial<LlmResult> = {}): LlmResult => ({
  output,
  model: 'claude-opus-5-5',
  inputTokens: 1000,
  outputTokens: 500,
  refused: false,
  ...extra,
});

async function pair() {
  const a = await register(ctx.app, 'asha@example.com', 'Asha');
  const b = await register(ctx.app, 'ravi@example.com', 'Ravi');
  await ctx.app.inject({
    method: 'PATCH',
    url: '/me/profile',
    headers: auth(a.tokens.accessToken),
    payload: { interests: ['cricket', 'chai'] },
  });
  const inv = await ctx.app.inject({ method: 'POST', url: '/invites', headers: auth(a.tokens.accessToken) });
  await ctx.app.inject({
    method: 'POST',
    url: '/invites/join',
    headers: auth(b.tokens.accessToken),
    payload: { code: inv.json().invite.code },
  });
  return ctx.prisma.pair.findFirstOrThrow();
}

const provider = (llm: LlmClient) =>
  createAiProvider({
    prisma: ctx.prisma,
    redis: ctx.redis,
    llm,
    model: 'claude-opus-5-5',
    log,
    timeoutMs: 5000,
  });

describe('AI game provider', () => {
  it('uses valid LLM output and logs latency, tokens and cost', async () => {
    const p = await pair();
    const llm = vi.fn<LlmClient>().mockResolvedValue(result(wyr));
    const game = await provider(llm)({ pair: p, day: '2026-10-29', type: 'WOULD_YOU_RATHER' });

    expect(game.source).toBe('AI');
    expect(game.content.title).toBe('Cricket & Chai');
    // Both partners' interests reach the prompt, as quoted data.
    expect(llm.mock.calls[0]![0].prompt).toContain('cricket, chai');

    const logRow = await ctx.prisma.generationLog.findFirstOrThrow();
    expect(logRow).toMatchObject({ status: 'SUCCESS', inputTokens: 1000, outputTokens: 500 });
    expect(Number(logRow.costUsd)).toBeCloseTo(costUsd('claude-opus-5-5', 1000, 500)!);
  });

  it('caches generated games so a retry does not call the LLM again', async () => {
    const p = await pair();
    const llm = vi.fn<LlmClient>().mockResolvedValue(result(wyr));
    const gen = provider(llm);
    await gen({ pair: p, day: '2026-10-29', type: 'WOULD_YOU_RATHER' });
    await gen({ pair: p, day: '2026-10-29', type: 'WOULD_YOU_RATHER' });
    expect(llm).toHaveBeenCalledTimes(1);
  });

  it('falls back to the bank when output fails validation', async () => {
    const p = await pair();
    const bad = { ...wyr, questions: wyr.questions.map((q) => ({ ...q, options: ['Same', 'same'] })) };
    const game = await provider(vi.fn<LlmClient>().mockResolvedValue(result(bad)))({
      pair: p,
      day: '2026-10-29',
      type: 'WOULD_YOU_RATHER',
    });
    expect(game.source).toBe('BANK');
    const logRow = await ctx.prisma.generationLog.findFirstOrThrow();
    expect(logRow.status).toBe('INVALID');
    expect(logRow.error).toContain('duplicate options');
  });

  it('treats a refusal or wrong game shape as invalid', async () => {
    const p = await pair();
    const refused = await provider(vi.fn<LlmClient>().mockResolvedValue(result(null, { refused: true })))({
      pair: p,
      day: '2026-10-29',
      type: 'SHARED_TRIVIA',
    });
    expect(refused.source).toBe('BANK');
    // Trivia without a correct answer is invalid even though the JSON shape is fine.
    const noAnswers = await provider(vi.fn<LlmClient>().mockResolvedValue(result(wyr)))({
      pair: p,
      day: '2026-10-30',
      type: 'SHARED_TRIVIA',
    });
    expect(noAnswers.source).toBe('BANK');
    expect(await ctx.prisma.generationLog.count({ where: { status: 'INVALID' } })).toBe(2);
  });

  it('falls back on API errors, or throws when fallback is disabled', async () => {
    const p = await pair();
    const llm = vi.fn<LlmClient>().mockRejectedValue(new Error('overloaded'));
    const fallback = await provider(llm)({ pair: p, day: '2026-10-29', type: 'WOULD_YOU_RATHER' });
    expect(fallback.source).toBe('BANK');

    await expect(
      provider(llm)({ pair: p, day: '2026-10-29', type: 'WOULD_YOU_RATHER', allowFallback: false }),
    ).rejects.toBeInstanceOf(GenerationError);
    expect(await ctx.prisma.generationLog.count({ where: { status: 'FAILED' } })).toBe(2);
  });
});

describe('pre-generation job', () => {
  it("plans today's and tomorrow's game for active pairs, skipping existing ones", async () => {
    const p = await pair();
    const today = localDay(p.timezone);
    expect(await planPregeneration(ctx.prisma)).toEqual([
      { pairId: p.id, day: today },
      { pairId: p.id, day: addDays(today, 1) },
    ]);

    const games = new GameService(ctx.prisma, provider(vi.fn<LlmClient>().mockResolvedValue(result(wyr))));
    await games.ensureGame(p, today);
    expect(await planPregeneration(ctx.prisma)).toEqual([{ pairId: p.id, day: addDays(today, 1) }]);

    await ctx.prisma.pair.update({ where: { id: p.id }, data: { endedAt: new Date() } });
    expect(await planPregeneration(ctx.prisma)).toEqual([]);
  });

  it('retries on AI failure and only uses the bank on the last attempt', async () => {
    const p = await pair();
    const llm = vi.fn<LlmClient>().mockRejectedValue(new Error('timeout'));
    const games = new GameService(ctx.prisma, provider(llm));
    const data = { pairId: p.id, day: '2026-11-01' };

    await expect(processGeneration({ prisma: ctx.prisma, games }, data, false)).rejects.toThrow('timeout');
    expect(await ctx.prisma.game.count()).toBe(0);

    expect(await processGeneration({ prisma: ctx.prisma, games }, data, true)).toBe('created');
    expect((await ctx.prisma.game.findFirstOrThrow()).source).toBe('BANK');
  });

  it('the generated game is what players get', async () => {
    const p = await pair();
    const games = new GameService(ctx.prisma, provider(vi.fn<LlmClient>().mockResolvedValue(result(wyr))));
    const today = localDay(p.timezone);
    // The fake returns would-you-rather, so pick the next day with that type.
    const day = [0, 1, 2, 3, 4, 5]
      .map((n) => addDays(today, n))
      .find((d) => typeForDay(d) === 'WOULD_YOU_RATHER')!;
    await processGeneration({ prisma: ctx.prisma, games }, { pairId: p.id, day }, false);
    const game = await ctx.prisma.game.findFirstOrThrow({ include: { questions: true } });
    expect(game).toMatchObject({ source: 'AI', title: 'Cricket & Chai', type: 'WOULD_YOU_RATHER' });
    expect(game.questions).toHaveLength(5);
  });

  it('deduplicates queued jobs per pair and day', async () => {
    const connection = new Redis(TEST_ENV.REDIS_URL, { maxRetriesPerRequest: null });
    const queue = new Queue('test-generation', { connection });
    try {
      await queue.obliterate({ force: true });
      const planned = [{ pairId: 'p1', day: '2026-11-01' }];
      await enqueuePlanned(queue, planned);
      await enqueuePlanned(queue, planned);
      expect(await queue.getJobCounts('waiting')).toEqual({ waiting: 1 });
    } finally {
      await queue.obliterate({ force: true });
      await queue.close();
      await connection.quit();
    }
  });
});
