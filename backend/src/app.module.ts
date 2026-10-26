import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_PIPE } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { ZodValidationPipe } from 'nestjs-zod';
import { AuthGuard } from './common/auth/auth.guard';
import { loadConfig } from './common/config';
import { AllExceptionsFilter } from './common/http-exception.filter';
import { PrismaModule } from './common/prisma.service';
import { AuthModule } from './modules/auth/module';
import { BackupModule } from './modules/backup/backup';
import { CustomersModule } from './modules/customers/module';
import { HealthModule } from './modules/health/health';
import { ProductsModule } from './modules/products/module';
import { ReportsModule } from './modules/reports/reports';
import { SalesModule } from './modules/sales/module';
import { ShopModule } from './modules/shop/shop';
import { StaffModule } from './modules/staff/staff';
import { SyncModule } from './modules/sync/module';

@Module({
  imports: [
    PrismaModule,
    JwtModule.registerAsync({ global: true, useFactory: () => ({ secret: loadConfig().jwtAccessSecret }) }),
    // General limit per IP; credential routes set a stricter one.
    ThrottlerModule.forRoot({
      throttlers: [{ ttl: 60_000, limit: 600 }],
      // The e2e tests sign up many shops from one address.
      skipIf: () => process.env.THROTTLE_DISABLED === 'true',
    }),
    AuthModule,
    ShopModule,
    StaffModule,
    ProductsModule,
    CustomersModule,
    SalesModule,
    ReportsModule,
    BackupModule,
    SyncModule,
    HealthModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
    { provide: APP_PIPE, useClass: ZodValidationPipe },
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
  ],
})
export class AppModule {}
