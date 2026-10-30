import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { badRequest } from '../../lib/errors.js';
import { track } from '../../lib/events.js';
import { parse } from '../../lib/validate.js';
import { GAME_TYPES } from './content.js';
import { REACTIONS } from './service.js';
import { rateLimit } from '../../lib/rate-limit.js';

const idParams = z.object({ id: z.string().uuid() });
const submitBody = z.object({
  answers: z
    .array(
      z.object({
        questionId: z.string().uuid(),
        choice: z.number().int().min(0).optional(),
        ranking: z.array(z.number().int().min(0)).max(10).optional(),
      }),
    )
    .min(1)
    .max(20),
});
const idempotencyKey = z.string().min(8).max(100);
const historyQuery = z.object({
  before: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

export async function gameRoutes(app: FastifyInstance) {
  const { prisma, redis, games } = app.deps;

  app.get('/games/today', { preHandler: app.authenticate }, async (req) => {
    const game = await games.today(req.userId);
    if (!game.me.submitted) {
      // Record "started" once per player per game.
      const first = await redis.set(`started:${game.id}:${req.userId}`, '1', 'EX', 2 * 86_400, 'NX');
      if (first)
        await track(prisma, 'game_started', {
          userId: req.userId,
          props: { gameId: game.id, type: game.type },
        });
    }
    return { game, lineup: await games.lineup(req.userId) };
  });

  // Bonus rounds: any game type, any time, just for fun (no streak).
  app.get('/games/bonus', { preHandler: app.authenticate }, async (req) => ({
    games: await games.openBonus(req.userId),
  }));

  app.post('/games/bonus', { preHandler: app.authenticate }, async (req, reply) => {
    const { type } = parse(z.object({ type: z.enum(GAME_TYPES) }), req.body);
    const { game, created } = await games.startBonus(req.userId, type);
    if (created) {
      reply.code(201);
      const { pair } = await games.gameForUser(game.id, req.userId);
      app.events.emit('bonus:changed', { pairId: pair.id });
    }
    return { game };
  });

  // Registered before /games/:id so "history" isn't parsed as an id.
  app.get('/games/history', { preHandler: app.authenticate }, async (req) => {
    return games.history(req.userId, parse(historyQuery, req.query));
  });

  app.get('/games/:id', { preHandler: app.authenticate }, async (req) => {
    const { id } = parse(idParams, req.params);
    await games.gameForUser(id, req.userId);
    return { game: await games.view(id, req.userId) };
  });

  // Reactions and chat on revealed results; both phones update live.
  app.put('/games/:id/questions/:qid/reaction', { preHandler: app.authenticate }, async (req) => {
    const { id, qid } = parse(z.object({ id: z.string().uuid(), qid: z.string().uuid() }), req.params);
    const { emoji } = parse(z.object({ emoji: z.enum(REACTIONS).nullable() }), req.body);
    const { game, pairId } = await games.react(req.userId, id, qid, emoji);
    app.events.emit('game:social', {
      gameId: id,
      pairId,
      userId: req.userId,
      kind: 'reaction',
      text: emoji ?? '',
    });
    return { game };
  });

  app.post(
    '/games/:id/comments',
    {
      preHandler: [
        app.authenticate,
        rateLimit(redis, { name: 'comment', max: 20, windowSeconds: 60, key: (req) => req.userId }),
      ],
    },
    async (req, reply) => {
      const { id } = parse(idParams, req.params);
      const { text } = parse(z.object({ text: z.string().trim().min(1).max(200) }), req.body);
      const { game, pairId } = await games.comment(req.userId, id, text);
      app.events.emit('game:social', { gameId: id, pairId, userId: req.userId, kind: 'comment', text });
      reply.code(201);
      return { game };
    },
  );

  app.post('/games/:id/submit', { preHandler: app.authenticate }, async (req) => {
    const { id } = parse(idParams, req.params);
    const keyResult = idempotencyKey.safeParse(req.headers['idempotency-key']);
    if (!keyResult.success)
      throw badRequest('IDEMPOTENCY_KEY_REQUIRED', 'Send an Idempotency-Key header (8–100 chars)');
    const { answers } = parse(submitBody, req.body);

    const result = await games.submit(req.userId, id, keyResult.data, answers);
    if (!result.replayed) app.events.emit('game:submitted', { gameId: id, userId: req.userId });
    if (result.justCompleted) app.events.emit('game:completed', { gameId: id });
    return { game: result.game, replayed: result.replayed };
  });
}
