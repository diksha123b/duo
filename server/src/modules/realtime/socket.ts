import type { FastifyInstance } from 'fastify';
import type { Redis } from 'ioredis';
import { Server, type DefaultEventsMap, type Socket } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { verifyAccessToken } from '../../lib/tokens.js';
import { dayToDate, localDay } from '../../lib/time.js';

// Client → server
//   presence:set  { state: 'online' | 'playing' }
//   sync          (ack) → same payload as the server's "sync" event
// Server → client
//   sync               { partnerPresence, game }   on connect / request; catch-up after reconnects
//   presence           { userId, state }           partner went online/playing/offline
//   game:partner_submitted { gameId }
//   game:revealed      { game }                    tailored per player, the moment the 2nd submits
//   pair:changed       {}                          paired/unpaired; client refetches /pair

type PresenceState = 'online' | 'playing' | 'offline';

interface SocketData {
  userId: string;
  pairId: string | null;
}

const pairRoom = (pairId: string) => `pair:${pairId}`;
const userRoom = (userId: string) => `user:${userId}`;
const CONNS = 'presence:conns';
const STATE = 'presence:state';

export function attachRealtime(app: FastifyInstance, opts: { pubClient: Redis; subClient: Redis }) {
  const { config, prisma, redis, games } = app.deps;
  const io = new Server<DefaultEventsMap, DefaultEventsMap, DefaultEventsMap, SocketData>(app.server, {
    cors: { origin: config.CORS_ORIGINS },
    adapter: createAdapter(opts.pubClient, opts.subClient),
  });

  // Event handlers are fire-and-forget; an unhandled rejection would crash
  // the process, so every async handler goes through this.
  // In-flight handlers are tracked so shutdown can wait for them (closing
  // sockets triggers "offline" broadcasts that still need Redis).
  const inflight = new Set<Promise<void>>();
  const safe =
    <A extends unknown[]>(fn: (...args: A) => Promise<void>) =>
    (...args: A) => {
      const run = fn(...args)
        .catch((err) => app.log.error({ err }, 'realtime handler failed'))
        .finally(() => inflight.delete(run));
      inflight.add(run);
    };

  io.use((socket, next) => {
    try {
      const token = socket.handshake.auth?.token;
      socket.data.userId = verifyAccessToken(config, typeof token === 'string' ? token : '');
      next();
    } catch {
      next(new Error('UNAUTHORIZED'));
    }
  });

  const presenceOf = async (userId: string): Promise<PresenceState> => {
    const [conns, state] = await Promise.all([redis.hget(CONNS, userId), redis.hget(STATE, userId)]);
    if (!conns || Number(conns) <= 0) return 'offline';
    return state === 'playing' ? 'playing' : 'online';
  };

  const announce = async (socket: Socket, state: PresenceState) => {
    if (socket.data.pairId) {
      socket.to(pairRoom(socket.data.pairId)).emit('presence', { userId: socket.data.userId, state });
    }
  };

  const joinPairRoom = async (socket: Socket) => {
    const user = await prisma.user.findUnique({ where: { id: socket.data.userId } });
    if (socket.data.pairId) socket.leave(pairRoom(socket.data.pairId));
    socket.data.pairId = user?.currentPairId ?? null;
    if (socket.data.pairId) socket.join(pairRoom(socket.data.pairId));
  };

  // Everything a client needs to be correct after (re)connecting.
  const snapshot = async (userId: string, pairId: string | null) => {
    if (!pairId) return { partnerPresence: null, game: null };
    const pair = await prisma.pair.findUnique({ where: { id: pairId } });
    if (!pair) return { partnerPresence: null, game: null };
    const partnerId = pair.userAId === userId ? pair.userBId : pair.userAId;
    // Only report a game that already exists; creating one is the HTTP API's job.
    const game = await prisma.game.findFirst({
      where: { pairId, day: dayToDate(localDay(pair.timezone)), isDaily: true },
    });
    return {
      partnerPresence: { userId: partnerId, state: await presenceOf(partnerId) },
      game: game ? await games.view(game.id, userId) : null,
    };
  };

  io.on('connection', (socket) => {
    const { userId } = socket.data;
    // Count the connection and register listeners before any await, so a
    // client that drops mid-setup can't leave a stale "online" behind.
    const counted = redis.hincrby(CONNS, userId, 1);

    socket.on(
      'sync',
      safe(async (ack?: (payload: unknown) => void) => {
        if (typeof ack === 'function') ack(await snapshot(userId, socket.data.pairId));
      }),
    );

    socket.on(
      'presence:set',
      safe(async (payload: { state?: string }) => {
        const state = payload?.state === 'playing' ? 'playing' : 'online';
        await redis.hset(STATE, userId, state);
        await announce(socket, state);
      }),
    );

    socket.on(
      'disconnect',
      safe(async () => {
        const left = await redis.hincrby(CONNS, userId, -1);
        if (left <= 0) await redis.multi().hdel(CONNS, userId).hdel(STATE, userId).exec();
        await announce(socket, await presenceOf(userId));
      }),
    );

    safe(async () => {
      socket.join(userRoom(userId));
      await counted;
      await joinPairRoom(socket);
      await announce(socket, await presenceOf(userId));
      socket.emit('sync', await snapshot(userId, socket.data.pairId));
    })();
  });

  app.events.on(
    'game:submitted',
    safe(async ({ gameId, userId }) => {
      const game = await prisma.game.findUnique({ where: { id: gameId } });
      if (game)
        io.to(pairRoom(game.pairId)).except(userRoom(userId)).emit('game:partner_submitted', { gameId });
    }),
  );

  // Each player's view differs ("me" vs "partner"), so emit per socket.
  app.events.on(
    'game:completed',
    safe(async ({ gameId }) => {
      const game = await prisma.game.findUnique({ where: { id: gameId } });
      if (!game) return;
      const sockets = await io.in(pairRoom(game.pairId)).fetchSockets();
      const views = new Map<string, unknown>();
      for (const s of sockets) {
        const uid = s.data.userId;
        if (!views.has(uid)) views.set(uid, await games.view(gameId, uid));
        s.emit('game:revealed', { game: views.get(uid) });
      }
    }),
  );

  // A reaction or chat message: refresh both players' results, each with their own view.
  app.events.on(
    'game:social',
    safe(async ({ gameId, pairId }) => {
      const sockets = await io.in(pairRoom(pairId)).fetchSockets();
      for (const s of sockets) s.emit('game:updated', { game: await games.view(gameId, s.data.userId) });
    }),
  );

  // A bonus round was started: the other person's home screen shows it.
  app.events.on(
    'bonus:changed',
    safe(async ({ pairId }) => {
      io.to(pairRoom(pairId)).emit('bonus:changed', {});
    }),
  );

  // A live game changed: send each player their own view (racks stay private).
  app.events.on(
    'match:updated',
    safe(async ({ matchId }) => {
      const pairId = await app.deps.arcade.pairIdOf(matchId);
      if (!pairId) return;
      const sockets = await io.in(pairRoom(pairId)).fetchSockets();
      for (const s of sockets) {
        s.emit('match:updated', { match: await app.deps.arcade.get(s.data.userId, matchId) });
      }
    }),
  );

  // Pairing changed: move both users' sockets into the right room.
  app.events.on(
    'pair:changed',
    safe(async ({ pairId }) => {
      const pair = await prisma.pair.findUnique({ where: { id: pairId } });
      if (!pair) return;
      for (const uid of [pair.userAId, pair.userBId]) {
        const sockets = await io.in(userRoom(uid)).fetchSockets();
        const user = await prisma.user.findUnique({ where: { id: uid } });
        for (const s of sockets) {
          if (s.data.pairId) s.leave(pairRoom(s.data.pairId));
          s.data.pairId = user?.currentPairId ?? null;
          if (s.data.pairId) s.join(pairRoom(s.data.pairId));
          s.emit('pair:changed', {});
        }
      }
    }),
  );

  app.addHook('onClose', async () => {
    await io.close();
    await Promise.allSettled([...inflight]);
  });
  return io;
}

/**
 * Closes the adapter's Redis connections after `io.close()`. The adapter's own
 * close() fires unsubscribe commands without awaiting them; replies arrive in
 * order, so awaiting our own unsubscribes first means quitting can't reject them.
 */
export async function closeAdapterClients(pubClient: Redis, subClient: Redis) {
  await Promise.all([subClient.punsubscribe(), subClient.unsubscribe()]);
  await Promise.all([pubClient.quit(), subClient.quit()]);
}
