import type { ArcadeKind } from '@prisma/client';
import { chess } from './chess.js';
import { dotsAndBoxes } from './dotsAndBoxes.js';
import { fourInARow } from './fourInARow.js';
import { ludo } from './ludo.js';
import { ticTacToe } from './ticTacToe.js';
import type { Engine } from './types.js';
import { wordTiles } from './wordTiles.js';

// Engines are typed per game; the registry erases that so the service can treat them uniformly.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const ENGINES: Record<ArcadeKind, Engine<any, any>> = {
  TIC_TAC_TOE: ticTacToe,
  FOUR_IN_A_ROW: fourInARow,
  DOTS_AND_BOXES: dotsAndBoxes,
  CHESS: chess,
  LUDO: ludo,
  WORD_TILES: wordTiles,
};
