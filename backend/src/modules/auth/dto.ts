import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { CURRENCY_CODES } from '../../common/currencies';
import { zName } from '../../common/validation';

export const zEmail = z.string().trim().toLowerCase().email('Please enter a valid email').max(200);
export const zPassword = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .max(128, 'Password must be at most 128 characters');

/**
 * `web` sets httpOnly cookies; `mobile` returns the tokens in the body for
 * the app to keep in secure storage.
 */
const zClient = z.enum(['web', 'mobile']).default('web');

export class SignupDto extends createZodDto(
  z.object({
    shopName: zName,
    name: zName,
    email: zEmail,
    password: zPassword,
    currency: z.enum(CURRENCY_CODES).default('INR'),
    client: zClient,
  }),
) {}

export class LoginDto extends createZodDto(
  z.object({
    email: zEmail,
    password: z.string().min(1).max(128),
    client: zClient,
  }),
) {}

export class RefreshDto extends createZodDto(
  z.object({
    /** Mobile sends it in the body; the web relies on the cookie. */
    refreshToken: z.string().max(200).optional(),
    client: zClient,
  }),
) {}

export class ChangePasswordDto extends createZodDto(
  z.object({
    currentPassword: z.string().min(1).max(128),
    newPassword: zPassword,
    client: zClient,
  }),
) {}
