import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { isValidTimezone } from '../../lib/time.js';
import { parse } from '../../lib/validate.js';
import { serializeMe } from './serialize.js';

const profileBody = z
  .object({
    displayName: z.string().trim().min(1).max(40),
    // Normalised so "Cricket " and "cricket" don't both end up in the prompt.
    interests: z
      .array(z.string().trim().toLowerCase().min(1).max(30))
      .max(10, 'Pick at most 10 interests')
      .transform((xs) => [...new Set(xs)]),
    timezone: z.string().refine(isValidTimezone, 'Unknown timezone'),
    avatarUrl: z.string().url().max(500).nullable(),
  })
  .partial();

export async function userRoutes(app: FastifyInstance) {
  const { prisma } = app.deps;

  app.get('/me', { preHandler: app.authenticate }, async (req) => {
    return { user: await serializeMe(prisma, req.userId) };
  });

  app.patch('/me/profile', { preHandler: app.authenticate }, async (req) => {
    const body = parse(profileBody, req.body);
    await prisma.profile.update({ where: { userId: req.userId }, data: body });
    return { user: await serializeMe(prisma, req.userId) };
  });
}
