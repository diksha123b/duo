import { execSync } from 'node:child_process';
import { TEST_ENV } from './env.js';

export default function setup() {
  execSync('npx prisma migrate deploy', { env: { ...process.env, ...TEST_ENV }, stdio: 'inherit' });
}
