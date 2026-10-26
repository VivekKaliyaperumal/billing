import { Body, Controller, Get, Param, Post, Query, Req } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { SaleSource } from '@prisma/client';
import { FastifyRequest } from 'fastify';
import { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser } from '../../common/auth/decorators';
import { CheckoutDto, ListSalesQuery } from './dto';
import { SalesService } from './service';

@ApiTags('sales')
@Controller('sales')
export class SalesController {
  constructor(private readonly sales: SalesService) {}

  /** Cash sale, or credit sale when `customer` is given. 409 `cart_changed` lists what to fix. */
  @Post()
  checkout(@CurrentUser() user: AuthUser, @Body() dto: CheckoutDto, @Req() req: FastifyRequest) {
    // The app authenticates with a bearer token, the website with cookies.
    const source = req.headers.authorization?.startsWith('Bearer ') ? SaleSource.MOBILE : SaleSource.WEB;
    return this.sales.checkout(user, dto, source);
  }

  @Get()
  list(@CurrentUser() user: AuthUser, @Query() q: ListSalesQuery) {
    return this.sales.list(user.shopId, q);
  }

  @Get(':id')
  get(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.sales.get(user.shopId, id);
  }
}
