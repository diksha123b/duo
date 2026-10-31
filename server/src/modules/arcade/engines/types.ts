import type { z } from 'zod';

export type Seat = 0 | 1;
export const other = (s: Seat): Seat => (s === 0 ? 1 : 0);

/** Whose turn it is, and who won once it's over. */
export interface Outcome {
  turn: Seat | null;
  winner: Seat | 'draw' | null;
}

/** Thrown for any illegal move; the API returns it as a 400 the player sees. */
export class MoveError extends Error {}

/** Injected randomness (dice, tile bags) so tests can be deterministic. */
export interface Rng {
  int(maxExclusive: number): number;
}

/**
 * A two-player, turn-based game. Engines are pure: `apply` returns a new
 * state and never mutates its input, so a rejected move leaves nothing behind.
 * The server is the only place moves are judged, so clients can't cheat.
 */
/** Options picked when a game starts. Engines ignore what doesn't apply to them. */
export interface GameOptions {
  /** Word Tiles: about half the tiles, for a ~10 minute game. */
  quick?: boolean;
}

export interface Engine<S, M> {
  init(rng: Rng, options?: GameOptions): S;
  /** Shape of a move from the client, validated before `apply`. */
  move: z.ZodType<M>;
  apply(state: S, seat: Seat, move: M, rng: Rng): S;
  outcome(state: S): Outcome;
  /**
   * Optional: advance anything that happens without a player (e.g. an
   * automatic dice roll) on a stored state. Returns the same object when
   * there is nothing to do.
   */
  settle?(state: S, rng: Rng): S;
  /** What `seat` may see: hidden information (racks, the bag) is removed. */
  view(state: S, seat: Seat): unknown;
}

export const clone = <T>(x: T): T => structuredClone(x);
