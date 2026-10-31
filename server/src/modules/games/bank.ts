import { createHash } from 'node:crypto';
import type { GameContent, GameTypeName } from './content.js';

// Curated questions. Used when AI generation is off, and as the fallback when
// LLM generation fails or returns something that doesn't validate.

import type { Relationship } from '@prisma/client';
import { AGREE_O_METER } from './questions/agreeOMeter.js';
import { EMOJI_DECODE } from './questions/emojiDecode.js';
import { RANK_IT } from './questions/rankIt.js';
import { SHARED_TRIVIA } from './questions/trivia.js';
import type { Q } from './questions/types.js';
import { WHO_KNOWS_WHOM } from './questions/whoKnowsWhom.js';
import { WOULD_YOU_RATHER } from './questions/wouldYouRather.js';

const TITLES: Record<GameTypeName, string> = {
  WOULD_YOU_RATHER: 'Would You Rather',
  WHO_KNOWS_WHOM: 'Who Knows Whom Better?',
  SHARED_TRIVIA: 'Team Trivia',
  EMOJI_DECODE: 'Emoji Decode',
  AGREE_O_METER: 'Agree-o-meter',
  RANK_IT: 'Rank It',
};

export const POOLS: Record<GameTypeName, Q[]> = {
  WHO_KNOWS_WHOM,
  WOULD_YOU_RATHER,
  SHARED_TRIVIA,
  EMOJI_DECODE,
  AGREE_O_METER,
  RANK_IT,
};

/**
 * Identifies a question regardless of the order its options are shown in, so
 * a pair's history can be matched against the bank.
 */
export const questionKey = (q: { prompt: string; options: string[] }) =>
  `${q.prompt} :: ${[...q.options].sort().join(' / ')}`;

const rankOf = (seed: string, i: number | string) =>
  createHash('sha256').update(`${seed}:${i}`).digest().readUInt32BE(0);

// Deterministic shuffle seeded by pair + day: both partners get the same game,
// and different pairs/days get different picks.
function seededPick<T>(items: T[], count: number, seed: string): T[] {
  return items
    .map((item, i) => ({ item, rank: rankOf(seed, i) }))
    .sort((a, b) => a.rank - b.rank)
    .slice(0, count)
    .map((x) => x.item);
}

/**
 * Picks questions the pair hasn't had yet. Once a type's pool runs out, the
 * ones they saw longest ago come back first. `seen` is newest first.
 */
function pickFresh(pool: Q[], count: number, seed: string, seen: string[]): Q[] {
  const age = new Map<string, number>();
  seen.forEach((key, i) => {
    if (!age.has(key)) age.set(key, i);
  });
  const fresh = pool.filter((q) => !age.has(questionKey(q)));
  if (fresh.length >= count) return seededPick(fresh, count, seed);
  const oldestFirst = pool
    .filter((q) => age.has(questionKey(q)))
    .sort((a, b) => age.get(questionKey(b))! - age.get(questionKey(a))!);
  return seededPick([...fresh, ...oldestFirst.slice(0, count - fresh.length)], count, seed);
}

/** Quiz answers are written first in the bank; shuffle so the answer moves around. */
function shuffleOptions(q: Q, seed: string) {
  if (q.correctOption === undefined) return { prompt: q.prompt, options: q.options };
  const order = q.options
    .map((_, i) => ({ i, rank: rankOf(`${seed}:${q.prompt}`, i) }))
    .sort((a, b) => a.rank - b.rank)
    .map((x) => x.i);
  return {
    prompt: q.prompt,
    options: order.map((i) => q.options[i]!),
    correctOption: order.indexOf(q.correctOption),
    explanation: q.explanation,
  };
}

const forPair = (pool: Q[], relationship: Relationship) =>
  pool.filter((q) => !q.only || q.only.includes(relationship));

export function bankGame(
  type: GameTypeName,
  seed: string,
  relationship: Relationship = 'FRIENDS',
  seen: string[] = [],
): GameContent {
  const count = type === 'WHO_KNOWS_WHOM' ? 6 : 5;
  const picks = pickFresh(forPair(POOLS[type], relationship), count, seed, seen).map((q) =>
    shuffleOptions(q, seed),
  );
  if (type === 'WHO_KNOWS_WHOM') {
    return {
      type,
      title: TITLES[type],
      questions: picks.map((q, i) => ({ ...q, about: i % 2 === 0 ? ('A' as const) : ('B' as const) })),
    };
  }
  return { type, title: TITLES[type], questions: picks };
}
