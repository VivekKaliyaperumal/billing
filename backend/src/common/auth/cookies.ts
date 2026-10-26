export const ACCESS_COOKIE = 'tb_access';
export const REFRESH_COOKIE = 'tb_refresh';
/** The refresh cookie is only sent to the auth routes. */
export const REFRESH_COOKIE_PATH = '/api/v1/auth';
/** Header the web client sends on writes; a cross-site form cannot set it. */
export const CSRF_HEADER = 'x-requested-with';
