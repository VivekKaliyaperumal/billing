import { NestFastifyApplication } from '@nestjs/platform-fastify';
import { randomUUID } from 'node:crypto';
import { createApp } from '../src/app.factory';
import { PrismaService } from '../src/common/prisma.service';

/** Response with the parsed JSON body. */
export interface Res<T = any> {
  status: number;
  body: T;
  headers: Record<string, string | string[] | undefined>;
}

export interface TestShop {
  token: string;
  refreshToken: string;
  shopId: string;
  userId: string;
  email: string;
  password: string;
}

export class Api {
  constructor(readonly app: NestFastifyApplication) {}

  async call<T = any>(
    method: 'GET' | 'POST' | 'PATCH' | 'DELETE',
    url: string,
    opts: { token?: string; body?: unknown; headers?: Record<string, string> } = {},
  ): Promise<Res<T>> {
    const res = await this.app.inject({
      method,
      url: `/api/v1${url}`,
      headers: {
        ...(opts.token ? { authorization: `Bearer ${opts.token}` } : {}),
        ...(opts.body !== undefined ? { 'content-type': 'application/json' } : {}),
        ...opts.headers,
      },
      payload: opts.body === undefined ? undefined : JSON.stringify(opts.body),
    });
    return {
      status: res.statusCode,
      body: res.body ? (safeJson(res.body) as T) : (undefined as T),
      headers: res.headers as Res['headers'],
    };
  }

  get<T = any>(url: string, token?: string) {
    return this.call<T>('GET', url, { token });
  }
  post<T = any>(url: string, body: unknown, token?: string) {
    return this.call<T>('POST', url, { token, body });
  }
  patch<T = any>(url: string, body: unknown, token?: string) {
    return this.call<T>('PATCH', url, { token, body });
  }
  del<T = any>(url: string, token?: string) {
    return this.call<T>('DELETE', url, { token });
  }

  /** Signs up a new shop as the mobile client (tokens in the body). */
  async signup(overrides: Record<string, unknown> = {}): Promise<TestShop> {
    const email = `owner-${randomUUID()}@example.com`;
    const password = 'correct horse battery';
    const res = await this.post('/auth/signup', {
      shopName: 'Test Shop',
      name: 'Owner',
      email,
      password,
      client: 'mobile',
      ...overrides,
    });
    if (res.status !== 201) throw new Error(`signup failed: ${res.status} ${JSON.stringify(res.body)}`);
    return {
      token: res.body.accessToken,
      refreshToken: res.body.refreshToken,
      shopId: res.body.shop.id,
      userId: res.body.user.id,
      email,
      password,
    };
  }

  /** Adds a cashier to the shop and signs them in. */
  async cashier(owner: TestShop): Promise<{ token: string; id: string }> {
    const email = `cashier-${randomUUID()}@example.com`;
    const created = await this.post('/staff', { name: 'Cashier', email, password: 'cashier password' }, owner.token);
    if (created.status !== 201) throw new Error(`staff create failed: ${JSON.stringify(created.body)}`);
    const login = await this.post('/auth/login', { email, password: 'cashier password', client: 'mobile' });
    return { token: login.body.accessToken, id: created.body.id };
  }

  async product(token: string, fields: { name?: string; priceMinor?: number; stock?: number; id?: string } = {}) {
    const res = await this.post('/products', { name: 'Milk 1L', priceMinor: 6000, stock: 10, ...fields }, token);
    if (res.status !== 201) throw new Error(`product create failed: ${JSON.stringify(res.body)}`);
    return res.body as { id: string; name: string; priceMinor: number; stock: number; usageCount: number };
  }
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

/** Boots the real app against the test database, emptied first. */
export async function setup(): Promise<{ app: NestFastifyApplication; api: Api; prisma: PrismaService }> {
  const app = await createApp({ logger: false, docs: false });
  await app.init();
  await app.getHttpAdapter().getInstance().ready();
  const prisma = app.get(PrismaService);
  await prisma.$executeRawUnsafe(
    'TRUNCATE "shops", "processed_ops", "customer_aliases" RESTART IDENTITY CASCADE',
  );
  return { app, api: new Api(app), prisma };
}

export function uuid(): string {
  return randomUUID();
}
