import { readFileSync } from 'node:fs';
import { z } from 'zod';
import { clone, MoveError, other, type Engine, type Seat } from './types.js';

// Word Tiles: Duo's own crossword-style tile game. 11×11 board, 7-tile racks,
// every word formed by a move must be a real word. Board layout, letter
// values and tile counts are Duo's own.

export const N = 11;
export const RACK = 7;
export const ALL_TILES_BONUS = 35;

// Letter → [points, copies in the bag]
export const LETTERS: Record<string, [number, number]> = {
  A: [1, 8],
  B: [3, 2],
  C: [3, 2],
  D: [2, 4],
  E: [1, 11],
  F: [4, 2],
  G: [2, 3],
  H: [4, 2],
  I: [1, 8],
  J: [8, 1],
  K: [5, 1],
  L: [1, 4],
  M: [3, 2],
  N: [1, 6],
  O: [1, 7],
  P: [3, 2],
  Q: [10, 1],
  R: [1, 6],
  S: [1, 5],
  T: [1, 6],
  U: [1, 4],
  V: [4, 1],
  W: [4, 2],
  X: [8, 1],
  Y: [4, 2],
  Z: [10, 1],
};

export type Bonus = 'TW' | 'DW' | 'TL' | 'DL';

/** Bonus squares, symmetric about the centre. The centre is a DW start square. */
export const BONUSES: Record<string, Bonus> = (() => {
  const m: Record<string, Bonus> = {};
  const mirror = (r: number, c: number, b: Bonus) => {
    for (const [rr, cc] of [
      [r, c],
      [c, r],
      [N - 1 - r, c],
      [r, N - 1 - c],
      [N - 1 - r, N - 1 - c],
      [c, N - 1 - r],
      [N - 1 - c, r],
      [N - 1 - c, N - 1 - r],
    ]) {
      m[`${rr},${cc}`] = b;
    }
  };
  mirror(0, 0, 'TW');
  mirror(0, 5, 'TW');
  mirror(1, 1, 'DW');
  mirror(2, 2, 'DW');
  mirror(3, 3, 'DW');
  mirror(1, 5, 'TL');
  mirror(4, 4, 'DL');
  mirror(2, 5, 'DL');
  mirror(3, 0, 'DL');
  m['5,5'] = 'DW';
  return m;
})();
export const CENTER = Math.floor(N / 2);

let dictionary: Set<string> | null = null;
/** The word list (ENABLE, public domain), loaded on first use. */
export function words(): Set<string> {
  dictionary ??= new Set(
    readFileSync(new URL('../../../../data/words.txt', import.meta.url), 'utf8')
      .split('\n')
      .map((w) => w.trim().toUpperCase())
      .filter(Boolean),
  );
  return dictionary;
}

export const isWord = (word: string): boolean => words().has(word);

export interface Placed {
  r: number;
  c: number;
  letter: string;
}

interface State {
  board: (string | null)[];
  racks: [string[], string[]];
  bag: string[];
  scores: [number, number];
  turn: Seat;
  /** Scoreless turns in a row (passes and swaps). Four ends the game. */
  scoreless: number;
  finished: boolean;
  last: {
    seat: Seat;
    kind: 'place' | 'pass' | 'swap';
    words?: string[];
    points?: number;
    tiles?: Placed[];
  } | null;
}

type Move = { type: 'place'; tiles: Placed[] } | { type: 'pass' } | { type: 'swap'; letters: string[] };

const idx = (r: number, c: number) => r * N + c;
const rackValue = (rack: string[]) => rack.reduce((s, l) => s + (LETTERS[l]?.[0] ?? 0), 0);

function takeFromRack(rack: string[], letters: string[]): string[] {
  const left = [...rack];
  for (const l of letters) {
    const i = left.indexOf(l);
    if (i < 0) throw new MoveError(`You don’t have the letter ${l}`);
    left.splice(i, 1);
  }
  return left;
}

/**
 * Refills a rack from the bag. A rack is never left without a vowel while the
 * bag still has one: the last tile drawn is a vowel if it has to be, so nobody
 * is stuck with seven consonants for turn after turn.
 */
function draw(state: State, seat: Seat) {
  const rack = state.racks[seat];
  while (rack.length < RACK && state.bag.length > 0) {
    const last = rack.length === RACK - 1 || state.bag.length === 1;
    const needVowel = last && !rack.some((l) => VOWELS.has(l));
    const i = needVowel ? state.bag.findLastIndex((l) => VOWELS.has(l)) : -1;
    rack.push(i >= 0 ? state.bag.splice(i, 1)[0]! : state.bag.pop()!);
  }
}

/** All words (with their cells) the placed tiles form, and the points they score. */
export function scorePlacement(
  board: (string | null)[],
  tiles: Placed[],
): { words: string[]; points: number } {
  const placed = new Map(tiles.map((t) => [`${t.r},${t.c}`, t.letter]));
  const letterAt = (r: number, c: number) =>
    r < 0 || r >= N || c < 0 || c >= N ? null : (placed.get(`${r},${c}`) ?? board[idx(r, c)]);

  const wordThrough = (r: number, c: number, dr: number, dc: number) => {
    while (letterAt(r - dr, c - dc)) [r, c] = [r - dr, c - dc];
    const cells: [number, number][] = [];
    while (letterAt(r, c)) {
      cells.push([r, c]);
      [r, c] = [r + dr, c + dc];
    }
    return cells;
  };

  const sameRow = tiles.every((t) => t.r === tiles[0]!.r);
  const [dr, dc] = sameRow ? [0, 1] : [1, 0];
  const lines: [number, number][][] = [wordThrough(tiles[0]!.r, tiles[0]!.c, dr, dc)];
  for (const t of tiles) lines.push(wordThrough(t.r, t.c, dc, dr));
  // A single tile can make its "main" word either way; both are covered above.

  const words: string[] = [];
  let points = 0;
  const seen = new Set<string>();
  for (const cells of lines) {
    if (cells.length < 2) continue;
    const key = cells.map(([r, c]) => `${r},${c}`).join('|');
    if (seen.has(key)) continue;
    seen.add(key);
    let sum = 0;
    let mult = 1;
    for (const [r, c] of cells) {
      const letter = letterAt(r, c)!;
      let value = LETTERS[letter]![0];
      if (placed.has(`${r},${c}`)) {
        const b = BONUSES[`${r},${c}`];
        if (b === 'DL') value *= 2;
        if (b === 'TL') value *= 3;
        if (b === 'DW') mult *= 2;
        if (b === 'TW') mult *= 3;
      }
      sum += value;
    }
    words.push(cells.map(([r, c]) => letterAt(r, c)).join(''));
    points += sum * mult;
  }
  if (tiles.length === RACK) points += ALL_TILES_BONUS;
  return { words, points };
}

export function checkPlacement(board: (string | null)[], tiles: Placed[]) {
  if (tiles.length === 0) throw new MoveError('Place at least one tile');
  const keys = new Set<string>();
  for (const t of tiles) {
    if (t.r < 0 || t.r >= N || t.c < 0 || t.c >= N) throw new MoveError('That’s off the board');
    if (board[idx(t.r, t.c)]) throw new MoveError('That square is taken');
    if (keys.has(`${t.r},${t.c}`)) throw new MoveError('Two tiles on one square');
    keys.add(`${t.r},${t.c}`);
  }
  const sameRow = tiles.every((t) => t.r === tiles[0]!.r);
  const sameCol = tiles.every((t) => t.c === tiles[0]!.c);
  if (!sameRow && !sameCol) throw new MoveError('Tiles must go in one line');

  // No gaps: every square between the first and last tile is filled.
  const along = tiles.map((t) => (sameRow ? t.c : t.r));
  const fixed = sameRow ? tiles[0]!.r : tiles[0]!.c;
  for (let k = Math.min(...along); k <= Math.max(...along); k++) {
    const [r, c] = sameRow ? [fixed, k] : [k, fixed];
    if (!keys.has(`${r},${c}`) && !board[idx(r, c)]) throw new MoveError('Leave no gaps in your word');
  }

  const empty = board.every((x) => x === null);
  if (empty) {
    if (!keys.has(`${CENTER},${CENTER}`)) throw new MoveError('The first word must cover the centre star');
    if (tiles.length < 2) throw new MoveError('The first word needs at least two letters');
    return;
  }
  const touches = tiles.some((t) =>
    [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ].some(([dr, dc]) => {
      const r = t.r + dr!;
      const c = t.c + dc!;
      return r >= 0 && r < N && c >= 0 && c < N && board[idx(r, c)] !== null;
    }),
  );
  if (!touches) throw new MoveError('Your word must connect to tiles on the board');
}

const VOWELS = new Set(['A', 'E', 'I', 'O', 'U']);

export const wordTiles: Engine<State, Move> = {
  init(rng, options) {
    // A quick game uses about half of each letter (at least one of each).
    const copies = (n: number) => (options?.quick ? Math.max(1, Math.round(n / 2)) : n);
    const bag = Object.entries(LETTERS).flatMap(([l, [, n]]) => Array<string>(copies(n)).fill(l));
    for (let i = bag.length - 1; i > 0; i--) {
      const j = rng.int(i + 1);
      [bag[i], bag[j]] = [bag[j]!, bag[i]!];
    }
    const state: State = {
      board: Array(N * N).fill(null),
      racks: [[], []],
      bag,
      scores: [0, 0],
      turn: 0,
      scoreless: 0,
      finished: false,
      last: null,
    };
    draw(state, 0);
    draw(state, 1);
    return state;
  },
  move: z.discriminatedUnion('type', [
    z.object({
      type: z.literal('place'),
      tiles: z
        .array(
          z.object({
            r: z.number().int(),
            c: z.number().int(),
            letter: z
              .string()
              .regex(/^[A-Za-z]$/)
              .transform((l) => l.toUpperCase()),
          }),
        )
        .min(1)
        .max(RACK),
    }),
    z.object({ type: z.literal('pass') }),
    z.object({
      type: z.literal('swap'),
      letters: z
        .array(z.string().regex(/^[A-Z]$/))
        .min(1)
        .max(RACK),
    }),
  ]),
  apply(state, seat, move, rng) {
    if (state.finished) throw new MoveError('The game is over');
    const next = clone(state);
    const opp = other(seat);

    if (move.type === 'pass') {
      next.scoreless++;
      next.last = { seat, kind: 'pass' };
    } else if (move.type === 'swap') {
      if (state.bag.length < move.letters.length)
        throw new MoveError('Not enough tiles left in the bag to swap');
      next.racks[seat] = takeFromRack(state.racks[seat], move.letters);
      next.bag.push(...move.letters);
      for (let i = next.bag.length - 1; i > 0; i--) {
        const j = rng.int(i + 1);
        [next.bag[i], next.bag[j]] = [next.bag[j]!, next.bag[i]!];
      }
      draw(next, seat);
      next.scoreless++;
      next.last = { seat, kind: 'swap' };
    } else {
      checkPlacement(state.board, move.tiles);
      next.racks[seat] = takeFromRack(
        state.racks[seat],
        move.tiles.map((t) => t.letter),
      );
      const { words, points } = scorePlacement(state.board, move.tiles);
      if (words.length === 0) throw new MoveError('Make a word of at least two letters');
      const bad = words.filter((w) => !isWord(w));
      if (bad.length) throw new MoveError(`Not in the dictionary: ${bad.join(', ')}`);
      for (const t of move.tiles) next.board[idx(t.r, t.c)] = t.letter;
      next.scores[seat] += points;
      next.scoreless = 0;
      draw(next, seat);
      next.last = { seat, kind: 'place', words, points, tiles: move.tiles };

      // Going out: the bag is empty and you used your last tile.
      if (next.bag.length === 0 && next.racks[seat].length === 0) {
        const leftover = rackValue(next.racks[opp]);
        next.scores[seat] += leftover;
        next.scores[opp] -= leftover;
        next.finished = true;
      }
    }

    if (next.scoreless >= 4) {
      next.scores[0] -= rackValue(next.racks[0]);
      next.scores[1] -= rackValue(next.racks[1]);
      next.finished = true;
    }
    next.turn = opp;
    return next;
  },
  outcome(state) {
    if (!state.finished) return { turn: state.turn, winner: null };
    const [a, b] = state.scores;
    return { turn: null, winner: a === b ? 'draw' : a > b ? 0 : 1 };
  },
  view(state, seat) {
    return {
      size: N,
      board: state.board,
      bonuses: BONUSES,
      letterValues: Object.fromEntries(Object.entries(LETTERS).map(([l, [v]]) => [l, v])),
      rack: state.racks[seat],
      otherRackCount: state.racks[other(seat)].length,
      bagCount: state.bag.length,
      scores: state.scores,
      last: state.last,
    };
  },
};
