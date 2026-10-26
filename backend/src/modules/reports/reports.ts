import { Controller, Get, Injectable, Module, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Prisma } from '@prisma/client';
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser } from '../../common/auth/decorators';
import { toMinor } from '../../common/money';
import { PrismaService } from '../../common/prisma.service';

function isTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** Months and "today" follow the shop's local time, not UTC. */
const zTimeZone = z.string().max(64).refine(isTimeZone, 'Unknown time zone').default('Asia/Kolkata');

export class TimeZoneQuery extends createZodDto(z.object({ tz: zTimeZone })) {}

export class TopProductsQuery extends createZodDto(
  z
    .object({
      tz: zTimeZone,
      year: z.coerce.number().int().min(2000).max(2100).optional(),
      /** 0-based (January = 0), as in the apps. Omit year and month for all time. */
      month: z.coerce.number().int().min(0).max(11).optional(),
      limit: z.coerce.number().int().min(1).max(100).default(10),
    })
    .refine((q) => (q.year === undefined) === (q.month === undefined), 'Give both year and month, or neither'),
) {}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export interface MonthlySales {
  month: string;
  year: number;
  monthNum: number;
  totalMinor: number;
  count: number;
}

export interface ProductSales {
  productId: string;
  productName: string;
  quantity: number;
  revenueMinor: number;
}

export interface Summary {
  todayTotalMinor: number;
  todayCount: number;
  monthTotalMinor: number;
  monthCount: number;
  totalPendingMinor: number;
  customersWithPending: number;
  productCount: number;
  outOfStockCount: number;
}

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Sales per month, oldest first (SalesHistoryContext.getMonthlySalesData). */
  async monthly(shopId: string, tz: string): Promise<MonthlySales[]> {
    const rows = await this.prisma.$queryRaw<{ year: number; month: number; total: Prisma.Decimal; count: number }[]>`
      SELECT EXTRACT(YEAR FROM ("date" AT TIME ZONE ${tz}))::int AS year,
             EXTRACT(MONTH FROM ("date" AT TIME ZONE ${tz}))::int AS month,
             SUM("total") AS total,
             COUNT(*)::int AS count
      FROM "sales"
      WHERE "shop_id" = ${shopId}::uuid
      GROUP BY 1, 2
      ORDER BY 1, 2`;
    return rows.map((r) => ({
      month: MONTHS[r.month - 1]!,
      year: r.year,
      monthNum: r.month - 1,
      totalMinor: toMinor(new Prisma.Decimal(r.total)),
      count: r.count,
    }));
  }

  /**
   * Best sellers by quantity, grouped by product id so a renamed product
   * keeps one entry under its most recent name (as the apps do).
   */
  async topProducts(shopId: string, q: TopProductsQuery): Promise<ProductSales[]> {
    const monthFilter =
      q.year !== undefined && q.month !== undefined
        ? Prisma.sql`AND EXTRACT(YEAR FROM (s."date" AT TIME ZONE ${q.tz})) = ${q.year}
                     AND EXTRACT(MONTH FROM (s."date" AT TIME ZONE ${q.tz})) = ${q.month + 1}`
        : Prisma.empty;
    const rows = await this.prisma.$queryRaw<
      { product_id: string; name: string; quantity: number; revenue: Prisma.Decimal }[]
    >`
      SELECT si."product_id",
             (array_agg(si."product_name" ORDER BY s."date" DESC))[1] AS name,
             SUM(si."quantity")::int AS quantity,
             SUM(si."unit_price" * si."quantity") AS revenue
      FROM "sale_items" si
      JOIN "sales" s ON s."shop_id" = si."shop_id" AND s."id" = si."sale_id"
      WHERE si."shop_id" = ${shopId}::uuid ${monthFilter}
      GROUP BY si."product_id"
      ORDER BY quantity DESC, name ASC
      LIMIT ${q.limit}`;
    return rows.map((r) => ({
      productId: r.product_id,
      productName: r.name,
      quantity: r.quantity,
      revenueMinor: toMinor(new Prisma.Decimal(r.revenue)),
    }));
  }

  async summary(shopId: string, tz: string): Promise<Summary> {
    const [period] = await this.prisma.$queryRaw<
      { today_total: Prisma.Decimal | null; today_count: number; month_total: Prisma.Decimal | null; month_count: number }[]
    >`
      SELECT SUM("total") FILTER (WHERE ("date" AT TIME ZONE ${tz})::date = (now() AT TIME ZONE ${tz})::date) AS today_total,
             (COUNT(*) FILTER (WHERE ("date" AT TIME ZONE ${tz})::date = (now() AT TIME ZONE ${tz})::date))::int AS today_count,
             SUM("total") AS month_total,
             COUNT(*)::int AS month_count
      FROM "sales"
      WHERE "shop_id" = ${shopId}::uuid
        AND date_trunc('month', "date" AT TIME ZONE ${tz}) = date_trunc('month', now() AT TIME ZONE ${tz})`;
    const [pending, withPending, productCount, outOfStock] = await Promise.all([
      this.prisma.customer.aggregate({ where: { shopId, deletedAt: null }, _sum: { pending: true } }),
      this.prisma.customer.count({ where: { shopId, deletedAt: null, pending: { gt: 0 } } }),
      this.prisma.product.count({ where: { shopId, deletedAt: null } }),
      this.prisma.product.count({ where: { shopId, deletedAt: null, stock: 0 } }),
    ]);
    const dec = (v: Prisma.Decimal | null | undefined) => toMinor(new Prisma.Decimal(v ?? 0));
    return {
      todayTotalMinor: dec(period?.today_total),
      todayCount: period?.today_count ?? 0,
      monthTotalMinor: dec(period?.month_total),
      monthCount: period?.month_count ?? 0,
      totalPendingMinor: dec(pending._sum.pending),
      customersWithPending: withPending,
      productCount,
      outOfStockCount: outOfStock,
    };
  }
}

@ApiTags('reports')
@Controller('reports')
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  @Get('monthly')
  monthly(@CurrentUser() user: AuthUser, @Query() q: TimeZoneQuery) {
    return this.reports.monthly(user.shopId, q.tz);
  }

  @Get('top-products')
  topProducts(@CurrentUser() user: AuthUser, @Query() q: TopProductsQuery) {
    return this.reports.topProducts(user.shopId, q);
  }

  @Get('summary')
  summary(@CurrentUser() user: AuthUser, @Query() q: TimeZoneQuery) {
    return this.reports.summary(user.shopId, q.tz);
  }
}

@Module({ controllers: [ReportsController], providers: [ReportsService] })
export class ReportsModule {}
