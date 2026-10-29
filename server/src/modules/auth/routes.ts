import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { conflict, unauthorized } from '../../lib/errors.js';
import { track } from '../../lib/events.js';
import { hashPassword, verifyPassword } from '../../lib/password.js';
import { isValidTimezone } from '../../lib/time.js';
import { parse } from '../../lib/validate.js';
import { serializeMe } from '../users/serialize.js';

const email = z.string().trim().toLowerCase().email().max(254);
const timezone = z.string().refine(isValidTimezone, 'Unknown timezone').optional();

const registerBody = z.object({
  email,
  password: z.string().min(8, 'Password must be at least 8 characters').max(128),
  displayName: z.string().trim().min(1).max(40),
  timezone,
});
const loginBody = z.object({ email, password: z.string().min(1).max(128) });
const googleBody = z.object({ idToken: z.string().min(1), timezone });
const refreshBody = z.object({ refreshToken: z.string().min(1) });

export async function authRoutes(app: FastifyInstance) {
  const { prisma, tokens, verifyGoogle } = app.deps;

  app.post('/auth/register', async (req, reply) => {
    const body = parse(registerBody, req.body);
    if (await prisma.user.findUnique({ where: { email: body.email } })) {
      throw conflict('EMAIL_TAKEN', 'An account with this email already exists');
    }
    const user = await prisma.user.create({
      data: {
        email: body.email,
        passwordHash: await hashPassword(body.password),
        profile: { create: { displayName: body.displayName, interests: [], timezone: body.timezone ?? 'UTC' } },
      },
    });
    await track(prisma, 'sign_up', { userId: user.id, props: { method: 'password' } });
    reply.code(201);
    return { user: await serializeMe(prisma, user.id), tokens: await tokens.issue(user.id) };
  });

  app.post('/auth/login', async (req) => {
    const body = parse(loginBody, req.body);
    const user = await prisma.user.findUnique({ where: { email: body.email } });
    // Same error for unknown email and wrong password, so emails can't be probed.
    if (!user?.passwordHash || !(await verifyPassword(body.password, user.passwordHash))) {
      throw unauthorized('INVALID_CREDENTIALS', 'Email or password is incorrect');
    }
    return { user: await serializeMe(prisma, user.id), tokens: await tokens.issue(user.id) };
  });

  app.post('/auth/google', async (req, reply) => {
    const body = parse(googleBody, req.body);
    const identity = await verifyGoogle(body.idToken);

    let user = await prisma.user.findUnique({ where: { googleId: identity.googleId } });
    if (!user) {
      const existing = await prisma.user.findUnique({ where: { email: identity.email.toLowerCase() } });
      if (existing) {
        // Google verified this email, so linking to the password account is safe.
        user = await prisma.user.update({ where: { id: existing.id }, data: { googleId: identity.googleId } });
      } else {
        user = await prisma.user.create({
          data: {
            email: identity.email.toLowerCase(),
            googleId: identity.googleId,
            profile: {
              create: {
                displayName: (identity.name ?? identity.email.split('@')[0]!).slice(0, 40),
                avatarUrl: identity.picture,
                interests: [],
                timezone: body.timezone ?? 'UTC',
              },
            },
          },
        });
        await track(prisma, 'sign_up', { userId: user.id, props: { method: 'google' } });
        reply.code(201);
      }
    }
    return { user: await serializeMe(prisma, user.id), tokens: await tokens.issue(user.id) };
  });

  app.post('/auth/refresh', async (req) => {
    const body = parse(refreshBody, req.body);
    const { tokens: next } = await tokens.rotate(body.refreshToken);
    return { tokens: next };
  });

  app.post('/auth/logout', async (req, reply) => {
    const body = parse(refreshBody, req.body);
    await tokens.revoke(body.refreshToken);
    reply.code(204);
  });
}
