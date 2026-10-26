import { Prisma } from '@prisma/client';

/**
 * The API carries money as integer minor units (paise, cents), like the
 * mobile app; the database stores Decimal(14,2). These convert at the edge.
 */

/** Largest amount accepted from input: 1 crore in major units, as in mobile/lib/utils/money.dart. */
export const MAX_AMOUNT_MINOR = 1_000_000_000;

export function fromMinor(minor: number): Prisma.Decimal {
  return new Prisma.Decimal(minor).div(100);
}

export function toMinor(value: Prisma.Decimal): number {
  return value.mul(100).toDecimalPlaces(0).toNumber();
}

/** Converts an older major-unit amount (e.g. 60.5) to minor units. */
export function majorToMinor(major: number): number {
  return Math.round(major * 100);
}
