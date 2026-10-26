import { Customer, Product, Sale } from '@/types/product';

/**
 * Shapes returned by the API (backend/src/modules/*). Money is in integer
 * minor units (paise); the web app works in major units, so the mappers
 * below convert at the boundary and nothing else needs to change.
 */

export type Role = 'owner' | 'cashier';

export interface ApiUser {
  id: string;
  email: string;
  name: string;
  role: Role;
}

export interface ApiShop {
  id: string;
  name: string;
  currency: string;
  currencySymbol: string;
}

export interface ApiProduct {
  id: string;
  name: string;
  priceMinor: number;
  stock: number;
  image: string | null;
  usageCount: number;
  createdAt: string;
}

export interface ApiTransaction {
  id: string;
  customerId: string;
  type: 'credit' | 'payment';
  amountMinor: number;
  description: string;
  date: string;
  saleId: string | null;
}

export interface ApiCustomer {
  id: string;
  name: string;
  phone: string;
  pendingMinor: number;
  createdAt: string;
  transactions?: ApiTransaction[];
}

export interface ApiSale {
  id: string;
  date: string;
  totalMinor: number;
  customerId: string | null;
  isPending: boolean | null;
  items: { productId: string; name: string; priceMinor: number; quantity: number; shortfall: number }[];
}

export interface CartChange {
  productId: string;
  kind: 'removed' | 'out_of_stock' | 'price_changed' | 'reduced';
  message: string;
  availableStock?: number;
  priceMinor?: number;
}

export interface StaffMember extends ApiUser {
  isActive: boolean;
  createdAt: string;
}

export const toMinor = (major: number): number => Math.round(major * 100);
export const toMajor = (minor: number): number => minor / 100;

export function toProduct(p: ApiProduct): Product {
  return {
    id: p.id,
    name: p.name,
    price: toMajor(p.priceMinor),
    stock: p.stock,
    image: p.image ?? undefined,
    usageCount: p.usageCount,
    createdAt: new Date(p.createdAt),
  };
}

export function toSale(s: ApiSale): Sale {
  const date = new Date(s.date);
  return {
    id: s.id,
    date,
    total: toMajor(s.totalMinor),
    customerId: s.customerId ?? undefined,
    isPending: s.isPending ?? undefined,
    // Each line keeps the product as it was sold.
    items: s.items.map((i) => ({
      product: { id: i.productId, name: i.name, price: toMajor(i.priceMinor), stock: 0, usageCount: 0, createdAt: date },
      quantity: i.quantity,
    })),
  };
}

export function toCustomer(c: ApiCustomer): Customer {
  return {
    id: c.id,
    name: c.name,
    phone: c.phone,
    pendingAmount: toMajor(c.pendingMinor),
    createdAt: new Date(c.createdAt),
    transactions: (c.transactions ?? []).map((t) => ({
      id: t.id,
      amount: toMajor(t.amountMinor),
      type: t.type,
      description: t.description,
      date: new Date(t.date),
      saleId: t.saleId ?? undefined,
    })),
  };
}
