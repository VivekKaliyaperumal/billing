import { NestFastifyApplication } from '@nestjs/platform-fastify';
import { Api, setup } from './helpers';

describe('auth, staff and shop settings', () => {
  let app: NestFastifyApplication;
  let api: Api;

  beforeAll(async () => {
    ({ app, api } = await setup());
  });
  afterAll(() => app.close());

  it('signs up a shop with its owner and returns mobile tokens', async () => {
    const res = await api.post('/auth/signup', {
      shopName: 'Sri Lakshmi Stores',
      name: 'Asha',
      email: 'Asha@Example.com',
      password: 'longenough',
      currency: 'INR',
      client: 'mobile',
    });
    expect(res.status).toBe(201);
    expect(res.body.user).toMatchObject({ email: 'asha@example.com', role: 'owner' });
    expect(res.body.shop).toMatchObject({ name: 'Sri Lakshmi Stores', currency: 'INR', currencySymbol: '₹' });
    expect(res.body.accessToken).toEqual(expect.any(String));
    expect(res.body.refreshToken).toEqual(expect.any(String));
    // The password hash never leaves the server.
    expect(JSON.stringify(res.body)).not.toContain('passwordHash');

    const dup = await api.post('/auth/signup', {
      shopName: 'Other',
      name: 'Asha',
      email: 'asha@example.com',
      password: 'longenough',
    });
    expect(dup.status).toBe(409);
    expect(dup.body.code).toBe('email_taken');
  });

  it('validates signup input', async () => {
    const res = await api.post('/auth/signup', { shopName: '', name: 'A', email: 'not-an-email', password: 'short' });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('validation_failed');
    expect(res.body.issues.map((i: { path: string }) => i.path)).toEqual(
      expect.arrayContaining(['shopName', 'email', 'password']),
    );
  });

  it('logs in, rejects a wrong password, and returns /me', async () => {
    const shop = await api.signup();
    expect((await api.post('/auth/login', { email: shop.email, password: 'wrong password' })).status).toBe(401);
    expect((await api.post('/auth/login', { email: 'nobody@example.com', password: 'whatever1' })).status).toBe(401);
    const login = await api.post('/auth/login', { email: shop.email, password: shop.password, client: 'mobile' });
    expect(login.status).toBe(200);
    const me = await api.get('/auth/me', login.body.accessToken);
    expect(me.status).toBe(200);
    expect(me.body.user.id).toBe(shop.userId);
    expect((await api.get('/auth/me')).status).toBe(401);
    expect((await api.get('/auth/me', 'garbage')).status).toBe(401);
  });

  it('rotates refresh tokens and revokes the login when an old one is reused', async () => {
    const shop = await api.signup();
    const first = await api.post('/auth/refresh', { refreshToken: shop.refreshToken, client: 'mobile' });
    expect(first.status).toBe(200);
    const next = first.body.refreshToken;
    expect(next).not.toBe(shop.refreshToken);

    // Replaying the rotated token looks like theft: the whole family is revoked.
    expect((await api.post('/auth/refresh', { refreshToken: shop.refreshToken, client: 'mobile' })).status).toBe(401);
    expect((await api.post('/auth/refresh', { refreshToken: next, client: 'mobile' })).status).toBe(401);
  });

  it('logs out by revoking the refresh token', async () => {
    const shop = await api.signup();
    expect((await api.post('/auth/logout', { refreshToken: shop.refreshToken })).status).toBe(204);
    expect((await api.post('/auth/refresh', { refreshToken: shop.refreshToken, client: 'mobile' })).status).toBe(401);
  });

  it('changes the password and ends other sessions', async () => {
    const shop = await api.signup();
    const bad = await api.post('/auth/change-password', { currentPassword: 'nope', newPassword: 'new password 1' }, shop.token);
    expect(bad.status).toBe(401);
    const ok = await api.post(
      '/auth/change-password',
      { currentPassword: shop.password, newPassword: 'new password 1', client: 'mobile' },
      shop.token,
    );
    expect(ok.status).toBe(200);
    expect((await api.post('/auth/refresh', { refreshToken: shop.refreshToken, client: 'mobile' })).status).toBe(401);
    expect((await api.post('/auth/login', { email: shop.email, password: 'new password 1' })).status).toBe(200);
  });

  describe('web cookies', () => {
    it('sets httpOnly cookies, keeps tokens out of the body, and requires X-Requested-With on writes', async () => {
      const email = 'web-owner@example.com';
      const signup = await api.post('/auth/signup', { shopName: 'Web', name: 'W', email, password: 'longenough' });
      expect(signup.status).toBe(201);
      expect(signup.body.accessToken).toBeUndefined();
      const cookies = ([] as string[]).concat(signup.headers['set-cookie'] as string[]);
      expect(cookies.find((c) => c.startsWith('tb_access='))).toMatch(/HttpOnly/i);
      expect(cookies.find((c) => c.startsWith('tb_refresh='))).toMatch(/Path=\/api\/v1\/auth/);
      const cookie = cookies.map((c) => c.split(';')[0]).join('; ');

      const me = await api.call('GET', '/auth/me', { headers: { cookie } });
      expect(me.status).toBe(200);

      const body = { name: 'Bread', priceMinor: 4500, stock: 5 };
      const noHeader = await api.call('POST', '/products', { body, headers: { cookie } });
      expect(noHeader.status).toBe(403);
      const withHeader = await api.call('POST', '/products', {
        body,
        headers: { cookie, 'x-requested-with': 'XMLHttpRequest' },
      });
      expect(withHeader.status).toBe(201);

      const refreshed = await api.call('POST', '/auth/refresh', { body: {}, headers: { cookie } });
      expect(refreshed.status).toBe(200);
      expect(refreshed.body.user.email).toBe(email);
    });
  });

  describe('staff', () => {
    it('lets the owner add, update, reset and disable a cashier, who cannot do owner work', async () => {
      const owner = await api.signup();
      const cashier = await api.cashier(owner);

      const list = await api.get('/staff', owner.token);
      expect(list.body.map((s: { role: string }) => s.role).sort()).toEqual(['cashier', 'owner']);

      // Cashier: can sell and read, cannot manage staff, products or settings.
      expect((await api.get('/staff', cashier.token)).status).toBe(403);
      expect((await api.post('/products', { name: 'X', priceMinor: 1, stock: 1 }, cashier.token)).status).toBe(403);
      expect((await api.patch('/shop', { shopName: 'Hacked' }, cashier.token)).status).toBe(403);
      expect((await api.get('/products', cashier.token)).status).toBe(200);
      expect((await api.get('/shop', cashier.token)).status).toBe(200);

      // Role change takes effect on the next request, without a new login.
      expect((await api.patch(`/staff/${cashier.id}`, { role: 'owner' }, owner.token)).status).toBe(200);
      expect((await api.get('/staff', cashier.token)).status).toBe(200);

      // Disabling ends access immediately.
      expect((await api.patch(`/staff/${cashier.id}`, { isActive: false }, owner.token)).status).toBe(200);
      expect((await api.get('/products', cashier.token)).status).toBe(401);
    });

    it('stops the owner locking themselves out', async () => {
      const owner = await api.signup();
      const self = await api.patch(`/staff/${owner.userId}`, { isActive: false }, owner.token);
      expect(self.status).toBe(409);
      expect(self.body.code).toBe('self_lockout');
      expect((await api.del(`/staff/${owner.userId}`, owner.token)).status).toBe(409);
    });

    it('does not let one shop touch another shop’s staff', async () => {
      const a = await api.signup();
      const b = await api.signup();
      expect((await api.patch(`/staff/${b.userId}`, { name: 'Mine now' }, a.token)).status).toBe(404);
    });
  });

  describe('shop settings', () => {
    it('updates name and currency, sets the symbol, and ignores a blank name', async () => {
      const owner = await api.signup();
      const res = await api.patch('/shop', { shopName: 'New Name', currency: 'USD' }, owner.token);
      expect(res.body).toMatchObject({ name: 'New Name', currency: 'USD', currencySymbol: '$' });
      const blank = await api.patch('/shop', { shopName: '   ' }, owner.token);
      expect(blank.body.name).toBe('New Name');
      expect((await api.patch('/shop', { currency: 'JPY' }, owner.token)).status).toBe(400);
    });
  });
});
