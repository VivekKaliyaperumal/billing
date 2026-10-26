import { Global, Injectable, Module, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';

export type Tx = Prisma.TransactionClient;

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit(): Promise<void> {
    await this.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }

  /**
   * Runs `fn` in a transaction holding the shop's advisory lock. Every write
   * to shop data goes through here, so a shop's writes never interleave:
   * stock and balances can't race, and `seq` values commit in order, which
   * the sync pull cursor relies on.
   */
  async withShopLock<T>(shopId: string, fn: (tx: Tx) => Promise<T>): Promise<T> {
    return this.$transaction(
      async (tx) => {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${shopId}))`;
        return fn(tx);
      },
      { timeout: 30_000, maxWait: 10_000 },
    );
  }
}

@Global()
@Module({ providers: [PrismaService], exports: [PrismaService] })
export class PrismaModule {}
