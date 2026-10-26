import { Injectable } from '@nestjs/common';
import { Prisma, Product, Sale, SaleItem, SaleSource } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { AuthUser } from '../../common/auth/auth-user';
import { DomainConflict, NotFound } from '../../common/errors';
import { fromMinor, toMinor } from '../../common/money';
import { PrismaService, Tx } from '../../common/prisma.service';
import { CustomerView } from '../customers/dto';
import { createCustomer, customerView, findLiveCustomer, recordCredit, resolveCustomerId } from '../customers/service';
import { productView } from '../products/service';
import { CartChange, CheckoutDto, ListSalesQuery, OfflineSale, SaleView } from './dto';

type SaleWithItems = Sale & { items: SaleItem[] };

const SOURCE_NAMES = { WEB: 'web', MOBILE: 'mobile', IMPORT: 'import' } as const;

export function saleView(s: SaleWithItems): SaleView {
  return {
    id: s.id,
    date: s.date,
    totalMinor: toMinor(s.total),
    customerId: s.customerId,
    isPending: s.isPending,
    source: SOURCE_NAMES[s.source],
    items: [...s.items]
      .sort((a, b) => a.position - b.position)
      .map((i) => ({
        productId: i.productId,
        name: i.productName,
        priceMinor: toMinor(i.unitPrice),
        quantity: i.quantity,
        shortfall: i.shortfall,
      })),
  };
}

/** Same wording as the apps, e.g. "Sale #1a2b3c4d". */
export function creditDescription(saleId: string): string {
  return `Sale #${saleId.slice(0, 8)}`;
}

/**
 * Compares the cart with current inventory, like CartProvider.reconcile in
 * the app: removed or sold-out products, price changes, and quantities above
 * stock are each reported. Empty when the cart can be sold as is.
 */
export function reconcileCart(items: CheckoutDto['items'], products: Map<string, Product>): CartChange[] {
  const changes: CartChange[] = [];
  for (const item of items) {
    const p = products.get(item.productId);
    if (!p || p.deletedAt) {
      changes.push({ productId: item.productId, kind: 'removed', message: 'A product in the cart was removed from inventory' });
      continue;
    }
    if (p.stock <= 0) {
      changes.push({ productId: p.id, kind: 'out_of_stock', message: `${p.name} is out of stock`, availableStock: 0 });
      continue;
    }
    const priceMinor = toMinor(p.price);
    if (item.expectedUnitPriceMinor !== undefined && item.expectedUnitPriceMinor !== priceMinor) {
      changes.push({ productId: p.id, kind: 'price_changed', message: `${p.name} price changed`, priceMinor });
    }
    if (item.quantity > p.stock) {
      changes.push({
        productId: p.id,
        kind: 'reduced',
        message: `${p.name} reduced to ${p.stock} (stock available)`,
        availableStock: p.stock,
      });
    }
  }
  return changes;
}

async function loadProducts(tx: Tx, shopId: string, ids: string[]): Promise<Map<string, Product>> {
  const rows = await tx.product.findMany({ where: { shopId, id: { in: ids } } });
  return new Map(rows.map((p) => [p.id, p]));
}

export interface CheckoutResult {
  sale: SaleView;
  /** The credit customer after the sale, for a credit sale. */
  customer?: CustomerView;
}

/**
 * Online checkout (web, or the app while online through the REST API).
 * Everything happens in one locked transaction: check the cart against
 * inventory → resolve or create the credit customer → lower stock and raise
 * usage counts → save the sale → add the credit. Any mismatch returns 409 and
 * nothing is saved.
 */
export async function checkout(tx: Tx, user: AuthUser, dto: CheckoutDto, source: SaleSource): Promise<CheckoutResult> {
  const products = await loadProducts(
    tx,
    user.shopId,
    dto.items.map((i) => i.productId),
  );
  const changes = reconcileCart(dto.items, products);
  if (changes.length > 0) {
    throw new DomainConflict('cart_changed', 'The cart no longer matches inventory. Please review it and confirm again.', {
      changes,
      products: [...products.values()].filter((p) => !p.deletedAt).map(productView),
    });
  }

  let customerId: string | undefined;
  if (dto.customer) {
    if ('id' in dto.customer) {
      try {
        customerId = (await findLiveCustomer(tx, user.shopId, dto.customer.id)).id;
      } catch {
        throw new DomainConflict('customer_missing', 'Selected customer no longer exists');
      }
    } else {
      customerId = (await createCustomer(tx, user, { name: dto.customer.name, phone: dto.customer.phone })).customer.id;
    }
  }

  const saleId = dto.id ?? randomUUID();
  if (await tx.sale.findUnique({ where: { shopId_id: { shopId: user.shopId, id: saleId } } })) {
    throw new DomainConflict('duplicate_id', 'A sale with this id already exists');
  }

  let total = new Prisma.Decimal(0);
  const lines: Prisma.SaleItemCreateManySaleInput[] = [];
  for (const [position, item] of dto.items.entries()) {
    const p = products.get(item.productId)!;
    const updated = await tx.product.updateMany({
      where: { shopId: user.shopId, id: p.id, deletedAt: null, stock: { gte: item.quantity } },
      data: { stock: { decrement: item.quantity }, usageCount: { increment: item.quantity } },
    });
    if (updated.count !== 1) throw new DomainConflict('cart_changed', `Not enough stock for ${p.name}`);
    total = total.add(p.price.mul(item.quantity));
    lines.push({ position, productId: p.id, productName: p.name, unitPrice: p.price, quantity: item.quantity });
  }

  const date = new Date();
  const sale = await tx.sale.create({
    data: {
      shopId: user.shopId,
      id: saleId,
      date,
      total,
      customerId: customerId ?? null,
      isPending: customerId ? true : null,
      source,
      createdById: user.id,
      items: { createMany: { data: lines } },
    },
    include: { items: true },
  });

  if (!customerId) return { sale: saleView(sale) };
  await recordCredit(tx, user, customerId, { amount: total, description: creditDescription(saleId), date, saleId });
  const customer = await tx.customer.findUniqueOrThrow({ where: { shopId_id: { shopId: user.shopId, id: customerId } } });
  return { sale: saleView(sale), customer: customerView(customer) };
}

export interface OfflineSaleResult {
  sale: SaleView;
  warnings: string[];
  /** Set when the sale's customer id was merged into another customer. */
  customerId?: string;
}

/**
 * A sale a device made while offline. It already happened at the counter, so
 * it is always recorded at the price the customer was charged. If another
 * device sold the same stock first, stock stops at 0 and the missing units
 * are recorded as a shortfall and reported back, for the owner to recount.
 */
export async function recordOfflineSale(
  tx: Tx,
  user: AuthUser,
  input: OfflineSale,
  deviceId: string | undefined,
): Promise<OfflineSaleResult> {
  const existing = await tx.sale.findUnique({
    where: { shopId_id: { shopId: user.shopId, id: input.id } },
    include: { items: true },
  });
  if (existing) return { sale: saleView(existing), warnings: [] };

  const warnings: string[] = [];
  const products = await loadProducts(
    tx,
    user.shopId,
    input.items.map((i) => i.productId),
  );
  let total = new Prisma.Decimal(0);
  const lines: Prisma.SaleItemCreateManySaleInput[] = [];
  for (const [position, item] of input.items.entries()) {
    const price = fromMinor(item.priceMinor);
    total = total.add(price.mul(item.quantity));
    const p = products.get(item.productId);
    let shortfall = 0;
    if (p) {
      const taken = Math.min(item.quantity, p.stock);
      shortfall = item.quantity - taken;
      await tx.product.update({
        where: { shopId_id: { shopId: user.shopId, id: p.id } },
        data: { stock: { decrement: taken }, usageCount: { increment: item.quantity } },
      });
      p.stock -= taken;
      if (shortfall > 0) {
        warnings.push(
          `${item.name}: ${item.quantity} sold offline but only ${taken} were in stock. Stock is now 0; please recount.`,
        );
      }
    }
    lines.push({
      position,
      productId: item.productId,
      productName: item.name,
      unitPrice: price,
      quantity: item.quantity,
      shortfall,
    });
  }

  const customerId = input.customerId ? await ensureCreditCustomer(tx, user, input, warnings) : undefined;
  const sale = await tx.sale.create({
    data: {
      shopId: user.shopId,
      id: input.id,
      date: input.date,
      total,
      customerId: customerId ?? null,
      isPending: customerId ? true : null,
      source: SaleSource.MOBILE,
      deviceId: deviceId ?? null,
      createdById: user.id,
      items: { createMany: { data: lines } },
    },
    include: { items: true },
  });
  if (customerId) {
    await recordCredit(tx, user, customerId, {
      id: input.credit?.id,
      amount: total,
      description: input.credit?.description || creditDescription(input.id),
      date: input.credit?.date ?? input.date,
      saleId: input.id,
    });
  }
  return { sale: saleView(sale), warnings, customerId };
}

/**
 * Finds the customer an offline credit sale belongs to. If the customer was
 * deleted meanwhile (only possible with nothing pending), they are restored
 * so the credit is not lost; if the server never received them, they are
 * created from the details sent with the sale.
 */
async function ensureCreditCustomer(tx: Tx, user: AuthUser, input: OfflineSale, warnings: string[]): Promise<string> {
  const id = await resolveCustomerId(tx, user.shopId, input.customerId!);
  const c = await tx.customer.findUnique({ where: { shopId_id: { shopId: user.shopId, id } } });
  if (c && !c.deletedAt) return c.id;
  if (c) {
    const phoneOwner = await tx.customer.findFirst({ where: { shopId: user.shopId, phone: c.phone, deletedAt: null } });
    if (phoneOwner) {
      await tx.customerAlias.create({ data: { shopId: user.shopId, aliasId: c.id, customerId: phoneOwner.id } });
      return phoneOwner.id;
    }
    await tx.customer.update({ where: { shopId_id: { shopId: user.shopId, id } }, data: { deletedAt: null } });
    warnings.push(`${c.name} had been deleted and was restored because of an offline credit sale.`);
    return c.id;
  }
  if (!input.customer) {
    throw new DomainConflict('customer_missing', 'The credit customer for this sale is not known to the server');
  }
  const created = await createCustomer(tx, user, { id, name: input.customer.name, phone: input.customer.phone }, true);
  return created.customer.id;
}

function encodeCursor(s: Sale): string {
  return Buffer.from(`${s.date.toISOString()}|${s.id}`).toString('base64url');
}

function decodeCursor(cursor: string): { date: Date; id: string } | undefined {
  const [date, id] = Buffer.from(cursor, 'base64url').toString().split('|');
  const d = new Date(date ?? '');
  return id && !Number.isNaN(d.getTime()) ? { date: d, id } : undefined;
}

@Injectable()
export class SalesService {
  constructor(private readonly prisma: PrismaService) {}

  checkout(user: AuthUser, dto: CheckoutDto, source: SaleSource): Promise<CheckoutResult> {
    return this.prisma.withShopLock(user.shopId, (tx) => checkout(tx, user, dto, source));
  }

  /** Newest first, paged by an opaque cursor. */
  async list(shopId: string, q: ListSalesQuery): Promise<{ sales: SaleView[]; nextCursor: string | null }> {
    const after = q.cursor ? decodeCursor(q.cursor) : undefined;
    const where: Prisma.SaleWhereInput = {
      shopId,
      ...(q.customerId ? { customerId: q.customerId } : {}),
      date: { ...(q.from ? { gte: q.from } : {}), ...(q.to ? { lte: q.to } : {}) },
      ...(after
        ? { OR: [{ date: { lt: after.date } }, { date: after.date, id: { lt: after.id } }] }
        : {}),
    };
    const rows = await this.prisma.sale.findMany({
      where,
      orderBy: [{ date: 'desc' }, { id: 'desc' }],
      take: q.limit + 1,
      include: { items: true },
    });
    const page = rows.slice(0, q.limit);
    return {
      sales: page.map(saleView),
      nextCursor: rows.length > q.limit ? encodeCursor(page[page.length - 1]!) : null,
    };
  }

  async get(shopId: string, id: string): Promise<SaleView> {
    const s = await this.prisma.sale.findUnique({ where: { shopId_id: { shopId, id } }, include: { items: true } });
    if (!s) throw new NotFound('Sale');
    return saleView(s);
  }
}
