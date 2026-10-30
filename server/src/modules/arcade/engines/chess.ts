import { Chess } from 'chess.js';
import { z } from 'zod';
import { MoveError, type Engine } from './types.js';

interface State {
  fen: string;
  history: string[];
  lastMove: { from: string; to: string } | null;
}

const square = z.string().regex(/^[a-h][1-8]$/);

/** Seat 0 plays white. Rules (checks, castling, en passant, draws) come from chess.js. */
export const chess: Engine<State, { from: string; to: string; promotion?: 'q' | 'r' | 'b' | 'n' }> = {
  init: () => ({ fen: new Chess().fen(), history: [], lastMove: null }),
  move: z.object({ from: square, to: square, promotion: z.enum(['q', 'r', 'b', 'n']).optional() }),
  apply(state, seat, move) {
    const game = new Chess(state.fen);
    if ((game.turn() === 'w' ? 0 : 1) !== seat) throw new MoveError('Not your turn');
    let made;
    try {
      made = game.move({ from: move.from, to: move.to, promotion: move.promotion ?? 'q' });
    } catch {
      throw new MoveError('That move isn’t legal');
    }
    return {
      fen: game.fen(),
      history: [...state.history, made.san],
      lastMove: { from: made.from, to: made.to },
    };
  },
  outcome(state) {
    const game = new Chess(state.fen);
    if (game.isCheckmate()) return { turn: null, winner: game.turn() === 'w' ? 1 : 0 };
    if (game.isDraw() || game.isStalemate()) return { turn: null, winner: 'draw' };
    return { turn: game.turn() === 'w' ? 0 : 1, winner: null };
  },
  view(state, seat) {
    const game = new Chess(state.fen);
    const myTurn = (game.turn() === 'w' ? 0 : 1) === seat;
    return {
      fen: state.fen,
      history: state.history,
      lastMove: state.lastMove,
      inCheck: game.inCheck(),
      color: seat === 0 ? 'w' : 'b',
      legalMoves: myTurn
        ? game
            .moves({ verbose: true })
            .map((m) => ({ from: m.from, to: m.to, promotion: m.promotion ?? null }))
        : [],
    };
  },
};
