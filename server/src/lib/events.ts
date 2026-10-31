import type { Prisma, PrismaClient } from '@prisma/client';

export type EventName = 'sign_up' | 'paired' | 'unpaired' | 'game_started' | 'game_completed' | 'guest_saved';

// Analytics must never break a user request, so failures are swallowed.
export async function track(
  prisma: PrismaClient,
  name: EventName,
  data: { userId?: string; pairId?: string; props?: Prisma.InputJsonObject } = {},
): Promise<void> {
  try {
    await prisma.event.create({ data: { name, ...data } });
  } catch {
    // intentionally ignored
  }
}
