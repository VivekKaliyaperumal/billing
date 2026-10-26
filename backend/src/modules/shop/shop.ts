import { Body, Controller, Get, Injectable, Module, Patch } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, OwnerOnly } from '../../common/auth/decorators';
import { CURRENCY_CODES, currencySymbol } from '../../common/currencies';
import { PrismaService, Tx } from '../../common/prisma.service';
import { MAX_NAME_LENGTH } from '../../common/validation';
import { PublicShop, publicShop } from '../auth/service';

export const zSettingsUpdate = z.object({
  // Blank is allowed and ignored, so the header and receipts always show a
  // name (as in mobile/lib/providers/settings_provider.dart).
  shopName: z.string().max(MAX_NAME_LENGTH).optional(),
  currency: z.enum(CURRENCY_CODES).optional(),
});
export type SettingsUpdate = z.infer<typeof zSettingsUpdate>;

export class UpdateShopDto extends createZodDto(zSettingsUpdate) {}

/** Applies a settings change inside an already-locked transaction. */
export async function applySettings(tx: Tx, shopId: string, dto: SettingsUpdate): Promise<PublicShop> {
  const name = dto.shopName?.trim();
  const shop = await tx.shop.update({
    where: { id: shopId },
    data: {
      ...(name ? { name } : {}),
      ...(dto.currency ? { currency: dto.currency, currencySymbol: currencySymbol(dto.currency) } : {}),
    },
  });
  return publicShop(shop);
}

@Injectable()
export class ShopService {
  constructor(private readonly prisma: PrismaService) {}

  async get(shopId: string): Promise<PublicShop> {
    return publicShop(await this.prisma.shop.findUniqueOrThrow({ where: { id: shopId } }));
  }

  update(user: AuthUser, dto: SettingsUpdate): Promise<PublicShop> {
    return this.prisma.withShopLock(user.shopId, (tx) => applySettings(tx, user.shopId, dto));
  }
}

@ApiTags('shop')
@Controller('shop')
export class ShopController {
  constructor(private readonly shop: ShopService) {}

  @Get()
  get(@CurrentUser() user: AuthUser) {
    return this.shop.get(user.shopId);
  }

  @OwnerOnly()
  @Patch()
  update(@CurrentUser() user: AuthUser, @Body() dto: UpdateShopDto) {
    return this.shop.update(user, dto);
  }
}

@Module({ controllers: [ShopController], providers: [ShopService] })
export class ShopModule {}
