import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, OwnerOnly } from '../../common/auth/decorators';
import { CreateCustomerDto, ListCustomersQuery, PaymentDto, UpdateCustomerDto } from './dto';
import { CustomersService } from './service';

@ApiTags('customers')
@Controller('customers')
export class CustomersController {
  constructor(private readonly customers: CustomersService) {}

  @Get()
  list(@CurrentUser() user: AuthUser, @Query() q: ListCustomersQuery) {
    return this.customers.list(user.shopId, q);
  }

  @Get(':id')
  get(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.customers.get(user.shopId, id);
  }

  @Post()
  create(@CurrentUser() user: AuthUser, @Body() dto: CreateCustomerDto) {
    return this.customers.create(user, dto);
  }

  @Patch(':id')
  update(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: UpdateCustomerDto) {
    return this.customers.update(user, id, dto);
  }

  @OwnerOnly()
  @Delete(':id')
  @HttpCode(204)
  remove(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.customers.remove(user, id);
  }

  @Post(':id/payments')
  pay(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: PaymentDto) {
    return this.customers.pay(user, id, dto);
  }
}
