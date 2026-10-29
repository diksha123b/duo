export const TEST_ENV = {
  NODE_ENV: 'test',
  DATABASE_URL: process.env.TEST_DATABASE_URL ?? 'postgresql://duo:duo@localhost:5432/duo_test',
  REDIS_URL: process.env.TEST_REDIS_URL ?? 'redis://localhost:6379/1',
  JWT_ACCESS_SECRET: 'test-access-secret-0123456789abcdefghij',
  GOOGLE_CLIENT_IDS: 'test-client-id',
};
