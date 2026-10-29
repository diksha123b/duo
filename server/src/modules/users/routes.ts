import type { FastifyInstance } from 'fastify';
import { serializeMe } from './serialize.js';

export async function userRoutes(app: FastifyInstance) {
  app.get('/me', { preHandler: app.authenticate }, async (req) => {
    return { user: await serializeMe(app.deps.prisma, req.userId) };
  });
}
