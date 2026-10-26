import { z } from 'zod';
import { MAX_AMOUNT_MINOR } from './money';

/** Input rules shared with the apps (mobile/lib/utils/validation.dart). */
export const MAX_NAME_LENGTH = 100;
export const MAX_STOCK = 1_000_000;
export const MAX_IMAGE_URL_LENGTH = 500;

/** Strips spaces, dashes, dots and brackets so "+91 98765-43210" equals "+919876543210". */
export function normalizePhone(input: string): string {
  return input.replace(/[\s\-().]/g, '');
}

const PHONE_PATTERN = /^\+?\d{7,15}$/;

export function isValidPhone(input: string): boolean {
  return PHONE_PATTERN.test(normalizePhone(input));
}

/** Product images must be https (cleartext is blocked on Android and leaks what a shop sells). */
export function isValidImageUrl(input: string): boolean {
  try {
    const url = new URL(input);
    return url.protocol === 'https:' && url.hostname.length > 0;
  } catch {
    return false;
  }
}

export const zId = z.string().trim().min(1).max(64);
export const zName = z
  .string()
  .trim()
  .min(1, 'Please enter a name')
  .max(MAX_NAME_LENGTH, `Name must be less than ${MAX_NAME_LENGTH} characters`);
export const zPhone = z
  .string()
  .refine(isValidPhone, 'Please enter a valid phone number')
  .transform(normalizePhone);
export const zAmountMinor = z.number().int().min(0).max(MAX_AMOUNT_MINOR);
export const zPositiveAmountMinor = z.number().int().min(1).max(MAX_AMOUNT_MINOR);
export const zStock = z.number().int().min(0).max(MAX_STOCK);
export const zImage = z
  .string()
  .max(MAX_IMAGE_URL_LENGTH)
  .refine(isValidImageUrl, 'Image must be an https URL')
  .nullable()
  .optional();
export const zDate = z.coerce.date();
export const zDescription = z.string().trim().max(200);
