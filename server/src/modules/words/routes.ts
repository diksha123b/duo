import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { rateLimit } from '../../lib/rate-limit.js';
import { parse } from '../../lib/validate.js';

/** A short definition of `word`, or null if the dictionary doesn't know it. */
export type MeaningLookup = (word: string) => Promise<string | null>;

/** The free Dictionary API (dictionaryapi.dev); no key needed. */
export const dictionaryApi: MeaningLookup = async (word) => {
  const res = await fetch(
    `https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word.toLowerCase())}`,
    {
      signal: AbortSignal.timeout(4000),
    },
  );
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`dictionary returned ${res.status}`);
  const entries = (await res.json()) as { meanings?: { definitions?: { definition?: string }[] }[] }[];
  const definition = entries[0]?.meanings?.[0]?.definitions?.[0]?.definition?.trim();
  if (!definition) return null;
  return definition.length > 140 ? `${definition.slice(0, 137).trimEnd()}…` : definition;
};

const DAY = 86_400;

/**
 * Word meanings for Word Tiles ("they played QUAY: a platform where boats
 * dock"). Looked up once per word and cached, including "not found".
 */
export async function wordRoutes(app: FastifyInstance, opts: { lookup: MeaningLookup }) {
  const { redis } = app.deps;
  const limit = rateLimit(redis, { name: 'words', max: 60, windowSeconds: 60, key: (req) => req.userId });

  app.get('/words/:word', { preHandler: [app.authenticate, limit] }, async (req) => {
    const { word } = parse(z.object({ word: z.string().regex(/^[A-Za-z]{2,15}$/) }), req.params);
    const upper = word.toUpperCase();
    const key = `meaning:${upper}`;
    const cached = await redis.get(key);
    if (cached !== null) return { word: upper, meaning: cached || null };
    try {
      const meaning = await opts.lookup(upper);
      await redis.set(key, meaning ?? '', 'EX', meaning ? 90 * DAY : 7 * DAY);
      return { word: upper, meaning };
    } catch (err) {
      req.log.warn({ err, word: upper }, 'meaning lookup failed');
      return { word: upper, meaning: null };
    }
  });
}
