import { z } from 'zod';

// The one shape every game takes, whether it comes from the question bank or
// the LLM. LLM output is validated against exactly this schema.

const option = z.string().trim().min(1).max(80);

const question = z.object({
  // Short enough minimum for an emoji clue like "🦁👑 (movie)".
  prompt: z.string().trim().min(3).max(200),
  options: z.array(option).min(2).max(5),
  // SHARED_TRIVIA and EMOJI_DECODE: index of the right option.
  correctOption: z.number().int().min(0).optional(),
  // WHO_KNOWS_WHOM only: which partner the question is about.
  about: z.enum(['A', 'B']).optional(),
  // SHARED_TRIVIA and EMOJI_DECODE: why the answer is right, shown with the results.
  explanation: z.string().trim().min(1).max(400).optional(),
});

export const GAME_TYPES = [
  'WHO_KNOWS_WHOM',
  'WOULD_YOU_RATHER',
  'SHARED_TRIVIA',
  'EMOJI_DECODE',
  'AGREE_O_METER',
  'RANK_IT',
] as const;
export type GameTypeName = (typeof GAME_TYPES)[number];

// Agree-o-meter always uses this scale; providers set it rather than trusting
// generated labels, so scoring by index distance stays meaningful.
export const AGREE_SCALE = ['Strongly disagree', 'Disagree', 'Not sure', 'Agree', 'Strongly agree'];

const hasAnswerKey = (type: GameTypeName) => type === 'SHARED_TRIVIA' || type === 'EMOJI_DECODE';

export const gameContentSchema = z
  .object({
    type: z.enum(GAME_TYPES),
    title: z.string().trim().min(3).max(80),
    questions: z.array(question).min(3).max(8),
  })
  .superRefine((game, ctx) => {
    game.questions.forEach((q, i) => {
      const at = (msg: string) => ctx.addIssue({ code: 'custom', path: ['questions', i], message: msg });
      if (new Set(q.options.map((o) => o.toLowerCase())).size !== q.options.length) at('duplicate options');
      if (game.type === 'WOULD_YOU_RATHER' && q.options.length !== 2)
        at('would-you-rather needs exactly 2 options');
      if (hasAnswerKey(game.type)) {
        if (q.correctOption === undefined) at('needs correctOption');
        else if (q.correctOption >= q.options.length) at('correctOption out of range');
        if (!q.explanation) at('needs an explanation');
      }
      if (game.type === 'EMOJI_DECODE' && q.options.length !== 4) at('emoji decode needs exactly 4 options');
      if (game.type === 'AGREE_O_METER' && q.options.join('|') !== AGREE_SCALE.join('|'))
        at('agree-o-meter must use the standard scale');
      if (game.type === 'RANK_IT' && q.options.length !== 4) at('rank it needs exactly 4 items');
      if (game.type === 'WHO_KNOWS_WHOM' && !q.about) at('who-knows-whom needs about');
    });
    if (game.type === 'WHO_KNOWS_WHOM') {
      const a = game.questions.filter((q) => q.about === 'A').length;
      if (a === 0 || a === game.questions.length) {
        ctx.addIssue({ code: 'custom', path: ['questions'], message: 'questions must cover both partners' });
      }
    }
  });

export type GameContent = z.infer<typeof gameContentSchema>;
