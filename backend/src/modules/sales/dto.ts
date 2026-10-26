import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { MAX_STOCK, zAmountMinor, zDate, zDescription, zId, zName, zPhone } from '../../common/validation';

const zQuantity = z.number().int().min(1).max(MAX_STOCK);

/** Existing customer by id, or a new one by name and phone. */
export const zCheckoutCustomer = z.union([
  z.object({ id: zId }),
  z.object({ name: zName, phone: zPhone }),
]);

export class CheckoutDto extends createZodDto(
  z.object({
    id: zId.optional(),
    items: z
      .array(
        z.object({
          productId: zId,
          quantity: zQuantity,
          /** The price the cashier saw. A mismatch returns 409 instead of charging a different price. */
          expectedUnitPriceMinor: zAmountMinor.optional(),
        }),
      )
      .min(1, 'Cart is empty')
      .max(500)
      .refine((items) => new Set(items.map((i) => i.productId)).size === items.length, 'Each product may appear once'),
    /** Present for a credit sale: the total is added to this customer's pending balance. */
    customer: zCheckoutCustomer.optional(),
  }),
) {}

/** A sale made on a device while offline; see SalesService.recordOffline. */
export const zOfflineSale = z.object({
  id: zId,
  date: zDate,
  items: z
    .array(z.object({ productId: zId, name: zName, priceMinor: zAmountMinor, quantity: zQuantity }))
    .min(1)
    .max(500),
  customerId: zId.nullish(),
  /** Details to recreate the customer if the server no longer has them. */
  customer: z.object({ name: zName, phone: zPhone }).nullish(),
  credit: z.object({ id: zId, description: zDescription, date: zDate }).nullish(),
});
export type OfflineSale = z.infer<typeof zOfflineSale>;

export class ListSalesQuery extends createZodDto(
  z.object({
    from: zDate.optional(),
    to: zDate.optional(),
    customerId: zId.optional(),
    limit: z.coerce.number().int().min(1).max(1000).default(100),
    /** Opaque, from the previous page's `nextCursor`. */
    cursor: z.string().max(200).optional(),
  }),
) {}

export interface SaleItemView {
  productId: string;
  name: string;
  priceMinor: number;
  quantity: number;
  /** Units sold offline that were not in stock when the sale reached the server. */
  shortfall: number;
}

export interface SaleView {
  id: string;
  date: Date;
  totalMinor: number;
  customerId: string | null;
  isPending: boolean | null;
  source: 'web' | 'mobile' | 'import';
  items: SaleItemView[];
}

export interface CartChange {
  productId: string;
  kind: 'removed' | 'out_of_stock' | 'price_changed' | 'reduced';
  message: string;
  availableStock?: number;
  priceMinor?: number;
}
