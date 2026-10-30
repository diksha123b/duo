import { describe, expect, it } from 'vitest';
import { chess } from '../src/modules/arcade/engines/chess.js';
import { dotsAndBoxes } from '../src/modules/arcade/engines/dotsAndBoxes.js';
import { fourInARow } from '../src/modules/arcade/engines/fourInARow.js';
import { HOME, ludo, START } from '../src/modules/arcade/engines/ludo.js';
import { ticTacToe } from '../src/modules/arcade/engines/ticTacToe.js';
import type { Engine, Rng, Seat } from '../src/modules/arcade/engines/types.js';
import { CENTER, scorePlacement, wordTiles, N } from '../src/modules/arcade/engines/wordTiles.js';

/** Returns the given numbers in order (dice: value-1), then zeros. */
const scripted = (...values: number[]): Rng => ({ int: () => values.shift() ?? 0 });
const noRng = scripted();

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function play<S>(engine: Engine<S, any>, state: S, moves: [Seat, unknown][], rng: Rng = noRng): S {
  return moves.reduce((s, [seat, m]) => engine.apply(s, seat, engine.move.parse(m), rng), state);
}

describe('tic-tac-toe', () => {
  it('detects a win and rejects taken squares', () => {
    const s = play(ticTacToe, ticTacToe.init(noRng), [
      [0, { cell: 0 }],
      [1, { cell: 3 }],
      [0, { cell: 1 }],
      [1, { cell: 4 }],
      [0, { cell: 2 }],
    ]);
    expect(ticTacToe.outcome(s)).toEqual({ turn: null, winner: 0 });
    expect(() =>
      play(ticTacToe, ticTacToe.init(noRng), [
        [0, { cell: 4 }],
        [1, { cell: 4 }],
      ]),
    ).toThrow('taken');
  });
});

describe('four in a row', () => {
  it('stacks discs and finds a vertical four', () => {
    const moves: [Seat, unknown][] = [];
    for (let i = 0; i < 3; i++) moves.push([0, { col: 3 }], [1, { col: 4 }]);
    moves.push([0, { col: 3 }]);
    const s = play(fourInARow, fourInARow.init(noRng), moves);
    expect(fourInARow.outcome(s).winner).toBe(0);
  });

  it('refuses a full column', () => {
    const moves: [Seat, unknown][] = Array.from({ length: 6 }, (_, i) => [(i % 2) as Seat, { col: 0 }]);
    const s = play(fourInARow, fourInARow.init(noRng), moves);
    expect(() => fourInARow.apply(s, 0, { col: 0 }, noRng)).toThrow('full');
  });
});

describe('dots and boxes', () => {
  it('gives another turn for closing a box', () => {
    const s = play(dotsAndBoxes, dotsAndBoxes.init(noRng), [
      [0, { dir: 'h', r: 0, c: 0 }],
      [1, { dir: 'h', r: 1, c: 0 }],
      [0, { dir: 'v', r: 0, c: 0 }],
      [1, { dir: 'v', r: 0, c: 1 }], // closes box (0,0)
    ]);
    expect(s.scores).toEqual([0, 1]);
    expect(dotsAndBoxes.outcome(s).turn).toBe(1);
  });
});

describe('chess', () => {
  it("knows fool's mate", () => {
    const s = play(chess, chess.init(noRng), [
      [0, { from: 'f2', to: 'f3' }],
      [1, { from: 'e7', to: 'e5' }],
      [0, { from: 'g2', to: 'g4' }],
      [1, { from: 'd8', to: 'h4' }],
    ]);
    expect(chess.outcome(s)).toEqual({ turn: null, winner: 1 });
    expect(s.history).toEqual(['f3', 'e5', 'g4', 'Qh4#']);
  });

  it('rejects illegal moves and moving out of turn', () => {
    const s = chess.init(noRng);
    expect(() => chess.apply(s, 0, { from: 'e2', to: 'e5' }, noRng)).toThrow('legal');
    expect(() => chess.apply(s, 1, { from: 'e7', to: 'e5' }, noRng)).toThrow('turn');
  });

  it('only lists legal moves for the player to move', () => {
    const s = chess.init(noRng);
    expect((chess.view(s, 0) as { legalMoves: unknown[] }).legalMoves).toHaveLength(20);
    expect((chess.view(s, 1) as { legalMoves: unknown[] }).legalMoves).toHaveLength(0);
  });
});

describe('ludo', () => {
  it('needs a six to leave base; otherwise the turn passes', () => {
    const s = ludo.apply(ludo.init(noRng), 0, { type: 'roll' }, scripted(2)); // rolls 3
    expect(s.turn).toBe(1);
    expect(s.last).toMatchObject({ roll: 3, passed: true });
  });

  it("keeps both players' latest rolls visible to both", () => {
    let s = ludo.apply(ludo.init(noRng), 0, { type: 'roll' }, scripted(2)); // seat 0 rolls 3, passes
    s = ludo.apply(s, 1, { type: 'roll' }, scripted(0)); // seat 1 rolls 1, passes
    for (const seat of [0, 1] as const) {
      expect((ludo.view(s, seat) as { dice: unknown }).dice).toEqual([
        { value: 3, count: 1 },
        { value: 1, count: 1 },
      ]);
    }
    s = ludo.apply(s, 0, { type: 'roll' }, scripted(2)); // 3 again: count still moves
    expect(s.dice?.[0]).toEqual({ value: 3, count: 2 });
  });

  it('a six brings a token out and earns another turn', () => {
    let s = ludo.apply(ludo.init(noRng), 0, { type: 'roll' }, scripted(5)); // 6
    expect((ludo.view(s, 0) as { movable: number[] }).movable).toEqual([0, 1, 2, 3]);
    s = ludo.apply(s, 0, { type: 'move', token: 2 }, noRng);
    expect(s.tokens[0][2]).toBe(0);
    expect(s.turn).toBe(0);
  });

  it('captures on unsafe squares but not safe ones', () => {
    const base = ludo.init(noRng);
    // Seat 1's token sits 3 squares ahead of seat 0's token on the shared track.
    base.tokens[0][0] = 2;
    base.tokens[1][0] = (START[0] + 5 - START[1] + 52) % 52;
    let s = ludo.apply(base, 0, { type: 'roll' }, scripted(2)); // 3
    s = ludo.apply(s, 0, { type: 'move', token: 0 }, noRng);
    expect(s.tokens[1][0]).toBe(-1);
    expect(s.turn).toBe(0); // capture earns another go

    const safe = ludo.init(noRng);
    safe.tokens[0][0] = 5;
    safe.tokens[1][0] = (START[0] + 8 - START[1] + 52) % 52; // square 8 is a star
    let t = ludo.apply(safe, 0, { type: 'roll' }, scripted(2));
    t = ludo.apply(t, 0, { type: 'move', token: 0 }, noRng);
    expect(t.tokens[1][0]).not.toBe(-1);
  });

  it('needs an exact roll to get home, and wins with four home', () => {
    const s = ludo.init(noRng);
    s.tokens[0] = [HOME, HOME, HOME, HOME - 2];
    const over = ludo.apply(s, 0, { type: 'roll' }, scripted(3)); // 4: too far
    expect(over.turn).toBe(1);
    let ok = ludo.apply(s, 0, { type: 'roll' }, scripted(1)); // 2: exact
    ok = ludo.apply(ok, 0, { type: 'move', token: 3 }, noRng);
    expect(ludo.outcome(ok)).toEqual({ turn: null, winner: 0 });
  });
});

describe('word tiles', () => {
  const fresh = () => {
    const s = wordTiles.init(noRng);
    s.racks = [
      ['C', 'A', 'T', 'S', 'E', 'R', 'O'],
      ['D', 'O', 'G', 'E', 'A', 'R', 'N'],
    ];
    return s;
  };
  const place = (tiles: [number, number, string][]) => ({
    type: 'place' as const,
    tiles: tiles.map(([r, c, letter]) => ({ r, c, letter })),
  });

  it('the first word must cover the centre and be a real word', () => {
    const s = fresh();
    expect(() =>
      wordTiles.apply(
        s,
        0,
        place([
          [0, 0, 'C'],
          [0, 1, 'A'],
          [0, 2, 'T'],
        ]),
        noRng,
      ),
    ).toThrow('centre');
    expect(() =>
      wordTiles.apply(
        s,
        0,
        place([
          [CENTER, CENTER, 'T'],
          [CENTER, CENTER + 1, 'C'],
          [CENTER, CENTER + 2, 'A'],
        ]),
        noRng,
      ),
    ).toThrow('dictionary');
    const ok = wordTiles.apply(
      s,
      0,
      place([
        [CENTER, CENTER - 1, 'C'],
        [CENTER, CENTER, 'A'],
        [CENTER, CENTER + 1, 'T'],
      ]),
      noRng,
    );
    expect(ok.last).toMatchObject({ words: ['CAT'], points: (3 + 1 + 1) * 2 }); // centre doubles the word
    expect(ok.racks[0]).toHaveLength(7); // refilled
  });

  it('later words must connect, leave no gaps, and score cross words', () => {
    let s = fresh();
    s = wordTiles.apply(
      s,
      0,
      place([
        [CENTER, CENTER - 1, 'C'],
        [CENTER, CENTER, 'A'],
        [CENTER, CENTER + 1, 'T'],
      ]),
      noRng,
    );
    s.racks[1] = ['D', 'O', 'G', 'E', 'A', 'R', 'N'];
    expect(() =>
      wordTiles.apply(
        s,
        1,
        place([
          [0, 0, 'D'],
          [0, 1, 'O'],
        ]),
        noRng,
      ),
    ).toThrow('connect');
    expect(() =>
      wordTiles.apply(
        s,
        1,
        place([
          [CENTER + 1, 0, 'D'],
          [CENTER + 1, 3, 'O'],
        ]),
        noRng,
      ),
    ).toThrow('gaps');
    // "ON" down from the A, forming AN... no: place O,N below the T to make "TON".
    const next = wordTiles.apply(
      s,
      1,
      place([
        [CENTER + 1, CENTER + 1, 'O'],
        [CENTER + 2, CENTER + 1, 'N'],
      ]),
      noRng,
    );
    expect(next.last?.words).toEqual(['TON']);
  });

  it('uses bonus squares only for newly placed tiles', () => {
    const board = Array(N * N).fill(null);
    const once = scorePlacement(board, [
      { r: CENTER, c: CENTER, letter: 'A' },
      { r: CENTER, c: CENTER + 1, letter: 'X' },
    ]);
    expect(once.points).toBe((1 + 8) * 2);
  });

  it('keeps the other rack and the bag secret', () => {
    const view = wordTiles.view(fresh(), 0) as Record<string, unknown>;
    expect(view.rack).toEqual(['C', 'A', 'T', 'S', 'E', 'R', 'O']);
    expect(view.otherRackCount).toBe(7);
    expect(JSON.stringify(view)).not.toContain('DOGEARN');
    expect(view).not.toHaveProperty('bag');
  });

  it('ends after four scoreless turns', () => {
    let s = fresh();
    for (const seat of [0, 1, 0, 1] as const) s = wordTiles.apply(s, seat, { type: 'pass' }, noRng);
    expect(wordTiles.outcome(s).winner).not.toBeNull();
  });
});
