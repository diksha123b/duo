import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { parse } from '../../lib/validate.js';
import { COLORS, OUTFIT_IDS } from './pet.js';

const updateBody = z
  .object({
    name: z.string().trim().min(1).max(16).optional(),
    color: z.enum(COLORS).optional(),
    outfit: z.enum(OUTFIT_IDS).nullable().optional(),
  })
  .refine((b) => Object.keys(b).length > 0, 'Nothing to change');

export async function petRoutes(app: FastifyInstance) {
  const { pets } = app.deps;

  app.get('/pet', { preHandler: app.authenticate }, async (req) => ({ pet: await pets.get(req.userId) }));

  app.post('/pet/pat', { preHandler: app.authenticate }, async (req) => {
    const { pet, pairId } = await pets.pat(req.userId);
    app.events.emit('pet:changed', { pairId, userId: req.userId, kind: 'pat' });
    return { pet };
  });

  app.patch('/pet', { preHandler: app.authenticate }, async (req) => {
    const { pet, pairId } = await pets.update(req.userId, parse(updateBody, req.body));
    app.events.emit('pet:changed', { pairId, userId: req.userId, kind: 'update' });
    return { pet };
  });
}
