import type { PrismaClient } from '@prisma/client';
import type { FastifyBaseLogger } from 'fastify';
import type { Redis } from 'ioredis';
import webpush from 'web-push';

export interface PushPayload {
  title: string;
  body: string;
  /** Where tapping the notification opens, e.g. "/#/game". */
  url: string;
  /** Notifications with the same tag replace each other instead of stacking. */
  tag?: string;
}

export interface StoredSubscription {
  endpoint: string;
  p256dh: string;
  auth: string;
}

/** Sends one push; resolves to false when the subscription is gone for good. */
export type PushSender = (sub: StoredSubscription, payload: PushPayload) => Promise<boolean>;

export function createWebPushSender(keys: {
  publicKey: string;
  privateKey: string;
  subject: string;
}): PushSender {
  webpush.setVapidDetails(keys.subject, keys.publicKey, keys.privateKey);
  return async (sub, payload) => {
    try {
      await webpush.sendNotification(
        { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
        JSON.stringify(payload),
        { TTL: 6 * 3600 },
      );
      return true;
    } catch (err) {
      // 404/410: the browser dropped this subscription.
      const status = (err as { statusCode?: number }).statusCode;
      if (status === 404 || status === 410) return false;
      throw err;
    }
  };
}

/**
 * Notifies a player who isn't currently in the app. Someone with the app
 * open already sees the change live, so they are skipped.
 */
export class Notifier {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly redis: Redis,
    private readonly send: PushSender | null,
    private readonly log: FastifyBaseLogger,
  ) {}

  get enabled() {
    return this.send !== null;
  }

  async notify(userId: string, payload: PushPayload) {
    if (!this.send) return;
    const online = Number((await this.redis.hget('presence:conns', userId)) ?? 0) > 0;
    if (online) return;
    const subs = await this.prisma.pushSubscription.findMany({ where: { userId } });
    for (const sub of subs) {
      try {
        if (!(await this.send(sub, payload))) {
          await this.prisma.pushSubscription.deleteMany({ where: { endpoint: sub.endpoint } });
        }
      } catch (err) {
        this.log.warn({ err, userId }, 'push failed');
      }
    }
  }
}
