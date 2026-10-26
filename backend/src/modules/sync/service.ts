import { HttpException, Injectable, Logger } from '@nestjs/common';
import { Prisma, Role } from '@prisma/client';
import { ZodError } from 'zod';
import { AuthUser } from '../../common/auth/auth-user';
import { PrismaService, Tx } from '../../common/prisma.service';
import { publicShop, PublicShop } from '../auth/service';
import { CustomerView, TransactionView } from '../customers/dto';
import {
  createCustomer,
  customerView,
  deleteCustomer,
  recordPayment,
  transactionView,
  updateCustomer,
} from '../customers/service';
import { ProductView } from '../products/dto';
import { createProduct, deleteProduct, productView, updateProduct } from '../products/service';
import { SaleView } from '../sales/dto';
import { recordOfflineSale, saleView } from '../sales/service';
import { applySettings } from '../shop/shop';
import { OP_PAYLOADS, OpResult, OpType, OWNER_OPS, PullQuery, PushDto } from './dto';

type PushOp = PushDto['ops'][number];

export interface PullResult {
  /** True when the device must discard its synced data and replace it with this download. */
  reset: boolean;
  cursor: string;
  hasMore: boolean;
  shop: PublicShop;
  products: (ProductView & { deleted: boolean })[];
  customers: (CustomerView & { deleted: boolean })[];
  sales: SaleView[];
  transactions: TransactionView[];
}

/** Thrown inside an op to reject it without failing the push. */
class Rejected extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

@Injectable()
export class SyncService {
  private readonly logger = new Logger(SyncService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Applies a device's queued operations in order. Each is applied exactly
   * once: its result is stored under its opId, and a retried push gets the
   * stored result back. A rejected op is reported and the rest continue.
   */
  async push(user: AuthUser, dto: PushDto): Promise<{ results: OpResult[] }> {
    const results: OpResult[] = [];
    for (const op of dto.ops) {
      results.push(await this.pushOne(user, dto.deviceId, op));
    }
    return { results };
  }

  private async pushOne(user: AuthUser, deviceId: string, op: PushOp): Promise<OpResult> {
    try {
      return await this.prisma.withShopLock(user.shopId, async (tx) => {
        const done = await this.findProcessed(tx, user.shopId, op.opId);
        if (done) return done;
        const result = await this.apply(tx, user, deviceId, op);
        await this.saveProcessed(tx, user.shopId, op, result);
        return result;
      });
    } catch (e) {
      const rejected = toRejection(op.opId, e);
      if (!rejected) {
        this.logger.error(`sync op ${op.type} ${op.opId} failed: ${e instanceof Error ? e.stack : String(e)}`);
        throw e;
      }
      // Remember the rejection so a retry gets the same answer.
      return this.prisma.withShopLock(user.shopId, async (tx) => {
        const done = await this.findProcessed(tx, user.shopId, op.opId);
        if (done) return done;
        await this.saveProcessed(tx, user.shopId, op, rejected);
        return rejected;
      });
    }
  }

  private async findProcessed(tx: Tx, shopId: string, opId: string): Promise<OpResult | null> {
    const row = await tx.processedOp.findUnique({ where: { shopId_opId: { shopId, opId } } });
    return row ? { ...(row.result as unknown as OpResult), replayed: true } : null;
  }

  private async saveProcessed(tx: Tx, shopId: string, op: PushOp, result: OpResult): Promise<void> {
    await tx.processedOp.create({
      data: { shopId, opId: op.opId, type: op.type, result: result as unknown as Prisma.InputJsonValue },
    });
  }

  private async apply(tx: Tx, user: AuthUser, deviceId: string, op: PushOp): Promise<OpResult> {
    if (OWNER_OPS.has(op.type) && user.role !== Role.OWNER) {
      throw new Rejected('forbidden', 'Only the shop owner can do this');
    }
    const applied: OpResult = { opId: op.opId, status: 'applied' };
    const shopId = user.shopId;
    switch (op.type) {
      case 'product.upsert': {
        const p = parse('product.upsert', op.payload);
        const existing = await tx.product.findUnique({ where: { shopId_id: { shopId, id: p.id } } });
        if (existing?.deletedAt) throw new Rejected('product_deleted', `${p.name} was deleted on another device`);
        if (existing) {
          await updateProduct(tx, user, p.id, { name: p.name, priceMinor: p.priceMinor, stock: p.stock, image: p.image }, p.baseStock);
        } else {
          await createProduct(tx, user, p);
        }
        return applied;
      }
      case 'product.delete': {
        const { id } = parse('product.delete', op.payload);
        const existing = await tx.product.findUnique({ where: { shopId_id: { shopId, id } } });
        if (existing && !existing.deletedAt) await deleteProduct(tx, user, id);
        return applied;
      }
      case 'customer.create': {
        const c = parse('customer.create', op.payload);
        if (await tx.customer.findUnique({ where: { shopId_id: { shopId, id: c.id } } })) return applied;
        const { mergedInto } = await createCustomer(tx, user, c, true);
        return mergedInto ? { ...applied, mergedInto } : applied;
      }
      case 'customer.update': {
        const c = parse('customer.update', op.payload);
        await updateCustomer(tx, user, c.id, { name: c.name, phone: c.phone });
        return applied;
      }
      case 'customer.delete': {
        const { id } = parse('customer.delete', op.payload);
        const existing = await tx.customer.findUnique({ where: { shopId_id: { shopId, id } } });
        if (existing && !existing.deletedAt) await deleteCustomer(tx, user, id);
        return applied;
      }
      case 'sale.create': {
        const s = parse('sale.create', op.payload);
        const r = await recordOfflineSale(tx, user, s, deviceId);
        return {
          ...applied,
          ...(r.warnings.length ? { warnings: r.warnings } : {}),
          ...(r.customerId && r.customerId !== s.customerId ? { mergedInto: r.customerId } : {}),
        };
      }
      case 'payment.create': {
        const p = parse('payment.create', op.payload);
        if (await tx.customerTransaction.findUnique({ where: { shopId_id: { shopId, id: p.id } } })) return applied;
        await recordPayment(tx, user, p.customerId, p);
        return applied;
      }
      case 'settings.update': {
        await applySettings(tx, shopId, parse('settings.update', op.payload));
        return applied;
      }
    }
  }

  /**
   * Everything that changed after the cursor, oldest change first, up to
   * `limit` records. Without a cursor, or after a restore changed the shop's
   * data epoch, it starts from the beginning with `reset: true`.
   */
  async pull(user: AuthUser, q: PullQuery): Promise<PullResult> {
    const shopId = user.shopId;
    const parsed = q.cursor ? parseCursor(q.cursor) : undefined;
    const take = q.limit + 1;
    const bySeq = { seq: 'asc' } as const;

    // One snapshot for every read: otherwise a write committing between two
    // reads could be skipped by the cursor.
    const { shop, reset, since, products, customers, sales, transactions } = await this.prisma.$transaction(
      async (tx) => {
        const shop = await tx.shop.findUniqueOrThrow({ where: { id: shopId } });
        const reset = !parsed || parsed.epoch !== shop.dataEpoch;
        const since = reset ? 0n : parsed.seq;
        const where = { shopId, seq: { gt: since } };
        const products = await tx.product.findMany({ where, orderBy: bySeq, take });
        const customers = await tx.customer.findMany({ where, orderBy: bySeq, take });
        const sales = await tx.sale.findMany({ where, orderBy: bySeq, take, include: { items: true } });
        const transactions = await tx.customerTransaction.findMany({ where, orderBy: bySeq, take });
        return { shop, reset, since, products, customers, sales, transactions };
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead, timeout: 30_000 },
    );

    // Keep the `limit` lowest seq values across all tables, so the next pull
    // resumes exactly where this one stopped.
    const seqs = [...products, ...customers, ...sales, ...transactions].map((r) => r.seq).sort((a, b) => (a < b ? -1 : 1));
    const hasMore = seqs.length > q.limit;
    const upTo = hasMore ? seqs[q.limit - 1]! : (seqs[seqs.length - 1] ?? since);
    const inPage = <T extends { seq: bigint }>(rows: T[]) => rows.filter((r) => r.seq <= upTo);

    return {
      reset,
      cursor: `${shop.dataEpoch}.${upTo}`,
      hasMore,
      shop: publicShop(shop),
      products: inPage(products).map((p) => ({ ...productView(p), deleted: p.deletedAt !== null })),
      customers: inPage(customers).map((c) => ({ ...customerView(c), deleted: c.deletedAt !== null })),
      sales: inPage(sales).map(saleView),
      transactions: inPage(transactions).map(transactionView),
    };
  }
}

function parse<T extends OpType>(type: T, payload: unknown) {
  return OP_PAYLOADS[type].parse(payload) as ReturnType<(typeof OP_PAYLOADS)[T]['parse']>;
}

function parseCursor(cursor: string): { epoch: number; seq: bigint } | undefined {
  const m = /^(\d{1,9})\.(\d{1,19})$/.exec(cursor);
  return m ? { epoch: Number(m[1]), seq: BigInt(m[2]!) } : undefined;
}

/** Business-rule failures and bad payloads reject the op; anything else is a server error. */
function toRejection(opId: string, e: unknown): OpResult | null {
  if (e instanceof Rejected) return { opId, status: 'rejected', code: e.code, reason: e.message };
  if (e instanceof ZodError) {
    return { opId, status: 'rejected', code: 'invalid', reason: e.issues[0]?.message ?? 'Invalid data' };
  }
  if (e instanceof HttpException && e.getStatus() < 500) {
    const body = e.getResponse();
    const obj = typeof body === 'object' ? (body as { code?: string; message?: string }) : {};
    return { opId, status: 'rejected', code: obj.code ?? 'rejected', reason: obj.message ?? e.message };
  }
  if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
    return { opId, status: 'rejected', code: 'duplicate', reason: 'A record with these details already exists' };
  }
  return null;
}
