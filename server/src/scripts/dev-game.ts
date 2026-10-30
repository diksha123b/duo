// Dev only: replace today's game for every active pair with a chosen type,
// so you can try each game without waiting for the daily rotation.
//   npm run dev:game -- RANK_IT
import { loadConfig } from '../config.js';
import { createPrisma } from '../lib/prisma.js';
import { dayToDate, localDay } from '../lib/time.js';
import { bankGame } from '../modules/games/bank.js';
import { GAME_TYPES, type GameTypeName } from '../modules/games/content.js';

const config = loadConfig();
if (config.NODE_ENV === 'production') throw new Error('dev:game must not run in production');

const type = process.argv[2] as GameTypeName;
if (!GAME_TYPES.includes(type)) {
  console.error(`Usage: npm run dev:game -- <${GAME_TYPES.join(' | ')}>`);
  process.exit(1);
}

const prisma = createPrisma(config.DATABASE_URL);
const pairs = await prisma.pair.findMany({ where: { endedAt: null } });
for (const pair of pairs) {
  const day = localDay(pair.timezone);
  await prisma.game.deleteMany({ where: { pairId: pair.id, day: dayToDate(day), isDaily: true } });
  const content = bankGame(type, `${pair.id}:${day}:${Date.now()}`);
  await prisma.game.create({
    data: {
      pairId: pair.id,
      day: dayToDate(day),
      type,
      source: 'BANK',
      title: content.title,
      questions: {
        create: content.questions.map((q, position) => ({
          position,
          prompt: q.prompt,
          options: q.options,
          correctOption: q.correctOption ?? null,
          meta: q.about ? { about: q.about === 'A' ? pair.userAId : pair.userBId } : {},
        })),
      },
    },
  });
}
console.log(`Today's game is now ${type} for ${pairs.length} pair(s). Pull to refresh in the app.`);
await prisma.$disconnect();
