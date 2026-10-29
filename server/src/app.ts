import { EventEmitter } from 'node:events';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import type { PrismaClient } from '@prisma/client';
import type { Redis } from 'ioredis';
import type { Config } from './config.js';
import { AppError, unauthorized } from './lib/errors.js';
import type { GoogleVerifier } from './lib/google.js';
import { TokenService, verifyAccessToken } from './lib/tokens.js';
import { authRoutes } from './modules/auth/routes.js';
import { gameRoutes } from './modules/games/routes.js';
import { bankProvider, GameService, type GameProvider } from './modules/games/service.js';
import { pairingRoutes } from './modules/pairing/routes.js';
import { userRoutes } from './modules/users/routes.js';

export interface Deps {
  config: Config;
  prisma: PrismaClient;
  redis: Redis;
  tokens: TokenService;
  games: GameService;
  verifyGoogle: GoogleVerifier;
}

// In-process domain events. HTTP routes emit; the real-time layer listens.
export interface AppEvents {
  'game:submitted': [{ gameId: string; userId: string }];
  'game:completed': [{ gameId: string }];
  'pair:changed': [{ pairId: string }];
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

export type BuildDeps = Omit<Deps, 'tokens' | 'games'> & { gameProvider?: GameProvider };

export async function buildApp(deps: BuildDeps, opts: { logger?: boolean } = {}) {
  const app: FastifyInstance = Fastify({ logger: opts.logger ?? false });

  app.decorate('deps', {
    ...deps,
    tokens: new TokenService(deps.prisma, deps.config),
    games: new GameService(deps.prisma, deps.gameProvider ?? bankProvider),
  });
  app.decorate('events', new EventEmitter<AppEvents>());
  app.decorateRequest('userId', '');
  app.decorate('authenticate', async (req: FastifyRequest) => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) throw unauthorized();
    req.userId = verifyAccessToken(deps.config, header.slice(7));
  });

  await app.register(helmet);
  await app.register(cors, { origin: deps.config.CORS_ORIGINS });

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
    return reply.code(500).send({ error: { code: 'INTERNAL', message: 'Something went wrong' } });
  });

  app.get('/health', async () => ({ ok: true }));
  await app.register(authRoutes);
  await app.register(userRoutes);
  await app.register(pairingRoutes);
  await app.register(gameRoutes);

  return app;
}
