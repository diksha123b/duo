import { randomInt } from 'node:crypto';
import type { ArcadeKind, Match, PrismaClient } from '@prisma/client';
import { AppError, badRequest, conflict, notFound } from '../../lib/errors.js';
import { track } from '../../lib/events.js';
import { ENGINES } from './engines/index.js';
import { MoveError, type Rng, type Seat } from './engines/types.js';

const cryptoRng: Rng = { int: (max) => randomInt(max) };

export class ArcadeService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly rng: Rng = cryptoRng,
  ) {}

  private async pairOf(userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: { currentPair: true },
    });
    if (!user.currentPair) throw notFound('NOT_PAIRED', 'Pair up with someone to play');
    return user.currentPair;
  }

  private async load(userId: string, matchId: string) {
    const pair = await this.pairOf(userId);
    const match = await this.prisma.match.findUnique({ where: { id: matchId } });
    if (!match || match.pairId !== pair.id) throw notFound('MATCH_NOT_FOUND', 'Game not found');
    return this.settle(match);
  }

  /** Lets an engine catch up on automatic steps (like an old ludo game's roll) and saves them. */
  private async settle(match: Match): Promise<Match> {
    const engine = ENGINES[match.kind];
    if (!engine.settle || match.status !== 'ACTIVE') return match;
    const state = engine.settle(match.state, this.rng);
    if (state === match.state) return match;
    const { count } = await this.prisma.match.updateMany({
      where: { id: match.id, version: match.version },
      data: { state, version: { increment: 1 } },
    });
    // Someone else settled it first: use theirs.
    if (count === 0) return this.prisma.match.findUniqueOrThrow({ where: { id: match.id } });
    return { ...match, state, version: match.version + 1 };
  }

  /** Active games plus a few recent finished ones. */
  async list(userId: string) {
    const pair = await this.pairOf(userId);
    const [active, recent] = await Promise.all([
      this.prisma.match.findMany({
        where: { pairId: pair.id, status: 'ACTIVE' },
        orderBy: { updatedAt: 'desc' },
      }),
      this.prisma.match.findMany({
        where: { pairId: pair.id, status: { not: 'ACTIVE' } },
        orderBy: { updatedAt: 'desc' },
        take: 10,
      }),
    ]);
    // Head-to-head record per game.
    const finished = await this.prisma.match.findMany({
      where: { pairId: pair.id, status: 'FINISHED' },
      select: { kind: true, winnerId: true },
    });
    const record: Record<string, { you: number; them: number; draws: number }> = {};
    for (const m of finished) {
      const r = (record[m.kind] ??= { you: 0, them: 0, draws: 0 });
      if (m.winnerId === null) r.draws++;
      else if (m.winnerId === userId) r.you++;
      else r.them++;
    }
    return {
      active: active.map((m) => this.summary(m, userId)),
      recent: recent.map((m) => this.summary(m, userId)),
      record,
    };
  }

  /** Starts a game of `kind`, or returns the one already in progress. The starter moves first. */
  async start(userId: string, kind: ArcadeKind) {
    const pair = await this.pairOf(userId);
    const existing = await this.prisma.match.findFirst({
      where: { pairId: pair.id, kind, status: 'ACTIVE' },
    });
    if (existing) return { match: this.serialize(existing, userId), created: false };
    const other = pair.userAId === userId ? pair.userBId : pair.userAId;
    const match = await this.prisma.match.create({
      data: { pairId: pair.id, kind, players: [userId, other], state: ENGINES[kind].init(this.rng) },
    });
    await track(this.prisma, 'game_started', { userId, pairId: pair.id, props: { arcade: kind } });
    return { match: this.serialize(match, userId), created: true };
  }

  async get(userId: string, matchId: string) {
    return this.serialize(await this.load(userId, matchId), userId);
  }

  async move(userId: string, matchId: string, version: number, rawMove: unknown) {
    const match = await this.load(userId, matchId);
    if (match.status !== 'ACTIVE') throw conflict('MATCH_OVER', 'This game is already over');
    if (match.version !== version) throw conflict('STALE_MATCH', 'The board changed. Refreshing…');

    const engine = ENGINES[match.kind];
    const seat = match.players.indexOf(userId) as Seat;
    if (engine.outcome(match.state).turn !== seat) throw conflict('NOT_YOUR_TURN', 'Wait for your turn');

    const parsed = engine.move.safeParse(rawMove);
    if (!parsed.success) throw badRequest('ILLEGAL_MOVE', 'That move doesn’t make sense here');
    let state;
    try {
      state = engine.apply(match.state, seat, parsed.data, this.rng);
    } catch (err) {
      if (err instanceof MoveError) throw new AppError(400, 'ILLEGAL_MOVE', err.message);
      throw err;
    }

    const outcome = engine.outcome(state);
    const over = outcome.winner !== null;
    // Only the request that still sees `version` gets to write: a racing
    // second move (double tap, two devices) is rejected instead of corrupting the game.
    const { count } = await this.prisma.match.updateMany({
      where: { id: match.id, version },
      data: {
        state,
        version: { increment: 1 },
        status: over ? 'FINISHED' : 'ACTIVE',
        winnerId:
          outcome.winner === null || outcome.winner === 'draw' ? null : match.players[outcome.winner]!,
      },
    });
    if (count === 0) throw conflict('STALE_MATCH', 'The board changed. Refreshing…');
    if (over) {
      await track(this.prisma, 'game_completed', {
        pairId: match.pairId,
        props: { arcade: match.kind, matchId: match.id },
      });
    }
    return this.get(userId, matchId);
  }

  async resign(userId: string, matchId: string) {
    const match = await this.load(userId, matchId);
    if (match.status !== 'ACTIVE') throw conflict('MATCH_OVER', 'This game is already over');
    const winner = match.players.find((p) => p !== userId)!;
    await this.prisma.match.update({
      where: { id: match.id },
      data: { status: 'FINISHED', winnerId: winner, version: { increment: 1 } },
    });
    return this.get(userId, matchId);
  }

  async pairIdOf(matchId: string) {
    return (
      (await this.prisma.match.findUnique({ where: { id: matchId }, select: { pairId: true } }))?.pairId ??
      null
    );
  }

  private summary(m: Match, userId: string) {
    const seat = m.players.indexOf(userId) as Seat;
    const outcome = ENGINES[m.kind].outcome(m.state);
    return {
      id: m.id,
      kind: m.kind,
      status: m.status,
      yourTurn: m.status === 'ACTIVE' && outcome.turn === seat,
      result: this.result(m, userId),
      updatedAt: m.updatedAt,
    };
  }

  private result(m: Match, userId: string) {
    if (m.status === 'ACTIVE') return null;
    if (m.winnerId === null) return 'draw';
    return m.winnerId === userId ? 'won' : 'lost';
  }

  /** The match as `userId` may see it. */
  serialize(m: Match, userId: string) {
    const engine = ENGINES[m.kind];
    const seat = m.players.indexOf(userId) as Seat;
    return {
      ...this.summary(m, userId),
      version: m.version,
      seat,
      view: engine.view(m.state, seat),
    };
  }
}
