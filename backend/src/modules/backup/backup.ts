import { BadRequestException, Body, Controller, Get, HttpCode, Injectable, Module, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Prisma, SaleSource, TransactionType } from '@prisma/client';
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, OwnerOnly } from '../../common/auth/decorators';
import { CURRENCIES, currencySymbol } from '../../common/currencies';
import { fromMinor, majorToMinor, toMinor } from '../../common/money';
import { PrismaService } from '../../common/prisma.service';
import { isValidImageUrl, isValidPhone, MAX_STOCK, normalizePhone } from '../../common/validation';

/**
 * The mobile app's backup file (mobile/lib/services/backup_service.dart), so
 * a phone backup restores to the server and a server export restores to a
 * phone. Older files hold major-unit amounts under `price`, `total`,
 * `pendingAmount` and `amount`; those are converted.
 */
const APP = 'thyantra_billing';
const FORMAT_VERSION = 1;

const zNum = z.number().finite();
const zStr = z.string().max(500);
// A missing amount becomes NaN, which validateBackup rejects.

const zProductRaw = z
  .object({
    id: z.string().min(1).max(64),
    name: zStr,
    priceMinor: zNum.optional(),
    price: zNum.optional(),
    stock: zNum,
    image: zStr.nullish(),
    usageCount: zNum.default(0),
    createdAt: z.coerce.date(),
  })
  .transform((p) => ({
    id: p.id,
    name: p.name.trim(),
    priceMinor: p.priceMinor !== undefined ? Math.round(p.priceMinor) : majorToMinor(p.price ?? Number.NaN),
    stock: Math.trunc(p.stock),
    image: p.image ?? null,
    usageCount: Math.trunc(p.usageCount),
    createdAt: p.createdAt,
  }));

const zSaleRaw = z
  .object({
    id: z.string().min(1).max(64),
    items: z.array(
      z.object({
        product: z.object({
          id: z.string().min(1).max(64),
          name: zStr,
          priceMinor: zNum.optional(),
          price: zNum.optional(),
        }),
        quantity: zNum,
      }),
    ),
    date: z.coerce.date(),
    customerId: z.string().max(64).nullish(),
    isPending: z.boolean().nullish(),
  })
  .transform((s) => ({
    id: s.id,
    date: s.date,
    customerId: s.customerId ?? null,
    isPending: s.isPending ?? null,
    items: s.items.map((i) => ({
      productId: i.product.id,
      name: i.product.name,
      priceMinor:
        i.product.priceMinor !== undefined ? Math.round(i.product.priceMinor) : majorToMinor(i.product.price ?? Number.NaN),
      quantity: Math.trunc(i.quantity),
    })),
  }));

const zCustomerRaw = z
  .object({
    id: z.string().min(1).max(64),
    name: zStr,
    phone: zStr,
    pendingMinor: zNum.optional(),
    pendingAmount: zNum.optional(),
    createdAt: z.coerce.date(),
    transactions: z.array(
      z.object({
        id: z.string().min(1).max(64),
        amountMinor: zNum.optional(),
        amount: zNum.optional(),
        type: z.enum(['credit', 'payment']),
        description: zStr,
        date: z.coerce.date(),
        saleId: z.string().max(64).nullish(),
      }),
    ),
  })
  .transform((c) => ({
    id: c.id,
    name: c.name.trim(),
    phone: c.phone,
    pendingMinor: c.pendingMinor !== undefined ? Math.round(c.pendingMinor) : majorToMinor(c.pendingAmount ?? Number.NaN),
    createdAt: c.createdAt,
    transactions: c.transactions.map((t) => ({
      id: t.id,
      amountMinor: t.amountMinor !== undefined ? Math.round(t.amountMinor) : majorToMinor(t.amount ?? Number.NaN),
      type: t.type,
      description: t.description,
      date: t.date,
      saleId: t.saleId ?? null,
    })),
  }));

export const zBackupFile = z.object({
  app: z.literal(APP, { errorMap: () => ({ message: 'This file is not a Thyantra Billing backup.' }) }),
  formatVersion: z.literal(FORMAT_VERSION, {
    errorMap: () => ({ message: 'This backup was made by a newer version of the app. Please update first.' }),
  }),
  exportedAt: z.coerce.date().optional(),
  settings: z.object({ currency: z.string(), currencySymbol: z.string(), shopName: zStr }),
  products: z.array(zProductRaw).max(100_000),
  sales: z.array(zSaleRaw).max(1_000_000),
  customers: z.array(zCustomerRaw).max(100_000),
});
export type BackupData = z.infer<typeof zBackupFile>;

export class RestoreDto extends createZodDto(zBackupFile) {}

export class RestoreQuery extends createZodDto(
  z.object({
    /**
     * `true` repairs older data instead of rejecting it, as the app does
     * when importing its earlier storage: negative stock and balances
     * become 0, phones are normalised, later duplicates of a phone number
     * are dropped and non-https images removed. Used for "import data from
     * this browser".
     */
    sanitize: z
      .enum(['true', 'false'])
      .transform((v) => v === 'true')
      .default('false'),
  }),
) {}

/** Repairs older data (see RestoreQuery.sanitize). */
export function sanitizeBackup(b: BackupData): BackupData {
  const seen = new Set<string>();
  const customers = b.customers.flatMap((c) => {
    const phone = normalizePhone(c.phone);
    if (seen.has(phone)) return [];
    seen.add(phone);
    return [
      {
        ...c,
        phone,
        name: c.name || 'Customer',
        pendingMinor: Math.max(0, c.pendingMinor),
        transactions: c.transactions.filter((t) => t.amountMinor >= 0),
      },
    ];
  });
  const products = b.products.map((p) => ({
    ...p,
    name: p.name || 'Product',
    priceMinor: Math.max(0, p.priceMinor),
    stock: Math.min(MAX_STOCK, Math.max(0, p.stock)),
    usageCount: Math.max(0, p.usageCount),
    image: p.image && isValidImageUrl(p.image) ? p.image : null,
  }));
  const sales = b.sales
    .map((s) => ({ ...s, items: s.items.filter((i) => i.quantity > 0 && i.priceMinor >= 0) }))
    .filter((s) => s.items.length > 0);
  // The symbol always follows the currency code.
  const settings = { ...b.settings, currencySymbol: currencySymbol(b.settings.currency) ?? b.settings.currencySymbol };
  return { ...b, settings, customers, products, sales };
}

/** Rejects a file with anything the database would refuse, before replacing any data (BackupService._validate). */
export function validateBackup(b: BackupData): string | null {
  const unique = (ids: string[]) => new Set(ids).size === ids.length;
  const damaged = 'The backup file is damaged and cannot be restored.';
  if (!unique(b.products.map((p) => p.id))) return damaged;
  if (!unique(b.sales.map((s) => s.id))) return damaged;
  if (!unique(b.customers.map((c) => c.id))) return damaged;
  if (!unique(b.customers.map((c) => normalizePhone(c.phone)))) return damaged;
  if (!unique(b.customers.flatMap((c) => c.transactions.map((t) => t.id)))) return damaged;
  const okMinor = (n: number) => Number.isFinite(n) && n >= 0 && n < 1e14;
  for (const p of b.products) {
    if (!p.name.trim() || !okMinor(p.priceMinor) || p.stock < 0 || p.stock > MAX_STOCK || p.usageCount < 0) {
      return damaged;
    }
  }
  for (const c of b.customers) {
    if (!c.name.trim() || !isValidPhone(c.phone) || !okMinor(c.pendingMinor)) return damaged;
    if (!c.transactions.every((t) => okMinor(t.amountMinor))) return damaged;
  }
  for (const s of b.sales) {
    if (s.items.length === 0 || !s.items.every((i) => i.quantity > 0 && okMinor(i.priceMinor))) return damaged;
  }
  if (!CURRENCIES.some((c) => c.code === b.settings.currency && c.symbol === b.settings.currencySymbol)) return damaged;
  return null;
}

@Injectable()
export class BackupService {
  constructor(private readonly prisma: PrismaService) {}

  async export(shopId: string) {
    const [shop, products, sales, customers] = await Promise.all([
      this.prisma.shop.findUniqueOrThrow({ where: { id: shopId } }),
      this.prisma.product.findMany({ where: { shopId, deletedAt: null }, orderBy: [{ createdAt: 'asc' }, { id: 'asc' }] }),
      this.prisma.sale.findMany({ where: { shopId }, orderBy: [{ date: 'desc' }, { id: 'desc' }], include: { items: true } }),
      this.prisma.customer.findMany({
        where: { shopId, deletedAt: null },
        orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
        include: { transactions: { orderBy: [{ date: 'asc' }, { seq: 'asc' }] } },
      }),
    ]);
    return {
      app: APP,
      formatVersion: FORMAT_VERSION,
      exportedAt: new Date().toISOString(),
      settings: { currency: shop.currency, currencySymbol: shop.currencySymbol, shopName: shop.name },
      products: products.map((p) => ({
        id: p.id,
        name: p.name,
        priceMinor: toMinor(p.price),
        stock: p.stock,
        ...(p.image ? { image: p.image } : {}),
        usageCount: p.usageCount,
        createdAt: p.createdAt.toISOString(),
      })),
      sales: sales.map((s) => ({
        id: s.id,
        items: [...s.items]
          .sort((a, b) => a.position - b.position)
          .map((i) => ({
            // The app's sale line holds a full product snapshot.
            product: {
              id: i.productId,
              name: i.productName,
              priceMinor: toMinor(i.unitPrice),
              stock: 0,
              usageCount: 0,
              createdAt: s.date.toISOString(),
            },
            quantity: i.quantity,
          })),
        totalMinor: toMinor(s.total),
        date: s.date.toISOString(),
        ...(s.customerId ? { customerId: s.customerId } : {}),
        ...(s.isPending !== null ? { isPending: s.isPending } : {}),
      })),
      customers: customers.map((c) => ({
        id: c.id,
        name: c.name,
        phone: c.phone,
        pendingMinor: toMinor(c.pending),
        createdAt: c.createdAt.toISOString(),
        transactions: c.transactions.map((t) => ({
          id: t.id,
          amountMinor: toMinor(t.amount),
          type: t.type === TransactionType.CREDIT ? 'credit' : 'payment',
          description: t.description,
          date: t.date.toISOString(),
          ...(t.saleId ? { saleId: t.saleId } : {}),
        })),
      })),
    };
  }

  /**
   * Replaces all of the shop's data with the backup, in one transaction.
   * The shop's data epoch moves on, so every syncing device reloads.
   */
  async restore(user: AuthUser, input: BackupData, sanitize: boolean) {
    const data = sanitize ? sanitizeBackup(input) : input;
    const error = validateBackup(data);
    if (error) throw new BadRequestException({ code: 'invalid_backup', message: error });
    const shopId = user.shopId;
    await this.prisma.withShopLock(shopId, async (tx) => {
      await tx.customerTransaction.deleteMany({ where: { shopId } });
      await tx.saleItem.deleteMany({ where: { shopId } });
      await tx.sale.deleteMany({ where: { shopId } });
      await tx.customer.deleteMany({ where: { shopId } });
      await tx.customerAlias.deleteMany({ where: { shopId } });
      await tx.product.deleteMany({ where: { shopId } });
      await tx.processedOp.deleteMany({ where: { shopId } });

      await tx.product.createMany({
        data: data.products.map((p) => ({
          shopId,
          id: p.id,
          name: p.name.trim(),
          price: fromMinor(p.priceMinor),
          stock: p.stock,
          image: p.image && isValidImageUrl(p.image) ? p.image : null,
          usageCount: p.usageCount,
          createdAt: p.createdAt,
          createdById: user.id,
          updatedById: user.id,
        })),
      });
      await tx.customer.createMany({
        data: data.customers.map((c) => ({
          shopId,
          id: c.id,
          name: c.name.trim(),
          phone: normalizePhone(c.phone),
          pending: fromMinor(c.pendingMinor),
          createdAt: c.createdAt,
          createdById: user.id,
          updatedById: user.id,
        })),
      });
      await tx.customerTransaction.createMany({
        data: data.customers.flatMap((c) =>
          c.transactions.map((t) => ({
            shopId,
            id: t.id,
            customerId: c.id,
            type: t.type === 'credit' ? TransactionType.CREDIT : TransactionType.PAYMENT,
            amount: fromMinor(t.amountMinor),
            description: t.description,
            date: t.date,
            saleId: t.saleId,
            createdById: user.id,
          })),
        ),
      });
      // Insert sales in chunks: a large history would exceed the bind-parameter limit.
      for (let i = 0; i < data.sales.length; i += 1000) {
        const chunk = data.sales.slice(i, i + 1000);
        await tx.sale.createMany({
          data: chunk.map((s) => ({
            shopId,
            id: s.id,
            date: s.date,
            total: s.items.reduce((sum, it) => sum.add(fromMinor(it.priceMinor).mul(it.quantity)), new Prisma.Decimal(0)),
            customerId: s.customerId,
            isPending: s.isPending,
            source: SaleSource.IMPORT,
            createdById: user.id,
          })),
        });
        await tx.saleItem.createMany({
          data: chunk.flatMap((s) =>
            s.items.map((it, position) => ({
              shopId,
              saleId: s.id,
              position,
              productId: it.productId,
              productName: it.name,
              unitPrice: fromMinor(it.priceMinor),
              quantity: it.quantity,
            })),
          ),
        });
      }
      await tx.shop.update({
        where: { id: shopId },
        data: {
          name: data.settings.shopName.trim() || undefined,
          currency: data.settings.currency,
          currencySymbol: data.settings.currencySymbol,
          dataEpoch: { increment: 1 },
        },
      });
    });
    return {
      products: data.products.length,
      sales: data.sales.length,
      customers: data.customers.length,
    };
  }
}

@ApiTags('backup')
@OwnerOnly()
@Controller('backup')
export class BackupController {
  constructor(private readonly backup: BackupService) {}

  @Get()
  export(@CurrentUser() user: AuthUser) {
    return this.backup.export(user.shopId);
  }

  @Post('restore')
  @HttpCode(200)
  restore(@CurrentUser() user: AuthUser, @Body() dto: RestoreDto, @Query() q: RestoreQuery) {
    return this.backup.restore(user, dto, q.sanitize);
  }
}

@Module({ controllers: [BackupController], providers: [BackupService] })
export class BackupModule {}
