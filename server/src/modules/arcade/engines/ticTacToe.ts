import { z } from 'zod';
import { clone, MoveError, other, type Engine, type Seat } from './types.js';

interface State {
  board: (Seat | null)[];
  turn: Seat;
}

const LINES = [
  [0, 1, 2],
  [3, 4, 5],
  [6, 7, 8],
  [0, 3, 6],
  [1, 4, 7],
  [2, 5, 8],
  [0, 4, 8],
  [2, 4, 6],
];

function winner(board: (Seat | null)[]): Seat | 'draw' | null {
  for (const [a, b, c] of LINES) {
    const v = board[a!];
    if (v !== null && v === board[b!] && v === board[c!]) return v!;
  }
  return board.every((x) => x !== null) ? 'draw' : null;
}

export const ticTacToe: Engine<State, { cell: number }> = {
  init: () => ({ board: Array(9).fill(null), turn: 0 }),
  move: z.object({ cell: z.number().int().min(0).max(8) }),
  apply(state, seat, { cell }) {
    if (state.board[cell] !== null) throw new MoveError('That square is taken');
    const next = clone(state);
    next.board[cell] = seat;
    next.turn = other(seat);
    return next;
  },
  outcome(state) {
    const w = winner(state.board);
    return { turn: w === null ? state.turn : null, winner: w };
  },
  view: (state) => ({ board: state.board, lines: LINES }),
};
