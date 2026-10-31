import type { PrismaClient } from '@prisma/client';
import { notFound } from '../../lib/errors.js';

export async function serializeMe(prisma: PrismaClient, userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId }, include: { profile: true } });
  if (!user) throw notFound('USER_NOT_FOUND', 'User no longer exists');
  // Demo mode: paired with the bot.
  const demo =
    user.currentPairId !== null &&
    (await prisma.user.count({ where: { currentPairId: user.currentPairId, isBot: true } })) > 0;
  return {
    id: user.id,
    email: user.email,
    guest: user.email === null,
    demo,
    hasPassword: user.passwordHash !== null,
    hasGoogle: user.googleId !== null,
    pairId: user.currentPairId,
    profile: user.profile && {
      displayName: user.profile.displayName,
      interests: user.profile.interests,
      timezone: user.profile.timezone,
      avatarUrl: user.profile.avatarUrl,
    },
  };
}
