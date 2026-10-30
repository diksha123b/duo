import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { parse } from '../../lib/validate.js';

const kind = z.enum(['TIC_TAC_TOE', 'FOUR_IN_A_ROW', 'DOTS_AND_BOXES', 'CHESS', 'LUDO', 'WORD_TILES']);
const idParams = z.object({ id: z.string().uuid() });
const moveBody = z.object({ version: z.number().int().min(0), move: z.unknown() });

export async function arcadeRoutes(app: FastifyInstance) {
  const { arcade } = app.deps;
  const auth = { preHandler: app.authenticate };

  app.get('/arcade', auth, async (req) => arcade.list(req.userId));

  app.post('/arcade/matches', auth, async (req, reply) => {
    const body = parse(z.object({ kind }), req.body);
    const { match, created } = await arcade.start(req.userId, body.kind);
    if (created) {
      reply.code(201);
      app.events.emit('match:updated', { matchId: match.id });
    }
    return { match };
  });

  app.get('/arcade/matches/:id', auth, async (req) => {
    const { id } = parse(idParams, req.params);
    return { match: await arcade.get(req.userId, id) };
  });

  app.post('/arcade/matches/:id/moves', auth, async (req) => {
    const { id } = parse(idParams, req.params);
    const { version, move } = parse(moveBody, req.body);
    const match = await arcade.move(req.userId, id, version, move);
    app.events.emit('match:updated', { matchId: id });
    return { match };
  });

  app.post('/arcade/matches/:id/resign', auth, async (req) => {
    const { id } = parse(idParams, req.params);
    const match = await arcade.resign(req.userId, id);
    app.events.emit('match:updated', { matchId: id });
    return { match };
  });
}
