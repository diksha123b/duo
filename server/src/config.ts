import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  JWT_ACCESS_SECRET: z.string().min(32),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().default(15 * 60),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().default(30),
  // Comma-separated OAuth client IDs (web + Android) accepted as Google ID token audiences.
  GOOGLE_CLIENT_IDS: z
    .string()
    .default('')
    .transform((s) =>
      s
        .split(',')
        .map((x) => x.trim())
        .filter(Boolean),
    ),
  // AI generation is on when a key is set; otherwise every game comes from the bank.
  ANTHROPIC_API_KEY: z.string().optional(),
  LLM_MODEL: z.string().default('claude-opus-5-5'),
  LLM_EFFORT: z.enum(['low', 'medium', 'high']).default('medium'),
  // A player is waiting on on-demand generation; the background job can take longer.
  LLM_REQUEST_TIMEOUT_MS: z.coerce.number().default(15_000),
  LLM_JOB_TIMEOUT_MS: z.coerce.number().default(120_000),
  CORS_ORIGINS: z
    .string()
    .default('*')
    .transform((s) => (s === '*' ? true : s.split(',').map((x) => x.trim()))),
});

export type Config = z.infer<typeof schema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    throw new Error(`Invalid environment: ${z.prettifyError(parsed.error)}`);
  }
  return parsed.data;
}
