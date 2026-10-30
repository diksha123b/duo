import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { parse } from '../../lib/validate.js';

const subscription = z.object({
  endpoint: z.string().url().max(1000),
  keys: z.object({ p256dh: z.string().min(1).max(200), auth: z.string().min(1).max(100) }),
});

export async function pushRoutes(app: FastifyInstance) {
  const { prisma, config } = app.deps;
  const auth = { preHandler: app.authenticate };

  /** The public key browsers need to subscribe; null when push isn't configured. */
  app.get('/push/key', async () => ({ key: config.VAPID_PUBLIC_KEY ?? null }));

  app.post('/push/subscribe', auth, async (req, reply) => {
    const { endpoint, keys } = parse(subscription, req.body);
    // A browser belongs to whoever subscribed it last (e.g. after switching accounts).
    await prisma.pushSubscription.upsert({
      where: { endpoint },
      create: { endpoint, userId: req.userId, p256dh: keys.p256dh, auth: keys.auth },
      update: { userId: req.userId, p256dh: keys.p256dh, auth: keys.auth },
    });
    reply.code(204);
  });

  app.post('/push/unsubscribe', auth, async (req, reply) => {
    const { endpoint } = parse(z.object({ endpoint: z.string().url() }), req.body);
    await prisma.pushSubscription.deleteMany({ where: { endpoint, userId: req.userId } });
    reply.code(204);
  });
}
