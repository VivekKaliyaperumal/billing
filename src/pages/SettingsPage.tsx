import { useState } from 'react';
import { Settings as SettingsIcon, Store, CreditCard, Save } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useSettings } from '@/context/SettingsContext';
import { useAuth } from '@/context/AuthContext';
import { CURRENCIES } from '@/types/product';
import { toast } from '@/hooks/use-toast';
import { errorMessage } from '@/lib/api/client';
import { AccountCard } from '@/components/settings/AccountCard';
import { StaffManager } from '@/components/settings/StaffManager';
import { LegacyImport } from '@/components/settings/LegacyImport';

export default function SettingsPage() {
  const { settings, updateSettings } = useSettings();
  const { isOwner } = useAuth();
  const [shopName, setShopName] = useState(settings.shopName);
  const [currency, setCurrency] = useState(settings.currency);
  const [busy, setBusy] = useState(false);

  const handleSave = async () => {
    setBusy(true);
    try {
      await updateSettings({ shopName, currency });
    } catch (e) {
      toast({ title: 'Settings not saved', description: errorMessage(e), variant: 'destructive' });
      return;
    } finally {
      setBusy(false);
    }
    toast({
      title: 'Settings saved',
      description: 'Your preferences have been updated.',
    });
  };

  return (
    <div className="container py-8">
      <div className="mb-8">
        <div className="flex items-center gap-3 mb-2">
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl gradient-primary shadow-medium">
            <SettingsIcon className="h-6 w-6 text-primary-foreground" />
          </div>
          <div>
            <h1 className="font-display text-3xl font-bold text-foreground">Settings</h1>
            <p className="text-muted-foreground">Manage your shop, staff and account</p>
          </div>
        </div>
      </div>

      <div className="grid gap-6 max-w-2xl">
        {isOwner && <LegacyImport />}

        <Card className="border-border shadow-medium">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 font-display">
              <Store className="h-5 w-5 text-primary" />
              Shop Information
            </CardTitle>
            <CardDescription>Basic details about your shop</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="shopName">Shop Name</Label>
              <Input
                id="shopName"
                value={shopName}
                onChange={e => setShopName(e.target.value)}
                placeholder="Enter shop name"
                className="h-12"
                disabled={!isOwner}
              />
            </div>
          </CardContent>
        </Card>

        <Card className="border-border shadow-medium">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 font-display">
              <CreditCard className="h-5 w-5 text-accent" />
              Currency Settings
            </CardTitle>
            <CardDescription>Set your preferred currency for transactions</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="currency">Currency Type</Label>
              <Select value={currency} onValueChange={setCurrency} disabled={!isOwner}>
                <SelectTrigger className="h-12">
                  <SelectValue placeholder="Select currency" />
                </SelectTrigger>
                <SelectContent className="bg-popover border-border">
                  {CURRENCIES.map(curr => (
                    <SelectItem key={curr.code} value={curr.code}>
                      <span className="flex items-center gap-2">
                        <span className="font-bold">{curr.symbol}</span>
                        <span>{curr.name}</span>
                        <span className="text-muted-foreground">({curr.code})</span>
                      </span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="p-4 rounded-xl bg-secondary/50 border border-border">
              <p className="text-sm text-muted-foreground">Preview:</p>
              <p className="text-2xl font-bold text-foreground mt-1">
                {CURRENCIES.find(c => c.code === currency)?.symbol}1,234.56
              </p>
            </div>
          </CardContent>
        </Card>

        {isOwner && (
          <Button onClick={handleSave} disabled={busy} size="lg" className="w-fit gradient-primary text-primary-foreground shadow-medium hover:shadow-glow transition-all">
            <Save className="h-5 w-5" />
            Save Settings
          </Button>
        )}

        {isOwner && <StaffManager />}

        <AccountCard />
      </div>
    </div>
  );
}
