import { EventEmitter } from 'node:events';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import type { PrismaClient } from '@prisma/client';
import type { Redis } from 'ioredis';
import type { Config } from './config.js';
import { AppError, unauthorized } from './lib/errors.js';
import { reportError } from './lib/sentry.js';
import type { GoogleVerifier } from './lib/google.js';
import { TokenService, verifyAccessToken } from './lib/tokens.js';
import { arcadeRoutes } from './modules/arcade/routes.js';
import { ArcadeService } from './modules/arcade/service.js';
import type { Rng } from './modules/arcade/engines/types.js';
import { authRoutes } from './modules/auth/routes.js';
import { createWebPushSender, Notifier, type PushSender } from './modules/push/notifier.js';
import { pushRoutes } from './modules/push/routes.js';
import { registerPushTriggers } from './modules/push/triggers.js';
import { gameRoutes } from './modules/games/routes.js';
import { bankProvider, GameService, type GameProvider } from './modules/games/service.js';
import { pairingRoutes } from './modules/pairing/routes.js';
import { petRoutes } from './modules/pet/routes.js';
import { PetService } from './modules/pet/service.js';
import { userRoutes } from './modules/users/routes.js';

export interface Deps {
  config: Config;
  prisma: PrismaClient;
  redis: Redis;
  tokens: TokenService;
  games: GameService;
  arcade: ArcadeService;
  pets: PetService;
  notifier: Notifier;
  verifyGoogle: GoogleVerifier;
}

// In-process domain events. HTTP routes emit; the real-time layer listens.
export interface AppEvents {
  'game:submitted': [{ gameId: string; userId: string }];
  'game:completed': [{ gameId: string }];
  'pair:changed': [{ pairId: string }];
  'match:updated': [{ matchId: string }];
  'bonus:changed': [{ pairId: string }];
  'pet:changed': [{ pairId: string; userId: string; kind: 'pat' | 'update' }];
  'game:social': [
    { gameId: string; pairId: string; userId: string; kind: 'reaction' | 'comment'; text: string },
  ];
}

declare module 'fastify' {
  interface FastifyInstance {
    deps: Deps;
    events: EventEmitter<AppEvents>;
    authenticate: (req: FastifyRequest) => Promise<void>;
  }
  interface FastifyRequest {
    userId: string;
  }
}

export type BuildDeps = Omit<Deps, 'tokens' | 'games' | 'arcade' | 'pets' | 'notifier'> & {
  gameProvider?: GameProvider;
  arcadeRng?: Rng;
  /** Overrides real web push (tests). */
  pushSender?: PushSender | null;
};

export async function buildApp(deps: BuildDeps, opts: { logger?: boolean } = {}) {
  const app: FastifyInstance = Fastify({ logger: opts.logger ?? false });

  const games = new GameService(deps.prisma, deps.gameProvider ?? bankProvider);
  app.decorate('deps', {
    ...deps,
    tokens: new TokenService(deps.prisma, deps.config),
    games,
    pets: new PetService(deps.prisma, games),
    arcade: new ArcadeService(deps.prisma, deps.arcadeRng),
    notifier: new Notifier(
      deps.prisma,
      deps.redis,
      deps.pushSender !== undefined
        ? deps.pushSender
        : deps.config.VAPID_PUBLIC_KEY && deps.config.VAPID_PRIVATE_KEY
          ? createWebPushSender({
              publicKey: deps.config.VAPID_PUBLIC_KEY,
              privateKey: deps.config.VAPID_PRIVATE_KEY,
              subject: deps.config.VAPID_SUBJECT || 'mailto:hello@duo.app',
            })
          : null,
      app.log,
    ),
  });
  app.decorate('events', new EventEmitter<AppEvents>());
  app.decorateRequest('userId', '');
  app.decorate('authenticate', async (req: FastifyRequest) => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) throw unauthorized();
    req.userId = verifyAccessToken(deps.config, header.slice(7));
  });

  await app.register(helmet);
  // @fastify/cors only allows GET/HEAD/POST by default; the API also uses PATCH and DELETE.
  await app.register(cors, {
    origin: deps.config.CORS_ORIGINS,
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'],
  });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof AppError) {
      return reply.code(err.statusCode).send({ error: { code: err.code, message: err.message } });
    }
    const status = (err as { statusCode?: number }).statusCode;
    if (status && status < 500) {
      // Fastify's own client errors, e.g. malformed JSON.
      return reply.code(status).send({ error: { code: 'BAD_REQUEST', message: (err as Error).message } });
    }
    req.log.error(err);
    reportError(err, { route: req.routeOptions.url, method: req.method, userId: req.userId || undefined });
    return reply.code(500).send({ error: { code: 'INTERNAL', message: 'Something went wrong' } });
  });

  app.get('/health', async () => ({ ok: true }));
  await app.register(authRoutes);
  await app.register(userRoutes);
  await app.register(pairingRoutes);
  await app.register(gameRoutes);
  await app.register(arcadeRoutes);
  await app.register(petRoutes);
  await app.register(pushRoutes);
  registerPushTriggers(app);

  return app;
}
