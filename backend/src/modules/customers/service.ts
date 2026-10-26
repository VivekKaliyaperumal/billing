import { Injectable } from '@nestjs/common';
import { Customer, CustomerTransaction, Prisma, TransactionType } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { AuthUser } from '../../common/auth/auth-user';
import { DomainConflict, NotFound } from '../../common/errors';
import { fromMinor, toMinor } from '../../common/money';
import { PrismaService, Tx } from '../../common/prisma.service';
import { CreateCustomerDto, CustomerView, ListCustomersQuery, PaymentDto, TransactionView, UpdateCustomerDto } from './dto';

export function transactionView(t: CustomerTransaction): TransactionView {
  return {
    id: t.id,
    customerId: t.customerId,
    type: t.type === TransactionType.CREDIT ? 'credit' : 'payment',
    amountMinor: toMinor(t.amount),
    description: t.description,
    date: t.date,
    saleId: t.saleId,
  };
}

export function customerView(c: Customer, transactions?: CustomerTransaction[]): CustomerView {
  return {
    id: c.id,
    name: c.name,
    phone: c.phone,
    pendingMinor: toMinor(c.pending),
    createdAt: c.createdAt,
    updatedAt: c.updatedAt,
    ...(transactions ? { transactions: transactions.map(transactionView) } : {}),
  };
}

// ---------------------------------------------------------------------------
// Operations on an already-locked transaction, shared with checkout and sync.
// ---------------------------------------------------------------------------

/** Follows a merged id (see CustomerAlias) to the customer it now belongs to. */
export async function resolveCustomerId(tx: Tx, shopId: string, id: string): Promise<string> {
  const alias = await tx.customerAlias.findUnique({ where: { shopId_aliasId: { shopId, aliasId: id } } });
  return alias?.customerId ?? id;
}

export async function findLiveCustomer(tx: Tx, shopId: string, id: string): Promise<Customer> {
  const c = await tx.customer.findUnique({
    where: { shopId_id: { shopId, id: await resolveCustomerId(tx, shopId, id) } },
  });
  if (!c || c.deletedAt) throw new NotFound('Customer');
  return c;
}

async function findByPhone(tx: Tx, shopId: string, phone: string): Promise<Customer | null> {
  return tx.customer.findFirst({ where: { shopId, phone, deletedAt: null } });
}

function phoneTaken(owner: Customer): DomainConflict {
  return new DomainConflict('phone_taken', `This phone number already belongs to ${owner.name}`, {
    customerId: owner.id,
  });
}

export interface CreateCustomerResult {
  customer: Customer;
  /** Set when the phone already belonged to a customer and the new id was merged into it. */
  mergedInto?: string;
}

/**
 * Adds a customer. A phone already in use is refused, unless `mergeOnPhone`
 * (sync: two devices added the same person offline), in which case the new
 * id becomes an alias of the existing customer.
 */
export async function createCustomer(
  tx: Tx,
  user: AuthUser,
  dto: CreateCustomerDto & { createdAt?: Date },
  mergeOnPhone = false,
): Promise<CreateCustomerResult> {
  const id = dto.id ?? randomUUID();
  const sameId = await tx.customer.findUnique({ where: { shopId_id: { shopId: user.shopId, id } } });
  if (sameId) throw new DomainConflict('duplicate_id', 'A customer with this id already exists');
  const owner = await findByPhone(tx, user.shopId, dto.phone);
  if (owner) {
    if (!mergeOnPhone) throw phoneTaken(owner);
    await tx.customerAlias.create({ data: { shopId: user.shopId, aliasId: id, customerId: owner.id } });
    return { customer: owner, mergedInto: owner.id };
  }
  const customer = await tx.customer.create({
    data: {
      shopId: user.shopId,
      id,
      name: dto.name,
      phone: dto.phone,
      createdById: user.id,
      updatedById: user.id,
      ...(dto.createdAt ? { createdAt: dto.createdAt } : {}),
    },
  });
  return { customer };
}

export async function updateCustomer(tx: Tx, user: AuthUser, id: string, dto: UpdateCustomerDto): Promise<Customer> {
  const current = await findLiveCustomer(tx, user.shopId, id);
  if (dto.phone && dto.phone !== current.phone) {
    const owner = await findByPhone(tx, user.shopId, dto.phone);
    if (owner && owner.id !== current.id) throw phoneTaken(owner);
  }
  return tx.customer.update({
    where: { shopId_id: { shopId: user.shopId, id: current.id } },
    data: { name: dto.name, phone: dto.phone, updatedById: user.id },
  });
}

/** Only a customer with nothing pending can be deleted. Their ledger is kept with the tombstone. */
export async function deleteCustomer(tx: Tx, user: AuthUser, id: string): Promise<void> {
  const current = await findLiveCustomer(tx, user.shopId, id);
  if (!current.pending.isZero()) {
    throw new DomainConflict('pending_balance', 'Customer still has a pending balance');
  }
  await tx.customer.update({
    where: { shopId_id: { shopId: user.shopId, id: current.id } },
    data: { deletedAt: new Date(), updatedById: user.id },
  });
}

/** Records a payment; refuses one larger than the pending balance so no money is silently discarded. */
export async function recordPayment(
  tx: Tx,
  user: AuthUser,
  customerId: string,
  dto: PaymentDto,
): Promise<{ customer: Customer; transaction: CustomerTransaction }> {
  const current = await findLiveCustomer(tx, user.shopId, customerId);
  const amount = fromMinor(dto.amountMinor);
  if (amount.greaterThan(current.pending)) {
    throw new DomainConflict('payment_exceeds_pending', 'Payment is more than the pending amount', {
      pendingMinor: toMinor(current.pending),
    });
  }
  const transaction = await tx.customerTransaction.create({
    data: {
      shopId: user.shopId,
      id: dto.id ?? randomUUID(),
      customerId: current.id,
      type: TransactionType.PAYMENT,
      amount,
      description: dto.description || 'Payment received',
      date: dto.date ?? new Date(),
      createdById: user.id,
    },
  });
  const customer = await tx.customer.update({
    where: { shopId_id: { shopId: user.shopId, id: current.id } },
    data: { pending: { decrement: amount }, updatedById: user.id },
  });
  return { customer, transaction };
}

/** Adds a credit (an unpaid sale) to a customer's ledger. */
export async function recordCredit(
  tx: Tx,
  user: AuthUser,
  customerId: string,
  credit: { id?: string; amount: Prisma.Decimal; description: string; date: Date; saleId: string },
): Promise<CustomerTransaction> {
  const transaction = await tx.customerTransaction.create({
    data: {
      shopId: user.shopId,
      id: credit.id ?? randomUUID(),
      customerId,
      type: TransactionType.CREDIT,
      amount: credit.amount,
      description: credit.description,
      date: credit.date,
      saleId: credit.saleId,
      createdById: user.id,
    },
  });
  await tx.customer.update({
    where: { shopId_id: { shopId: user.shopId, id: customerId } },
    data: { pending: { increment: credit.amount }, updatedById: user.id },
  });
  return transaction;
}

@Injectable()
export class CustomersService {
  constructor(private readonly prisma: PrismaService) {}

  async list(shopId: string, q: ListCustomersQuery): Promise<CustomerView[]> {
    const where: Prisma.CustomerWhereInput = {
      shopId,
      deletedAt: null,
      ...(q.search
        ? {
            OR: [
              { name: { contains: q.search, mode: 'insensitive' } },
              { phone: { contains: q.search.replace(/[\s\-().]/g, '') } },
            ],
          }
        : {}),
      ...(q.withPending ? { pending: { gt: 0 } } : {}),
    };
    const customers = await this.prisma.customer.findMany({
      where,
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
      include: q.include === 'transactions' ? { transactions: { orderBy: [{ date: 'asc' }, { seq: 'asc' }] } } : undefined,
    });
    return customers.map((c) => customerView(c, 'transactions' in c ? (c.transactions as CustomerTransaction[]) : undefined));
  }

  async get(shopId: string, id: string): Promise<CustomerView> {
    const c = await findLiveCustomer(this.prisma, shopId, id);
    const transactions = await this.prisma.customerTransaction.findMany({
      where: { shopId, customerId: c.id },
      orderBy: [{ date: 'asc' }, { seq: 'asc' }],
    });
    return customerView(c, transactions);
  }

  async create(user: AuthUser, dto: CreateCustomerDto): Promise<CustomerView> {
    const { customer } = await this.prisma.withShopLock(user.shopId, (tx) => createCustomer(tx, user, dto));
    return customerView(customer, []);
  }

  async update(user: AuthUser, id: string, dto: UpdateCustomerDto): Promise<CustomerView> {
    return customerView(await this.prisma.withShopLock(user.shopId, (tx) => updateCustomer(tx, user, id, dto)));
  }

  remove(user: AuthUser, id: string): Promise<void> {
    return this.prisma.withShopLock(user.shopId, (tx) => deleteCustomer(tx, user, id));
  }

  async pay(user: AuthUser, id: string, dto: PaymentDto): Promise<{ customer: CustomerView; transaction: TransactionView }> {
    const { customer, transaction } = await this.prisma.withShopLock(user.shopId, (tx) =>
      recordPayment(tx, user, id, dto),
    );
    return { customer: customerView(customer), transaction: transactionView(transaction) };
  }

  /** Sum of every customer's pending balance. */
  async totalPending(shopId: string): Promise<number> {
    const agg = await this.prisma.customer.aggregate({ where: { shopId, deletedAt: null }, _sum: { pending: true } });
    return toMinor(agg._sum.pending ?? new Prisma.Decimal(0));
  }
}
