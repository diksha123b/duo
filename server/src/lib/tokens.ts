import { createHash, randomBytes, randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import type { PrismaClient } from '@prisma/client';
import type { Config } from '../config.js';
import { unauthorized } from './errors.js';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

export function signAccessToken(config: Config, userId: string): string {
  return jwt.sign({}, config.JWT_ACCESS_SECRET, {
    subject: userId,
    expiresIn: config.ACCESS_TOKEN_TTL_SECONDS,
    algorithm: 'HS256',
  });
}

export function verifyAccessToken(config: Config, token: string): string {
  try {
    const payload = jwt.verify(token, config.JWT_ACCESS_SECRET, { algorithms: ['HS256'] });
    if (typeof payload === 'string' || !payload.sub) throw new Error('no subject');
    return payload.sub;
  } catch {
    throw unauthorized('INVALID_ACCESS_TOKEN', 'Access token is invalid or expired');
  }
}

// Refresh tokens are opaque random strings; only their hash is stored.
// Each refresh rotates the token. Presenting an already-rotated token means
// it leaked, so the whole family (that login session) is revoked.
export class TokenService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly config: Config,
  ) {}

  async issue(userId: string, familyId: string = randomUUID()): Promise<TokenPair> {
    const refreshToken = randomBytes(48).toString('base64url');
    await this.prisma.refreshToken.create({
      data: {
        userId,
        familyId,
        tokenHash: sha256(refreshToken),
        expiresAt: new Date(Date.now() + this.config.REFRESH_TOKEN_TTL_DAYS * 86_400_000),
      },
    });
    return {
      accessToken: signAccessToken(this.config, userId),
      refreshToken,
      expiresIn: this.config.ACCESS_TOKEN_TTL_SECONDS,
    };
  }

  async rotate(refreshToken: string): Promise<{ userId: string; tokens: TokenPair }> {
    const record = await this.prisma.refreshToken.findUnique({ where: { tokenHash: sha256(refreshToken) } });
    if (!record) throw unauthorized('INVALID_REFRESH_TOKEN', 'Refresh token is invalid');

    // Conditional update: of two concurrent refreshes with the same token,
    // exactly one wins; the loser is treated as reuse.
    const { count } = await this.prisma.refreshToken.updateMany({
      where: { id: record.id, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (count === 0) {
      await this.revokeFamily(record.familyId);
      throw unauthorized('REFRESH_TOKEN_REUSED', 'Session was revoked, please sign in again');
    }
    if (record.expiresAt < new Date()) {
      throw unauthorized('REFRESH_TOKEN_EXPIRED', 'Session expired, please sign in again');
    }
    return { userId: record.userId, tokens: await this.issue(record.userId, record.familyId) };
  }

  async revoke(refreshToken: string): Promise<void> {
    const record = await this.prisma.refreshToken.findUnique({ where: { tokenHash: sha256(refreshToken) } });
    if (record) await this.revokeFamily(record.familyId);
  }

  private async revokeFamily(familyId: string): Promise<void> {
    await this.prisma.refreshToken.updateMany({
      where: { familyId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }
}
