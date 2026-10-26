import React, { createContext, useContext, ReactNode } from 'react';
import { AppSettings } from '@/types/product';
import { useAuth } from '@/context/AuthContext';
import { api } from '@/lib/api/client';
import { ApiShop } from '@/lib/api/types';

interface SettingsContextType {
  settings: AppSettings;
  /** Owner only. Saves to the server; the currency symbol follows the currency. */
  updateSettings: (updates: Partial<AppSettings>) => Promise<void>;
  formatPrice: (amount: number) => string;
}

const SettingsContext = createContext<SettingsContextType | undefined>(undefined);

const defaultSettings: AppSettings = {
  currency: 'INR',
  currencySymbol: '₹',
  shopName: 'ShopEase',
};

/** Shop settings now live on the server, with the signed-in shop. */
export function SettingsProvider({ children }: { children: ReactNode }) {
  const { shop, setShop } = useAuth();

  const settings: AppSettings = shop
    ? { currency: shop.currency, currencySymbol: shop.currencySymbol, shopName: shop.name }
    : defaultSettings;

  const updateSettings = async (updates: Partial<AppSettings>) => {
    setShop(await api<ApiShop>('PATCH', '/shop', { shopName: updates.shopName, currency: updates.currency }));
  };

  const formatPrice = (amount: number): string => {
    return `${settings.currencySymbol}${amount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  };

  return (
    <SettingsContext.Provider value={{ settings, updateSettings, formatPrice }}>
      {children}
    </SettingsContext.Provider>
  );
}

export function useSettings() {
  const context = useContext(SettingsContext);
  if (!context) {
    throw new Error('useSettings must be used within a SettingsProvider');
  }
  return context;
}
