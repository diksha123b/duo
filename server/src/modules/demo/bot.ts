import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { ENGINES } from '../arcade/engines/index.js';
import type { MatchSettings } from '../arcade/service.js';
import type { Rng, Seat } from '../arcade/engines/types.js';
import { REACTIONS, type SubmittedAnswer } from '../games/service.js';
import { botMove } from './botMoves.js';

const CHAT = {
  close: ['we’re basically the same person 😄', 'okay we really think alike', 'great minds!! ✨'],
  apart: [
    'how are we this different 😂',
    'interesting choices there 👀',
    'we need to talk about these answers 😅',
  ],
  any: ['that was fun! same time tomorrow?', 'haha good one', 'okay I liked that round'],
};

const random: Rng = { int: (n) => Math.floor(Math.random() * n) };
const pick = <T>(xs: readonly T[]) => xs[random.int(xs.length)]!;

/**
 * The demo partner. It listens to the same domain events as the real-time
 * layer and plays along: answers games after you, makes its arcade moves,
 * reacts and chats about results, and pats the pet back. Each action is
 * delayed a little so it feels like a person.
 */
export class DemoBot {
  private readonly pending = new Set<Promise<void>>();

  constructor(
    private readonly app: FastifyInstance,
    private readonly delayMs: number,
  ) {}

  /** Resolves once every queued bot action has finished (tests). */
  async idle() {
    while (this.pending.size > 0) await Promise.allSettled([...this.pending]);
  }

  register() {
    const { events } = this.app;
    events.on('game:submitted', ({ gameId, userId }) => this.later(() => this.answer(gameId, userId)));
    events.on('game:completed', ({ gameId }) => this.later(() => this.chat(gameId)));
    events.on('match:updated', ({ matchId }) => this.later(() => this.play(matchId)));
    events.on('pet:changed', ({ pairId, userId, kind }) => {
      if (kind === 'pat') this.later(() => this.patBack(pairId, userId));
    });
  }

  private later(action: () => Promise<void>) {
    const run = new Promise<void>((resolve) => setTimeout(resolve, this.delayMs))
      .then(action)
      .catch((err) => this.app.log.warn({ err }, 'demo bot action failed'))
      .finally(() => this.pending.delete(run));
    this.pending.add(run);
  }

  /** The bot in this pair, if it's a demo pair. */
  private bot(pairId: string) {
    return this.app.deps.prisma.user.findFirst({ where: { currentPairId: pairId, isBot: true } });
  }

  private async answer(gameId: string, by: string) {
    const { prisma, games } = this.app.deps;
    const game = await prisma.game.findUnique({
      where: { id: gameId },
      include: { questions: true, submissions: true },
    });
    if (!game || game.completedAt) return;
    const bot = await this.bot(game.pairId);
    if (!bot || bot.id === by || game.submissions.some((s) => s.userId === bot.id)) return;

    const answers: SubmittedAnswer[] = game.questions.map((q) => {
      if (game.type === 'RANK_IT') {
        const order = q.options.map((_, i) => i);
        for (let i = order.length - 1; i > 0; i--) {
          const j = random.int(i + 1);
          [order[i], order[j]] = [order[j]!, order[i]!];
        }
        return { questionId: q.id, ranking: order };
      }
      // Quizzes: right more often than not, so the reveal is fun either way.
      if (q.correctOption !== null && random.int(10) < 6)
        return { questionId: q.id, choice: q.correctOption };
      return { questionId: q.id, choice: random.int(q.options.length) };
    });
    const result = await games.submit(bot.id, gameId, randomUUID(), answers);
    if (result.replayed) return;
    this.app.events.emit('game:submitted', { gameId, userId: bot.id });
    if (result.justCompleted) this.app.events.emit('game:completed', { gameId });
  }

  /** A reaction on one answer and a line in the chat. */
  private async chat(gameId: string) {
    const { prisma, games } = this.app.deps;
    const game = await prisma.game.findUnique({ where: { id: gameId }, include: { questions: true } });
    if (!game) return;
    const bot = await this.bot(game.pairId);
    if (!bot) return;

    const question = pick(game.questions);
    const emoji = pick(REACTIONS);
    await games.react(bot.id, gameId, question.id, emoji);
    this.app.events.emit('game:social', {
      gameId,
      pairId: game.pairId,
      userId: bot.id,
      kind: 'reaction',
      text: emoji,
    });

    const summary = (await games.view(gameId, bot.id)).summary as { matches?: number; total?: number } | null;
    const ratio = summary?.total ? (summary.matches ?? 0) / summary.total : null;
    const text = pick(ratio === null ? CHAT.any : ratio >= 0.6 ? CHAT.close : CHAT.apart);
    await games.comment(bot.id, gameId, text);
    this.app.events.emit('game:social', {
      gameId,
      pairId: game.pairId,
      userId: bot.id,
      kind: 'comment',
      text,
    });
  }

  /** Makes the bot's arcade move when it's its turn. */
  private async play(matchId: string) {
    const { prisma, arcade } = this.app.deps;
    const match = await prisma.match.findUnique({ where: { id: matchId } });
    if (!match || match.status !== 'ACTIVE') return;
    const bot = await this.bot(match.pairId);
    if (!bot) return;
    const seat = match.players.indexOf(bot.id) as Seat;
    const engine = ENGINES[match.kind];
    const state = engine.settle ? engine.settle(match.state, random) : match.state;
    if (seat < 0 || engine.outcome(state).turn !== seat) return;

    const level = (match.settings as MatchSettings).botLevel ?? 'normal';
    const move = botMove(match.kind, state, seat, random, level);
    if (move === null) return;
    try {
      await arcade.move(bot.id, matchId, match.version, move);
    } catch {
      // The board moved on meanwhile; the resulting update brings us back here.
      return;
    }
    this.app.events.emit('match:updated', { matchId });
  }

  private async patBack(pairId: string, by: string) {
    const bot = await this.bot(pairId);
    if (!bot || bot.id === by) return;
    try {
      await this.app.deps.pets.pat(bot.id);
    } catch {
      return; // Already patted today.
    }
    this.app.events.emit('pet:changed', { pairId, userId: bot.id, kind: 'pat' });
  }
}
