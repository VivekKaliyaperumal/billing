import { NestFastifyApplication } from '@nestjs/platform-fastify';
import { Api, setup, TestShop } from './helpers';

describe('products, checkout, customers and reports', () => {
  let app: NestFastifyApplication;
  let api: Api;
  let owner: TestShop;

  beforeAll(async () => {
    ({ app, api } = await setup());
    owner = await api.signup();
  });
  afterAll(() => app.close());

  describe('products', () => {
    it('creates, lists, updates and soft-deletes products', async () => {
      const p = await api.product(owner.token, { name: 'Butter 250g', priceMinor: 5500, stock: 20 });
      expect(p).toMatchObject({ name: 'Butter 250g', priceMinor: 5500, stock: 20, usageCount: 0 });

      const updated = await api.patch(`/products/${p.id}`, { priceMinor: 5750 }, owner.token);
      expect(updated.body).toMatchObject({ priceMinor: 5750, stock: 20 });

      const search = await api.get('/products?search=butter', owner.token);
      expect(search.body.map((x: { id: string }) => x.id)).toContain(p.id);

      expect((await api.del(`/products/${p.id}`, owner.token)).status).toBe(204);
      expect((await api.get(`/products/${p.id}`, owner.token)).status).toBe(404);
      const all = await api.get('/products', owner.token);
      expect(all.body.map((x: { id: string }) => x.id)).not.toContain(p.id);
    });

    it('validates product input like the apps do', async () => {
      const cases = [
        { name: '', priceMinor: 100, stock: 1 },
        { name: 'x'.repeat(101), priceMinor: 100, stock: 1 },
        { name: 'Neg', priceMinor: -1, stock: 1 },
        { name: 'Frac', priceMinor: 10.5, stock: 1 },
        { name: 'Stock', priceMinor: 100, stock: 1_000_001 },
        { name: 'Http', priceMinor: 100, stock: 1, image: 'http://insecure.example/img.png' },
      ];
      for (const body of cases) {
        expect((await api.post('/products', body, owner.token)).status).toBe(400);
      }
      const ok = await api.post('/products', { name: 'Img', priceMinor: 100, stock: 1, image: 'https://x.example/i.png' }, owner.token);
      expect(ok.status).toBe(201);
    });

    it('keeps short client ids such as "1" separate per shop', async () => {
      const other = await api.signup();
      await api.product(owner.token, { id: '1', name: 'Milk' });
      await api.product(other.token, { id: '1', name: 'Other milk' });
      expect((await api.get('/products/1', owner.token)).body.name).toBe('Milk');
      expect((await api.get('/products/1', other.token)).body.name).toBe('Other milk');
    });
  });

  describe('checkout', () => {
    it('records a cash sale: lowers stock, raises usage, prices from the server', async () => {
      const milk = await api.product(owner.token, { name: 'Milk', priceMinor: 6000, stock: 10 });
      const bread = await api.product(owner.token, { name: 'Bread', priceMinor: 4550, stock: 3 });
      const res = await api.post(
        '/sales',
        {
          items: [
            { productId: milk.id, quantity: 2, expectedUnitPriceMinor: 6000 },
            { productId: bread.id, quantity: 3 },
          ],
        },
        owner.token,
      );
      expect(res.status).toBe(201);
      expect(res.body.sale).toMatchObject({ totalMinor: 2 * 6000 + 3 * 4550, customerId: null, isPending: null, source: 'mobile' });
      expect(res.body.sale.items).toEqual([
        { productId: milk.id, name: 'Milk', priceMinor: 6000, quantity: 2, shortfall: 0 },
        { productId: bread.id, name: 'Bread', priceMinor: 4550, quantity: 3, shortfall: 0 },
      ]);
      expect((await api.get(`/products/${milk.id}`, owner.token)).body).toMatchObject({ stock: 8, usageCount: 2 });
      expect((await api.get(`/products/${bread.id}`, owner.token)).body).toMatchObject({ stock: 0, usageCount: 3 });
      expect((await api.get(`/sales/${res.body.sale.id}`, owner.token)).body.totalMinor).toBe(25650);
    });

    it('refuses a stale cart with the list of changes, and sells nothing', async () => {
      const a = await api.product(owner.token, { name: 'Eggs', priceMinor: 9000, stock: 2 });
      const b = await api.product(owner.token, { name: 'Cheese', priceMinor: 15000, stock: 0 });
      const c = await api.product(owner.token, { name: 'Juice', priceMinor: 8000, stock: 5 });
      const res = await api.post(
        '/sales',
        {
          items: [
            { productId: a.id, quantity: 5 },
            { productId: b.id, quantity: 1 },
            { productId: c.id, quantity: 1, expectedUnitPriceMinor: 7500 },
            { productId: 'gone', quantity: 1 },
          ],
        },
        owner.token,
      );
      expect(res.status).toBe(409);
      expect(res.body.code).toBe('cart_changed');
      expect(res.body.changes.map((x: { kind: string; message: string }) => [x.kind, x.message])).toEqual([
        ['reduced', 'Eggs reduced to 2 (stock available)'],
        ['out_of_stock', 'Cheese is out of stock'],
        ['price_changed', 'Juice price changed'],
        ['removed', 'A product in the cart was removed from inventory'],
      ]);
      // Current inventory comes back so the client can repair the cart.
      expect(res.body.products.map((p: { id: string }) => p.id).sort()).toEqual([a.id, b.id, c.id].sort());
      expect((await api.get(`/products/${a.id}`, owner.token)).body.stock).toBe(2);
      expect((await api.get(`/products/${c.id}`, owner.token)).body.stock).toBe(5);
    });

    it('rejects an empty cart or a product listed twice', async () => {
      const p = await api.product(owner.token);
      expect((await api.post('/sales', { items: [] }, owner.token)).status).toBe(400);
      const twice = { items: [{ productId: p.id, quantity: 1 }, { productId: p.id, quantity: 1 }] };
      expect((await api.post('/sales', twice, owner.token)).status).toBe(400);
    });

    it('never oversells under concurrent checkouts', async () => {
      const p = await api.product(owner.token, { name: 'Last few', priceMinor: 100, stock: 5 });
      const attempts = await Promise.all(
        Array.from({ length: 12 }, () => api.post('/sales', { items: [{ productId: p.id, quantity: 1 }] }, owner.token)),
      );
      expect(attempts.filter((r) => r.status === 201)).toHaveLength(5);
      expect(attempts.filter((r) => r.status === 409)).toHaveLength(7);
      expect((await api.get(`/products/${p.id}`, owner.token)).body).toMatchObject({ stock: 0, usageCount: 5 });
    });

    it('records a credit sale for a new customer in one step', async () => {
      const p = await api.product(owner.token, { priceMinor: 2500, stock: 10 });
      const res = await api.post(
        '/sales',
        { items: [{ productId: p.id, quantity: 4 }], customer: { name: 'Ravi', phone: '+91 98765-43210' } },
        owner.token,
      );
      expect(res.status).toBe(201);
      expect(res.body.sale).toMatchObject({ totalMinor: 10000, isPending: true });
      expect(res.body.customer).toMatchObject({ name: 'Ravi', phone: '+919876543210', pendingMinor: 10000 });

      const ledger = await api.get(`/customers/${res.body.customer.id}`, owner.token);
      expect(ledger.body.transactions).toEqual([
        expect.objectContaining({
          type: 'credit',
          amountMinor: 10000,
          saleId: res.body.sale.id,
          description: `Sale #${res.body.sale.id.slice(0, 8)}`,
        }),
      ]);

      // The same phone cannot open a second ledger.
      const again = await api.post(
        '/sales',
        { items: [{ productId: p.id, quantity: 1 }], customer: { name: 'Ravi K', phone: '+919876543210' } },
        owner.token,
      );
      expect(again.status).toBe(409);
      expect(again.body.code).toBe('phone_taken');
      expect((await api.get(`/products/${p.id}`, owner.token)).body.stock).toBe(6);
    });

    it('adds a credit sale to an existing customer, and refuses a missing one', async () => {
      const p = await api.product(owner.token, { priceMinor: 1000, stock: 10 });
      const c = (await api.post('/customers', { name: 'Meena', phone: '9000000001' }, owner.token)).body;
      await api.post('/sales', { items: [{ productId: p.id, quantity: 1 }], customer: { id: c.id } }, owner.token);
      await api.post('/sales', { items: [{ productId: p.id, quantity: 2 }], customer: { id: c.id } }, owner.token);
      expect((await api.get(`/customers/${c.id}`, owner.token)).body.pendingMinor).toBe(3000);

      const missing = await api.post('/sales', { items: [{ productId: p.id, quantity: 1 }], customer: { id: 'nope' } }, owner.token);
      expect(missing.status).toBe(409);
      expect(missing.body.code).toBe('customer_missing');
    });

    it('lets a cashier sell', async () => {
      const cashier = await api.cashier(owner);
      const p = await api.product(owner.token, { stock: 3 });
      expect((await api.post('/sales', { items: [{ productId: p.id, quantity: 1 }] }, cashier.token)).status).toBe(201);
    });

    it('pages through history newest first', async () => {
      const shop = await api.signup();
      const p = await api.product(shop.token, { stock: 100 });
      for (let i = 0; i < 5; i++) await api.post('/sales', { items: [{ productId: p.id, quantity: 1 }] }, shop.token);
      const first = await api.get('/sales?limit=2', shop.token);
      expect(first.body.sales).toHaveLength(2);
      const second = await api.get(`/sales?limit=2&cursor=${first.body.nextCursor}`, shop.token);
      const third = await api.get(`/sales?limit=2&cursor=${second.body.nextCursor}`, shop.token);
      expect(third.body.sales).toHaveLength(1);
      expect(third.body.nextCursor).toBeNull();
      const ids = [...first.body.sales, ...second.body.sales, ...third.body.sales].map((s: { id: string }) => s.id);
      expect(new Set(ids).size).toBe(5);
    });
  });

  describe('customers and payments', () => {
    it('normalises phones and keeps them unique per shop', async () => {
      const c = await api.post('/customers', { name: 'Kumar', phone: '(080) 1234-5678' }, owner.token);
      expect(c.body.phone).toBe('08012345678');
      const dup = await api.post('/customers', { name: 'Other', phone: '080 1234 5678' }, owner.token);
      expect(dup.status).toBe(409);
      expect(dup.body.message).toBe('This phone number already belongs to Kumar');
      expect((await api.post('/customers', { name: 'Bad', phone: '12' }, owner.token)).status).toBe(400);
      const other = await api.signup();
      expect((await api.post('/customers', { name: 'Kumar', phone: '08012345678' }, other.token)).status).toBe(201);
    });

    it('takes payments up to the pending balance, then allows deletion', async () => {
      const p = await api.product(owner.token, { priceMinor: 5000, stock: 10 });
      const sale = await api.post(
        '/sales',
        { items: [{ productId: p.id, quantity: 2 }], customer: { name: 'Lata', phone: '9111111111' } },
        owner.token,
      );
      const id = sale.body.customer.id;

      const cannotDelete = await api.del(`/customers/${id}`, owner.token);
      expect(cannotDelete.status).toBe(409);
      expect(cannotDelete.body.code).toBe('pending_balance');

      const over = await api.post(`/customers/${id}/payments`, { amountMinor: 10001 }, owner.token);
      expect(over.status).toBe(409);
      expect(over.body.code).toBe('payment_exceeds_pending');
      expect((await api.post(`/customers/${id}/payments`, { amountMinor: 0 }, owner.token)).status).toBe(400);

      const part = await api.post(`/customers/${id}/payments`, { amountMinor: 4000 }, owner.token);
      expect(part.body.customer.pendingMinor).toBe(6000);
      expect(part.body.transaction).toMatchObject({ type: 'payment', amountMinor: 4000, description: 'Payment received' });
      await api.post(`/customers/${id}/payments`, { amountMinor: 6000, description: 'UPI' }, owner.token);

      const cashier = await api.cashier(owner);
      expect((await api.del(`/customers/${id}`, cashier.token)).status).toBe(403);
      expect((await api.del(`/customers/${id}`, owner.token)).status).toBe(204);
      expect((await api.get(`/customers/${id}`, owner.token)).status).toBe(404);
      // A deleted customer's number can be used again.
      expect((await api.post('/customers', { name: 'New Lata', phone: '9111111111' }, owner.token)).status).toBe(201);
    });

    it('lists customers with their ledgers when asked', async () => {
      const shop = await api.signup();
      const c = (await api.post('/customers', { name: 'A', phone: '9222222222' }, shop.token)).body;
      const plain = await api.get('/customers', shop.token);
      expect(plain.body[0].transactions).toBeUndefined();
      const full = await api.get('/customers?include=transactions', shop.token);
      expect(full.body).toEqual([expect.objectContaining({ id: c.id, transactions: [] })]);
    });
  });

  describe('reports', () => {
    it('summarises by month and best seller, grouped by product id', async () => {
      const shop = await api.signup();
      const tea = await api.product(shop.token, { name: 'Tea', priceMinor: 1000, stock: 50 });
      const sugar = await api.product(shop.token, { name: 'Sugar', priceMinor: 4000, stock: 50 });
      await api.post('/sales', { items: [{ productId: tea.id, quantity: 3 }, { productId: sugar.id, quantity: 1 }] }, shop.token);
      await api.patch(`/products/${tea.id}`, { name: 'Tea Premium' }, shop.token);
      await api.post('/sales', { items: [{ productId: tea.id, quantity: 2 }] }, shop.token);
      await api.post('/sales', { items: [{ productId: sugar.id, quantity: 1 }], customer: { name: 'Z', phone: '9333333333' } }, shop.token);

      const monthly = await api.get('/reports/monthly', shop.token);
      expect(monthly.body).toHaveLength(1);
      expect(monthly.body[0]).toMatchObject({ totalMinor: 3000 + 4000 + 2000 + 4000, count: 3 });

      const now = new Date();
      const ist = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }));
      const top = await api.get(`/reports/top-products?year=${ist.getFullYear()}&month=${ist.getMonth()}`, shop.token);
      expect(top.body).toEqual([
        { productId: tea.id, productName: 'Tea Premium', quantity: 5, revenueMinor: 5000 },
        { productId: sugar.id, productName: 'Sugar', quantity: 2, revenueMinor: 8000 },
      ]);
      expect((await api.get('/reports/top-products?year=2020&month=0', shop.token)).body).toEqual([]);
      expect((await api.get('/reports/top-products?year=2020', shop.token)).status).toBe(400);

      const summary = await api.get('/reports/summary', shop.token);
      expect(summary.body).toMatchObject({
        todayTotalMinor: 13000,
        todayCount: 3,
        totalPendingMinor: 4000,
        customersWithPending: 1,
        productCount: 2,
        outOfStockCount: 0,
      });
      expect((await api.get('/reports/monthly?tz=Mars/Base', shop.token)).status).toBe(400);
    });
  });

  it('keeps shops isolated', async () => {
    const a = await api.signup();
    const b = await api.signup();
    const p = await api.product(a.token);
    const c = (await api.post('/customers', { name: 'Private', phone: '9444444444' }, a.token)).body;
    expect((await api.get(`/products/${p.id}`, b.token)).status).toBe(404);
    expect((await api.patch(`/products/${p.id}`, { stock: 0 }, b.token)).status).toBe(404);
    expect((await api.get(`/customers/${c.id}`, b.token)).status).toBe(404);
    expect((await api.post('/sales', { items: [{ productId: p.id, quantity: 1 }] }, b.token)).status).toBe(409);
    expect((await api.get('/products', b.token)).body).toEqual([]);
  });
});
