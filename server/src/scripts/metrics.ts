// Prints the launch dashboard: funnel, daily activity, and AI generation health.
//   npm run metrics            (last 14 days)
//   npm run metrics -- 30      (last 30 days)
import { loadConfig } from '../config.js';
import { createPrisma } from '../lib/prisma.js';

const days = Number(process.argv[2] ?? 14);
const prisma = createPrisma(loadConfig().DATABASE_URL);
const since = new Date(Date.now() - days * 86_400_000);

const funnel = await prisma.$queryRaw<{ name: string; users: bigint; events: bigint }[]>`
  SELECT name, COUNT(DISTINCT COALESCE(user_id::text, pair_id::text)) AS users, COUNT(*) AS events
  FROM events WHERE created_at >= ${since} GROUP BY name ORDER BY events DESC`;

const daily = await prisma.$queryRaw<{ day: Date; started: bigint; completed: bigint }[]>`
  SELECT date_trunc('day', created_at) AS day,
         COUNT(*) FILTER (WHERE name = 'game_started') AS started,
         COUNT(*) FILTER (WHERE name = 'game_completed') AS completed
  FROM events WHERE created_at >= ${since} GROUP BY 1 ORDER BY 1`;

const generation = await prisma.$queryRaw<
  { status: string; attempts: bigint; avg_ms: number | null; p95_ms: number | null; cost: number | null }[]
>`
  SELECT status, COUNT(*) AS attempts, AVG(latency_ms)::float AS avg_ms,
         percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)::float AS p95_ms,
         SUM(cost_usd)::float AS cost
  FROM generation_logs WHERE created_at >= ${since} GROUP BY status`;

const sources = await prisma.$queryRaw<{ source: string; games: bigint }[]>`
  SELECT source::text, COUNT(*) AS games FROM games WHERE created_at >= ${since} GROUP BY source`;

const [activePairs, users] = await Promise.all([
  prisma.pair.count({ where: { endedAt: null } }),
  prisma.user.count(),
]);

const num = (n: bigint | number | null) => Number(n ?? 0);
console.log(`\nDuo metrics, last ${days} days\n`);
console.log(`Users: ${users}   Active pairs: ${activePairs}\n`);
console.table(
  funnel.map((r) => ({ event: r.name, 'unique users/pairs': num(r.users), events: num(r.events) })),
);
console.table(
  daily.map((r) => ({
    day: r.day.toISOString().slice(0, 10),
    started: num(r.started),
    completed: num(r.completed),
  })),
);
const totalAttempts = generation.reduce((s, r) => s + num(r.attempts), 0);
console.table(
  generation.map((r) => ({
    status: r.status,
    attempts: num(r.attempts),
    share: totalAttempts ? `${((num(r.attempts) / totalAttempts) * 100).toFixed(1)}%` : '-',
    'avg ms': Math.round(r.avg_ms ?? 0),
    'p95 ms': Math.round(r.p95_ms ?? 0),
    'cost $': (r.cost ?? 0).toFixed(4),
  })),
);
const totalGames = sources.reduce((s, r) => s + num(r.games), 0);
const bank = num(sources.find((s) => s.source === 'BANK')?.games ?? 0);
console.log(
  `Games served: ${totalGames}   from AI: ${totalGames - bank}   fallback to bank: ${bank}` +
    (totalGames ? ` (${((bank / totalGames) * 100).toFixed(1)}%)` : ''),
);
await prisma.$disconnect();
