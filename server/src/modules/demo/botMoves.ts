import { readFileSync } from 'node:fs';
import type { ArcadeKind } from '@prisma/client';
import { Chess, type Move as ChessMove } from 'chess.js';
import { SIZE } from '../arcade/engines/dotsAndBoxes.js';
import { COLS } from '../arcade/engines/fourInARow.js';
import { ENGINES } from '../arcade/engines/index.js';
import { HOME, movableTokens } from '../arcade/engines/ludo.js';
import { other, type Rng, type Seat } from '../arcade/engines/types.js';
import type { BotLevel } from '../arcade/service.js';
import {
  CENTER,
  checkPlacement,
  isWord,
  LETTERS,
  N,
  scorePlacement,
  words,
  type Placed,
} from '../arcade/engines/wordTiles.js';

// The demo bot's moves. Each game scores every legal move (take a win, block
// yours, don't hang chess pieces…), then the level decides how often the bot
// actually plays its best one:
//   hard   always the best move (Word Tiles: any word in the dictionary)
//   normal usually the best, sometimes just a good one (common words only)
//   easy   often a random move (common words, smaller plays)

type Scored = { move: unknown; score: number };

/** Throwaway randomness for trying moves out; the real move uses the server's. */
const scratch: Rng = { int: (n) => Math.floor(Math.random() * n) };

/** The best-scoring move, picking at random between near-ties. */
function best(candidates: Scored[], rng: Rng): unknown | null {
  if (candidates.length === 0) return null;
  const top = Math.max(...candidates.map((c) => c.score));
  const pool = candidates.filter((c) => c.score >= top - 0.5);
  return pool[rng.int(pool.length)]!.move;
}

/** How often each level plays its best move; otherwise it picks from a wider pool. */
const BEST_CHANCE: Record<BotLevel, number> = { hard: 100, normal: 70, easy: 30 };

function choose(candidates: Scored[], level: BotLevel, rng: Rng): unknown | null {
  if (candidates.length === 0) return null;
  if (rng.int(100) < BEST_CHANCE[level]) return best(candidates, rng);
  const sorted = [...candidates].sort((a, b) => b.score - a.score);
  // Normal still picks a decent move; easy can pick anything legal.
  const pool = level === 'normal' ? sorted.slice(0, Math.ceil(sorted.length / 2)) : sorted;
  return pool[rng.int(pool.length)]!.move;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyState = any;

function tryApply(kind: ArcadeKind, state: AnyState, seat: Seat, move: unknown): AnyState | null {
  try {
    return ENGINES[kind].apply(state, seat, move, scratch);
  } catch {
    return null;
  }
}

const winsFor = (kind: ArcadeKind, state: AnyState, seat: Seat) =>
  ENGINES[kind].outcome(state).winner === seat;

/** Win if we can, otherwise block a square or column that would win for them. */
function lineGame(
  kind: 'TIC_TAC_TOE' | 'FOUR_IN_A_ROW',
  state: AnyState,
  seat: Seat,
  rng: Rng,
  level: BotLevel,
) {
  const opp = other(seat);
  const moves =
    kind === 'TIC_TAC_TOE'
      ? [...Array(9).keys()].map((cell) => ({ cell }))
      : [...Array(COLS).keys()].map((col) => ({ col }));
  const scored: Scored[] = [];
  for (const move of moves) {
    const next = tryApply(kind, state, seat, move);
    if (!next) continue;
    let score = winsFor(kind, next, seat) ? 100 : 0;
    const theirs = tryApply(kind, { ...state, turn: opp }, opp, move);
    if (theirs && winsFor(kind, theirs, opp)) score += 50;
    if (kind === 'FOUR_IN_A_ROW') {
      const col = (move as { col: number }).col;
      score += 3 - Math.abs(col - Math.floor(COLS / 2));
      // Don't hand them a win on top of our disc.
      if (
        moves.some((m) => {
          const reply = tryApply(kind, next, opp, m);
          return reply && winsFor(kind, reply, opp);
        })
      )
        score -= 40;
    } else {
      const cell = (move as { cell: number }).cell;
      score += cell === 4 ? 3 : [0, 2, 6, 8].includes(cell) ? 2 : 0;
    }
    scored.push({ move, score });
  }
  return choose(scored, level, rng);
}

/** Take boxes when offered; otherwise avoid drawing a box's third side. */
function dotsAndBoxes(state: AnyState, seat: Seat, rng: Rng, level: BotLevel) {
  const moves = [
    ...[...Array((SIZE + 1) * SIZE).keys()].map((i) => ({ dir: 'h', r: Math.floor(i / SIZE), c: i % SIZE })),
    ...[...Array(SIZE * (SIZE + 1)).keys()].map((i) => ({
      dir: 'v',
      r: Math.floor(i / (SIZE + 1)),
      c: i % (SIZE + 1),
    })),
  ];
  const sides = (s: AnyState, r: number, c: number) =>
    [s.h[r * SIZE + c], s.h[(r + 1) * SIZE + c], s.v[r * (SIZE + 1) + c], s.v[r * (SIZE + 1) + c + 1]].filter(
      (x: Seat | null) => x !== null,
    ).length;
  const scored: Scored[] = [];
  for (const move of moves) {
    const next = tryApply('DOTS_AND_BOXES', state, seat, move);
    if (!next) continue;
    const gained = next.scores[seat] - state.scores[seat];
    let gifts = 0;
    for (let r = 0; r < SIZE; r++) for (let c = 0; c < SIZE; c++) if (sides(next, r, c) === 3) gifts++;
    scored.push({ move, score: gained * 10 - (gained ? 0 : gifts * 5) });
  }
  return choose(scored, level, rng);
}

const PIECE: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };

/** Greedy with one move of lookahead: grab material, don't leave pieces hanging. */
function chess(state: AnyState, rng: Rng, level: BotLevel) {
  const game = new Chess(state.fen);
  const scored: Scored[] = game.moves({ verbose: true }).map((m: ChessMove) => {
    const after = new Chess(state.fen);
    after.move(m);
    if (after.isCheckmate()) return { move: toMove(m), score: 1000 };
    const gain = (m.captured ? PIECE[m.captured]! : 0) + (m.promotion ? 8 : 0);
    const risk = Math.max(
      0,
      ...after.moves({ verbose: true }).map((r: ChessMove) => (r.captured ? PIECE[r.captured]! : 0)),
    );
    return { move: toMove(m), score: gain - risk + (after.inCheck() ? 0.3 : 0) };
  });
  return choose(scored, level, rng);
}
const toMove = (m: ChessMove) => ({ from: m.from, to: m.to, ...(m.promotion && { promotion: m.promotion }) });

/** Capture if possible, then get a token home, then out of base. */
function ludo(state: AnyState, seat: Seat, rng: Rng, level: BotLevel) {
  if (state.roll === null) return null;
  const scored: Scored[] = movableTokens(state, seat, state.roll).map((token) => {
    const move = { type: 'move', token };
    const next = tryApply('LUDO', state, seat, move);
    const from = state.tokens[seat][token];
    let score = 1 + from / 100;
    if (next?.last?.captured) score += 50;
    if (next && next.tokens[seat][token] === HOME) score += 40;
    if (from === -1) score += 20;
    return { move, score };
  });
  return choose(scored, level, rng);
}

let common: string[] | null = null;
/** ~10k everyday words (SCOWL levels 10–20, see data/SCOWL-LICENSE.txt). */
function commonWords(): string[] {
  common ??= readFileSync(new URL('../../../data/common-words.txt', import.meta.url), 'utf8')
    .split('\n')
    .map((w) => w.trim().toUpperCase())
    .filter(Boolean);
  return common;
}

type Play = { tiles: Placed[]; points: number; length: number };

/** Every placement of `list` words it can find within the time budget. */
function findPlays(state: AnyState, seat: Seat, list: string[], budgetMs: number): Play[] {
  const rack: string[] = state.racks[seat];
  const board: (string | null)[] = state.board;
  const have = new Map<string, number>();
  for (const l of rack) have.set(l, (have.get(l) ?? 0) + 1);
  const empty = board.every((x) => x === null);
  const onBoard = new Set(board.filter(Boolean) as string[]);
  const filled = board.flatMap((l, i) => (l ? [{ r: Math.floor(i / N), c: i % N, l }] : []));
  const plays: Play[] = [];
  const seen = new Set<string>();

  const consider = (tiles: Placed[]) => {
    if (tiles.length === 0) return;
    const need = new Map<string, number>();
    for (const t of tiles) need.set(t.letter, (need.get(t.letter) ?? 0) + 1);
    for (const [l, n] of need) if ((have.get(l) ?? 0) < n) return;
    const key = tiles.map((t) => `${t.r},${t.c},${t.letter}`).join('|');
    if (seen.has(key)) return;
    seen.add(key);
    try {
      checkPlacement(board, tiles);
      const { words: formed, points } = scorePlacement(board, tiles);
      if (formed.length > 0 && formed.every(isWord)) plays.push({ tiles, points, length: tiles.length });
    } catch {
      // Not a legal placement.
    }
  };
  const place = (word: string, r0: number, c0: number, dr: number, dc: number) => {
    const tiles: Placed[] = [];
    for (let k = 0; k < word.length; k++) {
      const r = r0 + dr * k;
      const c = c0 + dc * k;
      if (r < 0 || r >= N || c < 0 || c >= N) return;
      const there = board[r * N + c];
      if (there) {
        if (there !== word[k]) return;
      } else tiles.push({ r, c, letter: word[k]! });
    }
    consider(tiles);
  };

  const start = Math.floor(Math.random() * list.length);
  const deadline = Date.now() + budgetMs;
  for (let n = 0; n < list.length && Date.now() < deadline; n++) {
    const word = list[(start + n) % list.length]!;
    if (word.length < 2 || word.length > 8) continue;
    // Letters the rack can't cover must come from the board.
    let missing = 0;
    const counts = new Map<string, number>();
    for (const l of word) counts.set(l, (counts.get(l) ?? 0) + 1);
    for (const [l, n2] of counts) missing += Math.max(0, n2 - (have.get(l) ?? 0));
    if (missing > (empty ? 0 : 2)) continue;

    if (empty) {
      for (let c0 = CENTER - word.length + 1; c0 <= CENTER; c0++) place(word, CENTER, c0, 0, 1);
      continue;
    }
    if (![...word].some((l) => onBoard.has(l))) continue;
    for (const cell of filled) {
      for (let k = 0; k < word.length; k++) {
        if (word[k] !== cell.l) continue;
        place(word, cell.r, cell.c - k, 0, 1);
        place(word, cell.r - k, cell.c, 1, 0);
      }
    }
  }
  return plays;
}

/**
 * Word Tiles. Hard searches the whole dictionary and plays the top score.
 * Normal and easy only use everyday words (falling back to the dictionary if
 * nothing fits): normal picks from its better plays, easy from the smaller ones.
 */
export function wordTilesMove(
  state: AnyState,
  seat: Seat,
  budgetMs = 400,
  level: BotLevel = 'normal',
  rng: Rng = scratch,
): unknown {
  let plays = findPlays(state, seat, level === 'hard' ? [...words()] : commonWords(), budgetMs);
  if (plays.length === 0 && level !== 'hard') plays = findPlays(state, seat, [...words()], budgetMs);
  if (plays.length > 0) {
    plays.sort((a, b) => b.points - a.points);
    const pick =
      level === 'hard'
        ? plays[0]!
        : level === 'normal'
          ? plays[rng.int(Math.max(1, Math.ceil(plays.length * 0.3)))]!
          : plays.slice(Math.floor(plays.length * 0.4))[
              rng.int(plays.length - Math.floor(plays.length * 0.4))
            ]!;
    return { type: 'place', tiles: pick.tiles };
  }
  // Nothing fits: swap the clunkiest letters while the bag allows, otherwise pass.
  const rack: string[] = state.racks[seat];
  const clunky = [...rack].sort((a, b) => LETTERS[b]![0] - LETTERS[a]![0]).slice(0, 3);
  return state.bag.length >= clunky.length ? { type: 'swap', letters: clunky } : { type: 'pass' };
}

/** The bot's move for `kind`, or null if it has nothing to do. */
export function botMove(
  kind: ArcadeKind,
  state: AnyState,
  seat: Seat,
  rng: Rng,
  level: BotLevel = 'normal',
): unknown | null {
  switch (kind) {
    case 'TIC_TAC_TOE':
    case 'FOUR_IN_A_ROW':
      return lineGame(kind, state, seat, rng, level);
    case 'DOTS_AND_BOXES':
      return dotsAndBoxes(state, seat, rng, level);
    case 'CHESS':
      return chess(state, rng, level);
    case 'LUDO':
      return ludo(state, seat, rng, level);
    case 'WORD_TILES':
      return wordTilesMove(state, seat, 400, level, rng);
  }
}
