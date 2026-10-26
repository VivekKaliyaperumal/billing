import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { zDate, zId, zStock } from '../../common/validation';
import { zCustomerFields, zPayment } from '../customers/dto';
import { zProductFields } from '../products/dto';
import { zOfflineSale } from '../sales/dto';
import { zSettingsUpdate } from '../shop/shop';

/** Payload schema for each operation type a device can queue while offline. */
export const OP_PAYLOADS = {
  'product.upsert': zProductFields.extend({
    id: zId,
    /** Stock the device's edit started from; the server applies the difference. */
    baseStock: zStock.optional(),
    createdAt: zDate.optional(),
  }),
  'product.delete': z.object({ id: zId }),
  'customer.create': zCustomerFields.extend({ id: zId, createdAt: zDate.optional() }),
  'customer.update': zCustomerFields.extend({ id: zId }),
  'customer.delete': z.object({ id: zId }),
  'sale.create': zOfflineSale,
  'payment.create': zPayment.extend({ id: zId, customerId: zId }),
  'settings.update': zSettingsUpdate,
} as const;

export type OpType = keyof typeof OP_PAYLOADS;
export const OP_TYPES = Object.keys(OP_PAYLOADS) as [OpType, ...OpType[]];

/** Operations only the owner may perform; a cashier's are rejected. */
export const OWNER_OPS: ReadonlySet<OpType> = new Set(['product.upsert', 'product.delete', 'customer.delete', 'settings.update']);

export class PushDto extends createZodDto(
  z.object({
    deviceId: z.string().trim().min(1).max(100),
    /** Applied in order. Each op is its own transaction; a rejection does not stop the rest. */
    ops: z
      .array(
        z.object({
          opId: zId,
          type: z.enum(OP_TYPES),
          payload: z.unknown(),
          at: zDate.optional(),
        }),
      )
      .max(500),
  }),
) {}

export class PullQuery extends createZodDto(
  z.object({
    /** Opaque, from the previous pull. Omit for a full download. */
    cursor: z.string().max(100).optional(),
    limit: z.coerce.number().int().min(1).max(2000).default(500),
  }),
) {}

export interface OpResult {
  opId: string;
  status: 'applied' | 'rejected';
  /** True when this op was already processed by an earlier push; the stored result is returned. */
  replayed?: boolean;
  code?: string;
  reason?: string;
  /** Messages for the user, e.g. an offline sale that oversold stock. */
  warnings?: string[];
  /** customer.create / sale.create: the id now used for this customer, if it was merged. */
  mergedInto?: string;
}
