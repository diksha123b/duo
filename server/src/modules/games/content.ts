import { z } from 'zod';

// The one shape every game takes, whether it comes from the question bank or
// the LLM. Day 5 validates LLM output against exactly this schema.

const option = z.string().trim().min(1).max(80);

const question = z.object({
  prompt: z.string().trim().min(5).max(200),
  options: z.array(option).min(2).max(4),
  // SHARED_TRIVIA only: index of the right option.
  correctOption: z.number().int().min(0).optional(),
  // WHO_KNOWS_WHOM only: which partner the question is about.
  about: z.enum(['A', 'B']).optional(),
});

export const gameContentSchema = z
  .object({
    type: z.enum(['WHO_KNOWS_WHOM', 'WOULD_YOU_RATHER', 'SHARED_TRIVIA']),
    title: z.string().trim().min(3).max(80),
    questions: z.array(question).min(3).max(8),
  })
  .superRefine((game, ctx) => {
    game.questions.forEach((q, i) => {
      const at = (msg: string) => ctx.addIssue({ code: 'custom', path: ['questions', i], message: msg });
      if (new Set(q.options.map((o) => o.toLowerCase())).size !== q.options.length) at('duplicate options');
      if (game.type === 'WOULD_YOU_RATHER' && q.options.length !== 2)
        at('would-you-rather needs exactly 2 options');
      if (game.type === 'SHARED_TRIVIA') {
        if (q.correctOption === undefined) at('trivia needs correctOption');
        else if (q.correctOption >= q.options.length) at('correctOption out of range');
      }
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
export type GameTypeName = GameContent['type'];
export const GAME_TYPES: GameTypeName[] = ['WHO_KNOWS_WHOM', 'WOULD_YOU_RATHER', 'SHARED_TRIVIA'];
