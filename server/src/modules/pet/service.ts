import type { Pair, PrismaClient } from '@prisma/client';
import { badRequest, conflict } from '../../lib/errors.js';
import { addDays, dateToDay, dayToDate, localDay } from '../../lib/time.js';
import type { GameService } from '../games/service.js';
import {
  levelFor,
  moodFor,
  OUTFITS,
  stageFor,
  unlockedOutfits,
  XP,
  xpForLevel,
  type OutfitId,
  type PetColor,
} from './pet.js';

export class PetService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly games: GameService,
  ) {}

  async get(userId: string) {
    const pair = await this.games.activePairFor(userId);
    return this.view(pair, userId);
  }

  /** One pat per person per day. */
  async pat(userId: string) {
    const pair = await this.games.activePairFor(userId);
    const day = dayToDate(localDay(pair.timezone));
    const done = await this.prisma.petPat.createMany({
      data: [{ pairId: pair.id, userId, day }],
      skipDuplicates: true,
    });
    if (done.count === 0) throw conflict('ALREADY_PATTED', 'You already gave a pat today');
    return { pet: await this.view(pair, userId), pairId: pair.id };
  }

  async update(userId: string, changes: { name?: string; color?: PetColor; outfit?: OutfitId | null }) {
    const pair = await this.games.activePairFor(userId);
    if (changes.outfit) {
      const { level } = await this.progress(pair);
      if (!unlockedOutfits(level).includes(changes.outfit))
        throw badRequest('LOCKED', 'Keep playing together to unlock that');
    }
    await this.prisma.pet.upsert({
      where: { pairId: pair.id },
      create: { pairId: pair.id, ...changes },
      update: changes,
    });
    return { pet: await this.view(pair, userId), pairId: pair.id };
  }

  private async progress(pair: Pair) {
    const [daily, bonus, matches, pats] = await Promise.all([
      this.prisma.game.count({ where: { pairId: pair.id, isDaily: true, completedAt: { not: null } } }),
      this.prisma.game.count({ where: { pairId: pair.id, isDaily: false, completedAt: { not: null } } }),
      this.prisma.match.count({ where: { pairId: pair.id, status: 'FINISHED' } }),
      this.prisma.petPat.count({ where: { pairId: pair.id } }),
    ]);
    const xp = daily * XP.daily + bonus * XP.bonus + matches * XP.match + pats * XP.pat;
    return { xp, level: levelFor(xp) };
  }

  async view(pair: Pair, userId: string) {
    const today = localDay(pair.timezone);
    const [pet, streak, patsToday, { xp, level }] = await Promise.all([
      this.prisma.pet.findUnique({ where: { pairId: pair.id } }),
      this.prisma.streak.findUnique({ where: { pairId: pair.id } }),
      this.prisma.petPat.findMany({ where: { pairId: pair.id, day: dayToDate(today) } }),
      this.progress(pair),
    ]);
    const lastDaily = streak?.lastCompletedDay ? dateToDay(streak.lastCompletedDay) : null;
    const unlocked = unlockedOutfits(level);
    const next = OUTFITS.find((o) => o.level > level);
    return {
      name: pet?.name ?? 'Mochi',
      color: pet?.color ?? 'peach',
      // An outfit stays on only while it's unlocked.
      outfit: pet?.outfit && (unlocked as string[]).includes(pet.outfit) ? pet.outfit : null,
      xp,
      level,
      stage: stageFor(level),
      levelXp: xpForLevel(level),
      nextLevelXp: xpForLevel(level + 1),
      mood: moodFor(lastDaily, today, addDays(today, -1)),
      patted: {
        me: patsToday.some((p) => p.userId === userId),
        partner: patsToday.some((p) => p.userId !== userId),
      },
      unlocked,
      nextUnlock: next ? { id: next.id, level: next.level } : null,
    };
  }
}
