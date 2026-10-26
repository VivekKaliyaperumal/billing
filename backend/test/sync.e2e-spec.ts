import { NestFastifyApplication } from '@nestjs/platform-fastify';
import { Api, setup, TestShop, uuid } from './helpers';

describe('offline sync, backup and restore', () => {
  let app: NestFastifyApplication;
  let api: Api;

  beforeAll(async () => {
    ({ app, api } = await setup());
  });
  afterAll(() => app.close());

  const push = (shop: TestShop | { token: string }, ops: { type: string; payload: unknown; opId?: string }[]) =>
    api.post(
      '/sync/push',
      { deviceId: 'phone-1', ops: ops.map((o) => ({ opId: o.opId ?? uuid(), type: o.type, payload: o.payload })) },
      shop.token,
    );

  const offlineSale = (items: { productId: string; name: string; priceMinor: number; quantity: number }[], extra = {}) => ({
    id: uuid(),
    date: new Date().toISOString(),
    items,
    ...extra,
  });

  it('applies queued ops in order and returns a result for each', async () => {
    const shop = await api.signup();
    const productId = uuid();
    const customerId = uuid();
    const res = await push(shop, [
      { type: 'product.upsert', payload: { id: productId, name: 'Rice 5kg', priceMinor: 32000, stock: 10 } },
      { type: 'customer.create', payload: { id: customerId, name: 'Gopal', phone: '98450 12345' } },
      {
        type: 'sale.create',
        payload: offlineSale([{ productId, name: 'Rice 5kg', priceMinor: 32000, quantity: 2 }], {
          customerId,
          credit: { id: uuid(), description: 'Sale #abcd1234', date: new Date().toISOString() },
        }),
      },
      { type: 'payment.create', payload: { id: uuid(), customerId, amountMinor: 20000, description: 'Cash' } },
      { type: 'settings.update', payload: { shopName: 'Gopal Rice Depot' } },
    ]);
    expect(res.status).toBe(200);
    expect(res.body.results.map((r: { status: string }) => r.status)).toEqual(['applied', 'applied', 'applied', 'applied', 'applied']);
    expect((await api.get(`/products/${productId}`, shop.token)).body).toMatchObject({ stock: 8, usageCount: 2 });
    const customer = await api.get(`/customers/${customerId}`, shop.token);
    expect(customer.body.pendingMinor).toBe(64000 - 20000);
    expect(customer.body.transactions.map((t: { type: string }) => t.type)).toEqual(['credit', 'payment']);
    expect((await api.get('/shop', shop.token)).body.name).toBe('Gopal Rice Depot');
  });

  it('applies a retried op only once', async () => {
    const shop = await api.signup();
    const p = await api.product(shop.token, { stock: 10 });
    const op = { opId: uuid(), type: 'sale.create', payload: offlineSale([{ productId: p.id, name: p.name, priceMinor: 6000, quantity: 3 }]) };
    const first = await push(shop, [op]);
    const again = await push(shop, [op]);
    expect(first.body.results[0]).toMatchObject({ status: 'applied' });
    expect(again.body.results[0]).toMatchObject({ status: 'applied', replayed: true });
    expect((await api.get(`/products/${p.id}`, shop.token)).body.stock).toBe(7);
    expect((await api.get('/sales', shop.token)).body.sales).toHaveLength(1);
  });

  it('accepts an offline sale that oversold, stops stock at 0 and flags the shortfall', async () => {
    const shop = await api.signup();
    const p = await api.product(shop.token, { name: 'Ghee 500ml', priceMinor: 45000, stock: 2 });
    // Another device sold one meanwhile.
    await api.post('/sales', { items: [{ productId: p.id, quantity: 1 }] }, shop.token);

    const sale = offlineSale([{ productId: p.id, name: 'Ghee 500ml', priceMinor: 44000, quantity: 3 }]);
    const res = await push(shop, [{ type: 'sale.create', payload: sale }]);
    expect(res.body.results[0].status).toBe('applied');
    expect(res.body.results[0].warnings).toEqual([
      'Ghee 500ml: 3 sold offline but only 1 were in stock. Stock is now 0; please recount.',
    ]);
    expect((await api.get(`/products/${p.id}`, shop.token)).body).toMatchObject({ stock: 0, usageCount: 4 });
    // Recorded at the price the customer was actually charged.
    const recorded = await api.get(`/sales/${sale.id}`, shop.token);
    expect(recorded.body).toMatchObject({ totalMinor: 132000, source: 'mobile' });
    expect(recorded.body.items[0]).toMatchObject({ quantity: 3, shortfall: 2 });
  });

  it('merges an offline stock edit with sales made elsewhere', async () => {
    const shop = await api.signup();
    const p = await api.product(shop.token, { stock: 10 });
    await api.post('/sales', { items: [{ productId: p.id, quantity: 4 }] }, shop.token); // server: 6
    // The phone saw 10 and restocked to 15 (+5) while offline.
    await push(shop, [{ type: 'product.upsert', payload: { id: p.id, name: 'Milk 1L', priceMinor: 6500, stock: 15, baseStock: 10 } }]);
    expect((await api.get(`/products/${p.id}`, shop.token)).body).toMatchObject({ stock: 11, priceMinor: 6500 });
  });

  it('merges a customer added on two devices with the same phone', async () => {
    const shop = await api.signup();
    const existing = (await api.post('/customers', { name: 'Fatima', phone: '9876500000' }, shop.token)).body;
    const p = await api.product(shop.token, { priceMinor: 1000, stock: 10 });
    const offlineId = uuid();
    const res = await push(shop, [
      { type: 'customer.create', payload: { id: offlineId, name: 'Fatima B', phone: '+9876500000'.slice(1) } },
      {
        type: 'sale.create',
        payload: offlineSale([{ productId: p.id, name: p.name, priceMinor: 1000, quantity: 2 }], { customerId: offlineId }),
      },
      { type: 'payment.create', payload: { id: uuid(), customerId: offlineId, amountMinor: 500, description: 'Cash' } },
    ]);
    expect(res.body.results[0]).toMatchObject({ status: 'applied', mergedInto: existing.id });
    expect(res.body.results[1]).toMatchObject({ status: 'applied', mergedInto: existing.id });
    expect(res.body.results[2].status).toBe('applied');
    expect((await api.get(`/customers/${existing.id}`, shop.token)).body.pendingMinor).toBe(1500);
    expect((await api.get('/customers', shop.token)).body).toHaveLength(1);
  });

  it('rejects a payment larger than the balance and owner-only ops from a cashier, and carries on', async () => {
    const owner = await api.signup();
    const cashier = await api.cashier(owner);
    const c = (await api.post('/customers', { name: 'Joseph', phone: '9000011111' }, owner.token)).body;
    const res = await push(cashier, [
      { type: 'payment.create', payload: { id: uuid(), customerId: c.id, amountMinor: 100, description: 'Cash' } },
      { type: 'product.upsert', payload: { id: uuid(), name: 'Sneaky', priceMinor: 1, stock: 1 } },
      { type: 'customer.update', payload: { id: c.id, name: 'Joseph M', phone: '9000011111' } },
      { type: 'sale.create', payload: { id: uuid() } },
    ]);
    expect(res.body.results.map((r: { status: string; code?: string }) => [r.status, r.code])).toEqual([
      ['rejected', 'payment_exceeds_pending'],
      ['rejected', 'forbidden'],
      ['applied', undefined],
      ['rejected', 'invalid'],
    ]);
    expect((await api.get(`/customers/${c.id}`, owner.token)).body.name).toBe('Joseph M');
    expect((await api.get('/products', owner.token)).body).toEqual([]);
  });

  it('restores a deleted customer who received an offline credit sale', async () => {
    const shop = await api.signup();
    const c = (await api.post('/customers', { name: 'Anil', phone: '9000022222' }, shop.token)).body;
    await api.del(`/customers/${c.id}`, shop.token);
    const p = await api.product(shop.token, { priceMinor: 700, stock: 5 });
    const res = await push(shop, [
      { type: 'sale.create', payload: offlineSale([{ productId: p.id, name: p.name, priceMinor: 700, quantity: 1 }], { customerId: c.id }) },
    ]);
    expect(res.body.results[0].warnings).toEqual(['Anil had been deleted and was restored because of an offline credit sale.']);
    expect((await api.get(`/customers/${c.id}`, shop.token)).body.pendingMinor).toBe(700);
  });

  describe('pull', () => {
    it('downloads everything first, then only what changed, including deletions', async () => {
      const shop = await api.signup();
      const p1 = await api.product(shop.token, { name: 'A' });
      const p2 = await api.product(shop.token, { name: 'B' });
      await api.post('/sales', { items: [{ productId: p1.id, quantity: 1 }], customer: { name: 'C', phone: '9555555555' } }, shop.token);

      const full = await api.get('/sync/pull', shop.token);
      expect(full.body.reset).toBe(true);
      expect(full.body.hasMore).toBe(false);
      expect(full.body.products.map((p: { id: string }) => p.id).sort()).toEqual([p1.id, p2.id].sort());
      expect(full.body.customers).toHaveLength(1);
      expect(full.body.sales).toHaveLength(1);
      expect(full.body.transactions).toHaveLength(1);
      expect(full.body.shop.name).toBe('Test Shop');

      const quiet = await api.get(`/sync/pull?cursor=${full.body.cursor}`, shop.token);
      expect(quiet.body).toMatchObject({ reset: false, hasMore: false, products: [], customers: [], sales: [], transactions: [] });
      expect(quiet.body.cursor).toBe(full.body.cursor);

      await api.del(`/products/${p2.id}`, shop.token);
      const delta = await api.get(`/sync/pull?cursor=${full.body.cursor}`, shop.token);
      expect(delta.body.reset).toBe(false);
      expect(delta.body.products).toEqual([expect.objectContaining({ id: p2.id, deleted: true })]);
      expect(delta.body.sales).toEqual([]);
    });

    it('pages without skipping or repeating a change', async () => {
      const shop = await api.signup();
      for (let i = 0; i < 7; i++) await api.product(shop.token, { name: `P${i}` });
      const seen: string[] = [];
      let cursor = '';
      for (let page = 0; page < 10; page++) {
        const res = await api.get(`/sync/pull?limit=3${cursor ? `&cursor=${cursor}` : ''}`, shop.token);
        seen.push(...res.body.products.map((p: { name: string }) => p.name));
        cursor = res.body.cursor;
        if (!res.body.hasMore) break;
      }
      expect(seen).toEqual(['P0', 'P1', 'P2', 'P3', 'P4', 'P5', 'P6']);
    });

    it('does not leak another shop’s changes', async () => {
      const a = await api.signup();
      const b = await api.signup();
      await api.product(a.token, { name: 'Secret' });
      const res = await api.get('/sync/pull', b.token);
      expect(res.body.products).toEqual([]);
    });
  });

  describe('backup and restore', () => {
    it('round-trips through the mobile backup format and makes devices reload', async () => {
      const shop = await api.signup();
      const p = await api.product(shop.token, { id: '1', name: 'Milk 1L', priceMinor: 6000, stock: 50 });
      await api.post('/sales', { items: [{ productId: p.id, quantity: 2 }], customer: { name: 'Uma', phone: '9666666666' } }, shop.token);
      const pulled = await api.get('/sync/pull', shop.token);

      const backup = await api.get('/backup', shop.token);
      expect(backup.body).toMatchObject({ app: 'thyantra_billing', formatVersion: 1 });
      expect(backup.body.products[0]).toMatchObject({ id: '1', priceMinor: 6000, stock: 48, usageCount: 2 });
      expect(backup.body.sales[0].items[0]).toMatchObject({ product: { id: '1', name: 'Milk 1L', priceMinor: 6000 }, quantity: 2 });
      expect(backup.body.customers[0]).toMatchObject({ pendingMinor: 12000, transactions: [expect.objectContaining({ type: 'credit' })] });

      // Into a fresh shop: same data comes back out.
      const other = await api.signup();
      const restored = await api.post('/backup/restore', backup.body, other.token);
      expect(restored.body).toEqual({ products: 1, sales: 1, customers: 1 });
      const again = (await api.get('/backup', other.token)).body;
      expect({ ...again, exportedAt: null }).toEqual({ ...backup.body, exportedAt: null });

      // Restoring over existing data tells syncing devices to start again.
      await api.post('/backup/restore', backup.body, shop.token);
      const after = await api.get(`/sync/pull?cursor=${pulled.body.cursor}`, shop.token);
      expect(after.body.reset).toBe(true);
      expect(after.body.products).toHaveLength(1);
    });

    it('rejects a damaged file before changing anything', async () => {
      const shop = await api.signup();
      await api.product(shop.token, { name: 'Keep me' });
      const base = (await api.get('/backup', shop.token)).body;
      const bad = { ...base, products: [...base.products, base.products[0]] };
      const res = await api.post('/backup/restore', bad, shop.token);
      expect(res.status).toBe(400);
      expect(res.body.message).toBe('The backup file is damaged and cannot be restored.');
      expect((await api.post('/backup/restore', { ...base, app: 'other' }, shop.token)).status).toBe(400);
      expect((await api.get('/products', shop.token)).body).toHaveLength(1);
    });

    it('imports older browser data with major-unit amounts when asked to repair it', async () => {
      const shop = await api.signup();
      const legacy = {
        app: 'thyantra_billing',
        formatVersion: 1,
        // A garbled symbol is repaired from the currency code.
        settings: { currency: 'INR', currencySymbol: 'â‚¹', shopName: 'ShopEase' },
        products: [
          { id: '1', name: 'Milk 1L', price: 60, stock: -2, usageCount: 120, createdAt: '2025-01-01T00:00:00Z' },
          { id: '2', name: 'Bread', price: 45.5, stock: 30, usageCount: 95, createdAt: '2025-01-01T00:00:00Z', image: 'http://x/y.png' },
        ],
        sales: [
          {
            id: 's1',
            items: [{ product: { id: '1', name: 'Milk 1L', price: 60, stock: 50, usageCount: 0, createdAt: '2025-01-01T00:00:00Z' }, quantity: 2 }],
            total: 120,
            date: '2025-02-01T10:00:00Z',
            customerId: 'c1',
            isPending: true,
          },
        ],
        customers: [
          {
            id: 'c1',
            name: 'Ravi',
            phone: '98765 43210',
            pendingAmount: 120,
            createdAt: '2025-01-01T00:00:00Z',
            transactions: [{ id: 't1', amount: 120, type: 'credit', description: 'Sale #s1', date: '2025-02-01T10:00:00Z', saleId: 's1' }],
          },
          { id: 'c2', name: 'Ravi again', phone: '9876543210', pendingAmount: 0, createdAt: '2025-01-02T00:00:00Z', transactions: [] },
        ],
      };
      expect((await api.post('/backup/restore', legacy, shop.token)).status).toBe(400);
      const res = await api.post('/backup/restore?sanitize=true', legacy, shop.token);
      expect(res.body).toEqual({ products: 2, sales: 1, customers: 1 });
      const products = (await api.get('/products', shop.token)).body;
      expect(products).toEqual([
        expect.objectContaining({ id: '1', priceMinor: 6000, stock: 0 }),
        expect.objectContaining({ id: '2', priceMinor: 4550, image: null }),
      ]);
      expect((await api.get('/customers/c1', shop.token)).body).toMatchObject({ phone: '9876543210', pendingMinor: 12000 });
      expect((await api.get('/shop', shop.token)).body).toMatchObject({ name: 'ShopEase', currencySymbol: '₹' });
    });

    it('is owner only', async () => {
      const owner = await api.signup();
      const cashier = await api.cashier(owner);
      expect((await api.get('/backup', cashier.token)).status).toBe(403);
    });
  });
});
