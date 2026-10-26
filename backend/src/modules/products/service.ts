import { Injectable } from '@nestjs/common';
import { Prisma, Product } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { AuthUser } from '../../common/auth/auth-user';
import { DomainConflict, NotFound } from '../../common/errors';
import { fromMinor, toMinor } from '../../common/money';
import { PrismaService, Tx } from '../../common/prisma.service';
import { CreateProductDto, ListProductsQuery, ProductView, UpdateProductDto } from './dto';

export function productView(p: Product): ProductView {
  return {
    id: p.id,
    name: p.name,
    priceMinor: toMinor(p.price),
    stock: p.stock,
    image: p.image,
    usageCount: p.usageCount,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
  };
}

// ---------------------------------------------------------------------------
// Operations on an already-locked transaction, shared with the sync push.
// ---------------------------------------------------------------------------

export async function createProduct(
  tx: Tx,
  user: AuthUser,
  dto: CreateProductDto & { createdAt?: Date },
): Promise<Product> {
  const id = dto.id ?? randomUUID();
  const existing = await tx.product.findUnique({ where: { shopId_id: { shopId: user.shopId, id } } });
  if (existing) throw new DomainConflict('duplicate_id', 'A product with this id already exists');
  return tx.product.create({
    data: {
      shopId: user.shopId,
      id,
      name: dto.name,
      price: fromMinor(dto.priceMinor),
      stock: dto.stock,
      image: dto.image ?? null,
      createdById: user.id,
      updatedById: user.id,
      ...(dto.createdAt ? { createdAt: dto.createdAt } : {}),
    },
  });
}

/**
 * Updates a live product. With `baseStock` (the stock the editor started
 * from, sent by offline devices), stock changes by the difference instead of
 * being overwritten, so sales recorded elsewhere meanwhile are not lost.
 */
export async function updateProduct(
  tx: Tx,
  user: AuthUser,
  id: string,
  dto: UpdateProductDto,
  baseStock?: number,
): Promise<Product> {
  const current = await findLive(tx, user.shopId, id);
  let stock = dto.stock;
  if (stock !== undefined && baseStock !== undefined) {
    stock = Math.max(0, current.stock + (stock - baseStock));
  }
  return tx.product.update({
    where: { shopId_id: { shopId: user.shopId, id } },
    data: {
      name: dto.name,
      price: dto.priceMinor === undefined ? undefined : fromMinor(dto.priceMinor),
      stock,
      image: dto.image === undefined ? undefined : dto.image,
      updatedById: user.id,
    },
  });
}

/** Soft delete: the row stays as a tombstone for devices that sync later. Past sales keep their own snapshot. */
export async function deleteProduct(tx: Tx, user: AuthUser, id: string): Promise<void> {
  await findLive(tx, user.shopId, id);
  await tx.product.update({
    where: { shopId_id: { shopId: user.shopId, id } },
    data: { deletedAt: new Date(), updatedById: user.id },
  });
}

async function findLive(tx: Tx, shopId: string, id: string): Promise<Product> {
  const p = await tx.product.findUnique({ where: { shopId_id: { shopId, id } } });
  if (!p || p.deletedAt) throw new NotFound('Product');
  return p;
}

@Injectable()
export class ProductsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(shopId: string, q: ListProductsQuery): Promise<ProductView[]> {
    const where: Prisma.ProductWhereInput = {
      shopId,
      deletedAt: null,
      ...(q.search ? { name: { contains: q.search, mode: 'insensitive' } } : {}),
      ...(q.inStock === true ? { stock: { gt: 0 } } : q.inStock === false ? { stock: 0 } : {}),
    };
    const orderBy: Prisma.ProductOrderByWithRelationInput[] =
      q.sort === 'usage'
        ? [{ usageCount: 'desc' }, { createdAt: 'asc' }]
        : q.sort === 'name'
          ? [{ name: 'asc' }]
          : [{ createdAt: 'asc' }, { id: 'asc' }];
    const products = await this.prisma.product.findMany({ where, orderBy, take: q.limit });
    return products.map(productView);
  }

  async get(shopId: string, id: string): Promise<ProductView> {
    return productView(await findLive(this.prisma, shopId, id));
  }

  async create(user: AuthUser, dto: CreateProductDto): Promise<ProductView> {
    return productView(await this.prisma.withShopLock(user.shopId, (tx) => createProduct(tx, user, dto)));
  }

  async update(user: AuthUser, id: string, dto: UpdateProductDto): Promise<ProductView> {
    return productView(await this.prisma.withShopLock(user.shopId, (tx) => updateProduct(tx, user, id, dto)));
  }

  remove(user: AuthUser, id: string): Promise<void> {
    return this.prisma.withShopLock(user.shopId, (tx) => deleteProduct(tx, user, id));
  }
}
