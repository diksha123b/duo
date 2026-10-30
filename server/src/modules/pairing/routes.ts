import { randomInt } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { AppError, badRequest, conflict, notFound } from '../../lib/errors.js';
import { track } from '../../lib/events.js';
import { rateLimit } from '../../lib/rate-limit.js';
import { displayStreak } from '../../lib/streak.js';
import { dateToDay, localDay } from '../../lib/time.js';
import { parse } from '../../lib/validate.js';

// No 0/O/1/I/L, so codes survive being read aloud or typed from a screenshot.
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 6;
const INVITE_TTL_MS = 24 * 60 * 60 * 1000;

const generateCode = () =>
  Array.from({ length: CODE_LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');

const joinBody = z.object({
  code: z
    .string()
    .trim()
    .toUpperCase()
    .transform((s) => s.replace(/[\s-]/g, ''))
    .pipe(z.string().length(CODE_LENGTH, 'Invite codes are 6 characters')),
});

const gone = (code: string, message: string) => new AppError(410, code, message);

const RELATIONSHIPS = [
  'PARTNERS',
  'BEST_FRIENDS',
  'FRIENDS',
  'SIBLINGS',
  'PARENT_CHILD',
  'COLLEAGUES',
] as const;
// For a parent and child, say which one you are; ignored otherwise.
const relationshipBody = z
  .object({
    relationship: z.enum(RELATIONSHIPS).default('FRIENDS'),
    // What they call each other: "cousins", "grandma & me", anything.
    label: z.string().trim().min(1).max(30).optional(),
    iAm: z.enum(['PARENT', 'CHILD']).optional(),
  })
  .refine((b) => b.relationship !== 'PARENT_CHILD' || b.iAm, {
    message: 'Say whether you are the parent or the child',
    path: ['iAm'],
  });

function serializeInvite(invite: {
  code: string;
  expiresAt: Date;
  relationship: string;
  relationshipLabel: string | null;
}) {
  return {
    code: invite.code,
    expiresAt: invite.expiresAt,
    relationship: invite.relationship,
    label: invite.relationshipLabel,
  };
}

export async function pairingRoutes(app: FastifyInstance) {
  const { prisma, redis } = app.deps;
  const byUser = { key: (req: { userId: string }) => req.userId };

  app.get('/pair', { preHandler: app.authenticate }, async (req) => {
    const me = await prisma.user.findUniqueOrThrow({ where: { id: req.userId } });
    if (!me.currentPairId) return { pair: null };

    const pair = await prisma.pair.findUniqueOrThrow({
      where: { id: me.currentPairId },
      include: { members: { include: { profile: true } }, streak: true },
    });
    const partner = pair.members.find((m) => m.id !== req.userId);
    return {
      pair: {
        id: pair.id,
        createdAt: pair.createdAt,
        timezone: pair.timezone,
        relationship: pair.relationship,
        relationshipLabel: pair.relationshipLabel,
        myRole:
          pair.relationship === 'PARENT_CHILD' ? (pair.parentId === req.userId ? 'PARENT' : 'CHILD') : null,
        streak: {
          current: pair.streak
            ? displayStreak(
                {
                  current: pair.streak.current,
                  longest: pair.streak.longest,
                  lastCompletedDay: pair.streak.lastCompletedDay
                    ? dateToDay(pair.streak.lastCompletedDay)
                    : null,
                },
                localDay(pair.timezone),
              )
            : 0,
          longest: pair.streak?.longest ?? 0,
          lastCompletedDay: pair.streak?.lastCompletedDay ? dateToDay(pair.streak.lastCompletedDay) : null,
        },
        partner: partner && {
          id: partner.id,
          displayName: partner.profile?.displayName ?? 'Partner',
          avatarUrl: partner.profile?.avatarUrl ?? null,
          interests: partner.profile?.interests ?? [],
        },
      },
    };
  });

  app.post(
    '/invites',
    {
      preHandler: [
        app.authenticate,
        rateLimit(redis, { name: 'invite-create', max: 10, windowSeconds: 60, ...byUser }),
      ],
    },
    async (req, reply) => {
      const body = parse(relationshipBody, req.body ?? {});
      const kind = {
        relationship: body.relationship,
        relationshipLabel: body.label ?? null,
        creatorIsParent: body.relationship === 'PARENT_CHILD' ? body.iAm === 'PARENT' : null,
      };
      const me = await prisma.user.findUniqueOrThrow({ where: { id: req.userId } });
      if (me.currentPairId) throw conflict('ALREADY_PAIRED', 'You are already paired');

      // Hand back the live invite instead of spamming new codes, updating
      // who it's for if that changed.
      const live = await prisma.invite.findFirst({
        where: { creatorId: req.userId, usedAt: null, expiresAt: { gt: new Date() } },
        orderBy: { createdAt: 'desc' },
      });
      if (live) {
        const updated = await prisma.invite.update({ where: { id: live.id }, data: kind });
        return { invite: serializeInvite(updated) };
      }

      for (let attempt = 0; attempt < 5; attempt++) {
        try {
          const invite = await prisma.invite.create({
            data: {
              code: generateCode(),
              creatorId: req.userId,
              expiresAt: new Date(Date.now() + INVITE_TTL_MS),
              ...kind,
            },
          });
          reply.code(201);
          return { invite: serializeInvite(invite) };
        } catch (err) {
          // Unique collision on code: try another.
          if (!(err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002')) throw err;
        }
      }
      throw new Error('Could not allocate a unique invite code');
    },
  );

  app.post(
    '/invites/join',
    {
      // Tight limit: codes are short, so guessing must be expensive.
      preHandler: [
        app.authenticate,
        rateLimit(redis, { name: 'invite-join', max: 10, windowSeconds: 300, ...byUser }),
      ],
    },
    async (req) => {
      const { code } = parse(joinBody, req.body);
      const invite = await prisma.invite.findUnique({ where: { code } });
      if (!invite) throw notFound('INVITE_INVALID', 'That code does not exist');
      if (invite.creatorId === req.userId) throw badRequest('OWN_INVITE', 'You cannot join your own invite');
      if (invite.usedAt) throw gone('INVITE_USED', 'That code has already been used');
      if (invite.expiresAt <= new Date())
        throw gone('INVITE_EXPIRED', 'That code has expired, ask for a new one');

      const [me, creator] = await Promise.all([
        prisma.user.findUniqueOrThrow({ where: { id: req.userId } }),
        prisma.user.findUniqueOrThrow({ where: { id: invite.creatorId }, include: { profile: true } }),
      ]);
      if (me.currentPairId) throw conflict('ALREADY_PAIRED', 'You are already paired');
      if (creator.currentPairId) throw conflict('PARTNER_ALREADY_PAIRED', 'That person has already paired');

      const pair = await prisma.$transaction(async (tx) => {
        const claimed = await tx.invite.updateMany({
          where: { id: invite.id, usedAt: null },
          data: { usedAt: new Date(), usedById: req.userId },
        });
        if (claimed.count === 0) throw gone('INVITE_USED', 'That code has already been used');

        const pair = await tx.pair.create({
          data: {
            userAId: creator.id,
            userBId: me.id,
            relationship: invite.relationship,
            relationshipLabel: invite.relationshipLabel,
            parentId:
              invite.relationship === 'PARENT_CHILD' ? (invite.creatorIsParent ? creator.id : me.id) : null,
            timezone: creator.profile?.timezone ?? 'UTC',
            streak: { create: {} },
          },
        });
        // Both users must still be unpaired; otherwise a concurrent join won and we roll back.
        const linked = await tx.user.updateMany({
          where: { id: { in: [creator.id, me.id] }, currentPairId: null },
          data: { currentPairId: pair.id },
        });
        if (linked.count !== 2) throw conflict('ALREADY_PAIRED', 'One of you paired with someone else');
        return pair;
      });

      // Any other open invites from either user are now meaningless.
      await prisma.invite.updateMany({
        where: { creatorId: { in: [creator.id, me.id] }, usedAt: null },
        data: { expiresAt: new Date() },
      });
      await track(prisma, 'paired', { userId: req.userId, pairId: pair.id });
      app.events.emit('pair:changed', { pairId: pair.id });
      return { pair: { id: pair.id } };
    },
  );

  // Either person can change what the pair is (e.g. friends → best friends).
  app.patch('/pair', { preHandler: app.authenticate }, async (req) => {
    const body = parse(relationshipBody, req.body);
    const me = await prisma.user.findUniqueOrThrow({
      where: { id: req.userId },
      include: { currentPair: true },
    });
    const pair = me.currentPair;
    if (!pair) throw notFound('NOT_PAIRED', 'You are not paired');
    const other = pair.userAId === req.userId ? pair.userBId : pair.userAId;
    await prisma.pair.update({
      where: { id: pair.id },
      data: {
        relationship: body.relationship,
        relationshipLabel: body.label ?? null,
        parentId: body.relationship === 'PARENT_CHILD' ? (body.iAm === 'PARENT' ? req.userId : other) : null,
      },
    });
    app.events.emit('pair:changed', { pairId: pair.id });
    return { pair: { id: pair.id, relationship: body.relationship, relationshipLabel: body.label ?? null } };
  });

  app.delete('/pair', { preHandler: app.authenticate }, async (req, reply) => {
    const me = await prisma.user.findUniqueOrThrow({ where: { id: req.userId } });
    if (!me.currentPairId) throw notFound('NOT_PAIRED', 'You are not paired');
    const pairId = me.currentPairId;

    await prisma.$transaction([
      prisma.pair.update({ where: { id: pairId }, data: { endedAt: new Date() } }),
      prisma.user.updateMany({ where: { currentPairId: pairId }, data: { currentPairId: null } }),
    ]);
    await track(prisma, 'unpaired', { userId: req.userId, pairId });
    app.events.emit('pair:changed', { pairId });
    reply.code(204);
  });
}
