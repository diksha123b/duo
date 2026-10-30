import { z } from 'zod';
import { clone, MoveError, other, type Engine, type Seat } from './types.js';

/** Boxes per side; the grid has SIZE+1 dots per side. */
export const SIZE = 4;

interface State {
  // h[r*SIZE + c]: line from dot (r,c) to (r,c+1), r in 0..SIZE
  h: (Seat | null)[];
  // v[r*(SIZE+1) + c]: line from dot (r,c) to (r+1,c), r in 0..SIZE-1
  v: (Seat | null)[];
  boxes: (Seat | null)[];
  scores: [number, number];
  turn: Seat;
}

const boxClosed = (s: State, r: number, c: number) =>
  s.h[r * SIZE + c] !== null &&
  s.h[(r + 1) * SIZE + c] !== null &&
  s.v[r * (SIZE + 1) + c] !== null &&
  s.v[r * (SIZE + 1) + c + 1] !== null;

export const dotsAndBoxes: Engine<State, { dir: 'h' | 'v'; r: number; c: number }> = {
  init: () => ({
    h: Array((SIZE + 1) * SIZE).fill(null),
    v: Array(SIZE * (SIZE + 1)).fill(null),
    boxes: Array(SIZE * SIZE).fill(null),
    scores: [0, 0],
    turn: 0,
  }),
  move: z.object({ dir: z.enum(['h', 'v']), r: z.number().int().min(0), c: z.number().int().min(0) }),
  apply(state, seat, { dir, r, c }) {
    const valid = dir === 'h' ? r <= SIZE && c < SIZE : r < SIZE && c <= SIZE;
    if (!valid) throw new MoveError('That line is off the board');
    const idx = dir === 'h' ? r * SIZE + c : r * (SIZE + 1) + c;
    const lines = dir === 'h' ? state.h : state.v;
    if (lines[idx] !== null) throw new MoveError('That line is already drawn');

    const next = clone(state);
    (dir === 'h' ? next.h : next.v)[idx] = seat;
    // A line touches up to two boxes; any it completes are yours.
    const touched =
      dir === 'h'
        ? [
            [r - 1, c],
            [r, c],
          ]
        : [
            [r, c - 1],
            [r, c],
          ];
    let closed = 0;
    for (const [br, bc] of touched) {
      if (br! < 0 || br! >= SIZE || bc! < 0 || bc! >= SIZE) continue;
      if (next.boxes[br! * SIZE + bc!] === null && boxClosed(next, br!, bc!)) {
        next.boxes[br! * SIZE + bc!] = seat;
        closed++;
      }
    }
    next.scores[seat] += closed;
    // Closing a box earns another go.
    next.turn = closed > 0 ? seat : other(seat);
    return next;
  },
  outcome(state) {
    if (state.boxes.some((b) => b === null)) return { turn: state.turn, winner: null };
    const [a, b] = state.scores;
    return { turn: null, winner: a === b ? 'draw' : a > b ? 0 : 1 };
  },
  view: (state) => ({ size: SIZE, h: state.h, v: state.v, boxes: state.boxes, scores: state.scores }),
};
