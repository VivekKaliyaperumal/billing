import { Module } from '@nestjs/common';
import { SalesController } from './controller';
import { SalesService } from './service';

@Module({ controllers: [SalesController], providers: [SalesService] })
export class SalesModule {}
