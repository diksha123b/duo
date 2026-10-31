import type { ArcadeKind } from '@prisma/client';
import { Chess, type Move as ChessMove } from 'chess.js';
import { SIZE } from '../arcade/engines/dotsAndBoxes.js';
import { COLS } from '../arcade/engines/fourInARow.js';
import { ENGINES } from '../arcade/engines/index.js';
import { HOME, movableTokens } from '../arcade/engines/ludo.js';
import { other, type Rng, type Seat } from '../arcade/engines/types.js';
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

// The demo bot's moves. Friendly rather than strong: it takes a win, blocks
// yours, and in chess avoids giving pieces away, but it doesn't plan ahead.

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
function lineGame(kind: 'TIC_TAC_TOE' | 'FOUR_IN_A_ROW', state: AnyState, seat: Seat, rng: Rng) {
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
  return best(scored, rng);
}

/** Take boxes when offered; otherwise avoid drawing a box's third side. */
function dotsAndBoxes(state: AnyState, seat: Seat, rng: Rng) {
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
  return best(scored, rng);
}

const PIECE: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };

/** Greedy with one move of lookahead: grab material, don't leave pieces hanging. */
function chess(state: AnyState, rng: Rng) {
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
  return best(scored, rng);
}
const toMove = (m: ChessMove) => ({ from: m.from, to: m.to, ...(m.promotion && { promotion: m.promotion }) });

/** Capture if possible, then get a token home, then out of base. */
function ludo(state: AnyState, seat: Seat, rng: Rng) {
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
  return best(scored, rng);
}

/**
 * Finds the best-scoring word it can place within a time budget: on an empty
 * board, across the centre; otherwise through a letter already on the board.
 */
export function wordTilesMove(state: AnyState, seat: Seat, budgetMs = 400): unknown {
  const rack: string[] = state.racks[seat];
  const board: (string | null)[] = state.board;
  const have = new Map<string, number>();
  for (const l of rack) have.set(l, (have.get(l) ?? 0) + 1);
  const empty = board.every((x) => x === null);
  const onBoard = new Set(board.filter(Boolean) as string[]);
  const filled = board.flatMap((l, i) => (l ? [{ r: Math.floor(i / N), c: i % N, l }] : []));

  let bestTiles: Placed[] | null = null;
  let bestPoints = 0;
  const consider = (tiles: Placed[]) => {
    if (tiles.length === 0) return;
    const need = new Map<string, number>();
    for (const t of tiles) need.set(t.letter, (need.get(t.letter) ?? 0) + 1);
    for (const [l, n] of need) if ((have.get(l) ?? 0) < n) return;
    try {
      checkPlacement(board, tiles);
      const { words: formed, points } = scorePlacement(board, tiles);
      if (formed.length > 0 && formed.every(isWord) && points > bestPoints) {
        bestPoints = points;
        bestTiles = tiles;
      }
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

  const list = [...words()];
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
  if (bestTiles) return { type: 'place', tiles: bestTiles };
  // Nothing fits: swap the clunkiest letters while the bag allows, otherwise pass.
  const clunky = [...rack].sort((a, b) => LETTERS[b]![0] - LETTERS[a]![0]).slice(0, 3);
  return state.bag.length >= clunky.length ? { type: 'swap', letters: clunky } : { type: 'pass' };
}

/** The bot's move for `kind`, or null if it has nothing to do. */
export function botMove(kind: ArcadeKind, state: AnyState, seat: Seat, rng: Rng): unknown | null {
  switch (kind) {
    case 'TIC_TAC_TOE':
    case 'FOUR_IN_A_ROW':
      return lineGame(kind, state, seat, rng);
    case 'DOTS_AND_BOXES':
      return dotsAndBoxes(state, seat, rng);
    case 'CHESS':
      return chess(state, rng);
    case 'LUDO':
      return ludo(state, seat, rng);
    case 'WORD_TILES':
      return wordTilesMove(state, seat);
  }
}
