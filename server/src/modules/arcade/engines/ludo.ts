import { z } from 'zod';
import { clone, MoveError, other, type Engine, type Rng, type Seat } from './types.js';

// Two-player ludo on the classic 52-square track, players on opposite sides.
//
// Each token's position is its own progress, not a board square:
//   -1        in base
//   0..50     on the shared track, counted from the owner's start square
//   51..55    in the owner's home column
//   56        home (finished)
// The shared-track square is (START[seat] + progress) % 52, which is what
// captures compare.

export const TRACK = 52;
export const HOME = 56;
export const START: Record<Seat, number> = { 0: 0, 1: 26 };
// Start squares and the star squares eight steps after each start are safe.
export const SAFE = new Set([0, 8, 13, 21, 26, 34, 39, 47]);

interface State {
  tokens: [number[], number[]];
  turn: Seat;
  /** The die for the current turn, once rolled. */
  roll: number | null;
  /** What just happened, for the other player's screen. */
  last: { seat: Seat; roll: number; token?: number; captured?: boolean; passed?: boolean } | null;
}

type Move = { type: 'roll' } | { type: 'move'; token: number };

const trackSquare = (seat: Seat, progress: number) => (START[seat] + progress) % TRACK;

export function movableTokens(state: State, seat: Seat, roll: number): number[] {
  return state.tokens[seat].flatMap((p, i) => {
    if (p === -1) return roll === 6 ? [i] : [];
    if (p === HOME) return [];
    return p + roll <= HOME ? [i] : [];
  });
}

export const ludo: Engine<State, Move> = {
  init: () => ({
    tokens: [
      [-1, -1, -1, -1],
      [-1, -1, -1, -1],
    ],
    turn: 0,
    roll: null,
    last: null,
  }),
  move: z.discriminatedUnion('type', [
    z.object({ type: z.literal('roll') }),
    z.object({ type: z.literal('move'), token: z.number().int().min(0).max(3) }),
  ]),
  apply(state, seat, move, rng: Rng) {
    const next = clone(state);
    if (move.type === 'roll') {
      if (state.roll !== null) throw new MoveError('You already rolled. Move a token');
      const roll = rng.int(6) + 1;
      if (movableTokens(state, seat, roll).length === 0) {
        // Nothing can move with this roll: the turn passes.
        next.turn = other(seat);
        next.last = { seat, roll, passed: true };
        return next;
      }
      next.roll = roll;
      next.last = { seat, roll };
      return next;
    }

    const roll = state.roll;
    if (roll === null) throw new MoveError('Roll the die first');
    if (!movableTokens(state, seat, roll).includes(move.token)) throw new MoveError('That token can’t move');

    const from = state.tokens[seat][move.token]!;
    const to = from === -1 ? 0 : from + roll;
    next.tokens[seat][move.token] = to;

    // Landing on the other player's token on an unsafe track square sends it home.
    let captured = false;
    if (to <= 50) {
      const square = trackSquare(seat, to);
      if (!SAFE.has(square)) {
        const opp = other(seat);
        next.tokens[opp] = next.tokens[opp].map((p) => {
          if (p >= 0 && p <= 50 && trackSquare(opp, p) === square) {
            captured = true;
            return -1;
          }
          return p;
        });
      }
    }

    // A six, a capture or reaching home earns another turn.
    const again = roll === 6 || captured || to === HOME;
    next.roll = null;
    next.turn = again ? seat : other(seat);
    next.last = { seat, roll, token: move.token, captured };
    return next;
  },
  outcome(state) {
    for (const seat of [0, 1] as const) {
      if (state.tokens[seat].every((p) => p === HOME)) return { turn: null, winner: seat };
    }
    return { turn: state.turn, winner: null };
  },
  view(state, seat) {
    return {
      tokens: state.tokens,
      roll: state.roll,
      last: state.last,
      movable: state.turn === seat && state.roll !== null ? movableTokens(state, seat, state.roll) : [],
    };
  },
};
