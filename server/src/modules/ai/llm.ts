import Anthropic from '@anthropic-ai/sdk';
import { betaZodOutputFormat } from '@anthropic-ai/sdk/helpers/beta/zod';
import { z } from 'zod';

// The shape requested from the model. Kept deliberately loose (no length
// limits, no cross-field rules) because structured outputs only constrain the
// JSON shape; the full rules live in gameContentSchema and are checked after.
export const llmGameSchema = z.object({
  title: z.string(),
  questions: z.array(
    z.object({
      prompt: z.string(),
      options: z.array(z.string()),
      correctOption: z.number().int().nullable(),
      about: z.enum(['A', 'B']).nullable(),
      explanation: z.string().nullable(),
    }),
  ),
});
export type LlmGame = z.infer<typeof llmGameSchema>;

export interface LlmResult {
  output: LlmGame | null;
  model: string;
  inputTokens: number;
  outputTokens: number;
  refused: boolean;
}

// The only thing the rest of the app knows about the LLM; tests pass a fake.
export type LlmClient = (args: {
  system: string;
  prompt: string;
  signal?: AbortSignal;
}) => Promise<LlmResult>;

export function createClaudeClient(opts: {
  apiKey?: string;
  model: string;
  effort: 'low' | 'medium' | 'high';
}): LlmClient {
  const client = new Anthropic({ apiKey: opts.apiKey, maxRetries: 1 });
  return async ({ system, prompt, signal }) => {
    const res = await client.beta.messages.parse(
      {
        model: opts.model,
        max_tokens: 16000,
        system,
        messages: [{ role: 'user', content: prompt }],
        output_config: { effort: opts.effort, format: betaZodOutputFormat(llmGameSchema) },
        // If a safety classifier declines, the API retries on a suitable model in the same call.
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default',
      },
      { signal },
    );
    return {
      output: res.stop_reason === 'refusal' ? null : (res.parsed_output ?? null),
      model: res.model,
      inputTokens: res.usage.input_tokens,
      outputTokens: res.usage.output_tokens,
      refused: res.stop_reason === 'refusal',
    };
  };
}

// USD per million tokens, for the generation cost log. Unknown models log no cost.
const PRICING: Record<string, { input: number; output: number }> = {
  'claude-opus-5-5': { input: 4, output: 20 },
  'claude-sonnet-5-5': { input: 2, output: 10 },
  'claude-haiku-5-5': { input: 0.1, output: 0.5 },
};

export function costUsd(model: string, inputTokens: number, outputTokens: number): number | null {
  const price = PRICING[model];
  if (!price) return null;
  return (inputTokens * price.input + outputTokens * price.output) / 1_000_000;
}
