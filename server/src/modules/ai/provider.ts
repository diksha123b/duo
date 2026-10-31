import type { Pair, PrismaClient } from '@prisma/client';
import type { Redis } from 'ioredis';
import type { FastifyBaseLogger } from 'fastify';
import { dayToDate } from '../../lib/time.js';
import { AGREE_SCALE, gameContentSchema, type GameContent, type GameTypeName } from '../games/content.js';
import { bankProvider, type GameProvider } from '../games/service.js';
import { costUsd, type LlmClient, type LlmGame } from './llm.js';

const SYSTEM = `You write short, warm daily games for two people who play together in the Duo app.
Make every question specific to their interests where you can, light-hearted, and safe for a general audience.
Keep prompts under 150 characters and options under 60 characters. Never repeat an option within a question.
Set explanation to null unless the game type asks for one.`;

const INSTRUCTIONS: Record<GameTypeName, string> = {
  WOULD_YOU_RATHER: `Game type: would you rather. Write 5 questions. Each has exactly 2 options; the prompt is a short lead-in like "Would you rather…". Set correctOption and about to null.`,
  WHO_KNOWS_WHOM: `Game type: who knows whom better. Write 6 questions with 3 or 4 options each: 3 about partner A and 3 about partner B (set "about" to "A" or "B"). The partner the question is about answers honestly; the other guesses. Phrase prompts neutrally (e.g. "Ideal weekend?") because both partners see the same text. Set correctOption to null.`,
  SHARED_TRIVIA: `Game type: shared trivia. Write 5 factual multiple-choice questions with 4 options each, drawn from both partners' interests. Set correctOption to the 0-based index of the right answer; only use facts you are certain of. Set explanation to one or two friendly sentences on why it's right, mentioning the most tempting wrong option and why it's wrong. Set about to null.`,
  EMOJI_DECODE: `Game type: emoji decode. Write 5 puzzles. The prompt is 2–4 emojis that clue a well-known movie, song, food, place or brand tied to their interests, followed by the category in brackets, e.g. "🦁👑🌅 (movie)". Give exactly 4 options and set correctOption to the 0-based index of the answer. Close decoys are fine, but every emoji must fit the answer better than any decoy. Set explanation to one or two friendly sentences that read the clues one by one and say why the closest decoy doesn't fit. Set about to null.`,
  AGREE_O_METER: `Game type: agree-o-meter. Write 5 light, non-divisive "hot take" statements tied to their interests (no politics, religion or anything hurtful), each under 100 characters, e.g. "Rainy days are the best days." Each partner rates how much they agree. Set options to an empty list (the app supplies the scale), and correctOption and about to null.`,
  RANK_IT: `Game type: rank it. Write 5 questions. The prompt is a short instruction like "Rank these weekend plans"; options are exactly 4 distinct items drawn from their interests that people would genuinely disagree on. Set correctOption and about to null.`,
};

export interface AiProviderOptions {
  prisma: PrismaClient;
  redis: Redis;
  llm: LlmClient;
  model: string;
  log: FastifyBaseLogger;
  timeoutMs: number;
}

export class GenerationError extends Error {}

const cacheKey = (pairId: string, day: string) => `gen:${pairId}:${day}`;

export function toContent(type: GameTypeName, out: LlmGame) {
  return gameContentSchema.safeParse({
    type,
    title: out.title,
    questions: out.questions.map((q) => ({
      prompt: q.prompt,
      options: type === 'AGREE_O_METER' ? AGREE_SCALE : q.options,
      correctOption: q.correctOption ?? undefined,
      about: q.about ?? undefined,
      explanation: q.explanation ?? undefined,
    })),
  });
}

/**
 * Generates a pair's game with the LLM and validates it against the content
 * schema. Successful games are cached in Redis so a retry or a second worker
 * never pays for the same game twice. Every attempt is logged with latency,
 * tokens and cost.
 *
 * With `allowFallback` (the default) any failure falls back to the curated
 * bank; the nightly job turns it off on early attempts so BullMQ retries first.
 */
export function createAiProvider(opts: AiProviderOptions): GameProvider {
  const { prisma, redis, llm, log } = opts;

  return async ({ pair, day, type, allowFallback = true, seen = [] }) => {
    const cached = await redis.get(cacheKey(pair.id, day));
    if (cached) {
      const parsed = gameContentSchema.safeParse(JSON.parse(cached));
      if (parsed.success && parsed.data.type === type) return { content: parsed.data, source: 'AI' };
    }

    const started = Date.now();
    const record = (data: {
      status: 'SUCCESS' | 'INVALID' | 'FAILED';
      model?: string;
      inputTokens?: number;
      outputTokens?: number;
      error?: string;
    }) =>
      prisma.generationLog
        .create({
          data: {
            pairId: pair.id,
            day: dayToDate(day),
            status: data.status,
            model: data.model ?? opts.model,
            latencyMs: Date.now() - started,
            inputTokens: data.inputTokens,
            outputTokens: data.outputTokens,
            costUsd:
              data.inputTokens !== undefined
                ? costUsd(data.model ?? opts.model, data.inputTokens, data.outputTokens ?? 0)
                : null,
            error: data.error?.slice(0, 500),
          },
        })
        .catch((err) => log.error({ err }, 'failed to write generation log'));

    const fail = async (status: 'INVALID' | 'FAILED', error: string, usage = {}) => {
      await record({ status, error, ...usage });
      log.warn({ pairId: pair.id, day, status, error }, 'AI game generation failed');
      if (!allowFallback) throw new GenerationError(error);
      return bankProvider({ pair, day, type, seen });
    };

    let result;
    try {
      result = await llm({
        system: SYSTEM,
        prompt: await buildPrompt(prisma, pair, type, seen),
        signal: AbortSignal.timeout(opts.timeoutMs),
      });
    } catch (err) {
      return fail('FAILED', err instanceof Error ? err.message : String(err));
    }

    const usage = { model: result.model, inputTokens: result.inputTokens, outputTokens: result.outputTokens };
    if (!result.output) return fail('INVALID', result.refused ? 'refused' : 'no parseable output', usage);

    const content = toContent(type, result.output);
    if (!content.success) {
      return fail(
        'INVALID',
        content.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; '),
        usage,
      );
    }

    await record({ status: 'SUCCESS', ...usage });
    await redis.set(cacheKey(pair.id, day), JSON.stringify(content.data), 'EX', 3 * 86_400);
    return { content: content.data as GameContent, source: 'AI' };
  };
}

// Tone and boundaries depend on who the two people are to each other.
function relationshipLine(pair: Pair): string {
  const parent = pair.parentId === pair.userAId ? 'A' : 'B';
  const child = parent === 'A' ? 'B' : 'A';
  switch (pair.relationship) {
    case 'PARTNERS':
      return 'They are a couple. Sweet, flirty-but-tasteful questions are welcome; keep everything non-explicit.';
    case 'BEST_FRIENDS':
      return 'They are best friends. Lean into inside-joke energy and playful teasing. Nothing romantic.';
    case 'FRIENDS':
      return 'They are friends getting to know each other better. Keep it light and inclusive. Nothing romantic.';
    case 'SIBLINGS':
      return 'They are siblings. Playful sibling rivalry and childhood memories work well. Nothing romantic.';
    case 'COLLEAGUES':
      return 'They know each other from work or study. Friendly and fun, office-safe, nothing romantic or too personal.';
    case 'PARENT_CHILD':
      return `Partner ${parent} is the grown-up (a parent, grandparent, aunt, uncle or similar) and partner ${child} is the younger one, who may be a child. Everything must suit a child aged 8+: warm, family-friendly, simple words, nothing romantic or mature.`;
  }
}

async function buildPrompt(
  prisma: PrismaClient,
  pair: Pair,
  type: GameTypeName,
  seen: string[],
): Promise<string> {
  const profiles = await prisma.profile.findMany({ where: { userId: { in: [pair.userAId, pair.userBId] } } });
  const describe = (userId: string, label: string) => {
    const p = profiles.find((x) => x.userId === userId);
    const interests = p?.interests.length ? p.interests.join(', ') : 'not shared';
    // Names and interests are user input: quote them as data, not instructions.
    return `Partner ${label}: name ${JSON.stringify(p?.displayName ?? label)}, interests ${JSON.stringify(interests)}`;
  };
  return [
    describe(pair.userAId, 'A'),
    describe(pair.userBId, 'B'),
    relationshipLine(pair),
    // Their own words for each other, quoted as data.
    pair.relationshipLabel ? `They describe themselves as: ${JSON.stringify(pair.relationshipLabel)}` : '',
    '',
    INSTRUCTIONS[type],
    'Give the game a short, fun title (under 50 characters) that hints at their shared interests.',
    // Keep it fresh: they've already played these.
    seen.length
      ? `They have already had these questions, so don't repeat them or ask near-copies:\n${seen
          .slice(0, 40)
          .map((q) => `- ${q}`)
          .join('\n')}`
      : '',
  ].join('\n');
}
