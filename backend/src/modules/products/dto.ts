import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { zAmountMinor, zId, zImage, zName, zStock } from '../../common/validation';

export const zProductFields = z.object({
  name: zName,
  /** Unit price in minor units (paise). */
  priceMinor: zAmountMinor,
  stock: zStock,
  image: zImage,
});

export class CreateProductDto extends createZodDto(
  /** `id` lets an offline client keep the id it already generated. */
  zProductFields.extend({ id: zId.optional() }),
) {}

export class UpdateProductDto extends createZodDto(zProductFields.partial()) {}

export class ListProductsQuery extends createZodDto(
  z.object({
    search: z.string().trim().max(100).optional(),
    inStock: z
      .enum(['true', 'false'])
      .transform((v) => v === 'true')
      .optional(),
    /** `usage` = most sold first, as on the Sales screen. */
    sort: z.enum(['created', 'name', 'usage']).default('created'),
    limit: z.coerce.number().int().min(1).max(5000).optional(),
  }),
) {}

export interface ProductView {
  id: string;
  name: string;
  priceMinor: number;
  stock: number;
  image: string | null;
  usageCount: number;
  createdAt: Date;
  updatedAt: Date;
}
