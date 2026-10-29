import type { FastifyReply, FastifyRequest } from 'fastify';
import type { Redis } from 'ioredis';
import { AppError } from './errors.js';

export interface RateLimitRule {
  name: string;
  max: number;
  windowSeconds: number;
  // Defaults to the client IP; authenticated routes key on the user instead.
  key?: (req: FastifyRequest) => string;
}

// Fixed-window counter in Redis. INCR + EXPIRE NX in one round trip keeps it
// atomic and works the same across multiple API instances.
export function rateLimit(redis: Redis, rule: RateLimitRule) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const id = rule.key ? rule.key(req) : req.ip;
    const key = `rl:${rule.name}:${id}`;
    const results = await redis.multi().incr(key).expire(key, rule.windowSeconds, 'NX').ttl(key).exec();
    const count = Number(results?.[0]?.[1] ?? 0);
    const ttl = Number(results?.[2]?.[1] ?? rule.windowSeconds);

    reply.header('X-RateLimit-Limit', rule.max);
    reply.header('X-RateLimit-Remaining', Math.max(0, rule.max - count));
    if (count > rule.max) {
      reply.header('Retry-After', Math.max(1, ttl));
      throw new AppError(429, 'RATE_LIMITED', 'Too many attempts, please wait a moment');
    }
  };
}
