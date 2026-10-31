import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { track } from '../../lib/events.js';
import { rateLimit } from '../../lib/rate-limit.js';
import { isValidTimezone } from '../../lib/time.js';
import { parse } from '../../lib/validate.js';
import { serializeMe } from '../users/serialize.js';

const demoBody = z.object({
  displayName: z.string().trim().min(1).max(40),
  timezone: z.string().refine(isValidTimezone, 'Unknown timezone').optional(),
});

export const BOT_NAME = 'Sam (bot)';
// Interests are filled in so the demo skips onboarding and goes straight home.
const DEMO_INTERESTS = ['Movies', 'Food', 'Music', 'Travel'];

/**
 * Try Duo alone: a guest account already paired with a bot that plays along,
 * so someone opening the link (a recruiter, a curious friend) sees the live
 * reveal, the arcade and the pet within a minute.
 */
export async function demoRoutes(app: FastifyInstance) {
  const { prisma, redis, tokens } = app.deps;
  const limit = rateLimit(redis, { name: 'auth', max: 10, windowSeconds: 60 });

  app.post('/auth/demo', { preHandler: limit }, async (req, reply) => {
    const body = parse(demoBody, req.body);
    const timezone = body.timezone ?? 'UTC';
    const me = await prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: { profile: { create: { displayName: body.displayName, interests: DEMO_INTERESTS, timezone } } },
      });
      const bot = await tx.user.create({
        data: {
          isBot: true,
          profile: { create: { displayName: BOT_NAME, interests: DEMO_INTERESTS, timezone } },
        },
      });
      const pair = await tx.pair.create({
        data: {
          userAId: user.id,
          userBId: bot.id,
          relationship: 'FRIENDS',
          timezone,
          streak: { create: {} },
        },
      });
      await tx.user.updateMany({
        where: { id: { in: [user.id, bot.id] } },
        data: { currentPairId: pair.id },
      });
      return { user, bot };
    });
    // The bot is always "online".
    await redis
      .multi()
      .hset('presence:conns', me.bot.id, 1)
      .hset('presence:state', me.bot.id, 'online')
      .exec();
    await track(prisma, 'sign_up', { userId: me.user.id, props: { method: 'demo' } });
    reply.code(201);
    return { user: await serializeMe(prisma, me.user.id), tokens: await tokens.issue(me.user.id) };
  });
}
