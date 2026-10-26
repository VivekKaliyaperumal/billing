/**
 * Small typed wrapper around fetch for the billing API.
 *
 * The session lives in httpOnly cookies set by the server, so no token is
 * ever visible to JavaScript. Every request sends X-Requested-With, which the
 * server requires on cookie-authenticated writes (CSRF protection). A 401 is
 * retried once after refreshing the session.
 */

const API_BASE = `${import.meta.env.VITE_API_URL ?? ''}/api/v1`;

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

type Method = 'GET' | 'POST' | 'PATCH' | 'DELETE';

const unauthorizedListeners = new Set<() => void>();

/** Called when the session has ended and could not be refreshed. */
export function onUnauthorized(listener: () => void): () => void {
  unauthorizedListeners.add(listener);
  return () => unauthorizedListeners.delete(listener);
}

let refreshing: Promise<boolean> | null = null;

/** One refresh at a time, shared by every request that hit a 401. */
function refreshSession(): Promise<boolean> {
  refreshing ??= send('POST', '/auth/refresh', {})
    .then((res) => res.ok)
    .catch(() => false)
    .finally(() => {
      refreshing = null;
    });
  return refreshing;
}

function send(method: Method, path: string, body?: unknown): Promise<Response> {
  return fetch(`${API_BASE}${path}`, {
    method,
    credentials: 'include',
    headers: {
      'X-Requested-With': 'XMLHttpRequest',
      ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

export async function api<T>(method: Method, path: string, body?: unknown): Promise<T> {
  let res: Response;
  try {
    res = await send(method, path, body);
    if (res.status === 401 && !path.startsWith('/auth/')) {
      if (await refreshSession()) {
        res = await send(method, path, body);
      }
      if (res.status === 401) unauthorizedListeners.forEach((l) => l());
    }
  } catch {
    throw new ApiError(0, 'network', 'Cannot reach the server. Check your internet connection and try again.');
  }

  if (res.status === 204) return undefined as T;
  const data: unknown = await res.json().catch(() => undefined);
  if (!res.ok) {
    const err = (data ?? {}) as { code?: string; message?: string | string[] };
    const message = Array.isArray(err.message) ? err.message[0] : err.message;
    throw new ApiError(res.status, err.code ?? 'error', message ?? 'Something went wrong. Please try again.', data as Record<string, unknown>);
  }
  return data as T;
}

/** The message to show for any error from `api`. */
export function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : 'Something went wrong. Please try again.';
}
