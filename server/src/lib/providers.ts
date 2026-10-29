import type { PrismaClient } from '@prisma/client';
import type { FastifyBaseLogger } from 'fastify';
import type { Redis } from 'ioredis';
import type { Config } from '../config.js';
import { createClaudeClient } from '../modules/ai/llm.js';
import { createAiProvider } from '../modules/ai/provider.js';
import { bankProvider, type GameProvider } from '../modules/games/service.js';

export function createGameProvider(
  config: Config,
  deps: { prisma: PrismaClient; redis: Redis; log: FastifyBaseLogger },
  timeoutMs: number,
): GameProvider {
  if (!config.ANTHROPIC_API_KEY) {
    deps.log.warn('ANTHROPIC_API_KEY not set: daily games will come from the question bank');
    return bankProvider;
  }
  return createAiProvider({
    ...deps,
    llm: createClaudeClient({
      apiKey: config.ANTHROPIC_API_KEY,
      model: config.LLM_MODEL,
      effort: config.LLM_EFFORT,
    }),
    model: config.LLM_MODEL,
    timeoutMs,
  });
}
