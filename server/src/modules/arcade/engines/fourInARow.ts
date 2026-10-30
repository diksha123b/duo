import { z } from 'zod';
import { clone, MoveError, other, type Engine, type Seat } from './types.js';

export const COLS = 7;
export const ROWS = 6;

interface State {
  // Row-major, row 0 at the top.
  board: (Seat | null)[];
  turn: Seat;
  last: number | null;
}

const at = (b: (Seat | null)[], r: number, c: number) =>
  r >= 0 && r < ROWS && c >= 0 && c < COLS ? b[r * COLS + c] : null;

/** The four winning cells, if someone has connected four. */
export function winningLine(board: (Seat | null)[]): number[] | null {
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      const v = at(board, r, c);
      if (v === null) continue;
      for (const [dr, dc] of [
        [0, 1],
        [1, 0],
        [1, 1],
        [1, -1],
      ] as const) {
        const cells = [0, 1, 2, 3].map((k) => [r + dr * k, c + dc * k] as const);
        if (cells.every(([rr, cc]) => at(board, rr, cc) === v))
          return cells.map(([rr, cc]) => rr * COLS + cc);
      }
    }
  }
  return null;
}

export const fourInARow: Engine<State, { col: number }> = {
  init: () => ({ board: Array(ROWS * COLS).fill(null), turn: 0, last: null }),
  move: z.object({
    col: z
      .number()
      .int()
      .min(0)
      .max(COLS - 1),
  }),
  apply(state, seat, { col }) {
    let row = -1;
    for (let r = ROWS - 1; r >= 0; r--) {
      if (at(state.board, r, col) === null) {
        row = r;
        break;
      }
    }
    if (row < 0) throw new MoveError('That column is full');
    const next = clone(state);
    next.board[row * COLS + col] = seat;
    next.last = row * COLS + col;
    next.turn = other(seat);
    return next;
  },
  outcome(state) {
    const line = winningLine(state.board);
    if (line) return { turn: null, winner: state.board[line[0]!]! };
    if (state.board.every((x) => x !== null)) return { turn: null, winner: 'draw' };
    return { turn: state.turn, winner: null };
  },
  view: (state) => ({
    board: state.board,
    rows: ROWS,
    cols: COLS,
    last: state.last,
    winningLine: winningLine(state.board),
  }),
};
