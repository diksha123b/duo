import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { conflict, unauthorized } from '../../lib/errors.js';
import { track } from '../../lib/events.js';
import { rateLimit } from '../../lib/rate-limit.js';
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
const guestBody = z.object({ displayName: z.string().trim().min(1).max(40), timezone });
const saveBody = z.object({
  email,
  password: z.string().min(8, 'Password must be at least 8 characters').max(128),
});
const loginBody = z.object({ email, password: z.string().min(1).max(128) });
const googleBody = z.object({ idToken: z.string().min(1), timezone });
const refreshBody = z.object({ refreshToken: z.string().min(1) });

export async function authRoutes(app: FastifyInstance) {
  const { prisma, redis, tokens, verifyGoogle } = app.deps;
  // Per-IP limits slow down password guessing and signup spam.
  const strict = { preHandler: rateLimit(redis, { name: 'auth', max: 10, windowSeconds: 60 }) };
  const loose = { preHandler: rateLimit(redis, { name: 'auth-refresh', max: 60, windowSeconds: 60 }) };

  app.post('/auth/register', strict, async (req, reply) => {
    const body = parse(registerBody, req.body);
    if (await prisma.user.findUnique({ where: { email: body.email } })) {
      throw conflict('EMAIL_TAKEN', 'An account with this email already exists');
    }
    const user = await prisma.user.create({
      data: {
        email: body.email,
        passwordHash: await hashPassword(body.password),
        profile: {
          create: { displayName: body.displayName, interests: [], timezone: body.timezone ?? 'UTC' },
        },
      },
    });
    await track(prisma, 'sign_up', { userId: user.id, props: { method: 'password' } });
    reply.code(201);
    return { user: await serializeMe(prisma, user.id), tokens: await tokens.issue(user.id) };
  });

  // Play straight away with just a name. The account lives on this device
  // until the guest saves it with an email and password.
  app.post('/auth/guest', strict, async (req, reply) => {
    const body = parse(guestBody, req.body);
    const user = await prisma.user.create({
      data: {
        profile: {
          create: { displayName: body.displayName, interests: [], timezone: body.timezone ?? 'UTC' },
        },
      },
    });
    await track(prisma, 'sign_up', { userId: user.id, props: { method: 'guest' } });
    reply.code(201);
    return { user: await serializeMe(prisma, user.id), tokens: await tokens.issue(user.id) };
  });

  // A guest keeps everything (pair, streak, pet) and can now sign in anywhere.
  app.post('/auth/save', { preHandler: [app.authenticate, strict.preHandler] }, async (req) => {
    const body = parse(saveBody, req.body);
    const passwordHash = await hashPassword(body.password);
    // Only a guest (no email yet) can be saved, and only once.
    const saved = await prisma.user
      .updateMany({ where: { id: req.userId, email: null }, data: { email: body.email, passwordHash } })
      .catch((err: { code?: string }) => {
        if (err.code === 'P2002') throw conflict('EMAIL_TAKEN', 'An account with this email already exists');
        throw err;
      });
    if (saved.count === 0) throw conflict('NOT_A_GUEST', 'This account is already saved');
    await track(prisma, 'guest_saved', { userId: req.userId });
    return { user: await serializeMe(prisma, req.userId) };
  });

  app.post('/auth/login', strict, async (req) => {
    const body = parse(loginBody, req.body);
    const user = await prisma.user.findUnique({ where: { email: body.email } });
    // Same error for unknown email and wrong password, so emails can't be probed.
    if (!user?.passwordHash || !(await verifyPassword(body.password, user.passwordHash))) {
      throw unauthorized('INVALID_CREDENTIALS', 'Email or password is incorrect');
    }
    return { user: await serializeMe(prisma, user.id), tokens: await tokens.issue(user.id) };
  });

  app.post('/auth/google', strict, async (req, reply) => {
    const body = parse(googleBody, req.body);
    const identity = await verifyGoogle(body.idToken);

    let user = await prisma.user.findUnique({ where: { googleId: identity.googleId } });
    if (!user) {
      const existing = await prisma.user.findUnique({ where: { email: identity.email.toLowerCase() } });
      if (existing) {
        // Google verified this email, so linking to the password account is safe.
        user = await prisma.user.update({
          where: { id: existing.id },
          data: { googleId: identity.googleId },
        });
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

  app.post('/auth/refresh', loose, async (req) => {
    const body = parse(refreshBody, req.body);
    const { tokens: next } = await tokens.rotate(body.refreshToken);
    return { tokens: next };
  });

  app.post('/auth/logout', loose, async (req, reply) => {
    const body = parse(refreshBody, req.body);
    await tokens.revoke(body.refreshToken);
    reply.code(204);
  });
}
