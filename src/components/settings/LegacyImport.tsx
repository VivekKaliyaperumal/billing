import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { HardDriveUpload } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useAuth } from '@/context/AuthContext';
import { toast } from '@/hooks/use-toast';
import { api, errorMessage } from '@/lib/api/client';
import { ApiShop } from '@/lib/api/types';
import { CURRENCIES } from '@/types/product';

// Keys the web app used before it had a server.
const LEGACY_KEYS = {
  products: 'shop_products',
  sales: 'shop_sales_history',
  customers: 'shop_customers',
  settings: 'shop_settings',
} as const;

function readJson(key: string): unknown {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : undefined;
  } catch {
    return undefined;
  }
}

function hasLegacyData(): boolean {
  try {
    return [LEGACY_KEYS.products, LEGACY_KEYS.sales, LEGACY_KEYS.customers].some(k => localStorage.getItem(k) !== null);
  } catch {
    return false;
  }
}

/**
 * Owner only, shown when this browser still holds data from before the
 * server existed. Uploads it as a backup the server repairs and validates
 * (`sanitize=true`), replacing the shop's data on the server.
 */
export function LegacyImport() {
  const { shop, setShop } = useAuth();
  const queryClient = useQueryClient();
  const [visible, setVisible] = useState(hasLegacyData);
  const [busy, setBusy] = useState(false);

  if (!visible) return null;

  const handleImport = async () => {
    if (!window.confirm('This replaces all products, sales and customers for this shop on the server with the data saved in this browser. Continue?')) {
      return;
    }
    const settings = readJson(LEGACY_KEYS.settings) as { currency?: string; shopName?: string } | undefined;
    const currency = CURRENCIES.find(c => c.code === settings?.currency) ?? CURRENCIES[0];
    const backup = {
      app: 'thyantra_billing',
      formatVersion: 1,
      settings: { currency: currency.code, currencySymbol: currency.symbol, shopName: settings?.shopName || shop?.name || 'My Shop' },
      products: readJson(LEGACY_KEYS.products) ?? [],
      sales: readJson(LEGACY_KEYS.sales) ?? [],
      customers: readJson(LEGACY_KEYS.customers) ?? [],
    };
    setBusy(true);
    try {
      const result = await api<{ products: number; sales: number; customers: number }>('POST', '/backup/restore?sanitize=true', backup);
      // Keep the original under a new name rather than deleting it.
      for (const key of Object.values(LEGACY_KEYS)) {
        const raw = localStorage.getItem(key);
        if (raw !== null) {
          localStorage.setItem(`${key}_imported`, raw);
          localStorage.removeItem(key);
        }
      }
      setShop(await api<ApiShop>('GET', '/shop'));
      await queryClient.invalidateQueries();
      setVisible(false);
      toast({
        title: 'Data imported',
        description: `${result.products} products, ${result.sales} sales and ${result.customers} customers are now on the server.`,
      });
    } catch (e) {
      toast({ title: 'Import failed — nothing was changed', description: errorMessage(e), variant: 'destructive' });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card className="border-accent shadow-medium">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 font-display">
          <HardDriveUpload className="h-5 w-5 text-accent" />
          Data saved in this browser
        </CardTitle>
        <CardDescription>
          This browser has products, sales or customers from before your shop had an account. Import them so every device sees them.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Button onClick={handleImport} disabled={busy} className="gradient-accent text-accent-foreground">
          Import into {shop?.name ?? 'this shop'}
        </Button>
      </CardContent>
    </Card>
  );
}
