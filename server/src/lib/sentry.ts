import * as Sentry from '@sentry/node';

// No-op without a DSN, so local dev and tests never report.
export function initSentry(dsn: string | undefined, environment: string, service: 'api' | 'worker') {
  if (!dsn) return;
  Sentry.init({ dsn, environment, initialScope: { tags: { service } }, tracesSampleRate: 0.1 });
}

export function reportError(err: unknown, context: Record<string, unknown> = {}) {
  Sentry.captureException(err, { extra: context });
}
