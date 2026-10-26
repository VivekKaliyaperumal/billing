export interface AppConfig {
  port: number;
  jwtAccessSecret: string;
  corsOrigins: string[];
  cookieSecure: boolean;
  production: boolean;
}

/**
 * Reads and checks the environment once. In production a missing or
 * placeholder secret stops the server rather than running insecurely.
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const production = env.NODE_ENV === 'production';
  const secret = env.JWT_ACCESS_SECRET ?? '';
  if (!env.DATABASE_URL) throw new Error('DATABASE_URL is not set');
  if (!secret) throw new Error('JWT_ACCESS_SECRET is not set');
  if (production && (secret.length < 32 || secret.startsWith('change-me'))) {
    throw new Error('JWT_ACCESS_SECRET must be a random string of at least 32 characters in production');
  }
  return {
    port: Number(env.PORT ?? 3100),
    jwtAccessSecret: secret,
    corsOrigins: (env.CORS_ORIGINS ?? '')
      .split(',')
      .map((o) => o.trim())
      .filter(Boolean),
    cookieSecure: env.COOKIE_SECURE === 'true',
    production,
  };
}
