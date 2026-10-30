import type { FastifyInstance } from 'fastify';
import { ENGINES } from '../arcade/engines/index.js';
import type { Seat } from '../arcade/engines/types.js';

const DAILY_NAMES: Record<string, string> = {
  WHO_KNOWS_WHOM: 'who knows whom',
  WOULD_YOU_RATHER: 'would you rather',
  SHARED_TRIVIA: 'team trivia',
  EMOJI_DECODE: 'emoji decode',
  AGREE_O_METER: 'agree-o-meter',
  RANK_IT: 'rank it',
};
const ARCADE_NAMES: Record<string, string> = {
  CHESS: 'chess',
  LUDO: 'ludo',
  WORD_TILES: 'word tiles',
  FOUR_IN_A_ROW: 'four in a row',
  DOTS_AND_BOXES: 'dots & boxes',
  TIC_TAC_TOE: 'tic-tac-toe',
};

/** Turns in-app events into push notifications for whoever isn't looking. */
export function registerPushTriggers(app: FastifyInstance) {
  const { prisma, notifier } = app.deps;
  if (!notifier.enabled) return;

  const nameOf = async (userId: string) =>
    (await prisma.profile.findUnique({ where: { userId } }))?.displayName ?? 'Your duo';
  const otherIn = async (pairId: string, userId: string) => {
    const pair = await prisma.pair.findUnique({ where: { id: pairId } });
    if (!pair) return null;
    return pair.userAId === userId ? pair.userBId : pair.userAId;
  };
  const safe =
    <A extends unknown[]>(fn: (...args: A) => Promise<void>) =>
    (...args: A) => {
      fn(...args).catch((err) => app.log.warn({ err }, 'push trigger failed'));
    };

  app.events.on(
    'game:submitted',
    safe(async ({ gameId, userId }) => {
      const game = await prisma.game.findUnique({ where: { id: gameId }, include: { submissions: true } });
      if (!game || game.completedAt) return;
      const other = await otherIn(game.pairId, userId);
      if (!other || game.submissions.some((s) => s.userId === other)) return;
      const who = await nameOf(userId);
      await notifier.notify(other, {
        title: `${who} played ✨`,
        body: game.isDaily
          ? 'Today’s game is waiting for you. Your turn!'
          : `A bonus round of ${DAILY_NAMES[game.type]} is waiting for you.`,
        url: game.isDaily ? '/#/game' : `/#/bonus/${game.id}`,
        tag: `game-${game.id}`,
      });
    }),
  );

  app.events.on(
    'game:completed',
    safe(async ({ gameId }) => {
      const game = await prisma.game.findUnique({ where: { id: gameId }, include: { pair: true } });
      if (!game) return;
      for (const userId of [game.pair.userAId, game.pair.userBId]) {
        await notifier.notify(userId, {
          title: 'The results are in 👀',
          body: 'See how your answers compare.',
          url: game.isDaily ? '/#/game' : `/#/bonus/${game.id}`,
          tag: `game-${game.id}`,
        });
      }
    }),
  );

  app.events.on(
    'game:social',
    safe(async ({ gameId, pairId, userId, kind, text }) => {
      const other = await otherIn(pairId, userId);
      if (!other) return;
      const game = await prisma.game.findUnique({ where: { id: gameId } });
      const who = await nameOf(userId);
      await notifier.notify(other, {
        title: kind === 'comment' ? who : `${who} reacted ${text}`,
        body: kind === 'comment' ? text : 'Tap to see which answer.',
        url: game?.isDaily ? '/#/game' : `/#/bonus/${gameId}`,
        tag: `chat-${gameId}`,
      });
    }),
  );

  app.events.on(
    'match:updated',
    safe(async ({ matchId }) => {
      const match = await prisma.match.findUnique({ where: { id: matchId } });
      if (!match) return;
      const game = ARCADE_NAMES[match.kind];
      if (match.status !== 'ACTIVE') {
        for (const userId of match.players) {
          const won = match.winnerId === userId;
          await notifier.notify(userId, {
            title:
              match.winnerId === null
                ? `${game}: it’s a draw 🤝`
                : won
                  ? `You won ${game}! 🎉`
                  : `${game} is over`,
            body: 'Tap for a rematch.',
            url: `/#/arcade/${matchId}`,
            tag: `match-${matchId}`,
          });
        }
        return;
      }
      const turn = ENGINES[match.kind].outcome(match.state).turn as Seat | null;
      if (turn === null) return;
      const next = match.players[turn]!;
      const other = match.players[1 - turn]!;
      await notifier.notify(next, {
        title: `Your move in ${game}`,
        body: `${await nameOf(other)} is waiting on you.`,
        url: `/#/arcade/${matchId}`,
        tag: `match-${matchId}`,
      });
    }),
  );
}
