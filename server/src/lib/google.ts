import { OAuth2Client } from 'google-auth-library';
import { unauthorized } from './errors.js';

export interface GoogleIdentity {
  googleId: string;
  email: string;
  name?: string;
  picture?: string;
}

// Injected into the app so tests can swap in a fake without calling Google.
export type GoogleVerifier = (idToken: string) => Promise<GoogleIdentity>;

export function createGoogleVerifier(clientIds: string[]): GoogleVerifier {
  const client = new OAuth2Client();
  return async (idToken) => {
    if (clientIds.length === 0) throw unauthorized('GOOGLE_DISABLED', 'Google sign-in is not configured');
    let payload;
    try {
      const ticket = await client.verifyIdToken({ idToken, audience: clientIds });
      payload = ticket.getPayload();
    } catch {
      throw unauthorized('INVALID_GOOGLE_TOKEN', 'Google token could not be verified');
    }
    if (!payload?.sub || !payload.email || !payload.email_verified) {
      throw unauthorized('INVALID_GOOGLE_TOKEN', 'Google account has no verified email');
    }
    return { googleId: payload.sub, email: payload.email, name: payload.name, picture: payload.picture };
  };
}
