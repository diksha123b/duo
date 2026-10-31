import type { Relationship } from '@prisma/client';

// A bank question. `only` limits it to some relationships (e.g. date ideas
// are for partners). Quiz answers are written first and shuffled when picked.
export type Q = {
  prompt: string;
  options: string[];
  correctOption?: number;
  explanation?: string;
  only?: Relationship[];
};

export const PARTNERS_ONLY: Relationship[] = ['PARTNERS'];
export const FAMILY: Relationship[] = ['PARENT_CHILD', 'SIBLINGS'];

/**
 * A question with a right answer. The explanation is shown with the results:
 * it should make the answer feel fair, including to someone who picked one
 * of the tempting wrong options.
 */
export const quiz = (
  prompt: string,
  answer: string,
  wrong: [string, string, string],
  explanation: string,
): Q => ({
  prompt,
  options: [answer, ...wrong],
  correctOption: 0,
  explanation,
});

export const wyr = (a: string, b: string, only?: Relationship[]): Q => ({
  prompt: 'Would you rather…',
  options: [a, b],
  ...(only && { only }),
});

export const ask = (prompt: string, options: string[], only?: Relationship[]): Q => ({
  prompt,
  options,
  ...(only && { only }),
});
