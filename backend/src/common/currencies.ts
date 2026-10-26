/** Same list as src/types/product.ts and mobile/lib/models/models.dart. */
export const CURRENCIES = [
  { code: 'INR', symbol: '₹', name: 'Indian Rupee' },
  { code: 'USD', symbol: '$', name: 'US Dollar' },
  { code: 'EUR', symbol: '€', name: 'Euro' },
  { code: 'GBP', symbol: '£', name: 'British Pound' },
] as const;

export type CurrencyCode = (typeof CURRENCIES)[number]['code'];

export const CURRENCY_CODES = CURRENCIES.map((c) => c.code) as [CurrencyCode, ...CurrencyCode[]];

export function currencySymbol(code: string): string | undefined {
  return CURRENCIES.find((c) => c.code === code)?.symbol;
}
