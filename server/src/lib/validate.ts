import { z } from 'zod';
import { AppError } from './errors.js';

export function parse<T extends z.ZodType>(schema: T, data: unknown): z.infer<T> {
  const result = schema.safeParse(data);
  if (!result.success) {
    const first = result.error.issues[0];
    const where = first?.path.length ? `${first.path.join('.')}: ` : '';
    throw new AppError(400, 'VALIDATION_ERROR', `${where}${first?.message ?? 'Invalid request'}`);
  }
  return result.data;
}
