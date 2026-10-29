import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { badRequest } from '../../lib/errors.js';
import { track } from '../../lib/events.js';
import { parse } from '../../lib/validate.js';

const idParams = z.object({ id: z.string().uuid() });
const submitBody = z.object({
  answers: z
    .array(z.object({ questionId: z.string().uuid(), choice: z.number().int().min(0) }))
    .min(1)
    .max(20),
});
const idempotencyKey = z.string().min(8).max(100);

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
    return { game };
  });

  app.get('/games/:id', { preHandler: app.authenticate }, async (req) => {
    const { id } = parse(idParams, req.params);
    await games.gameForUser(id, req.userId);
    return { game: await games.view(id, req.userId) };
  });

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
