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
//
// The die rolls itself: whenever it becomes someone's turn the server rolls
// for them, so the only thing a player ever does is pick a token. Rolls with
// no legal move pass the turn automatically. While all of a player's tokens
// are stuck in base they get up to three tries to roll a six.

export const TRACK = 52;
export const HOME = 56;
export const START: Record<Seat, number> = { 0: 0, 1: 26 };
// Start squares and the star squares eight steps after each start are safe.
export const SAFE = new Set([0, 8, 13, 21, 26, 34, 39, 47]);
export const BASE_TRIES = 3;
const FEED_LENGTH = 8;

interface Die {
  value: number;
  count: number;
}

/** One roll, as shown in the roll feed. */
interface Roll {
  seat: Seat;
  value: number;
  /** "moved" once the player has used it; "stuck" if nothing could move. */
  result: 'waiting' | 'moved' | 'stuck';
  token?: number;
  captured?: boolean;
}

interface State {
  tokens: [number[], number[]];
  turn: Seat;
  /** The die for the current turn, waiting for a token to be picked. */
  roll: number | null;
  /** What just happened, for the other player's screen. */
  last: { seat: Seat; roll: number; token?: number; captured?: boolean; passed?: boolean } | null;
  /**
   * Each player's most recent roll, so both dice stay on screen for both
   * players. `count` goes up with every roll, so clients can replay the
   * tumble even when the same number comes up twice.
   */
  dice?: [Die | null, Die | null];
  /** Recent rolls, newest last, so nobody misses an automatic pass. */
  feed?: Roll[];
}

type Move = { type: 'move'; token: number };

const trackSquare = (seat: Seat, progress: number) => (START[seat] + progress) % TRACK;
const finished = (s: State) => ([0, 1] as const).some((seat) => s.tokens[seat].every((p) => p === HOME));

export function movableTokens(state: State, seat: Seat, roll: number): number[] {
  return state.tokens[seat].flatMap((p, i) => {
    if (p === -1) return roll === 6 ? [i] : [];
    if (p === HOME) return [];
    return p + roll <= HOME ? [i] : [];
  });
}

function record(state: State, roll: Roll) {
  state.feed = [...(state.feed ?? []), roll].slice(-FEED_LENGTH);
}

/**
 * Rolls for whoever's turn it is until someone has a token they can move.
 * Mutates `state`; call on a clone.
 */
function autoRoll(state: State, rng: Rng) {
  if (finished(state) || state.roll !== null) return;
  let tries = 0;
  // Bounded only as a safety net; a six comes up long before this.
  for (let i = 0; i < 500; i++) {
    const seat = state.turn;
    const value = rng.int(6) + 1;
    const dice = state.dice ?? [null, null];
    dice[seat] = { value, count: (dice[seat]?.count ?? 0) + 1 };
    state.dice = dice;

    if (movableTokens(state, seat, value).length > 0) {
      state.roll = value;
      state.last = { seat, roll: value };
      record(state, { seat, value, result: 'waiting' });
      return;
    }
    record(state, { seat, value, result: 'stuck' });
    state.last = { seat, roll: value, passed: true };

    // Everything still in base (or home): a few tries to get that six.
    const allWaiting = state.tokens[seat].every((p) => p === -1 || p === HOME);
    tries++;
    if (allWaiting && tries < BASE_TRIES) continue;
    tries = 0;
    state.turn = other(seat);
  }
}

export const ludo: Engine<State, Move> = {
  init(rng) {
    const state: State = {
      tokens: [
        [-1, -1, -1, -1],
        [-1, -1, -1, -1],
      ],
      turn: 0,
      roll: null,
      last: null,
      dice: [null, null],
      feed: [],
    };
    autoRoll(state, rng);
    return state;
  },
  move: z.object({ type: z.literal('move'), token: z.number().int().min(0).max(3) }),
  apply(state, seat, move, rng: Rng) {
    const roll = state.roll;
    if (roll === null) throw new MoveError('The die is still rolling');
    if (!movableTokens(state, seat, roll).includes(move.token)) throw new MoveError('That token can’t move');

    const next = clone(state);
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

    // Mark the waiting roll as used.
    const feed = next.feed ?? [];
    const waiting = feed[feed.length - 1];
    if (waiting && waiting.result === 'waiting')
      Object.assign(waiting, { result: 'moved', token: move.token, captured });

    // A six, a capture or reaching home earns another turn.
    const again = roll === 6 || captured || to === HOME;
    next.roll = null;
    next.turn = again ? seat : other(seat);
    next.last = { seat, roll, token: move.token, captured };
    autoRoll(next, rng);
    return next;
  },
  settle(state, rng) {
    // Games saved before the die rolled itself may be waiting on a manual roll.
    if (state.roll !== null || finished(state)) return state;
    const next = clone(state);
    autoRoll(next, rng);
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
      dice: state.dice ?? [null, null],
      feed: state.feed ?? [],
      movable: state.turn === seat && state.roll !== null ? movableTokens(state, seat, state.roll) : [],
    };
  },
};
