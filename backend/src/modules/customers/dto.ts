import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { zDate, zDescription, zId, zName, zPhone, zPositiveAmountMinor } from '../../common/validation';

export const zCustomerFields = z.object({ name: zName, phone: zPhone });

export class CreateCustomerDto extends createZodDto(zCustomerFields.extend({ id: zId.optional() })) {}

export class UpdateCustomerDto extends createZodDto(zCustomerFields.partial()) {}

export const zPayment = z.object({
  id: zId.optional(),
  /** Between 1 and the pending balance, in minor units. */
  amountMinor: zPositiveAmountMinor,
  description: zDescription.default('Payment received'),
  date: zDate.optional(),
});

export class PaymentDto extends createZodDto(zPayment) {}

export class ListCustomersQuery extends createZodDto(
  z.object({
    search: z.string().trim().max(100).optional(),
    /** `transactions` embeds each customer's ledger, as the web context expects. */
    include: z.enum(['transactions']).optional(),
    withPending: z
      .enum(['true', 'false'])
      .transform((v) => v === 'true')
      .optional(),
  }),
) {}

export interface TransactionView {
  id: string;
  customerId: string;
  type: 'credit' | 'payment';
  amountMinor: number;
  description: string;
  date: Date;
  saleId: string | null;
}

export interface CustomerView {
  id: string;
  name: string;
  phone: string;
  pendingMinor: number;
  createdAt: Date;
  updatedAt: Date;
  transactions?: TransactionView[];
}
